import AppKit
import Combine
import CoreLocation
import Foundation

enum PPSKImportFailure: LocalizedError {
    case connectionInProgress
    case keychainFailed(reason: String, rollbackSucceeded: Bool)

    var errorDescription: String? {
        switch self {
        case .connectionInProgress:
            return "A Wi-Fi connection attempt is in progress. Import again when it finishes."
        case .keychainFailed(let reason, let rollbackSucceeded):
            return "Unable to save imported passwords to Keychain: \(reason). " +
                (rollbackSucceeded ? "Previous changes were restored." : "Some Keychain changes may not have been restored; check your profiles.")
        }
    }
}

@MainActor
final class PPSKModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var profiles: [PPSKProfile] = []
    @Published private(set) var isConnecting = false
    @Published var status = "Add a PPSK profile to get started."
    @Published var wifiSSID = "Checking…"
    @Published var ipAddress = "Checking…"
    @Published private(set) var lastVerifiedProfileID: UUID?

    private let settingsKey = "profiles-v1"
    private let locationManager = CLLocationManager()
    private var refreshTimer: Timer?

    override init() {
        super.init()
        locationManager.delegate = self
        load()
        refreshDetails()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshDetails() }
        }
    }

    func saveProfile(id: UUID?, name: String, ssid: String,
                     expectedIPv4Prefix: String, newPassword: String, vlanID: Int? = nil) throws -> UUID {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSSID = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = expectedIPv4Prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = id.flatMap { key in profiles.first(where: { $0.id == key }) }
        try PPSKProfile.validate(name: cleanName, ssid: cleanSSID, prefix: prefix,
                                 password: newPassword.isEmpty ? nil : newPassword, isNew: existing == nil,
                                 vlanID: vlanID)

        let key = existing?.id ?? UUID()
        if !newPassword.isEmpty {
            try CredentialStore.setPassword(newPassword, for: key)
        } else if try CredentialStore.password(for: key) == nil {
            throw ProfileValidationError.passwordRequired
        }
        let profile = PPSKProfile(id: key, name: cleanName, ssid: cleanSSID,
                                  expectedIPv4Prefix: prefix, vlanID: vlanID)
        if let index = profiles.firstIndex(where: { $0.id == key }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        persist()
        status = "Saved \(profile.name)."
        return key
    }

    /// Creates or updates profiles from UniFi's PPSK CSV without persisting any
    /// plaintext secrets in the profile model, UserDefaults, app logs or ZIP.
    func importCSV(_ document: PPSKCSVDocument, ssid: String) throws -> PPSKImportSummary {
        if isConnecting { throw PPSKImportFailure.connectionInProgress }
        let changes = try PPSKImportPlanner.plan(document, ssid: ssid, existing: profiles)

        // Snapshot existing Keychain values before doing any write so a Keychain
        // failure can be rolled back without changing the saved profile list.
        var before: [UUID: String] = [:]
        for change in changes {
            if let old = try CredentialStore.password(for: change.profile.id) {
                before[change.profile.id] = old
            }
        }
        var written: [UUID] = []
        do {
            for change in changes {
                try CredentialStore.setPassword(change.password, for: change.profile.id)
                written.append(change.profile.id)
            }
        } catch {
            var reverted = true
            for id in written.reversed() {
                do {
                    if let old = before[id] {
                        try CredentialStore.setPassword(old, for: id)
                    } else {
                        try CredentialStore.deletePassword(for: id)
                    }
                } catch {
                    reverted = false
                }
            }
            throw PPSKImportFailure.keychainFailed(reason: error.localizedDescription,
                                                   rollbackSucceeded: reverted)
        }

        for change in changes {
            if let index = profiles.firstIndex(where: { $0.id == change.profile.id }) {
                profiles[index] = change.profile
            } else {
                profiles.append(change.profile)
            }
        }
        // A former verified profile must be checked again if its PPSK changed.
        lastVerifiedProfileID = nil
        persist()
        let summary = PPSKImportSummary(created: changes.filter { !$0.isUpdate }.count,
                                        updated: changes.filter { $0.isUpdate }.count)
        status = "CSV imported: \(summary.created) created, \(summary.updated) updated."
        return summary
    }

    func deleteProfile(_ id: UUID) throws {
        try CredentialStore.deletePassword(for: id)
        profiles.removeAll { $0.id == id }
        if lastVerifiedProfileID == id { lastVerifiedProfileID = nil }
        persist()
        status = "Profile deleted."
    }

    func connect(_ id: UUID) {
        guard !isConnecting, let profile = profiles.first(where: { $0.id == id }) else { return }
        let password: String
        do {
            guard let stored = try CredentialStore.password(for: profile.id) else {
                status = "No saved password for \(profile.name). Update this profile in Settings."
                return
            }
            password = stored
        } catch {
            status = error.localizedDescription
            return
        }
        isConnecting = true
        lastVerifiedProfileID = nil
        status = "Switching to \(profile.name)…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = WiFiSwitcher.connect(profile: profile, password: password) { progress in
                Task { @MainActor [weak self] in self?.status = progress }
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnecting = false
                self.status = outcome.message
                self.lastVerifiedProfileID = outcome.result == .verified ? profile.id : nil
                self.refreshDetails()
            }
        }
    }

    func requestLocationPermission() {
        let permission = locationManager.authorizationStatus
        if permission == .denied || permission == .restricted {
            openLocationSettings()
        } else {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshDetails()
    }

    func openLocationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(url)
    }

    func openWiFiSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.WiFi-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func copyPasswordForManualJoin(_ id: UUID) {
        do {
            guard let password = try CredentialStore.password(for: id) else {
                status = "No saved password found."
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(password, forType: .string)
            status = "Password copied to clipboard (not a secure storage location). Forget the SSID in macOS Wi-Fi Settings, then reconnect using the copied password."
            openWiFiSettings()
        } catch {
            status = error.localizedDescription
        }
    }

    func refreshDetails() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let details = WiFiSwitcher.wifiDetails()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.wifiSSID = details.ssid
                self.ipAddress = details.ipAddress
                if let id = self.lastVerifiedProfileID,
                   let profile = self.profiles.first(where: { $0.id == id }),
                   (details.ssid != profile.ssid || IPv4Subnet(profile.expectedIPv4Prefix)?.contains(details.ipAddress) != true) {
                    self.lastVerifiedProfileID = nil
                }
            }
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode([PPSKProfile].self, from: data) else { return }
        profiles = decoded
        status = "Select a PPSK profile to switch networks."
    }

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(encoded, forKey: settingsKey)
    }
}
