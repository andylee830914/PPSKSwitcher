# PPSK Switcher for macOS

A lightweight, native **macOS menu bar app** for switching between UniFi **Private Pre-Shared Keys (PPSK)** on a **single Wi-Fi SSID**, where each password maps to a different VLAN. Written in SwiftUI with Apple's CoreWLAN and Keychain APIs. No third-party dependencies or cloud services.

> **Experimental:** macOS may reuse a saved Wi-Fi password or refuse same-SSID reauthentication via CoreWLAN. A successful Wi-Fi association does **not** prove that you switched VLANs. The app can compare a DHCP IPv4 prefix to provide a limited verification signal. Actual behavior on macOS 27 and your UniFi setup must be tested.

## Features

- Store multiple profiles with one shared SSID but different PPSK passwords.
- Import UniFi PPSK exports with the `VLAN ID`, `Password`, and `Network` columns.
- Switch profiles from the macOS menu bar using CoreWLAN.
- Keep each password in **macOS Keychain**, separate from non-secret profile metadata.
- Check the Wi-Fi interface's IPv4 address against an optional expected DHCP subnet prefix.
- Offer a manual fallback: copy a password and open macOS Wi-Fi Settings.
- Never automatically forget known macOS Wi-Fi networks or modify their saved system passwords.

## Requirements

- macOS 14 or later as configured by the project's deployment target; **macOS 27 is the intended test platform**.
- Xcode installed on a Mac for compiling and running the app.
- UniFi Wi-Fi with PPSK configured to map passwords to networks/VLANs.
- Wi-Fi access and Location Services permission for SSID discovery and network scanning.

## Build and run

1. Clone or download this repository and open `PPSKSwitcher.xcodeproj` in Xcode.
2. Select the **PPSKSwitcher** scheme and **My Mac** as the run destination, then click **Run**.
3. Alternatively, from Terminal on your Mac:

   ```bash
   ./build.sh
   open .build/PPSKSwitcher.app
   ```

4. Open the Wi-Fi icon in the menu bar and choose **Manage PPSK Profiles…**.
5. Add a profile manually or choose **Import UniFi CSV…**.
6. Use **Request Wi-Fi Scan Permission** and grant location access in **System Settings → Privacy & Security → Location Services** if needed.
7. Select a profile in the menu bar to attempt reconnection.

**Important:** The app disconnects Wi-Fi as part of switching. Test locally, not over a remote session that depends on the same Wi-Fi connection.

## Import a UniFi PPSK CSV

UniFi exports must contain these column names (order can vary):

```csv
VLAN ID,Password,Network
,examplepass123,Default
20,anotherpass123,IoT
```

The example uses **dummy passwords only**. Do not commit a real UniFi export to a repository.

1. Click **Import UniFi CSV…** in the profile manager and select the file.
2. Check the preview (passwords are masked).
3. Enter the **shared Wi-Fi SSID**. The UniFi CSV does not include an SSID column.
4. Click **Import N PPSK Entries**.

`Network` becomes the profile name. `VLAN ID` is displayed as a label; it **does not** configure an 802.1Q VLAN interface on the Mac. A blank VLAN ID remains *Unspecified*. When an existing profile matches the same SSID and network name—or a unique VLAN ID—the imported password updates the existing profile while preserving its saved UUID and IP verification prefix. Ambiguous matches are rejected.

The parser accepts UTF-8, UTF-8 BOM, quoted fields, embedded commas/newlines, and CRLF. CSV validation happens before applying changes. If writing passwords to Keychain fails partway through, the app attempts to restore prior Keychain values; rollback itself can fail, in which case the app warns you.

**Sensitive data:** A UniFi CSV contains plaintext PPSK passwords. The importer does not add it to app storage, but **the original file remains on your disk**. Store it securely or delete it after import. The repository's `.gitignore` ignores `*.csv` by default to reduce the risk of accidental commits, but this is not a substitute for checking your Git changes.

## Verifying a switch

For example, if a VLAN is expected to use the `192.168.2.x` subnet, set its **Expected DHCP IPv4 Prefix** to `192.168.2.`. After reconnecting, the app checks whether the active Wi-Fi interface has the same SSID and an IPv4 address beginning with this prefix.

