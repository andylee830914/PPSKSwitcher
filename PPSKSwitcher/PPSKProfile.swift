import Foundation

struct PPSKProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var ssid: String
    /// Optional DHCP address prefix, e.g. "192.168.2.".
    /// This is used to verify the VLAN, not to assign a static IP.
    var expectedIPv4Prefix: String
    /// UniFi VLAN ID (nil for the default/unspecified VLAN).
    /// Optional keeps existing v1 UserDefaults profiles decodable.
    var vlanID: Int?

    init(id: UUID = UUID(), name: String, ssid: String, expectedIPv4Prefix: String = "", vlanID: Int? = nil) {
        self.id = id
        self.name = name
        self.ssid = ssid
        self.expectedIPv4Prefix = expectedIPv4Prefix
        self.vlanID = vlanID
    }
}

enum ProfileValidationError: LocalizedError {
    case missingName
    case invalidSSID
    case invalidPassword
    case passwordRequired
    case invalidIPPrefix
    case invalidVLANID

    var errorDescription: String? {
        switch self {
        case .missingName:
            return "Enter a profile name."
        case .invalidSSID:
            return "SSID must contain 1–32 UTF-8 bytes."
        case .invalidPassword:
            return "WPA2-Personal / PPSK password must be 8–63 UTF-8 bytes, or a 64-character hexadecimal PSK."
        case .passwordRequired:
            return "A password is required to create a profile."
        case .invalidIPPrefix:
            return "Enter an IPv4 prefix such as 192.168.2., or leave it blank."
        case .invalidVLANID:
            return "VLAN ID must be between 1 and 4094, or blank."
        }
    }
}

extension PPSKProfile {
    static func parseVLANID(_ input: String) throws -> Int? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        guard let number = Int(value), (1...4094).contains(number) else {
            throw ProfileValidationError.invalidVLANID
        }
        return number
    }

    static func validate(name: String, ssid: String, prefix: String, password: String?, isNew: Bool,
                         vlanID: Int? = nil) throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProfileValidationError.missingName
        }
        if ssid.isEmpty || ssid.utf8.count > 32 {
            throw ProfileValidationError.invalidSSID
        }
        if isNew && (password == nil || password!.isEmpty) {
            throw ProfileValidationError.passwordRequired
        }
        if let password, !password.isEmpty {
            let count = password.utf8.count
            let isPassphrase = (8...63).contains(count)
            let isPSK = count == 64 && password.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
            if !isPassphrase && !isPSK {
                throw ProfileValidationError.invalidPassword
            }
        }
        if let vlanID, !(1...4094).contains(vlanID) {
            throw ProfileValidationError.invalidVLANID
        }
        if !prefix.isEmpty {
            let fields = prefix.split(separator: ".", omittingEmptySubsequences: false)
            guard fields.count == 4, fields.last == "",
                  fields.dropLast().allSatisfy({ part in
                      guard let number = Int(part) else { return false }
                      return !part.isEmpty && number >= 0 && number <= 255
                  }) else {
                throw ProfileValidationError.invalidIPPrefix
            }
        }
    }
}
