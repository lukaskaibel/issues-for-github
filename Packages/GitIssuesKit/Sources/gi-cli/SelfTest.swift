import Foundation
@testable import GitIssuesKit
import GRDB

/// End-to-end check of every kind of write, against the sandbox project only.
enum SelfTest {
    static let sandboxTitle = "Git Issues Sandbox"

    static func run() async throws {
        // Two independent clients: "A" makes changes like the app would, "B" stands in for a teammate.
        let (dbA, engineA, statusA, _) = try await makeEngine()
        let (dbB, engineB, _, apiB) = try await makeEngine()
        try await engineA.refreshProjects()
        try await engineB.refreshProjects()
        let project = try findProject(dbA, title: sandboxTitle)
        guard project.title == sandboxTitle else { throw CLIError("Refusing to write to \(project.title).") }
        try await engineA.pull(projectId: project.id)
        try await engineB.pull(projectId: project.id)

        var failures = 0
        func check(_ name: String, _ condition: Bool) {
            print(condition ? "  ok    \(name)" : "  FAIL  \(name)")
            if !condition { failures += 1 }
        }
        func item(_ db: AppDatabase, _ number: Int) throws -> Item {
            guard let item = try db.reader.read({ try Item.filter(Column("number") == number && Column("projectId") == project.id).fetchOne($0) }) else {
                throw CLIError("Issue #\(number) not found locally.")
            }
            return item
        }
        func options(_ kind: OptionKind) throws -> [FieldOption] {
            try dbA.reader.read {
                try FieldOption.filter(Column("projectId") == project.id && Column("kind") == kind.rawValue).order(Column("position")).fetchAll($0)
            }
        }
        func enqueue(_ mutations: Mutation...) throws {
            try dbA.writer.write { db in
                for mutation in mutations { try Outbox.enqueue(db, mutation) }
            }
        }
        /// GitHub's project reads lag behind writes, at times for half a minute; poll B until it sees what we expect.
        func eventually(_ name: String, _ predicate: () throws -> Bool) async throws {
            for _ in 0..<24 {
                try await engineB.pull(projectId: project.id)
                if try predicate() {
                    check(name, true)
                    return
                }
                try await Task.sleep(for: .seconds(1.5))
            }
            check(name, false)
        }

        let fresh = try await dbA.reader.read { try Project.fetchOne($0, key: project.id)! }
        guard let statusField = fresh.statusFieldId, let priorityField = fresh.priorityFieldId else {
            throw CLIError("Sandbox project needs Status and Priority fields.")
        }
        let statuses = try options(.status)
        let priorities = try options(.priority)
        func status(_ name: String) throws -> FieldOption {
            guard let option = statuses.first(where: { $0.name == name }) else { throw CLIError("No status \(name)") }
            return option
        }

        print("1. Status and priority")
        let target = try item(dbA, 16)
        let originalStatus = target.statusId
        let inReview = try status("In Review")
        try enqueue(
            .setField(.init(itemId: target.id, projectId: project.id, fieldId: statusField, kind: .status, optionId: inReview.id, base: target.statusId)),
            .setField(.init(itemId: target.id, projectId: project.id, fieldId: priorityField, kind: .priority, optionId: priorities.first?.id, base: target.priorityId))
        )
        check("applied locally at once", try item(dbA, 16).statusId == inReview.id)
        try await engineA.pushPending()
        try await eventually("teammate sees new status and priority") {
            let seen = try item(dbB, 16)
            return seen.statusId == inReview.id && seen.priorityId == priorities.first?.id
        }

        print("2. Reorder")
        let anchor = try item(dbA, 5)
        try enqueue(
            .setField(.init(itemId: target.id, projectId: project.id, fieldId: statusField, kind: .status, optionId: anchor.statusId, base: inReview.id)),
            .move(.init(itemId: target.id, projectId: project.id, afterItemId: anchor.id))
        )
        try await engineA.pushPending()
        try await eventually("teammate sees the card directly below #5") {
            let all = try dbB.reader.read { try Item.filter(Column("projectId") == project.id).order(Column("position")).fetchAll($0) }
            guard let index = all.firstIndex(where: { $0.number == 5 }), index + 1 < all.count else { return false }
            return all[index + 1].number == 16
        }

        print("3. Title, labels, assignees")
        let stamp = String(Int(Date().timeIntervalSince1970) % 100000)
        let newTitle = "Markdown editor for descriptions and comments (\(stamp))"
        let viewer = dbA.viewer()!.person
        let labels = try await dbA.reader.read { db in try Item.fetchAll(db).flatMap(\.labels) }
        let apiLabel = labels.first { $0.name == "api" }!
        try enqueue(
            .setTitle(.init(itemId: target.id, contentId: target.contentId!, value: newTitle, base: target.title)),
            .editLabels(.init(contentId: target.contentId!, add: [apiLabel], remove: [])),
            .editAssignees(.init(contentId: target.contentId!, add: [viewer], remove: []))
        )
        try await engineA.pushPending()
        try await eventually("teammate sees title, label and assignee") {
            let seen = try item(dbB, 16)
            return seen.title == newTitle && seen.labels.contains { $0.name == "api" } && seen.assignees.contains { $0.login == viewer.login }
        }

        print("4. Independent changes to one card merge")
        // Teammate changes priority directly on GitHub while we change status without having seen it.
        let low = priorities.last!
        try await apiB.setFieldValue(projectId: project.id, itemId: target.id, fieldId: priorityField, optionId: low.id)
        let backlog = try status("Backlog")
        try enqueue(.setField(.init(itemId: target.id, projectId: project.id, fieldId: statusField, kind: .status, optionId: backlog.id, base: try item(dbA, 16).statusId)))
        try await engineA.pushPending()
        try await eventually("both the teammate's priority and our status stick") {
            let seen = try item(dbB, 16)
            return seen.statusId == backlog.id && seen.priorityId == low.id
        }

        print("5. Description edited on both sides")
        let base = "Line one\n\nLine two\n\nLine three"
        try await apiB.updateIssue(contentId: target.contentId!, body: base)
        try await engineA.forcePull(projectId: project.id)
        check("local copy has the base text", try item(dbA, 16).body == base)
        // Non-overlapping edits merge.
        try await apiB.updateIssue(contentId: target.contentId!, body: "Line one (theirs)\n\nLine two\n\nLine three")
        try enqueue(.setBody(.init(itemId: target.id, contentId: target.contentId!, value: "Line one\n\nLine two\n\nLine three (mine)", base: base)))
        try await engineA.pushPending()
        let merged = try await apiB.issueText(contentId: target.contentId!).body
        check("non-overlapping edits were merged", merged == "Line one (theirs)\n\nLine two\n\nLine three (mine)")
        // Overlapping edits are held back for the user.
        try await engineA.forcePull(projectId: project.id)
        let current = try item(dbA, 16).body
        try await apiB.updateIssue(contentId: target.contentId!, body: current.replacingOccurrences(of: "Line two", with: "Line two (theirs)"))
        try enqueue(.setBody(.init(itemId: target.id, contentId: target.contentId!, value: current.replacingOccurrences(of: "Line two", with: "Line two (mine)"), base: current)))
        try await engineA.pushPending()
        let conflicts = try await dbA.reader.read { try OutboxEntry.filter(Column("state") == OutboxState.conflict.rawValue).fetchAll($0) }
        check("overlapping edit is held as a conflict, not sent", conflicts.count == 1)
        let remoteNow = try await apiB.issueText(contentId: target.contentId!).body
        check("GitHub still has the teammate's text", remoteNow.contains("Line two (theirs)"))
        check("screen still shows our text", try item(dbA, 16).body.contains("Line two (mine)"))
        if let conflict = conflicts.first {
            try await dbA.writer.write { try Outbox.resolveConflict($0, entryId: conflict.id!, keepMine: true) }
            try await engineA.pushPending()
            let after = try await apiB.issueText(contentId: target.contentId!).body
            check("\"keep mine\" sends our text", after.contains("Line two (mine)"))
        }

        print("6. Comment")
        let commentId = LocalID.make()
        try enqueue(.addComment(.init(commentId: commentId, contentId: target.contentId!, body: "Self-test comment \(stamp)", author: viewer, createdAt: Date())))
        try await engineA.pushPending()
        let detail = try await apiB.issueDetail(contentId: target.contentId!)
        check("comment arrived", detail.comments.contains { $0.body == "Self-test comment \(stamp)" })

        print("7. Create an issue, with a follow-up change queued before it exists")
        let repo = try await dbA.reader.read { try RepoRef.filter(Column("projectId") == project.id).fetchOne($0)! }
        let parent = try item(dbA, 9)
        let tempItem = LocalID.make(), tempContent = LocalID.make()
        try enqueue(
            .createIssue(.init(
                itemId: tempItem, contentId: tempContent, projectId: project.id, repoId: repo.id, repo: repo.nameWithOwner,
                title: "Self-test issue \(stamp)", body: "Created by gi-cli selftest.",
                statusFieldId: statusField, statusId: try status("Todo").id, priorityFieldId: priorityField, priorityId: low.id,
                assignees: [viewer], labels: [apiLabel], parentContentId: parent.contentId, parentNumber: parent.number, parentTitle: parent.title,
                author: viewer.login, createdAt: Date()
            )),
            .setField(.init(itemId: tempItem, projectId: project.id, fieldId: statusField, kind: .status, optionId: inReview.id, base: try status("Todo").id))
        )
        let shownLocally = try await dbA.reader.read { try Item.fetchOne($0, key: tempItem) } != nil
        check("new issue shows locally before it exists on GitHub", shownLocally)
        try await engineA.pushPending()
        let remap = await MainActor.run { statusA.idRemaps[tempItem] }
        check("temporary id was replaced", remap != nil)
        var createdNumber: Int?
        try await eventually("teammate sees the new issue, in In Review, as a sub-issue of #9") {
            let found = try dbB.reader.read { try Item.filter(Column("title") == "Self-test issue \(stamp)").fetchOne($0) }
            createdNumber = found?.number
            return found?.statusId == inReview.id && found?.parentNumber == 9 && found?.priorityId == low.id
        }

        print("8. Close and reopen")
        if let createdNumber {
            let created = try item(dbA, createdNumber)
            try enqueue(.setState(.init(contentId: created.contentId!, closed: true, reason: "NOT_PLANNED")))
            try await engineA.pushPending()
            try await eventually("teammate sees it closed as not planned") {
                let seen = try item(dbB, createdNumber)
                return seen.state == "CLOSED" && seen.stateReason == "NOT_PLANNED"
            }
        }

        print("8b. Parent and blocker")
        if let createdNumber {
            let created = try item(dbA, createdNumber)
            let other = try item(dbA, 5)
            try enqueue(.setParent(.init(
                child: created.summary!, parentId: other.contentId, parentNumber: other.number, parentTitle: other.title, base: created.parentId
            )))
            check("moved under #5 at once", try item(dbA, createdNumber).parentNumber == 5)
            try await engineA.pushPending()
            try await eventually("teammate sees it under #5 instead of #9") { try item(dbB, createdNumber).parentNumber == 5 }
            try enqueue(.setParent(.init(child: try item(dbA, createdNumber).summary!, parentId: nil, base: other.contentId)))
            try await engineA.pushPending()
            try await eventually("teammate sees it without a parent") { try item(dbB, createdNumber).parentId == nil }

            try enqueue(.setBlocking(.init(blocked: try item(dbA, createdNumber).summary!, blocker: other.summary!, isBlocked: true, base: false)))
            try await engineA.pushPending()
            let blockedDetail = try await apiB.issueDetail(contentId: created.contentId!)
            check("GitHub lists #5 as blocking it", blockedDetail.links.contains { $0.relation == .blockedBy && $0.number == 5 })
            try enqueue(.setBlocking(.init(blocked: try item(dbA, createdNumber).summary!, blocker: other.summary!, isBlocked: false, base: true)))
            try await engineA.pushPending()
            let unblockedDetail = try await apiB.issueDetail(contentId: created.contentId!)
            check("and no longer after that", !unblockedDetail.links.contains { $0.relation == .blockedBy })
        }

        print("9. An issue on no board, then onto the board")
        let looseTemp = LocalID.make(), looseTempContent = LocalID.make()
        let looseTitle = "Self-test issue on no board \(stamp)"
        try enqueue(.createIssue(.init(
            itemId: looseTemp, contentId: looseTempContent, projectId: nil, repoId: repo.id, repo: repo.nameWithOwner,
            title: looseTitle, body: "Created by gi-cli selftest.", assignees: [], labels: [], author: viewer.login, createdAt: Date()
        )))
        try await engineA.pushPending()
        let looseId = await MainActor.run { statusA.idRemaps[looseTemp] }
        let looseContent = await MainActor.run { statusA.idRemaps[looseTempContent] }
        check("it keeps an id of its own, without a project", looseId?.hasPrefix(Item.withoutProjectPrefix) == true)
        var looseSeen: Item?
        for _ in 0..<12 {
            try await engineB.pullRepository(repo.id)
            looseSeen = try await dbB.reader.read { try Item.filter(Column("title") == looseTitle).fetchOne($0) }
            if looseSeen != nil { break }
            try await Task.sleep(for: .seconds(1.5))
        }
        check("teammate reads it from the repository, on no board", looseSeen != nil && looseSeen?.projectId == nil)
        if let looseId, let looseContent {
            try enqueue(.addToProject(.init(
                itemId: looseId, contentId: looseContent, projectId: project.id, statusFieldId: statusField, statusId: backlog.id
            )))
            check("on the board at once", try await dbA.reader.read { try Item.fetchOne($0, key: looseId)?.projectId } == project.id)
            try await engineA.pushPending()
            try await eventually("teammate sees it on the board in Backlog, and no longer on no board") {
                let copies = try dbB.reader.read { try Item.filter(Column("title") == looseTitle).fetchAll($0) }
                return copies.count == 1 && copies[0].projectId == project.id && copies[0].statusId == backlog.id
            }
            try enqueue(.setState(.init(contentId: looseContent, closed: true, reason: "NOT_PLANNED")))
            try await engineA.pushPending()
        }

        print("10. Status columns")
        let before = statuses.map { RemoteOption(id: $0.id, name: $0.name, color: $0.color, descr: $0.descr) }
        try await engineA.updateOptions(projectId: project.id, fieldId: statusField, kind: .status, options: before + [RemoteOption(id: nil, name: "Self-test column", color: "PINK")])
        var now = try options(.status)
        check("column added", now.last?.name == "Self-test column")
        check("existing columns kept their ids", Array(now.dropLast().map(\.id)) == statuses.map(\.id))
        var renamed = now.map { RemoteOption(id: $0.id, name: $0.name, color: $0.color, descr: $0.descr) }
        renamed[renamed.count - 1].name = "Renamed column"
        try await engineA.updateOptions(projectId: project.id, fieldId: statusField, kind: .status, options: renamed)
        now = try options(.status)
        check("column renamed in place", now.last?.name == "Renamed column")
        try await engineA.updateOptions(projectId: project.id, fieldId: statusField, kind: .status, options: before)
        now = try options(.status)
        check("column removed", now.map(\.name) == statuses.map(\.name))
        try await engineB.forcePull(projectId: project.id)
        check("cards kept their status through all of that", try item(dbB, 9).statusId == (try item(dbA, 9)).statusId && (try item(dbB, 9)).statusId != nil)

        print("11. Restore")
        let restore = try item(dbA, 16)
        try enqueue(
            .setField(.init(itemId: restore.id, projectId: project.id, fieldId: statusField, kind: .status, optionId: originalStatus, base: restore.statusId)),
            .setTitle(.init(itemId: restore.id, contentId: restore.contentId!, value: "Markdown editor for descriptions and comments", base: restore.title)),
            .editLabels(.init(contentId: restore.contentId!, add: [], remove: [apiLabel]))
        )
        try await engineA.pushPending()
        let left = try await dbA.reader.read { try OutboxEntry.filter(Column("state") != OutboxState.sent.rawValue).fetchCount($0) }
        check("nothing left unsent", left == 0)

        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
        if failures > 0 { exit(1) }
    }
}
