import Foundation
import GRDB
import Testing
@testable import GitIssuesKit

@Suite("All project fields in an issue's inspector")
struct IssueProjectSectionTests {
    private func project(_ id: String) -> Project {
        Project(id: id, ownerLogin: "me", ownerIsOrg: false, number: 1, title: id, url: "", closed: false,
                viewerCanUpdate: true, statusFieldId: "\(id)-status", priorityFieldId: "\(id)-priority", dueFieldId: "\(id)-due")
    }

    private func item(_ projectId: String?, contentId: String? = "issue-93") -> Item {
        Item(id: "\(projectId ?? "inbox")-item", projectId: projectId, kind: .issue, position: 0, statusId: "done",
             priorityId: "high", dueDate: "2026-11-03", contentId: contentId, number: 93, title: "Screenshots", body: "", state: "CLOSED")
    }

    private func fields(_ id: String) -> [ProjectField] {
        ["TITLE", "SINGLE_SELECT", "SINGLE_SELECT", "DATE", "SINGLE_SELECT", "SINGLE_SELECT", "NUMBER", "DATE", "DATE", "TEXT", "ITERATION", "LABELS", "MULTI_SELECT"]
            .enumerated().map { position, type in
                let suffix = ["title", "status", "priority", "due", "version", "ready", "requests", "start", "finish", "notes", "iteration", "labels", "platforms"][position]
                return ProjectField(id: "\(id)-\(suffix)", projectId: id, databaseId: position, name: suffix, dataType: type, position: position)
            }
    }

    @Test("Every project membership has its own fields, including empty ones hidden in the current view")
    func includesAllMemberships() throws {
        var ios = item("iOS")
        ios.fieldValues["iOS-version"] = FieldValue(optionId: "2.5.X")
        let brain = item("Brain")
        let other = item("Other", contentId: "another-issue")
        let sections = IssueProjectSection.sections(for: ios, items: [ios, brain, other], projects: [project("iOS"), project("Brain"), project("Other")],
                                                    fields: Array((fields("iOS") + fields("Brain") + fields("Other")).reversed()))
        #expect(sections.map(\.project.id) == ["iOS", "Brain"])
        #expect(sections.map(\.item.id) == ["iOS-item", "Brain-item"])
        #expect(sections[0].fields.map(\.name) == ["status", "priority", "due", "version", "ready", "requests", "start", "finish", "notes", "iteration", "platforms"])
        #expect(sections[0].value(of: try #require(sections[0].fields.first { $0.name == "version" }))?.optionId == "2.5.X")
        #expect(sections[1].value(of: try #require(sections[1].fields.first { $0.name == "version" })) == nil)
        #expect(sections[1].fields.contains { $0.name == "start" })
        #expect(sections[1].fields.contains { $0.name == "finish" })
    }

    @Test("Status, priority and due date read from their dedicated storage without duplicate rows")
    func dedicatedValues() throws {
        let sections = IssueProjectSection.sections(for: item("P"), items: [], projects: [project("P")], fields: fields("P"))
        let section = try #require(sections.first)
        #expect(section.value(of: section.fields[0]) == FieldValue(optionId: "done"))
        #expect(section.value(of: section.fields[1]) == FieldValue(optionId: "high"))
        #expect(section.value(of: section.fields[2]) == FieldValue(date: "2026-11-03"))
        #expect(Set(section.fields.map(\.id)).count == section.fields.count)
    }

    @Test("Closed projects stay out of the issue inspector, including when their cached membership remains")
    func closedProjects() {
        var closed = project("Closed")
        closed.closed = true
        let open = item("Open")
        #expect(IssueProjectSection.sections(for: open, items: [open, item("Closed")], projects: [closed, project("Open")], fields: []).map(\.project.id) == ["Open"])
        #expect(IssueProjectSection.sections(for: item("Closed"), items: [item("Closed")], projects: [closed], fields: []).isEmpty)
    }

