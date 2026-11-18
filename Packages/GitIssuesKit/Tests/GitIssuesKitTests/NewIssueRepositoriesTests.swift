import Foundation
import Testing
@testable import GitIssuesKit

@Suite("The repository of a new issue")
struct NewIssueRepositoriesTests {
    private func repo(_ name: String) -> RepoRef {
        RepoRef(id: name, nameWithOwner: name, projectId: "")
    }

    private func emptyBoard(synced: Bool = true, canEdit: Bool = true, yours: [RepoRef]?) -> NewIssueRepositories {
        .ofEmptyBoard(synced: synced, canEdit: canEdit, ownerLogin: "Acme", yours: yours)
    }

    @Test func aBoardStillBeingReadIsNotCalledEmpty() {
        #expect(emptyBoard(synced: false, yours: [repo("me/one")]) == .loading)
    }

    @Test func aBoardWithoutRepositoriesOffersYours() {
        #expect(emptyBoard(yours: nil) == .loading)
        #expect(emptyBoard(yours: [repo("me/one")]) == .yours([repo("me/one")]))
    }

    @Test func theRepositoriesOfTheBoardsOwnerComeFirst() {
        let yours = [repo("me/recent"), repo("acme/app"), repo("other/acme"), repo("ACME/web")]
        #expect(emptyBoard(yours: yours).choices.map(\.id) == ["acme/app", "ACME/web", "me/recent", "other/acme"])
    }

    @Test func nothingIsOfferedWhereNoIssueCouldBeMade() {
        // A board you can only read wouldn't take the issue; with no repository there is nowhere to put it.
        #expect(emptyBoard(canEdit: false, yours: [repo("me/one")]) == .unavailable)
        #expect(emptyBoard(yours: []) == .unavailable)
    }

    @Test func aRepositoryThatArrivesLaterIsChosen() {
        // The form opened with none; the board's first read then found its one repository.
        let found = NewIssueRepositories.board([repo("acme/app")])
        #expect(found.settled(current: nil, preferred: nil) == "acme/app")
    }

    @Test func aChoiceStillOnOfferIsKept() {
        let board = NewIssueRepositories.board([repo("acme/app"), repo("acme/web")])
        #expect(board.settled(current: "acme/web", preferred: "acme/app") == "acme/web")
    }

    @Test func aChoiceNoLongerOnOfferGivesWayToTheUsualOne() {
        let board = NewIssueRepositories.board([repo("acme/app"), repo("acme/web")])
        #expect(board.settled(current: "other/repo", preferred: "acme/web") == "acme/web")
    }

    @Test func oneOfSeveralOfYoursIsLeftToYou() {
        let yours = NewIssueRepositories.yours([repo("me/one"), repo("me/two")])
        #expect(yours.settled(current: nil, preferred: nil) == nil)
        #expect(yours.settled(current: "me/two", preferred: nil) == "me/two")
    }

    @Test func yourOnlyRepositoryIsChosen() {
        #expect(NewIssueRepositories.yours([repo("me/one")]).settled(current: nil, preferred: nil) == "me/one")
    }

    @Test func noRepositoryIsHeldWhileNoneIsOnOffer() {
        // Otherwise Create would be on for a repository the board doesn't have, and do nothing.
        #expect(NewIssueRepositories.loading.settled(current: "old/repo", preferred: "old/repo") == nil)
        #expect(NewIssueRepositories.unavailable.settled(current: "old/repo", preferred: nil) == nil)
    }

    @Test func onlyRepositoriesThatTakeIssuesAreListed() async throws {
        let github = FakeGitHub([])
        github.viewerRepositories = [
            ["id": "R1", "nameWithOwner": "me/one", "hasIssuesEnabled": true],
            NSNull(),
            ["id": "R2", "nameWithOwner": "me/no-issues", "hasIssuesEnabled": false],
            ["id": "R3", "nameWithOwner": "acme/app", "hasIssuesEnabled": true],
        ]
        let repositories = try await github.api.viewerRepositories()
        #expect(repositories.map(\.nameWithOwner) == ["me/one", "acme/app"])
    }
}
