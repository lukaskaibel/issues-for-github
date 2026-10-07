# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org).

## [Unreleased]

### Added

- **Due dates, with reminders.** Give an issue the day it is due: press `D`, click its date, or use the command
  palette, the right-click menu or the selection bar for several issues at once; on iPhone and iPad, tap the date chip
  or touch and hold the issue. Pick today, tomorrow, Friday, next week or in two weeks, click a day in the month, or
  type it in a few words ("fri", "next week", "in 3 days", "12.10."). The date is the project's "Due date" field on
  GitHub, which the app adds the first time; cards, list rows and the issue show it, orange on the day and red once
  it has passed. On the day an issue assigned to you is due, your Mac, iPhone and iPad remind you with a notification,
  and once more the next morning if it is still open. Its buttons start the issue, mark it done or move it to
  tomorrow. The time is set in Settings (9:00 at first); GitHub's dates have no time of day, so issues don't either.
- **An Inbox for what changed**, as in Linear: who assigned you, mentioned you or your team, commented, asked for
  your review, closed, reopened or merged an issue or pull request you follow, with who did it and the comment
  itself. It is GitHub's own notifications, so what you read or archive is read or done on github.com and your other
  devices too. On the Mac it is the first row of the sidebar, with the number of unread entries (also on the Dock
  icon, which Settings can turn off); the issue opens beside the list with what's new on top and the new comments
  marked, and changes in place. J and K move, U reads or unreads, E or ⌫ archives (⌘Z or the message undoes it),
  H snoozes until later today, tomorrow, next week or a date, ⇧S unsubscribes, ⌥U reads everything and ⇧⌫ archives
  everything read; ⌘-click and Shift-click pick several. For you and Watching keep repositories you only watch
  apart. On the iPhone the Inbox is the first tab, with the count on it: swipe right to read, left to snooze or
  archive, touch and hold for everything. On the iPad the issue sits beside the list, as in Mail. An issue on none of
  your boards opens there too and goes onto one with its status, as everywhere. One from a repository none of your
  boards use, such as one you only watch, can be commented on, assigned, labelled and put on a board; its title and
  description are changed on GitHub. Snoozes and entries marked unread are kept in iCloud, so your devices agree. Releases, CI runs and discussions stay on GitHub; the end
  of the list says how many there are. `gi-cli inbox` lists the notifications as the Inbox reads them.
- **Every issue, on a board or not.** Issues that are on none of your GitHub Projects no longer stay invisible. My
  Issues shows every open issue assigned to you, wherever it is, and the sidebar has a Repositories section with the
  repositories your boards use, like the teams in Linear (on the iPhone, in the Projects tab). A repository lists all
  its issues, grouped by status like My Issues; those on no board lead under **No project**. Click their circle with
  the plus, press S or use the right-click menu, and pick a column: the issue goes onto the board, in that column.
  A new issue started in a repository can go on one of its boards or on none.
- **Descriptions drawn as on GitHub.** A description with a table, a checklist, a code block or a Mermaid diagram is
  drawn the way GitHub draws it, on the Mac, iPhone and iPad: tables with lines and a header row, checkboxes that tick
  with a click (saved to GitHub like any edit), code in a box that scrolls sideways, and flowcharts, sequence, state,
  class, ER and XY diagrams drawn natively. A click on the text shows the Markdown to edit, and leaving it draws it
  again. Plain descriptions are still edited right where you click. Comments and the peek show tables, checklists
  and diagrams too, and the peek's checkboxes tick as well.
- Issues can be put in a new order in the list, as on the board: drag a row up or down within its section, or into
  another section to change its status. The row lifts off as a card and the list makes room where it would land.
  ⌥↑ and ⌥↓ (or ⌥K and ⌥J) move the issue under the pointer or keyboard focus one place up or down its column or
  section, on the board and in the list. On iPhone and iPad, touch and hold an issue in a project's list, then drag
  it. My Issues mixes projects, so its rows stay where their boards put them.
- Change several issues at once, as in Linear. Pick them with X, the checkbox at the start of a list row,
  ⌘-click or Shift-click (Shift with the arrows or J/K picks a run, ⌘A picks everything on screen). A bar at the
  bottom sets status, priority, assignee and labels for all of them; S, P, A, L, I, the command palette and the
  right-click menu act on all of them too, with checkmarks for the values they share. Escape clears the pick.
- Space peeks at the issue under the pointer or keyboard focus in a panel beside the board or list: title,
  status, priority, assignees, labels and description, each changeable in place. J and K move the peek along,
  Return opens the issue, Space or Escape puts it away. The right-click menu has Peek too.
- **Issues for iPhone and iPad.** The same app, built from the same project, with sync, the offline queue,
  conflict handling and every action shared with the Mac. On the iPhone: My Issues, Projects and Search as tabs, lists
  grouped by status with folding sections and pinned headers, swipe actions (done, assign, delete), the issue menu on a
  long press, the description edited in place with live Markdown styling, properties as chips, sub-issues, comments,
  new issues and sub-issues, statuses and section order to edit, and pull to refresh. On the iPad: a sidebar with every
  project, the board with drag and drop, the issue beside its properties, and the Mac's keyboard shortcuts.
- The GitHub login is shared between Mac, iPhone and iPad through iCloud Keychain. A Mac signed in with the GitHub CLI
  asks once whether to share it. "Sign Out Everywhere" signs out all devices.
- Sample data: two sample projects to try the app without a GitHub account ("Explore with Sample Data" on the
  sign-in screen, on the Mac too). The account menu and Settings leave them again.
- The iPhone and iPad send queued changes when the app goes to the background and refresh now and then in the
  background, so they open up to date.
- UI tests for every feature of the iPhone and iPad app (`Tools/test-ios.sh`), and `Tools/testflight.sh` to upload
  builds to TestFlight.