    @Test("Opening from the Inbox finds the same projects; unrelated drafts do not become memberships")
    func inboxAndDrafts() {
        let projects = [project("iOS"), project("Brain")]
        #expect(IssueProjectSection.sections(for: item(nil), items: [item("iOS"), item("Brain")], projects: projects, fields: []).count == 2)
        var draft = item("iOS", contentId: nil)
        draft.kind = .draft
        var otherDraft = item("Brain", contentId: nil)
        otherDraft.kind = .draft
        let draftSections = IssueProjectSection.sections(for: draft, items: [draft, otherDraft], projects: projects, fields: fields("iOS"))
        #expect(draftSections.map(\.project.id) == ["iOS"])
        #expect(draftSections.first?.fields.contains { $0.name == "version" } == true)
        #expect(IssueProjectSection.sections(for: item("iOS"), items: [item("Brain"), item("iOS")], projects: Array(projects.reversed()), fields: []).map(\.project.id) == ["iOS", "Brain"])
    }

    @Test("A change to one project's version is queued for that item and survives rebasing without changing the other")
    func projectValuesStaySeparate() throws {
        let db = try AppDatabase.inMemory()
        let ios = item("iOS")
        let brain = item("Brain")
        try db.writer.write { db in
            try project("iOS").insert(db)
            try project("Brain").insert(db)
            try ios.insert(db)
            try brain.insert(db)
            try Outbox.enqueue(db, .setProjectField(.init(itemId: ios.id, projectId: "iOS", fieldId: "iOS-version", fieldName: "Version",
                                                        value: FieldValue(optionId: "2.5.X"), valueName: "2.5.X", base: nil)))
            try ios.update(db)
            try Outbox.rebase(db)
        }
        let (storedIOS, storedBrain) = try db.reader.read { (try Item.fetchOne($0, key: ios.id), try Item.fetchOne($0, key: brain.id)) }
        #expect(storedIOS?.fieldValues["iOS-version"]?.optionId == "2.5.X")
        #expect(storedBrain?.fieldValues.isEmpty == true)
        #expect(storedBrain?.dueDate == brain.dueDate)
    }

    @Test("Numeric input respects the user's decimal separator and rejects invalid and non-finite values")
    func numbers() {
        #expect(ProjectFieldInput.number("12.5", locale: Locale(identifier: "en_US")) == 12.5)
        #expect(ProjectFieldInput.number("-3", locale: Locale(identifier: "en_US")) == -3)
        #expect(ProjectFieldInput.number("0", locale: Locale(identifier: "en_US")) == 0)
        #expect(ProjectFieldInput.number("12,5", locale: Locale(identifier: "de_DE")) == 12.5)
        #expect(ProjectFieldInput.number("1,234.5", locale: Locale(identifier: "en_US")) == 1234.5)
        #expect(ProjectFieldInput.number("1e2", locale: Locale(identifier: "en_US")) == 100)
        #expect(ProjectFieldInput.number("words", locale: Locale(identifier: "en_US")) == nil)
        #expect(ProjectFieldInput.number("12abc", locale: Locale(identifier: "en_US")) == nil)
        #expect(ProjectFieldInput.number("12-3", locale: Locale(identifier: "en_US")) == nil)
        #expect(ProjectFieldInput.number("NaN", locale: Locale(identifier: "en_US")) == nil)
        #expect(ProjectFieldInput.number("∞", locale: Locale(identifier: "en_US")) == nil)
    }

    @Test("Number editors accept their own localized values, including minus signs and direction marks", arguments:
        ["en_US", "de_DE", "fr_FR", "sv_SE", "fi_FI", "nb_NO", "ar_EG", "fa_IR", "ja_JP"], [-12.5, 0.0, 12.5])
    func formattedNumberInput(localeId: String, value: Double) {
        let locale = Locale(identifier: localeId)
        let text = value.formatted(.number.locale(locale).grouping(.never))
        #expect(ProjectFieldInput.number(text, locale: locale) == value)
        #expect(ProjectFieldInput.number(text + "invalid", locale: locale) == nil)
    }
}
