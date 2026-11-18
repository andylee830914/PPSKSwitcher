# PPSK Switcher for macOS

A menu bar app for switching between UniFi PPSK profiles on the same Wi-Fi SSID. Passwords are stored in macOS Keychain.

## Build and run

Requires macOS 14+ and Xcode. Open `PPSKSwitcher.xcodeproj` and click **Run**, or use:

```bash
./build.sh
open .build/PPSKSwitcher.app
```

To build a DMG with the app and an Applications shortcut:

```bash
./package-dmg.sh
```

The output is `.build/PPSKSwitcher-<version>.dmg`. Users open it and drag the app to **Applications**. Packaging does not add Developer ID signing or Apple notarization.

## If macOS blocks the app

The current build uses an ad-hoc signature and is not notarized by Apple. If macOS says the developer cannot be verified or Apple cannot check the app, follow these steps only for a copy you trust:

1. Move `PPSKSwitcher.app` to **Applications** and try opening it once.
2. Dismiss the warning, then open **System Settings → Privacy & Security**.
3. Scroll to **Security**, find the PPSKSwitcher notice, and click **Open Anyway** (強制打開).
4. Authenticate if prompted, then click **Open** to confirm.

This saves an exception for this app. A replacement build may require approval again. If a managed Mac does not offer **Open Anyway**, contact your administrator.

See [Apple’s instructions](https://support.apple.com/en-us/102445). These steps apply to developer-verification warnings; if macOS reports malware or a damaged app, obtain a fresh trusted copy instead.

## Set up profiles

1. Open the app’s menu bar icon → **Manage PPSK Profiles…**.
2. Add a profile, or choose **Import UniFi CSV…**. CSV exports need `VLAN ID`, `Password`, and `Network` columns.
3. Confirm the SSID. A filename like `llwge_VLAN-ppsk.csv` automatically fills in `llwge_VLAN`.
4. Set **Expected DHCP IPv4 Subnet**, for example `192.168.0.0/24`, to enable connection detection.
5. If prompted, allow Location Services so the app can read the SSID and scan Wi-Fi.

## Import a UniFi PPSK CSV

Export the PPSK CSV from UniFi, then:

1. Open **Manage PPSK Profiles…** → **Import UniFi CSV…** and select the file.
2. Check the preview and SSID. `SSIDxxx-ppsk.csv` fills in `SSIDxxx` automatically; you can edit it.
3. Click **Import N PPSK Entries**.

The CSV must include these columns (column order can vary):

```csv
VLAN ID,Password,Network
,examplepass123,Default
20,anotherpass123,IoT
```

`Network` becomes the profile name. A blank VLAN ID stays unspecified. Reimporting updates matching profiles while preserving their configured IPv4 subnets. VLAN IDs are labels; the app does not configure a VLAN interface on the Mac.

The example passwords are placeholders. Your real export contains plaintext passwords; keep it secure or delete it after importing.

## Switch networks

Select a profile from the menu bar. Switching briefly disconnects Wi-Fi.

The app checks the current SSID and IP every eight seconds:

- **✓ next to a profile:** exactly one profile matches the SSID and subnet.
- **Network icon:** a matching profile is detected.
- **Slashed network icon:** no unique match, or a switch is in progress.

Profiles with missing or overlapping subnets may not be identifiable. Detection infers the profile from SSID and IP; it does not confirm the actual PPSK or UniFi VLAN.

## If switching fails

macOS may reuse a saved Wi-Fi password. In the profile manager, use **Manual Fallback: Copy Password and Open Wi-Fi Settings**, then forget the network if needed and reconnect with the copied password. Clear the clipboard afterwards.

Keychain may request permission to read a password. Choose **Always Allow** if you want to remember that authorization for the app.

UniFi CSV files contain plaintext passwords. Keep the original file secure or delete it after importing.

## Development

Run tests with `./Tests/run-tests.sh`. Real Wi-Fi switching requires testing on a Mac with UniFi PPSK configured.

[Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [MIT License](LICENSE)