- `Tools/testflight-mac.sh` uploads the Mac app to App Store Connect. Its App Store build, which Product › Archive
  makes too, runs in the App Sandbox, is signed with your team, shares the login through iCloud Keychain and leaves
  out the GitHub CLI sign-in.
- [PRIVACY.md](PRIVACY.md): what the app stores and sends, to link from the App Store listing.
- A website, [lukaskaibel.github.io/issues-for-github](https://lukaskaibel.github.io/issues-for-github/), with the
  privacy policy, terms of use, support with answers to common questions, and the Impressum. It follows the light or
  dark appearance and is published from `Website/` whenever it changes on main.
- fastlane lanes release the Mac, iPhone and iPad apps together: screenshots, the listing's texts, TestFlight builds
  and the submission for review, signed in with an App Store Connect API key. `Tools/mac-app-store-screenshots.sh`
  takes the Mac App Store screenshots on the sample data.

- Clicking an issue's priority, status, labels, assignees or sub-issue count, on a card or in the list, opens a
  dropdown right there, as in Linear: the search field has focus, number keys pick, and the current value is
  checked. The sub-issue count lists the sub-issues and opens the one you pick. The parts light up on hover.
- All dropdowns (also in the issue view and the new-issue dialog) open as floating panels without an arrow, take
  the keyboard straight away, shrink as you filter, and close with Escape or a click elsewhere.
- The right-click menu has icons and submenus for status, priority, assignee and labels, with the same glyphs and
  number keys as the dropdowns. Cards, list rows and sub-issues share it.
- List sections fold in and out with a click on their header, shown by an arrow on the left. Kept per project.
- In the sub-issue dropdown, each sub-issue's status, priority and assignee open their own dropdown on top, as
  in Linear; Escape or a click back closes just that one. The list ends with **New sub-issue…**.
- Sub-issues in the issue view change status, priority and assignee from their row, like cards.
- A sub-issue's header shows its parent between the project and its number; click it to go up.
- Right-click a project in the sidebar to hide it, copy its link or open it on GitHub. Hidden projects fold away
  under one line at the end of the list.
- **Copy Branch Name** (⌘⇧.), in the right-click menu, the Issue menu and the issue header, copies the branch name
  GitHub suggests, such as `14-sign-in-with-github-device-flow`. The header also has a copy-link button.
- Tooltips name what you point at on cards and list rows (priority, status, assignees, labels, sub-issues), and
  the list's date shows when the issue was updated and created.
- Board column headers have a right-click menu and rename on a double-click. List section headers have a
  right-click menu too, and Option-click folds or unfolds every section.
- Closing the new-issue dialog keeps what you typed, as Linear does; the next new issue picks up from there, with
  **Discard draft** to start over.
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

- G then B goes to the board of the project used last from the Inbox, My Issues or a repository, and G then L from
  the Inbox to that project's list; before, they did nothing there.
- A single line break in a comment or a drawn description stays a line break, as on GitHub.
- Fewer clicks: picking a value closes the dropdown, for assignees and labels too, so one change is one click. To
  pick several people or labels, tick the checkbox at the start of their rows, or hold Shift while you click or press
  Return; the dropdown then stays open. On iPhone and iPad a tap in the assignee and label sheets picks and closes
  the sheet as well, and the circle at the start of a row picks several.
- A new issue takes the keyboard focus once it's created, so Return opens it and S, A or L change it. After
  deleting an issue the focus moves on to the next one instead of back to the top.
- While peeking, S, P, A, L, I, J and K act on the issue in the peek, also with the pointer over the panel. Its
  labels can be changed there, as its status, priority and assignees already could.
- On an iPad with a keyboard, S, P, A and L open their picker with the search field ready: type and press Return.
- The sidebar is calmer, as in Linear. The account, search and New Issue share the top row, and the state of
  syncing is a dot on your avatar: green when everything is on GitHub, the accent while changes go out, amber when
  you're offline or something needs you. "Synced just now" moved into the account menu (and the avatar's tooltip).
  That menu opens as a dropdown like the pickers, with Sync Now, the queued changes, Appearance as a submenu,
  Settings and Sign Out, and works with the arrow keys. A card at the bottom of the sidebar appears only when you're
  offline, a change needs your decision or syncing failed, with a button to show the changes, open the issue or try
  again. The iPad sidebar works the same way.
- List rows start a little further in, so the checkbox has its place under the section headers' fold arrow and
  the priority lines up with the headers' status icon. Stepping with J/K skips folded sections.
- Parts of cards and list rows light up in a shape that suits them, as in Linear: a small square behind an icon,
  a round halo around avatars (with a dashed placeholder where an unassigned issue's avatar would be), and chips
  brighten in their own outline instead of getting a box behind them.
- The app is called Issues now; "Git Issues" was a working title. Data, settings and sign-in carry over, and the
  built app is `Issues.app`.
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

- Turning an iPad from portrait to landscape could quit the app when the sidebar appeared.
- HTML comments such as the hints issue templates leave (`<!-- … -->`) no longer show in comments and the peek;
  GitHub hides them too.
- Renaming a column, adding one and the token field on the sign-in screen take the keyboard focus straight away,
  so you can type without clicking into them first.
- When a saved sign-in no longer works, such as a GitHub CLI login without the CLI or a token missing from the
  keychain, the sign-in screen appears instead of an endless "Looking for your projects…".
- The issue view's back arrow and Escape return to the issue you came from, such as the parent of a sub-issue,
  instead of closing everything. Moving through issues with J and K no longer piles up history.
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

[Unreleased]: https://github.com/lukaskaibel/issues-for-github/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/lukaskaibel/issues-for-github/releases/tag/v0.1.0
