# Contributing

Thanks for your interest in improving PPSK Switcher!

## Before opening an issue

- Search existing issues first.
- For Wi-Fi problems, provide the macOS version, Mac model (optional), UniFi firmware version, and the exact CoreWLAN error code when available.
- **Never attach a real UniFi PPSK CSV, password, Keychain dump, private key, or full diagnostic log containing credentials.** Redact SSIDs, local IPs, MAC addresses, and personal identifiers as appropriate.
- Report sensitive security issues privately as described in [SECURITY.md](SECURITY.md).

## Pull requests

1. Create a feature branch.
2. Keep all source code, UI copy, test names, and documentation in English.
3. Run `./Tests/run-tests.sh` and include or update tests for CSV/parser/merge changes.
4. If you have a Mac with Xcode, build the macOS app and test the relevant UI flows.
5. Update `generate_project.py` and regenerate the project whenever you add/remove Swift files.
6. Confirm `git status --short` contains no credentials, real `.csv` files, or generated build artifacts before pushing.

macOS Wi-Fi APIs can behave differently across OS versions. Document tested configurations and avoid claiming reliable same-SSID PPSK switching without reproducible hardware tests.
