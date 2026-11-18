import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: PPSKModel

    @State private var selection: UUID?
    @State private var profileName = ""
    @State private var ssid = ""
    @State private var password = ""
    @State private var expectedPrefix = ""
    @State private var vlanID = ""
    @State private var feedback = ""

    @State private var showImportSheet = false
    @State private var importDocument: PPSKCSVDocument?
    @State private var importSSID = ""
    @State private var importError = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("PPSK Profiles")
                    .font(.headline)
                List(selection: $selection) {
                    ForEach(model.profiles) { profile in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.name).fontWeight(.medium)
                            Text("\(profile.ssid) · \(profile.vlanID.map { "VLAN \($0)" } ?? "VLAN unspecified")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(profile.id)
                    }
                }
                Button {
                    selection = nil
                    clearFields()
                } label: {
                    Label("Add VLAN Profile", systemImage: "plus")
                }
                Button {
                    openCSVPicker()
                } label: {
                    Label("Import UniFi CSV…", systemImage: "square.and.arrow.down")
                }
                .disabled(model.isConnecting)
                Text("Requires VLAN ID, Password, and Network columns. Passwords are stored in Keychain.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 225)

            Divider()

            Form {
                Section("Wi-Fi PPSK") {
                    TextField("Name (e.g. Home or IoT)", text: $profileName)
                    TextField("Shared Wi-Fi SSID", text: $ssid)
                    SecureField(selection == nil ? "Wi-Fi Password" : "New Password (leave blank to keep current)", text: $password)
                    TextField("VLAN ID (optional, e.g. 20)", text: $vlanID)
                    TextField("Expected DHCP IPv4 Prefix (e.g. 192.168.2.)", text: $expectedPrefix)
                    Text("VLAN ID is a label, not an 802.1Q configuration on your Mac. The IPv4 prefix helps verify the switch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    HStack {
                        Button("Save Profile") { save() }
                            .buttonStyle(.borderedProminent)
                        if let selection {
                            Button("Connect with This Password") {
                                feedback = ""
                                model.connect(selection)
                            }
                            .disabled(model.isConnecting)
                            Spacer()
                            Button("Delete", role: .destructive) { delete(selection) }
                        }
                    }
                    Text(feedback.isEmpty ? model.status : feedback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("macOS 27 Limitations") {
                    Text("macOS may reject a CoreWLAN reauthentication attempt or reuse saved credentials for the same SSID. The app does not delete known Wi-Fi networks or modify macOS Wi-Fi credentials.")
                        .font(.caption)
                    HStack {
                        Button("Request Location Permission") { model.requestLocationPermission() }
                        Button("Open Wi-Fi Settings") { model.openWiFiSettings() }
                        Button("Copy Diagnostics") {
                            let report = "PPSK Switcher 1.2\nSSID: \(model.wifiSSID)\nWi-Fi IPv4: \(model.ipAddress)\nStatus: \(model.status)"
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(report, forType: .string)
                            feedback = "Diagnostics copied (no passwords included)."
                        }
                    }
                    if let selection {
                        Button("Manual Fallback: Copy Password and Open Wi-Fi Settings") {
                            model.copyPasswordForManualJoin(selection)
                            feedback = "Forget the SSID in Wi-Fi Settings, reconnect with the copied password, and clear your clipboard afterwards."
                        }
                    }
                }
            }
            .padding(12)
            .formStyle(.grouped)
        }
        .frame(width: 815, height: 535)
        .onAppear { loadFields() }
        .onChange(of: selection) { _ in loadFields() }
        .sheet(isPresented: $showImportSheet, onDismiss: {
            // Release plaintext CSV secrets from SwiftUI state after confirmation.
            importDocument = nil
            importSSID = ""
            importError = ""
        }) {
            importSheet
        }
    }

    @ViewBuilder
    private var importSheet: some View {
        if let document = importDocument {
            VStack(alignment: .leading, spacing: 14) {
                Text("Import UniFi PPSK CSV")
                    .font(.title3).fontWeight(.semibold)
                Text("Found \(document.rows.count) PPSK entries. Confirm the shared Wi-Fi SSID. UniFi export filenames are used to fill it automatically when available.")
                    .foregroundStyle(.secondary)
                TextField("Shared Wi-Fi SSID (required)", text: $importSSID)
                    .textFieldStyle(.roundedBorder)
                Table(document.rows) {
                    TableColumn("Network") { row in
                        Text(row.network)
                    }
                    TableColumn("VLAN ID") { row in
                        Text(row.vlanID.map(String.init) ?? "Unspecified")
                    }
                    TableColumn("Password") { _ in
                        Text("Imported · Hidden")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 170)
                Text("Existing profiles are updated when SSID and Network name match (or a VLAN ID is unique). Their IPv4 prefixes are preserved. The original plaintext CSV remains on disk; store or delete it securely.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !importError.isEmpty {
                    Text(importError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { showImportSheet = false }
                    Button("Import \(document.rows.count) PPSK Entries") {
                        commitImport(document)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(importSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isConnecting)
                }
            }
            .padding(20)
            .frame(width: 640, height: 490)
        }
    }

    private func openCSVPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose UniFi PPSK CSV"
        panel.message = "Select a UniFi CSV export with VLAN ID, Password, and Network columns."
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            // No CSV data is written to application storage or diagnostics.
            let data = try Data(contentsOf: url)
            let document = try PPSKCSVImporter.parse(data: data)
            importDocument = document
            let candidates = Set(model.profiles.map(\.ssid))
            if let filenameSSID = PPSKCSVImporter.suggestedSSID(from: url) {
                importSSID = filenameSSID
            } else if candidates.count == 1 {
                importSSID = candidates.first ?? ""
            } else if model.wifiSSID.utf8.count <= 32,
                      !model.wifiSSID.isEmpty,
                      !["Checking…", "Unknown", "Unknown (location access may be denied)"].contains(model.wifiSSID) {
                importSSID = model.wifiSSID
            } else {
                importSSID = ""
            }
            importError = ""
            showImportSheet = true
        } catch {
            feedback = error.localizedDescription
        }
    }

    private func commitImport(_ document: PPSKCSVDocument) {
        do {
            let summary = try model.importCSV(document, ssid: importSSID)
            showImportSheet = false
            loadFields()
            feedback = "CSV import complete: \(summary.created) created, \(summary.updated) updated. Passwords saved to Keychain."
        } catch {
            importError = error.localizedDescription
        }
    }

    private func loadFields() {
        feedback = ""
        password = ""  // Never display/retrieve a saved secret in a text field.
        guard let selection,
              let profile = model.profiles.first(where: { $0.id == selection }) else {
            clearFields()
            return
        }
        profileName = profile.name
        ssid = profile.ssid
        expectedPrefix = profile.expectedIPv4Prefix
        vlanID = profile.vlanID.map(String.init) ?? ""
    }

    private func clearFields() {
        profileName = ""
        ssid = ""
        password = ""
        expectedPrefix = ""
        vlanID = ""
        feedback = ""
    }

    private func save() {
        do {
            let number = try PPSKProfile.parseVLANID(vlanID)
            let newID = try model.saveProfile(id: selection, name: profileName, ssid: ssid,
                                              expectedIPv4Prefix: expectedPrefix,
                                              newPassword: password, vlanID: number)
            selection = newID
            password = ""
            feedback = "Profile saved. Password stored in macOS Keychain."
        } catch {
            feedback = error.localizedDescription
        }
    }

    private func delete(_ id: UUID) {
        do {
            try model.deleteProfile(id)
            selection = nil
            clearFields()
            feedback = "Profile and its Keychain password deleted."
        } catch {
            feedback = error.localizedDescription
        }
    }
}
