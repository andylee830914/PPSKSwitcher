import SwiftUI

@main
struct PPSKSwitcherApp: App {
    @StateObject private var model = PPSKModel()

    var body: some Scene {
        MenuBarExtra("PPSK Switcher", systemImage: model.currentProfileID == nil ? "network.slash" : "network") {
            MenuBarView(model: model)
        }
        Settings {
            SettingsView(model: model)
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var model: PPSKModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text("Current SSID: \(model.wifiSSID)")
        Text("Wi-Fi IPv4: \(model.ipAddress)")
        Divider()
        if model.profiles.isEmpty {
            Text("No PPSK profiles configured")
        } else {
            Picker("PPSK Profiles", selection: Binding<UUID?>(
                get: { model.currentProfileID },
                set: { id in
                    guard let id, id != model.currentProfileID else { return }
                    model.connect(id)
                }
            )) {
                ForEach(model.profiles) { profile in
                    Text("\(profile.name)  ·  \(profile.ssid)")
                        .tag(Optional(profile.id))
                }
            }
            .pickerStyle(.inline)
            .disabled(model.isConnecting)
        }
        Divider()
        Text(model.status)
        if model.isConnecting {
            Text("Connecting…")
        }
        Divider()
        Button {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            Label("Manage PPSK Profiles…", systemImage: "gearshape")
                .labelStyle(.titleAndIcon)
        }
        Button("Request Wi-Fi Scan Permission") { model.requestLocationPermission() }
        Button("Refresh Wi-Fi Status") { model.refreshDetails() }
        Button("Open macOS Wi-Fi Settings") { model.openWiFiSettings() }
        Divider()
        Button("Quit PPSK Switcher") { NSApplication.shared.terminate(nil) }
    }
}
