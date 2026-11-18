import Foundation
import Testing
@testable import GitIssuesKit

@Suite("Issue identity across project changes")
struct IssueReferenceTests {
    private func project(_ id: String, closed: Bool = false) -> Project {
        Project(id: id, ownerLogin: "octo", ownerIsOrg: false, number: 1, title: id, url: "", closed: closed, viewerCanUpdate: true)
    }

    private func item(_ id: String, project: String?, content: String? = "I1") -> Item {
        Item(id: id, projectId: project, kind: .issue, position: 0, contentId: content, number: 1, title: "Issue", body: "", state: "OPEN")
    }

    @Test("Removing the open card follows the same issue on another open project")
    func anotherProject() {
        let original = item("card1", project: "P1")
        let other = item("card2", project: "P2")
        let projects = [project("P1"), project("P2")]
        #expect(IssueReference(original).resolve(in: [other], projects: projects)?.id == other.id)
        #expect(IssueReference.replacements(from: [original, other], to: [other], projects: projects) == [original.id: other.id])
    }

    @Test("Last membership removal follows the retained issue instead of a cached closed project")
    func lastProject() {
        let original = item("card1", project: "P1")
        let loose = item("loose", project: nil)
        let closed = item("closed", project: "Closed")
        #expect(IssueReference(original).resolve(in: [closed, loose], projects: [project("Closed", closed: true)])?.id == loose.id)
    }

    @Test("Adding an issue without a project and server ID remaps preserve its identity")
    func additionAndRemap() {
        let loose = item("loose", project: nil)
        let added = item("local-card", project: "P1")
        let server = item("PVTI_1", project: "P1")
        let projects = [project("P1")]
        #expect(IssueReference(loose).resolve(in: [added], projects: projects)?.id == added.id)
        #expect(IssueReference(added).resolve(in: [server], projects: projects)?.id == server.id)
        #expect(IssueReference.replacements(from: [added], to: [server], projects: projects) == [added.id: server.id])
    }

    @Test("Issue editors keep their view identity through project changes and creation acknowledgement")
    func editorIdentity() {
        let local = IssueReference(item("local-card", project: "P1", content: "local-content"))
        let server = IssueReference(item("PVTI_1", project: "P1", content: "I1"))
        let loose = IssueReference(item("loose", project: nil, content: "I1"))
        let remaps = ["local-card": "PVTI_1", "local-content": "I1"]
        #expect(local.viewID(remaps: [:]) == server.viewID(remaps: remaps))
        #expect(server.viewID(remaps: remaps) == loose.viewID(remaps: remaps))
        #expect(server.viewID(remaps: [:]) == loose.viewID(remaps: [:]))
        #expect(server.viewID(remaps: [:]) != IssueReference(item("other", project: "P1", content: "I2")).viewID(remaps: [:]))
    }

    @Test("Navigation stays on its live card until the acknowledged replacement is observed")
    func navigationWaitsForSnapshot() {
        let local = item("local-card", project: "P1", content: "local-content")
        let server = item("PVTI_1", project: "P1", content: "I1")
        let remaps = ["local-card": "PVTI_1", "local-content": "I1"]
        #expect(IssueReference.observedRemaps(remaps, in: [local]).isEmpty)
        #expect(IssueReference.observedRemaps(remaps, in: [server]) == [local.id: server.id])
        // A delayed editor callback can still resolve the original while the observation is behind.
        #expect(IssueReference(local).resolve(in: [local], projects: [project("P1")]) == local)
        #expect(ProjectFieldTarget(item: local, fieldId: "version").resolve(in: [local]) == local)
    }

    @Test("Navigation already following creation acknowledgement reaches the retained loose issue")
    func acknowledgedCardRemovedBeforeSnapshot() {
        let original = item("local-card", project: "P1", content: "local-content")
        let kept = item(Item.idWithoutProject("I1"), project: nil, content: "I1")
        let remaps = ["local-card": "PVTI_created", "local-content": "I1"]
        let replacements = IssueReference.replacements(from: [original], to: [kept], projects: [project("P1")], remaps: remaps)
        #expect(replacements[original.id] == kept.id)
        #expect(replacements["PVTI_created"] == kept.id)
    }

    @Test("A deleted issue or a draft without content is not replaced with another issue")
    func genuineDeletion() {
        let original = item("card1", project: "P1")
        let unrelated = item("card2", project: "P1", content: "I2")
        #expect(IssueReference(original).resolve(in: [unrelated], projects: [project("P1")]) == nil)
        #expect(IssueReference(item("draft", project: "P1", content: nil)).resolve(in: [unrelated], projects: []) == nil)
        #expect(IssueReference.replacements(from: [original], to: [unrelated], projects: []).isEmpty)
    }

    @Test("An open issue and its field editor follow both IDs assigned during creation")
    func createdIssueRemap() {
        let original = item("local-card", project: "P1", content: "local-content")
        let server = item("PVTI_1", project: "P1", content: "I1")
        let remaps = [original.id: server.id, "local-content": "I1"]
        let target = ProjectFieldTarget(item: original, fieldId: "version")
        #expect(IssueReference(original).remapping(remaps).resolve(in: [server], projects: [project("P1")]) == server)
        #expect(target.remapping(remaps).resolve(in: [server]) == server)
        #expect(IssueReference.replacements(from: [original], to: [server], projects: [project("P1")], remaps: remaps) == [original.id: server.id])
        var anotherProject = server
        anotherProject.projectId = "P2"
        #expect(target.remapping(remaps).resolve(in: [anotherProject]) == nil)
    }

    @Test("A field target cannot switch projects when its membership is removed")
    func exactFieldTarget() {
        let original = item("card1", project: "P1")
        let other = item("card2", project: "P2")
        let target = ProjectFieldTarget(item: original, fieldId: "version")
        #expect(target.resolve(in: [other]) == nil)
        let server = item("PVTI_new", project: "P1")
        #expect(target.resolve(in: [other, server])?.id == server.id)
    }

    @Test("Detached references use the Inbox until the issue is kept on a project")
    func detachedInboxReference() throws {
        var entry = InboxEntry(id: "notification", reason: "mention", unread: true, updatedAt: Date(), subjectType: "Issue",
                               title: "Inbox-only issue", repo: "octo/outside", number: 93)
        entry.contentId = "I1"
        let detached = try #require(Item(detached: entry))
        let reference = IssueReference(detached)
        #expect(reference.resolve(in: [], projects: [], inbox: [entry]) == detached)
        let card = item("local-card", project: "P1")
        #expect(reference.resolve(in: [card], projects: [project("P1")], inbox: [entry])?.id == card.id)
        #expect(reference.resolve(in: [], projects: [], inbox: []) == nil)
        entry.missing = true
        #expect(reference.resolve(in: [], projects: [], inbox: [entry]) == nil)
    }

    @Test("A stale Inbox notification cannot resurrect a removed ordinary issue")
    func ordinaryReferenceDoesNotUseInboxFallback() {
        var entry = InboxEntry(id: "notification", reason: "mention", unread: true, updatedAt: Date(), subjectType: "Issue",
                               title: "Old notification", repo: "octo/outside", number: 93)
        entry.contentId = "I1"
        let reference = IssueReference(item("card", project: "P1"))
        #expect(reference.resolve(in: [], projects: [project("P1")], inbox: [entry]) == nil)
    }
}
