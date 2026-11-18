import CoreWLAN
import Foundation

struct ConnectionOutcome {
    enum Result {
        case verified
        case unverified
        case failed
    }

    let result: Result
    let message: String
    let ipAddress: String?
}

enum WiFiSwitcher {
    /// Called on a background queue. We intentionally use CoreWLAN instead of
    /// `networksetup SSID password`: command-line arguments leak passwords via `ps`.
    static func connect(profile: PPSKProfile, password: String,
                        progress: @escaping (String) -> Void) -> ConnectionOutcome {
        guard let wifi = CWWiFiClient.shared().interface() else {
            return ConnectionOutcome(result: .failed, message: "No Wi-Fi interface found.", ipAddress: nil)
        }
        guard wifi.powerOn() else {
            return ConnectionOutcome(result: .failed, message: "Wi-Fi is turned off.", ipAddress: nil)
        }
        guard let interfaceName = wifi.interfaceName else {
            return ConnectionOutcome(result: .failed, message: "Unable to identify the Wi-Fi interface.", ipAddress: nil)
        }

        do {
            progress("Scanning for \(profile.ssid)…")
            let networks = try wifi.scanForNetworks(withSSID: Data(profile.ssid.utf8))
            guard let target = networks.max(by: { $0.rssiValue < $1.rssiValue }) else {
                return ConnectionOutcome(result: .failed,
                                         message: "Could not find \(profile.ssid). Confirm that the SSID is nearby and allow location access for Wi-Fi scanning.",
                                         ipAddress: nil)
            }

            // A real disassociation is necessary for a same-SSID different-PSK change.
            // macOS can still reject the explicit re-association or reuse system credentials.
            progress("Disconnecting and authenticating with \(profile.name)…")
            wifi.disassociate()
            try wifi.associate(to: target, password: password)
            progress("Connection requested; waiting for DHCP…")

            let prefix = profile.expectedIPv4Prefix
            var lastIP: String?
            for _ in 0..<15 {
                Thread.sleep(forTimeInterval: 1)
                let ip = ipv4Address(interface: interfaceName)
                lastIP = ip
                if !prefix.isEmpty, let ip, ip.hasPrefix(prefix), wifi.ssid() == profile.ssid {
                    return ConnectionOutcome(result: .verified,
                                             message: "Connected",
                                             ipAddress: ip)
                }
            }

            if prefix.isEmpty {
                return ConnectionOutcome(result: .unverified,
                                         message: "Connection attempted with the selected password\(lastIP.map { ", IP: \($0)" } ?? ""), but no expected IPv4 prefix is set, so the VLAN cannot be verified.",
                                         ipAddress: lastIP)
            }
            return ConnectionOutcome(result: .failed,
                                     message: "Could not verify VLAN: expected \(prefix)*, current IPv4 \(lastIP ?? "unknown"). macOS may have reused a saved password, or DHCP may not have updated yet.",
                                     ipAddress: lastIP)
        } catch {
            let nsError = error as NSError
            let code = "\(nsError.domain) \(nsError.code)"
            let ip = ipv4Address(interface: interfaceName)
            return ConnectionOutcome(result: .failed,
                                     message: "CoreWLAN rejected the connection (\(code)): \(error.localizedDescription). Try the manual fallback in Settings.",
                                     ipAddress: ip)
        }
    }

    static func wifiDetails() -> (ssid: String, ipAddress: String) {
        guard let wifi = CWWiFiClient.shared().interface() else { return ("Unknown", "Unknown") }
        let ssid = wifi.ssid() ?? "Unknown (location access may be denied)"
        let ip = wifi.interfaceName.flatMap { ipv4Address(interface: $0) } ?? "Not assigned"
        return (ssid, ip)
    }

    /// ipconfig is used for a non-secret DHCP address only. No password is
    /// passed to a shell or a command-line argument.
    private static func ipv4Address(interface: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
        process.arguments = ["getifaddr", interface]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let string = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return string?.isEmpty == false ? string : nil
        } catch {
            return nil
        }
    }
}
