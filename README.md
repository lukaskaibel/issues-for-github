<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Design/icon-dark.png">
    <img src="Design/icon.png" width="128" height="128" alt="Git Issues app icon">
  </picture>
</p>

<h1 align="center">Git Issues</h1>

<p align="center">
  A fast, native app for GitHub Issues on Mac, iPhone and iPad, with the board, keyboard flow and polish of Linear.<br>
  Everything stays in GitHub, so teammates who don't use the app notice nothing.
</p>

<p align="center">
  <img alt="Platform: macOS 27 or later" src="https://img.shields.io/badge/macOS-27%2B-111214">
  <img alt="Platform: iOS and iPadOS 27 or later" src="https://img.shields.io/badge/iOS%20%26%20iPadOS-27%2B-111214">
  <img alt="Apple silicon" src="https://img.shields.io/badge/Apple%20silicon-native-111214">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-5B63D3"></a>
  <a href="CHANGELOG.md"><img alt="Version 0.1.0" src="https://img.shields.io/badge/version-0.1.0-5B63D3"></a>
</p>

![The board, dark appearance](Design/screenshots/board-dark.png)

> **New: Git Issues for iPhone and iPad.** The same app, built from the same project, with the same sync, offline
> queue and actions: lists with swipes and the issue menu on iPhone, the board with drag and drop on iPad.
> [See it below.](#iphone-and-ipad)

> **Status: early.** Version 0.1.0 covers the daily work of moving, editing and creating issues on the Mac; the
> iPhone and iPad app comes with 0.2.0. There are no downloadable builds yet; you build it from source (five minutes,
> see below). "Git Issues" is a working title.

## Why

GitHub Issues holds the data most teams already have. Its interface is slow to drive: every status change is a
page load and a menu. Git Issues puts a native, keyboard-first front end on the same data. It reads and writes
GitHub Projects, issues, sub-issues, labels, assignees and comments, and stores nothing anywhere else.

## What it does

| | |
|---|---|
| ![Dragging a card](Design/screenshots/drag-dark.png) | ![An issue](Design/screenshots/issue-dark.png) |
| **Board** with drag and drop: cards lift, tilt and settle with springs, and neighbours make room. | **Issues** with Markdown, sub-issues, comments and every property one click or one key away. |
| ![Command palette](Design/screenshots/palette-dark.png) | ![List, light appearance](Design/screenshots/list-light.png) |
| **Command palette** (⌘K) for every action and for jumping to any issue. | **List** grouped by status. Light, dark, or following the system. |

- **Board and list** for every GitHub Project you can see, plus **My Issues** across all of them.
- **Instant.** Every change is written to a local database first and shows in the same frame. GitHub is updated in
  the background.
- **Works offline.** Changes queue up and are sent when the connection returns.
- **Careful with other people's work.** Changes are sent field by field, descriptions edited in two places are
  merged, and when a merge isn't possible nothing is overwritten: you choose.
- **Status columns are yours to shape.** Add, rename, recolour and remove columns from the board, and drag a column
  by its header to move it; they are the project's Status field on GitHub. In the list, drag a section by its header
  to arrange the list your way (that order is a preference on your Mac and leaves GitHub alone).
- **Keyboard first.** Single keys change status, priority, assignee and labels. Back and forward work like a
  browser: ⌘[ and ⌘], the side buttons of a mouse, or a two-finger swipe.
- **Native.** Swift and SwiftUI, with AppKit where it matters for smoothness. Apple silicon only.
- **On iPhone and iPad too.** One app for all three: the same sync, offline queue and actions, with an interface
  built from the system's own parts (see below).

## iPhone and iPad

<p align="center">
  <img src="Design/screenshots/app-store/iphone/1-my-issues.png" width="200" alt="My Issues on iPhone">
  <img src="Design/screenshots/app-store/iphone/2-issue.png" width="200" alt="An issue on iPhone">
  <img src="Design/screenshots/app-store/iphone/4-menu.png" width="200" alt="The issue menu on a long press">
  <img src="Design/screenshots/app-store/iphone/7-project-dark.png" width="200" alt="A project in the dark appearance">
</p>
<p align="center">
  <img src="Design/screenshots/app-store/ipad/1-board.png" width="820" alt="The board on iPad, with the sidebar">
</p>

The iPhone and iPad app is the same app as the Mac's, built from the same project: sync, offline queue, conflict
handling and every action are shared code, and so are the colours, status circles, priority bars, labels and avatars.
The interface uses the system's own parts.

- **iPhone:** a list per project and My Issues, grouped by status, with sections that fold and headers that stay
  pinned. Tabs for My Issues, Projects and Search. Swipe right to mark an issue done, swipe left to assign it to
  yourself or delete it, touch and hold for the same menu as the Mac's right-click. In an issue, the title and
  description are edited in place (Markdown is styled as you type), the properties are chips under the title, and the
  comment field stays at the bottom as in Messages.
- **iPad:** the tabs become a sidebar with every project as an entry, as on the Mac. Projects open as a board or a
  list; cards are moved with drag and drop (touch and hold, then drag). An issue shows its properties in a column
  beside it. With a keyboard, the Mac's shortcuts work: J and K, S P A L I, ⌘1 ⌘2 ⌘3, ⌘K, ⌘N, ⌘R, ⌘[ and ⌘↵.
- **Sample data:** "Explore with Sample Data" on the sign-in screen shows two sample projects without a GitHub account.
  Nothing there is sent anywhere.
- **In the background:** changes made just before locking the phone are still sent, and iOS refreshes the app now and
  then so it opens up to date. There are no push notifications: GitHub can't push to an app without a server of its
  own, which Git Issues deliberately doesn't have.

## How it maps to GitHub

Nothing is invented on top of GitHub. Each concept is the GitHub feature it looks like:

| In the app | On GitHub |
|---|---|
| Board | A GitHub Project |
| Columns | The project's **Status** field |
| Moving a card to a "done" or "cancelled" column | Status changes, and the issue is closed as *completed* or *not planned* |
| Priority | A single-select project field named **Priority** (the app can add it for you) |
| Card order | The item's position in the project |
| Sub-issues, labels, assignees, comments | The native GitHub features |

Only issues that are in a Project appear. What a column means (backlog, in progress, done, cancelled) is inferred
from its name, since GitHub stores only the label.

## Offline and conflicts

GitHub cannot push changes to a desktop app, so the app asks for changes every 15 seconds while it is in front, and
immediately when you return to it. Other people's changes therefore appear with a short delay.

When you and someone else change the same issue:

1. **Different fields:** both changes stick. You set the priority, they move the card; nobody loses anything.
2. **The same field:** yours is applied when you reconnect, and a notice offers to switch to theirs.
3. **The same description or title:** edits to different lines are merged. If they overlap, your version is kept on
   screen but not sent until you pick "Keep mine" or "Use the GitHub version".
4. **The issue was deleted or removed from the project:** your queued changes are dropped and you are told.

## Getting started

### Requirements

- A Mac with Apple silicon running macOS 27 or later
- Xcode 27 or later
- A GitHub account with at least one [Project](https://docs.github.com/issues/planning-and-tracking-with-projects)

### Build and run

```bash
git clone https://github.com/lukaskaibel/git-issues-mac-app.git
cd git-issues-mac-app
open GitIssues.xcodeproj
```

Choose **My Mac**, an iPhone or iPad simulator, or your own device as the destination and press **Run** (⌘R) in Xcode.
Dependencies are fetched automatically on the first build. Running on your own iPhone or iPad needs your team in
`Config/Local.xcconfig`; the simulator doesn't.

To use the app day to day without Xcode, build an optimised copy instead. The script quits a running copy and opens
the new one, so you can run it again after pulling changes:

```bash
Tools/run-release.sh
```

Without any setup the app is signed to run on your Mac only, which is all a local build needs. To sign with your own
Apple Developer team, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and fill in your team ID.

To put the iPhone and iPad app on TestFlight, create the app in App Store Connect with the bundle identifier
`com.lukaskbl.GitIssues`, sign in to your Apple ID under Xcode › Settings › Accounts, and run:

```bash
Tools/testflight.sh
```

For the App Store listing, [Design/app-store.md](Design/app-store.md) has the texts, the privacy answers and notes for
App Review, and this takes the screenshots on a 6.9-inch iPhone and a 13-inch iPad simulator:

```bash
Tools/app-store-screenshots.sh
```

### Signing in

The sign-in screen offers up to three ways, depending on your setup:

| Option | When to use it |
|---|---|
| **Use my GitHub CLI login** | You have [`gh`](https://cli.github.com) installed and signed in. Nothing to configure. If projects don't load, run `gh auth refresh -s project,read:org`. |
| **Personal access token** | Create a classic token with the `repo`, `project` and `read:org` scopes. It is stored in your Mac's keychain. |
| **Sign in with GitHub** | Shown when the build has an OAuth client ID. Register a GitHub OAuth app with the device flow enabled and set its client ID as `GITHUB_CLIENT_ID` in `Config/Local.xcconfig`. |

On iPhone and iPad there is no GitHub CLI; sign in with GitHub or a token there, or let the Mac's login carry over:

- **The login is shared through iCloud Keychain.** Signed in on the Mac, the iPhone and iPad sign in by themselves (and
  the other way round). The Mac needs a build signed with your team for that: set `GI_MAC_ENTITLEMENTS` in
  `Config/Local.xcconfig` (see the example file). Signed in with the GitHub CLI, the Mac asks once whether to share it.
- **Sign Out** signs out of one device. **Sign Out Everywhere** removes the login from iCloud Keychain, which signs
  out all of them.

Your token never leaves your devices except to talk to `api.github.com`. There is no server and no analytics.

## Using it

Hover an issue or move to it with the arrow keys, then:

| Key | Action |
|---|---|
| `⌘K` or `/` | Command palette: run a command or jump to an issue |
| `C` or `⌘N` | New issue |
| `S` `P` `A` `L` | Change status, priority, assignee, labels |
| `I` | Assign to me, or unassign |
| `↑` `↓` or `J` `K` | Move through issues; `←` `→` change column on the board |
| `Return` | Open the issue; `Esc` goes back |
| `⌘[` `⌘]` | Back and forward (also mouse side buttons and two-finger swipe) |
| `G` then `B` / `L` / `M` / `P` | Go to board, list, My Issues, or switch project |
| `⌘1` `⌘2` `⌘3` | Board, list, My Issues |
| `⌘↵` | Save a description, send a comment, create the issue |
| `⌘⇧C` / `⌘⇧O` | Copy the issue's GitHub link / open it on GitHub |
| `⌘⌫` | Delete the issue (asks first; needs admin rights in the repository) |
| `⌘R` | Sync with GitHub now |
| `⌘,` | Settings: light, dark or system appearance, and the app icon |

Click an issue's priority, status, labels, assignees or sub-issue count to change it in place, or right-click
it for everything at once. In the list, click a section header to fold it.

On the board, drag cards between and within columns; press `Esc` mid-drag to put a card back. Drag a column by its
header to reorder it, hover the header for its menu (rename, colour, delete), and use **Add column** at the right
end of the board.

## Using it on iPhone and iPad

| Gesture | Action |
|---|---|
| Tap a section header | Fold it in or out |
| Swipe right on an issue | Done, or reopen |
| Swipe left on an issue | Assign to me (or unassign), delete |
| Touch and hold an issue | Status, priority, assignee and labels as submenus; copy link, share, open on GitHub, delete |
| Pull down | Sync with GitHub now |
| Tap the description | Edit it in place; the bar above the keyboard adds bold, italics, code, lists and links |
| Touch and hold a card, then drag (iPad) | Move it to another place or column |

## Not there yet

Cycles, an inbox for notifications, roadmaps, linked pull requests, file uploads and real-time updates are planned
but not built. Also good to know in 0.1.0:

- Pull requests and draft issues appear on the board and can be moved, but their text is read-only.
- Images in descriptions of private repositories may not load.
- Filtering and saved views don't exist yet.

## For contributors

```
GitIssues/                   The app target for Mac, iPhone and iPad: a few lines that show the scene, and the icons
GitIssuesUITests/            UI tests of the iPhone and iPad app, on the sample data
Packages/GitIssuesKit/
  Sources/GitIssuesKit/
    API/                     GitHub GraphQL client and sign-in
    Model/                   Records, and what column and priority names mean
    Store/                   The local SQLite database (GRDB), and the sample data
    Sync/                    Sync engine, queued changes, three-way text merge
    UI/Shared/               The model and every action, design tokens, glyphs, Markdown, the board's cards
    UI/Mac/                  The Mac's window, sidebar, AppKit issue table, palette, dropdowns and keys
    UI/iOS/                  The iPhone and iPad tabs, lists, issue screen, sheets, search and sign-in
  Sources/gi-cli/            Command-line tool for exercising sync without the UI
  Tests/                     Unit tests
Config/                      Build settings, Info.plist and entitlements
Design/                      The violet icon, earlier icon variants, screenshots
Tools/                       Icons, release builds, iOS tests, App Store screenshots and TestFlight uploads
```

Everything under `UI/Shared` and below `API`, `Model`, `Store` and `Sync` runs on all three devices, so a change there
applies everywhere. `UI/Mac` and `UI/iOS` are compiled for their platform only.

Run the unit tests, and the iPhone and iPad UI tests (they create their simulators on first use):

```bash
cd Packages/GitIssuesKit && swift test
```

```bash
Tools/test-ios.sh
```

`gi-cli selftest` runs every kind of write end to end against GitHub. It only touches a project titled
"Git Issues Sandbox", which you create yourself with Status and Priority fields.

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to propose changes. The design choices behind sync are documented in
the source, starting with `Sync/SyncEngine.swift` and `Sync/Mutation.swift`.

## Versions

The project follows [semantic versioning](https://semver.org). Every release is tagged (`v0.1.0`) and described in
the [changelog](CHANGELOG.md). Until 1.0, minor versions may change behaviour.

## Acknowledgements

Built with [GRDB](https://github.com/groue/GRDB.swift) and
[MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui). The interaction design is inspired by
[Linear](https://linear.app).

Git Issues is an independent project and is not affiliated with, endorsed by, or sponsored by GitHub or Linear.

## License

[MIT](LICENSE) © Lukas Kaibel
