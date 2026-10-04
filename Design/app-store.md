# App Store listing

Texts and answers for App Store Connect, iPhone and iPad. Screenshots come from `Tools/app-store-screenshots.sh`
(6.9-inch iPhone and 13-inch iPad, in `Design/screenshots/app-store`).

## Basics

| Field | Value |
|---|---|
| Name | Issues (App Store names are unique; if it is taken, "Issues for GitHub" matches the repository) |
| Subtitle | Issues and boards for GitHub |
| Bundle ID | `com.lukaskbl.GitIssues` |
| SKU | `git-issues-ios` |
| Primary category | Developer Tools |
| Secondary category | Productivity |
| Age rating | 4+ (no objectionable content; answer "No" to every question) |
| Price | Free |
| Privacy policy URL | The published [PRIVACY.md](../PRIVACY.md), e.g. `https://github.com/lukaskaibel/issues-for-github/blob/main/PRIVACY.md` |
| Support URL | `https://github.com/lukaskaibel/issues-for-github/issues` |
| Copyright | 2026 Lukas Kaibel |

## App Privacy ("nutrition label")

Data collection: **"No, we do not collect data from this app."** The app talks only to GitHub with the user's own
login and has no server, analytics or ads. GitHub is the service the user signs in to, not a third party the developer
shares data with.

## Export compliance

`ITSAppUsesNonExemptEncryption` is `NO` in the Info.plist: the app only uses HTTPS through Apple's frameworks.

## Promotional text (170 characters)

Your GitHub Projects as a board and a list, with swipes, the issue menu on a long press, and edits that show at once,
even offline.

## Description

Issues is a fast, native client for GitHub Issues and GitHub Projects: calm to look at and quick to drive.
Everything stays in GitHub, so teammates who don't use the app see the same issues and boards on github.com.

ON IPHONE
• My Issues across all your projects, grouped by status
• Every project as a list with sections that fold and headers that stay in place
• Swipe right to mark an issue done, swipe left to assign it to yourself or delete it
• Touch and hold an issue for status, priority, assignee, labels, links and more
• Edit titles and descriptions in place, with Markdown styled as you type
• Sub-issues, comments, labels and assignees
• Search across every project by title or number

ON IPAD
• A sidebar with every project, and the board with drag and drop
• Issues open beside their properties, as on the Mac
• Keyboard shortcuts: J and K to move between issues, S P A L to change status, priority, assignee and labels,
  ⌘N for a new issue, ⌘K to search

FAST AND RELIABLE
• Every change shows instantly and is sent to GitHub in the background
• Works offline: changes wait and go out when you're back online
• Careful with other people's work: when someone else changed the same text, nothing is overwritten

PRIVATE
• No account, no server, no tracking. Your login stays in your iCloud Keychain and is only sent to GitHub.
• Signed in on the Mac app? Your iPhone and iPad sign in by themselves.

Try it without an account: "Explore with Sample Data" shows two sample projects.

Issues is not affiliated with or endorsed by GitHub.

## Keywords (100 characters at most; other apps' names aren't allowed here)

github,issues,projects,kanban,board,tasks,todo,developer,tracker,bugs,pull requests,agile,sprint

## What's new (first release)

The first version for iPhone and iPad: your GitHub Projects as lists and boards, with swipe actions, quick menus,
in-place editing, sub-issues and comments, offline changes, and the login shared with the Mac.

## Notes for App Review

Issues is a client for GitHub Issues and GitHub Projects (Guideline 4.8 does not apply: users sign in to their
own GitHub account to see their own content).

To review without a GitHub account, tap **Explore with Sample Data** on the first screen. It shows two sample
projects stored on the device; every feature works there, and nothing is sent anywhere. To leave it, open the account
menu (the avatar at the top left) and tap **Leave Sample Data**.

To review with GitHub, sign in with the personal access token below (a test account with a sample project):

    Token: <create one for a test account and paste it here>

Background refresh is used to update issues now and then while the app is closed.