- **Verified** means only that SSID and DHCP IPv4 prefix matched. It is **not cryptographic proof** of the PPSK or actual UniFi Client VLAN.
- **Unverified** means no IPv4 prefix was configured; the app cannot verify the VLAN.
- **Failed** may mean an association error, a stale DHCP lease, the wrong VLAN, or a macOS restriction.

If several VLANs share the same IP subnet, prefix matching cannot distinguish them. Confirm the real Client VLAN and DHCP lease in UniFi when troubleshooting.

## macOS limitations and manual fallback

The app calls CoreWLAN `scanForNetworks(withSSID:)`, `disassociate()`, and `associate(to:password:)`. macOS may reject reauthentication (occasionally reporting errors such as `-3900`) or reuse credentials it already has for the SSID. **One-click PPSK changes are not guaranteed, including on macOS 27.**

If the automatic attempt fails, use **Manual Fallback: Copy Password and Open Wi-Fi Settings**, forget the SSID in macOS Wi-Fi Settings if necessary, and reconnect with the selected PPSK. The clipboard contains the plaintext password until you clear or overwrite it; clipboard managers may retain it.

## Privacy and security

- Each secret is stored in a Keychain generic-password item keyed by profile UUID. Profile names, SSIDs, VLAN IDs, and verification prefixes are saved in UserDefaults.
- PPSKs are not intentionally written to logs, command-line arguments, app settings, or the project source.
- The app requests location permission for Wi-Fi SSID and scanning APIs; it does not ask for GPS coordinates or send data to a server.
- No administrator/root privileges are requested, and no `sudo` calls are used.
- `LSUIElement = true` makes this a menu bar-only app (no Dock icon).
- The project uses the existing development bundle identifier `app.local.PPSKSwitcher` to preserve local preferences and Keychain behavior from earlier versions. If you change it for distribution, test existing-user migration first.

Read [SECURITY.md](SECURITY.md) before filing issues involving your network.

## Project structure

| Path | Responsibility |
| --- | --- |
| `PPSKSwitcher/PPSKSwitcherApp.swift` | Menu bar and app entry point |
| `PPSKSwitcher/SettingsView.swift` | Profile management and CSV import UI |
| `PPSKSwitcher/PPSKModel.swift` | Profile persistence and connection orchestration |
| `PPSKSwitcher/WiFiSwitcher.swift` | CoreWLAN association and IPv4 checks |
| `PPSKSwitcher/CredentialStore.swift` | Password management in Keychain |
| `PPSKSwitcher/PPSKProfile.swift` | Profile model and input validation |
| `PPSKSwitcher/PPSKCSVImporter.swift` | CSV parser and validation |
| `PPSKSwitcher/PPSKImportService.swift` | CSV-to-profile merge planning |
| `Tests/` | Portable Swift parser/merge tests |
| `generate_project.py` | Deterministic Xcode project generator |

## Tests and project generation

Run the portable CSV and merge tests with a Swift compiler:

```bash
./Tests/run-tests.sh
```

To check the Xcode project on a Mac:

```bash
xcodebuild -project PPSKSwitcher.xcodeproj \
  -scheme PPSKSwitcher -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

If you add or remove Swift files, update the `swift_files` list in `generate_project.py` and then run `python3 generate_project.py`. Do not commit real PPSK CSVs, signing identities, API tokens, or local environment configuration.

## Publish to GitHub

Review and choose the license before publishing. The included `LICENSE` is **MIT**; change it if you prefer another licensing model. Then create an **empty** repository on GitHub (do not initialize it with another README or `.gitignore`) and run:

```bash
git init -b main
git add .
git status --short     # Check every staged file for private data
git commit -m "Initial public release"
git remote add origin https://github.com/YOUR_USERNAME/PPSKSwitcher.git
git push -u origin main
```

Replace `YOUR_USERNAME` with your GitHub username (and adjust the repository name if needed). The ZIP contains **source code**, not a signed or notarized app and not a preconfigured Git remote. Set repository details, release metadata, and signing identifiers before distributing binaries.

## Contributing and licensing

See [CONTRIBUTING.md](CONTRIBUTING.md) for pull requests and issue guidelines. This source is offered under the [MIT License](LICENSE).

**Project status:** The pure Swift CSV parser/merge tests are runnable without macOS. A Linux test run does **not** validate AppKit, SwiftUI, CoreWLAN, Keychain integration, code signing, or real Wi-Fi switching on macOS 27. Those require an actual Mac and suitable UniFi access point.
