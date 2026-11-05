import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("Editing text, number and multi-select project fields")
struct ProjectFieldSyncTests {
    @Test("Values and clearing reach GitHub with the right type and survive a fresh pull", arguments: [
        FieldValue(text: "Release notes\nwith details"), FieldValue(text: ""),
        FieldValue(number: 0), FieldValue(number: -12.5), FieldValue(optionIds: ["a", "b"]),
    ])
    func roundTrip(value: FieldValue) async throws {
        let github = FakeGitHub([.init(contentId: "I_1", number: 1, itemId: "PVTI_1")])
        let type = value.text != nil ? "TEXT" : value.number != nil ? "NUMBER" : "MULTI_SELECT"
        var field: [String: Any] = ["__typename": type == "MULTI_SELECT" ? "ProjectV2MultiSelectField" : "ProjectV2Field",
                                    "id": "F-extra", "name": "Extra", "databaseId": 2, "dataType": type]
        if type == "MULTI_SELECT" {
            field["multiOptions"] = [["id": "a", "name": "A", "color": "BLUE"], ["id": "b", "name": "B", "color": "GREEN"]]
        }
        github.extraFields = [field]
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            try Project(id: "P1", ownerLogin: "octo", ownerIsOrg: false, number: 1, title: "Board", url: "", closed: false, viewerCanUpdate: true).insert(db)
        }
        let status = await MainActor.run { SyncStatus() }
        let engine = SyncEngine(db: db, api: github.api, status: status)
        try await engine.pull(projectId: "P1")
        try await db.writer.write { db in
            try Outbox.enqueue(db, .setProjectField(.init(itemId: "PVTI_1", projectId: "P1", fieldId: "F-extra", fieldName: "Extra",
                                                        value: value, valueName: nil, base: nil)))
        }
        #expect(try await db.reader.read { try Item.fetchOne($0, key: "PVTI_1")?.fieldValues["F-extra"] } == value)
        try await engine.pushPending()
        let writes = github.fieldWrites()
        #expect(writes.count == 1)
        let write = try #require(writes.first)
        #expect(!write.isClear)
        #expect(write.variables["p"] as? String == "P1")
        #expect(write.variables["i"] as? String == "PVTI_1")
        #expect(write.variables["f"] as? String == "F-extra")
        if let text = value.text {
            #expect(write.query.contains("text: $v"))
            #expect(write.variables["v"] as? String == text)
        } else if let number = value.number {
            #expect(write.query.contains("$v: Float!"))
            #expect(write.query.contains("number: $v"))
            #expect(write.variables["v"] as? Double == number)
        } else {
            #expect(write.query.contains("multiSelectOptionIds: $v"))
            #expect(write.variables["v"] as? [String] == value.optionIds)
        }
        try await db.writer.write { try Outbox.purgeSent($0, now: Date().addingTimeInterval(Outbox.graceInterval + 1)) }
        try await engine.forcePull(projectId: "P1")
        let pulled = try await db.reader.read { try Item.fetchOne($0, key: "PVTI_1") }
        #expect(pulled?.fieldValues["F-extra"] == value)
        if type == "MULTI_SELECT" {
            #expect(try await db.reader.read { try ProjectField.fetchOne($0, key: "F-extra")?.options.map(\.name) } == ["A", "B"])
        }
        try await db.writer.write { db in
            try Outbox.enqueue(db, .setProjectField(.init(itemId: "PVTI_1", projectId: "P1", fieldId: "F-extra", fieldName: "Extra",
                                                        value: nil, valueName: nil, base: value)))
        }
        try await engine.pushPending()
        #expect(github.fieldWrites().last?.isClear == true)
        try await db.writer.write { try Outbox.purgeSent($0, now: Date().addingTimeInterval(Outbox.graceInterval + 1)) }
        try await engine.forcePull(projectId: "P1")
        #expect(try await db.reader.read { try Item.fetchOne($0, key: "PVTI_1")?.fieldValues["F-extra"] } == nil)
    }

    @Test("Older stored values decode without multi-select data, and an empty selection is a clear")
    func storedValues() throws {
        let old = try JSONDecoder().decode(FieldValue.self, from: Data(#"{"text":"old value"}"#.utf8))
        #expect(old == FieldValue(text: "old value"))
        #expect(FieldValue(optionIds: []).isEmpty)
        #expect(!FieldValue(optionIds: ["a"]).isEmpty)
    }
}
