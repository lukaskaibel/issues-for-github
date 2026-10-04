# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org).

## [Unreleased]

### Added

- **Git Issues for iPhone and iPad.** The same app, built from the same project, with sync, the offline queue,
  conflict handling and every action shared with the Mac. On the iPhone: My Issues, Projects and Search as tabs, lists
  grouped by status with folding sections and pinned headers, swipe actions (done, assign, delete), the issue menu on a
  long press, the description edited in place with live Markdown styling, properties as chips, sub-issues, comments,
  new issues and sub-issues, statuses and section order to edit, and pull to refresh. On the iPad: a sidebar with every
  project, the board with drag and drop, the issue beside its properties, and the Mac's keyboard shortcuts.
- The GitHub login is shared between Mac, iPhone and iPad through iCloud Keychain. A Mac signed in with the GitHub CLI
  asks once whether to share it. "Sign Out Everywhere" signs out all devices.
- Sample data: two sample projects to try the app without a GitHub account ("Explore with Sample Data" on iOS).
- The iPhone and iPad send queued changes when the app goes to the background and refresh now and then in the
  background, so they open up to date.
- UI tests for every feature of the iPhone and iPad app (`Tools/test-ios.sh`), and `Tools/testflight.sh` to upload
  builds to TestFlight.
- [PRIVACY.md](PRIVACY.md): what the app stores and sends, to link from the App Store listing.

- Clicking an issue's priority, status, labels, assignees or sub-issue count, on a card or in the list, opens a
  dropdown right there, as in Linear: the search field has focus, number keys pick, and the current value is
  checked. The sub-issue count lists the sub-issues and opens the one you pick. The parts light up on hover.
- All dropdowns (also in the issue view and the new-issue dialog) open as floating panels without an arrow, take
  the keyboard straight away, shrink as you filter, and close with Escape or a click elsewhere.
- The right-click menu has icons and submenus for status, priority, assignee and labels, with the same glyphs and
  number keys as the dropdowns. Cards, list rows and sub-issues share it.
- List sections fold in and out with a click on their header, shown by an arrow on the left. Kept per project.
- Every status header in the list stays pinned at the top while you scroll through its section, and the next
  header pushes it out of the way. The pinned header folds its section with a click too.
- Descriptions are edited in place, as in Linear: click anywhere and type. Markdown is styled as you type
  (headings, bold, italics, code, links, lists) and saved after a short pause or when you leave the field. Escape
  leaves the field; ⌘↵ does too.
- Deleting issues, from the right-click menu, the command palette, the Issue menu or with ⌘⌫. A confirmation
  explains that the issue is deleted on GitHub for everyone; Return confirms. Deleting needs admin rights in the
  repository, so the action is unavailable where GitHub wouldn't allow it. Drafts are removed from the board.
- Right-clicking a sub-issue opens the same menu as a card on the board (status, priority, assign to me, copy link,
  open on GitHub). Sub-issues that aren't on the board offer what applies to them: mark as done or reopen, and the
  links.
- Sub-issue rows show their priority, in the same order as list rows.

### Changed

- The project is one app for Mac, iPhone and iPad. Code shared by all of them lives in `UI/Shared`, the rest in
  `UI/Mac` and `UI/iOS`.
- The GitHub OAuth client ID is set in `Config/Local.xcconfig` (`GITHUB_CLIENT_ID`) rather than in `Info.plist`, so
  forks don't use yours.

- New app icon: a card lifted off a board, in the accent colour. It's an Icon Composer icon, so it follows light and
  dark mode by itself (and the tinted and clear styles). Settings offers it fixed in light or dark, and on violet;
  the earlier designs are still there. Everyone starts from the new icon once, even after picking another before.
- Clicking the account at the top of the sidebar opens a menu with Sync Now, Appearance, Settings and Sign Out.
  The separate "…" button next to the sync status is gone.
- The sync status sits lower, lines up with the sidebar's icons, and shows a capsule on hover.

### Fixed

- In the list, the header of the section you've scrolled into stays at the top without a line under it, and no
  rows show above it; the next header pushes it up.
- The command palette, its pickers and the new-issue dialog reliably take keyboard focus when they open, so you
  can type straight away. Before, SwiftUI sometimes dropped the focus request and left nothing focused.
- Escape closes the command palette and the new-issue dialog whatever has focus inside them.
- Typing straight after pressing C (or ⌘N, or ⌘K) no longer loses the first letters: keys pressed before the
  title field has focus are held and handed to it. If anything takes focus away while the new-issue dialog
  appears, the title gets it back.
- The board now shows a loading state while a project is fetched for the first time, as the list already did.
  Both say so when you are offline or the project can't be loaded, instead of loading forever.

## [0.1.0] - 2026-10-01

First public version.

### Added

- Board for GitHub Projects with drag and drop between and within columns, including spring animations,
  auto-scroll near the edges and cancelling with Escape.
- List grouped by status, and "My Issues" across all projects.
- Issue view with Markdown, sub-issues, comments and editable status, priority, assignees and labels.
- Creating issues and sub-issues.
- Adding, renaming, recolouring and removing status columns, and reordering them by dragging their headers.
- Reordering the list's sections by dragging their headers (kept as a local preference).
- Command palette and single-key shortcuts for the common actions.
- Back and forward navigation with ⌘[ and ⌘], mouse side buttons and trackpad swipes.
- Local database with instant edits, an offline queue, and background sync with GitHub.
- Conflict handling: field-level changes, automatic merging of description edits, and a choice when edits overlap.
- Light and dark appearance, or following the system, and a choice of Dock icons.
- Sign-in with the GitHub CLI, a personal access token, or the OAuth device flow.

[Unreleased]: https://github.com/lukaskaibel/git-issues-mac-app/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/lukaskaibel/git-issues-mac-app/releases/tag/v0.1.0
