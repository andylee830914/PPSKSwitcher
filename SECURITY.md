# Security Policy

## Sensitive data

UniFi PPSK CSV exports contain plaintext Wi-Fi credentials. Never upload them to GitHub issues, commits, CI artifacts, or pull requests. Store them privately, and rotate passwords immediately if they are exposed.

PPSK Switcher stores saved PPSK values in macOS Keychain. It stores SSIDs, profile names, VLAN IDs, and expected IPv4 prefixes in UserDefaults. Copying a password for manual connection places it on the system clipboard; clear or overwrite the clipboard after use and be aware of clipboard history applications.

The `.gitignore` ignores CSV files by default, but `git add -f` can override it. Review every commit, including past Git history, for secrets.

## Reporting a vulnerability

Do **not** disclose the exploit or credentials in a public issue. If the GitHub repository has private vulnerability reporting enabled, use **Security → Report a vulnerability**. Otherwise, ask maintainers in a public issue for a private reporting channel without sharing any exploit details or secrets.

## Supported versions

This is an experimental source-only project. There is no published security-support SLA. The latest version in the default branch is the development target.
