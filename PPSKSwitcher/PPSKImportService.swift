import Foundation

struct PPSKImportSummary {
    let created: Int
    let updated: Int
}

/// Pure matching/validation logic, separated for tests and deterministic imports.
enum PPSKImportPlanner {
    struct Change {
        let profile: PPSKProfile
        let password: String
        let isUpdate: Bool
    }

    static func plan(_ document: PPSKCSVDocument, ssid: String,
                     existing: [PPSKProfile]) throws -> [Change] {
        let cleanSSID = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSSID.isEmpty, cleanSSID.utf8.count <= 32 else {
            throw ProfileValidationError.invalidSSID
        }
        var targetIDs = Set<UUID>()
        var changes: [Change] = []
        for row in document.rows {
            try PPSKProfile.validate(name: row.network, ssid: cleanSSID,
                                     prefix: "", password: row.password, isNew: true,
                                     vlanID: row.vlanID)
            // The network name is the primary key. Old v1 profiles lack VLAN IDs;
            // matching by name preserves their Keychain UUID and custom IP prefix.
            let sameSSID = existing.filter { $0.ssid == cleanSSID }
            let sameName = sameSSID.filter { $0.name.caseInsensitiveCompare(row.network) == .orderedSame }
            let match: PPSKProfile?
            if sameName.count == 1 {
                match = sameName[0]
            } else if sameName.count > 1 {
                throw PPSKCSVError.invalidRow(line: row.id, reason: "Multiple existing profiles use the same SSID and Network name; importing would be ambiguous.")
            } else if let vlan = row.vlanID {
                let sameVLAN = sameSSID.filter { $0.vlanID == vlan }
                // Only rename when the VLAN uniquely identifies an existing profile.
                match = sameVLAN.count == 1 ? sameVLAN[0] : nil
            } else {
                match = nil
            }
            let id = match?.id ?? UUID()
            guard targetIDs.insert(id).inserted else {
                throw PPSKCSVError.invalidRow(line: row.id, reason: "Multiple CSV rows would overwrite the same profile. Import cancelled.")
            }
            let profile = PPSKProfile(id: id, name: row.network, ssid: cleanSSID,
                                     expectedIPv4Prefix: match?.expectedIPv4Prefix ?? "",
                                     vlanID: row.vlanID)
            changes.append(Change(profile: profile, password: row.password, isUpdate: match != nil))
        }
        return changes
    }
}
