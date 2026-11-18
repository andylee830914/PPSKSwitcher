import Foundation

/// A UniFi PPSK CSV row. Passwords live in memory only until the user confirms
/// the import; do not include rows in logs, string interpolation or UserDefaults.
struct PPSKCSVRow: Identifiable {
    let id: Int  // Source line number (used for diagnostics only).
    let vlanID: Int?
    let network: String
    let password: String
}

struct PPSKCSVDocument {
    let rows: [PPSKCSVRow]
}

enum PPSKCSVError: LocalizedError {
    case invalidEncoding
    case malformed(line: Int)
    case missingColumns
    case emptyDocument
    case invalidRow(line: Int, reason: String)
    case duplicateRow(line: Int)

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Unable to decode CSV. Please save the file as UTF-8."
        case .malformed(let line):
            return "Invalid CSV quoting or field format at line \(line)."
        case .missingColumns:
            return "Missing required UniFi CSV columns: VLAN ID, Password, and Network."
        case .emptyDocument:
            return "CSV does not contain any importable PPSK entries."
        case .invalidRow(let line, let reason):
            return "CSV line \(line): \(reason)"
        case .duplicateRow(let line):
            return "Duplicate Network and VLAN ID combination at CSV line \(line). Remove duplicate rows before importing."
        }
    }
}

enum PPSKCSVImporter {
    /// Reads the current UniFi export format: "VLAN ID,Password,Network".
    /// Empty VLAN IDs remain nil, rather than being silently interpreted as VLAN 1.
    static func parse(data: Data) throws -> PPSKCSVDocument {
        // Exports from UniFi are UTF-8; tolerate a UTF-8 BOM.
        guard var text = String(data: data, encoding: .utf8) else {
            throw PPSKCSVError.invalidEncoding
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let records = try parseRFC4180(text)
        guard let header = records.first else { throw PPSKCSVError.emptyDocument }

        let normalized = header.fields.map { column in
            column.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .filter { !$0.isWhitespace && $0 != "_" && $0 != "-" }
        }
        guard let vlanIndex = normalized.firstIndex(of: "vlanid"),
              let passwordIndex = normalized.firstIndex(of: "password"),
              let networkIndex = normalized.firstIndex(of: "network") else {
            throw PPSKCSVError.missingColumns
        }
        let requiredColumnCount = max(vlanIndex, passwordIndex, networkIndex) + 1
        var rows: [PPSKCSVRow] = []
        var rowKeys = Set<String>()

        // Source line numbers are tracked by the CSV parser, even for embedded newlines.
        for record in records.dropFirst() {
            let fields = record.fields
            if fields.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }
            guard fields.count >= requiredColumnCount else {
                throw PPSKCSVError.invalidRow(line: record.line, reason: "Not enough columns.")
            }
            let rawVLAN = fields[vlanIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let name = fields[networkIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let password = fields[passwordIndex]  // Never trim a password.

            let vlanID: Int?
            if rawVLAN.isEmpty {
                vlanID = nil
            } else if let value = Int(rawVLAN), (1...4094).contains(value) {
                vlanID = value
            } else {
                throw PPSKCSVError.invalidRow(line: record.line, reason: "VLAN ID must be between 1 and 4094, or blank.")
            }
            if name.isEmpty {
                throw PPSKCSVError.invalidRow(line: record.line, reason: "Network name cannot be empty.")
            }
            // Validate the password without echoing it in any error message.
            guard isValidPSK(password) else {
                throw PPSKCSVError.invalidRow(line: record.line, reason: "Invalid WPA PPSK password: expected 8–63 UTF-8 bytes or 64 hexadecimal characters.")
            }
            let key = "\(name.lowercased())\u{0}\(vlanID.map(String.init) ?? "default")"
            guard rowKeys.insert(key).inserted else {
                throw PPSKCSVError.duplicateRow(line: record.line)
            }
            rows.append(PPSKCSVRow(id: record.line, vlanID: vlanID,
                                   network: name, password: password))
        }
        guard !rows.isEmpty else { throw PPSKCSVError.emptyDocument }
        return PPSKCSVDocument(rows: rows)
    }

    private static func isValidPSK(_ value: String) -> Bool {
        let count = value.utf8.count
        if (8...63).contains(count) { return true }
        return count == 64 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
        }
    }

    private struct CSVRecord {
        let line: Int
        let fields: [String]
    }

    /// Small RFC 4180 parser supporting UTF-8, quoted commas, escaped quotes,
    /// CRLF/LF and embedded line breaks. Intentionally has no external dependencies.
    private static func parseRFC4180(_ text: String) throws -> [CSVRecord] {
        let scalars = Array(text.unicodeScalars)
        var records: [CSVRecord] = []
        var cells: [String] = []
        var cell = ""
        var line = 1
        var recordStart = 1
        var index = 0
        enum State { case start, plain, quoted, closedQuote }
        var state = State.start

        func flushCell() {
            cells.append(cell)
            cell = ""
            state = .start
        }
        func flushRecord() {
            flushCell()
            records.append(CSVRecord(line: recordStart, fields: cells))
            cells = []
            recordStart = line + 1
        }

        while index < scalars.count {
            let scalar = scalars[index]
            let code = scalar.value
            if code == 34 { // "
                switch state {
                case .start: state = .quoted
                case .quoted:
                    if index + 1 < scalars.count && scalars[index + 1].value == 34 {
                        cell.append("\"")
                        index += 1
                    } else {
                        state = .closedQuote
                    }
                case .plain, .closedQuote:
                    throw PPSKCSVError.malformed(line: line)
                }
            } else if code == 44 && state != .quoted { // comma
                flushCell()
            } else if (code == 10 || code == 13) {
                if code == 13 && index + 1 < scalars.count && scalars[index + 1].value == 10 {
                    index += 1  // CRLF is a single newline.
                }
                if state == .quoted {
                    cell.append("\n")
                } else {
                    flushRecord()
                }
                line += 1
                if state == .start && cells.isEmpty { recordStart = line }
            } else {
                if state == .closedQuote {
                    // Spaces after a closing quote are tolerated before separators.
                    if code != 32 && code != 9 { throw PPSKCSVError.malformed(line: line) }
                } else {
                    cell.unicodeScalars.append(scalar)
                    if state == .start { state = .plain }
                }
            }
            index += 1
        }
        if state == .quoted { throw PPSKCSVError.malformed(line: line) }
        if !cells.isEmpty || !cell.isEmpty || state != .start {
            flushRecord()
        }
        return records
    }
}
