import Foundation

@main
struct CSVTests {
    static func main() throws {
        var checks = 0
        func verify(_ condition: Bool, _ message: String) {
            if !condition { fatalError("FAILED: \(message)") }
            checks += 1
        }
        func importDoc(_ raw: String) throws -> PPSKCSVDocument {
            try PPSKCSVImporter.parse(data: Data(raw.utf8))
        }
        verify(PPSKCSVImporter.suggestedSSID(from: URL(fileURLWithPath: "/tmp/llwge_VLAN-ppsk.csv")) == "llwge_VLAN", "SSID from UniFi filename")
        verify(PPSKCSVImporter.suggestedSSID(from: URL(fileURLWithPath: "/tmp/Home-ppsk-ppsk.csv")) == "Home-ppsk", "strip only final suffix")
        for filename in ["export.csv", "-ppsk.csv", String(repeating: "a", count: 33) + "-ppsk.csv"] {
            verify(PPSKCSVImporter.suggestedSSID(from: URL(fileURLWithPath: "/tmp/" + filename)) == nil, "ignore invalid filename suggestion")
        }
        let basic = try importDoc("VLAN ID,Password,Network\r\n,defaultpass,Default\r\n20,otherpassword,IoT\r\n")
        verify(basic.rows.count == 2, "row count")
        verify(basic.rows[0].vlanID == nil, "blank VLAN stays nil")
        verify(basic.rows[1].vlanID == 20, "VLAN parses")
        verify(basic.rows[0].network == "Default", "network name parses")
        verify(basic.rows[0].password == "defaultpass", "password stays intact")

        let bom = try importDoc("\u{FEFF}Network,Password,VLAN ID\n\"Main, Test\",\"alpha\"\"beta\",14\n")
        verify(bom.rows[0].network == "Main, Test", "quoted comma")
        verify(bom.rows[0].password == "alpha\"beta", "escaped quote")
        verify(bom.rows[0].vlanID == 14, "reordered header")

        let special = try importDoc("VLAN ID,Password,Network\n3,\"  abcdefgh  \",\"M\nN\"\n")
        verify(special.rows[0].password == "  abcdefgh  ", "password not trimmed")
        verify(special.rows[0].network == "M\nN", "quoted multiline")

        for invalid in [
            "VLAN ID,Password,Network\n0,goodpassword,IoT\n",
            "VLAN ID,Password,Network\n4095,goodpassword,IoT\n",
            "VLAN ID,Password,Network\n1,short,IoT\n",
            "VLAN ID,Password,Network\n1,goodpassword,\n",
            "VLAN ID,Password,Network\n1,goodpassword,IoT\n1,goodpassword,IoT\n",
            "VLAN ID,Password,Network\n\"1,goodpassword,IoT\n",
            "SSID,Password,Network\nS,goodpassword,IoT\n"
        ] {
            do {
                _ = try importDoc(invalid)
                fatalError("FAILED: invalid input accepted")
            } catch is PPSKCSVError {
                checks += 1
            }
        }

        let old = PPSKProfile(name: "IoT", ssid: "Main", expectedIPv4Prefix: "192.168.2.")
        let doc = try importDoc("VLAN ID,Password,Network\n10,abcdefghijk,IoT\n11,morepassword,NAS\n")
        let first = try PPSKImportPlanner.plan(doc, ssid: "Main", existing: [old])
        verify(first.count == 2, "planned changes")
        verify(first[0].profile.id == old.id, "migrated profile UUID preserved")
        verify(first[0].profile.expectedIPv4Prefix == "192.168.2.", "IP prefix preserved")
        verify(first[0].profile.vlanID == 10, "VLAN ID applied")
        verify(first[0].isUpdate && !first[1].isUpdate, "update/create plan")
        let second = try PPSKImportPlanner.plan(doc, ssid: "Main", existing: first.map(\.profile))
        verify(second.allSatisfy { $0.isUpdate }, "re-import updates existing")
        verify(second.map(\.profile.id) == first.map(\.profile.id), "re-import IDs stable")
        let otherSSID = try PPSKImportPlanner.plan(doc, ssid: "Guest", existing: first.map(\.profile))
        verify(otherSSID.allSatisfy { !$0.isUpdate }, "SSID isolation")

        let encoded = try JSONEncoder().encode(old)
        // Compatibility with v1 profile data missing the newly-added optional vlanID.
        var oldJSON = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        oldJSON.removeValue(forKey: "vlanID")
        let legacy = try JSONSerialization.data(withJSONObject: oldJSON)
        let restored = try JSONDecoder().decode(PPSKProfile.self, from: legacy)
        verify(restored.vlanID == nil, "legacy JSON profiles decode")

        if CommandLine.arguments.count > 1 {
            // Verify real user CSV structure without printing its secrets or names.
            let userData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let userDoc = try PPSKCSVImporter.parse(data: userData)
            verify(!userDoc.rows.isEmpty, "optional CSV contains at least one row")
            let plan = try PPSKImportPlanner.plan(userDoc, ssid: "TestWiFi", existing: [])
            verify(plan.count == userDoc.rows.count, "optional CSV can be imported")
        }
        print("PASS: \(checks) CSV parse/import checks")
    }
}
