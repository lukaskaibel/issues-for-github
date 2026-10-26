# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org).

## [Unreleased]

### Added

- **The board on iPhone.** A board view shows as a board on the iPhone now, one column at a time across the screen,
  with every column and its count in a strip over it: swipe, or tap the strip, to turn to another column. Touch and
  hold a card and the strip becomes a target for each column: let go on one and the card goes first in that column;
  hold it there a moment and the board turns to that column, to place the card among the cards there. Over the board
  the project's views are in the menu of its title, which names the open one under it, and Display in the project's
  "…" turns a view into a list or back, picks its columns and shows hidden columns again, as on the iPad. Before, the
  iPhone showed every view as a list; a milestone still is one, grouped by epic.
- **Sub-issues in the order you pick.** An issue lists its sub-issues by priority now, the most urgent first and those
  without a priority after them, with the done ones at the bottom. The arrows beside the plus over them (on iPhone and
  iPad, the "…" there) order them by status, newest first or in GitHub's order instead; the choice holds for every
  issue on that device, and the list a card's sub-issue count opens follows it too. Before, they were always in
  GitHub's order, which is mostly the order they were added in.
- **A blocked issue says what blocks it.** The red flag on a blocked issue's card and list row now carries the number
  of the issue to finish first, as in `#364`, with `+1` for each further one, and the sub-issues listed in an issue,
  which had no flag at all, carry the same. On the Mac a click on the flag lists the blockers and changes them, as on
  the card, and pointing at it names them all. The chip at the top of a blocked issue says "Blocked by #364". The app
  reads which issues block a card along with the board, so the numbers are there without opening each issue.
- **Sub-issues of sub-issues, as a tree.** In an issue, a sub-issue that has sub-issues of its own says how many of
  them are done, as "1/2" next to its number, and the arrow beside its status unfolds them under it, indented and
  joined by lines as in the board's lists; theirs unfold the same way, as many levels down as GitHub has. An epic's
  issues do it too. What you unfold stays unfolded on that device. On the Mac, iPhone and iPad.
- **Pick several sub-issues on an issue's page.** On the Mac, ⌘-click and Shift-click pick sub-issues in an issue's
  list of sub-issues, also ones unfolded under another, as on the board and in the list. Right-click one of them and the menu changes all of them: move
  them under another parent with Change Parent Issue…, into an epic or out of their parent, or set their status,
  priority, assignee, labels, due date or milestone. Their status, priority and assignee buttons and the single keys
  act on all of them too, and `Esc` lets them go before it leaves the issue.
- **Pick several sub-issues on iPhone and iPad.** Choose **Select** in the "…" beside the plus over an issue's
  sub-issues, or in one's long-press menu, and a circle stands where each status circle was, as in Mail; a tap then
  picks a sub-issue instead of opening it, also one unfolded under another. **Change Parent Issue…** in the bar at the
  bottom moves all picked ones under another parent, and the "…" beside it, like the long-press menu of a picked one,
  sets their status, priority, assignee, labels, due date or milestone, or moves them into an epic or out of their
  parent. Select All and ✓ are at the top. On iPad, ⌘-click and Shift-click with a pointer pick sub-issues straight
  away, S, P, A, L, D and I then change all of them, and `Esc` lets them go.
- **Pickers offer what you chose last.** The issue you just made a parent is at the top of the parent picker for the
  next issue, above a line, and Return picks it again. The same goes for epics, blocked by and blocking, labels and
  assignees, also in a new issue, on the Mac, iPhone and iPad: up to three of your latest choices come first. Rows no
  longer move while you tick several labels or people in a picker that stays open.
- **Bold typed with its stars, headings typed with their #s.** Typing `**` (or `~~`) where a style can start puts in
  the closing pair too, with the caret between them, so you type straight into bold; typing the closing stars yourself
  steps over them, a space right after `**` leaves plain stars (`2 ** 3`), and a star in the empty pair makes bold
  italics. Text typed right after `##` gets the space a heading needs, so `##Plan` becomes the heading Plan, and so
  does a line you type `##` in front of; one `#` is left alone, as it may be an issue's number. Return on a heading
  without text turns it back into body text, and Return at the start of a heading puts an empty line above it.
- **From the title into the description and back with the keys.** Tab, ↓ on the title's last line and → at its end go
  to the start of the description; ↑ on the description's first line, and ← or Delete at its very start, go back to
  the end of the title, as between lines. On an issue's page, in the Inbox, in a new issue and in a milestone, on the
  Mac and on iPhone or iPad with a keyboard (Delete also on the touch keyboard). Holding Delete down stops at the start
  of the description instead of going on to delete the title. In a new issue or milestone, Return in the title now
  goes to the start of the description too, rather than its end.

- **Hide board columns, on your device only.** A column's menu (right-click its header, or its "…"; on iPad its "…")
  has **Hide Column**: the column and its cards leave the board, and nothing changes on GitHub. Hidden columns wait at
  the right end of the board with their counts and under Display (`⇧V`), and a click brings one back. Each view keeps
  its own; the list still shows every status, and a milestone's board every column. A new issue that goes into a
  hidden column says so. On the Mac and iPad.
- **Close an issue that's on no board.** Its status picker offers **Mark as Done**, or **Reopen** once it's closed, as
  well as the boards to put it on.
- **More in the command palette.** New Issue wherever `C` makes one, Copy Branch Name, Show or Hide Inspector, Reset
  Filter and Reset Display for a changed view, and the keys of Open on GitHub.

### Changed

- **A quieter board.** The cards stand on a grey board without a border, each on a soft shadow, and the columns
  without the grey lanes; the gap between them sets them apart. A label on a card is a dot in its colour and its name,
  no longer a tinted pill, and the milestone and the epic a card belongs to are grey, so that colour is left for what
  needs you: a date that's due, an urgent issue, a blocker. On the Mac and iPad. On the Mac, the card under the
  pointer rises a little, and a column's + shows while the pointer is in that column.
- **All Issues instead of Repositories.** The sidebar's Repositories section is gone. In its place **All Issues** heads
  a project's views on the Mac and iPad, and sits under each project in the iPhone's Projects tab: the board's issues by
  status, after every issue of its repositories that is on no board, under No project. The number beside it says how
  many of those are open, so an issue someone opened straight in a repository doesn't wait unseen. A new issue started
  there goes on the board or, if you choose, on none; where a project has several repositories, each row names its
  own. On the Mac, `G` then `A` opens it, and the project switcher finds it by the project's or a repository's name.
  Before, each repository had a row of its own whose list mostly repeated the board, with issues of other boards mixed
  in.
- On a board, `J` and `K` go up and down the column, as `↑` and `↓` do. With an issue open they step through the board
  or list it was opened from, in the order you see, on iPad too.
- `G` `B`, `G` `L`, `⌘1` and `⌘2` go to the board or list of the project you used last from anywhere, My Issues and
  the Inbox included, as `G` `R` goes to its roadmap (now in one step back).
- On the Mac, a new issue started where no board is on screen goes to the project at the top of the sidebar, and its
  board can be changed in the dialog; started in My Issues, it is assigned to you, as on iPhone and iPad. A new epic
  from a roadmap goes on that roadmap's board.
- Signing out asks first while changes are still waiting to reach GitHub, since it deletes them.
- In the Inbox, `S` `P` `A` `L` `I` change the issues of all picked notifications, `⇧J` and `⇧K` pick a run, and
  moving with `J` and `K` keeps what is picked.
- On the Mac, picked issues let go when you click elsewhere, as in the Finder: a click on the board or list beside
  the issues clears the pick, and a plain click on another issue opens it and clears the pick too. A click on a picked
  issue's priority, labels and the like still changes all of them; on an issue that isn't picked, it changes just
  that one and the pick goes. Before, only `Esc` or the × in the bar at the bottom let them go.
- **Markdown that reads as GitHub draws it, while you write it.** Descriptions, comments, the comment field, new
  issues and milestones are drawn as on GitHub at all times: headings, lists, checklists that tick, quotes, code in
  colour, tables and Mermaid diagrams, and now also GitHub's alerts (`> [!NOTE]`, Tip, Important, Warning, Caution),
  `$maths$` set as formulas, footnotes, pictures from the web (`<img>` tags too) and HTML comments, which are faint
  while you write and hidden in what you read. The Markdown shows only next to the caret, faintly, and folds away when
  you move on; a click puts the caret right where you clicked, and a click into a table, a diagram or a formula brings
  up its source, with the diagram or formula drawn under it as you type. Lists continue on Return, Tab nests them and
  Backspace takes a bullet away. A link's address hides behind a small pencil that changes it, and a code block has a
  button that copies it. Typing works as in 1.0.0: styles turn on and off, a style's marks come and go as a pair,
  Return leaves bold, `-` starts a bullet, and text eases into its new look. On the Mac, the new Format menu has the
  shortcuts of Notes (`⌘B`, `⌘I`, `⌘L`, `⇧⌘H`, `⇧⌘L`, `⇧⌘U` and more), and on iPad with a keyboard the same shortcuts
  work, listed while you hold `⌘`; the list shortcuts are now those of Notes too: `⇧⌘7` bullets, `⇧⌘9` numbers and
  `⇧⌘L` a checklist. On iPhone and iPad the bar above the keyboard is a capsule of glass as in Notes: Aa opens the
  Format panel in place of the keyboard, next to a checklist, a link, undo, redo and more formatting, with Done beside
  it, and the buttons for where the caret is stay on its left. VoiceOver reads each checkbox with its item and whether
  it is ticked, and ticks it.
- **Markdown marks depend on how you type, and fold in and out.** With a keyboard (the Mac, or an iPad or iPhone with
  one attached), the marks of a style show next to the caret as before, so the arrow keys reach them and Delete takes
  them, and a heading's `#`s show while the caret is on it. On the touch keyboard they stay hidden, and the buttons on
  the left of the bar above the keyboard show the style you're in: a tap at the end of bold text puts the caret inside
  its stars, so typing goes on in bold, as in Notes; Delete behind hidden stars takes the letter you can see and keeps
  the style, and bold that loses its last letter goes entirely; the caret never rests between hidden marks; and a
  heading's `#`s show only while you type them, until you leave the line. Marks no longer pop in and out: they unfold
  as the caret arrives and fold away behind it, the text beside them sliding along (at once with Reduce Motion).

### Fixed

- The Mac app no longer quits when you pick two issues in a list grouped by people (such as the Team view), and `J`
  no longer loops back up in it when an issue is listed under two people.
- Moving a column on a milestone's board, by dragging or with Move Left and Right, no longer deletes the project's
  empty Backlog columns that the milestone leaves out, which took the status of every issue in them.
- Deleting a column says how many issues of the whole project lose their status, not only the ones on screen.
- Issues picked on the board or in the list no longer change along with the one you open; picks of issues that leave
  the list (deleted, or filtered out) are let go, and so is a peek.
- When the issue in focus leaves the board or list, after a change of status, assignee or milestone or a fold, the
  focus goes to the issue next to it. On the Mac the board scrolls to keep the issue in focus in sight.
- A comment you started writing is still there when you come back to the issue.
- On the Mac, a title you were typing is kept when you leave the issue with Back, the arrows or a key; Back and
  Forward work again after closing an issue in a project with views; deleting a sub-issue opened from its parent goes
  back to the parent.
- The milestone picker no longer takes the first digit you type as a shortcut when milestones are versions ("0.4"),
  and a name typed there becomes the name of **New Milestone…**, on the Mac, iPhone and iPad. The milestone editor
  says why Create is off when an open milestone has that name already.
- An issue's Epic row is offered only where picking an epic doesn't take the issue from another parent, and not in
  projects without epics.
- On iPhone and iPad, sub-issues listed in an issue show their assignees as just changed.
- On iPad, a board by an iteration or another field shows each column's colour or iteration and dates as the Mac does,
  its plus gives the new issue that column's value, and it no longer offers Add Status.
- An issue made with the plus of the "No status" column or list section has no status, one made in a folded section or
  under a folded parent shows, and one made with the plus of a repository's group starts in that repository.
- On the Mac, reordering cards on a milestone's board works when the project's open view is sorted.
- A view whose filter leaves out every issue says so, with Reset for a changed filter, instead of "No issues yet".
- iPhone and iPad no longer let you drag rows in groups by another field than Status, where they can't stay, and on
  the Mac `⌥↑` and `⌥↓` in the list move an issue within its section.
- Fold All and Unfold All in one view no longer reset the folds of the project's other views.
- With issues from several projects picked, as in My Issues, Priority and `P` are there when any of them has a
  priority, not only when the first one does.
- A column name typed into Add Column is kept when you click elsewhere.
- On the Mac, the right-click menu of a list section's header has **Back to the Usual Order** once sections were
  dragged into an order of your own, as iPhone and iPad have.
- Hiding the project at the top of the sidebar works from the Inbox, My Issues, its milestones and its roadmap too.
- `⌘S` isn't offered for a view while offline or while it is being saved, and the palette no longer offers Unsubscribe
  for due dates and your own assignments in the Inbox.
- On the Mac, dragging one of several picked issues moves all of them, on the board and in the list. They lift off
  together, as one card with the edge of another under it and how many there are on its corner, and land one after the
  other where you let go, with that column's status. A message says how many moved, with Undo, and `Esc` mid-drag puts
  them all back. Before, only the issue under the pointer moved and the others stayed where they were.
- Dragging only offers what can change. On the Mac, a board you can only read no longer lets you lift its cards, as
  its list already didn't, and in a view sorted by a field a card or row can't be dropped at another place in its own
  column or section, where it used to snap back; it can still go to another column. On iPad, cards on a milestone's
  board can be moved up and down again while the project's open view is sorted.
- The heading over an issue's sub-issues stays on one line on a small iPhone, in every language. When the row is short
  of room, the bar beside the title gets shorter and then steps aside, and only after it "4 of 6". Before, the title
  broke onto two lines on an iPhone SE, in English too, and in Spanish even on an iPhone 17 Pro.
- On the Mac, cards in a long board column light up under the pointer without lagging behind it. Going from one card
  to the next used to work out every card in the column again; now only the card the pointer leaves and the one it
  enters are drawn anew, so a column of a hundred issues answers the pointer as quickly as a short one.
- Board cards are drawn faster, on the Mac and on iPad, and look exactly as before. A card worked out its colours and
  each of its texts anew every time it was drawn, which is whenever the pointer goes onto it or leaves it and whenever
  it scrolls into view; now it keeps them, so drawing a card again takes about a quarter of the time. On the Mac the
  pointer going from card to card and a long column scrolling miss a frame of a 120 Hz display less often.
- On the Mac, the pointer no longer stutters over the header above an epic's issues on the board. Its light and its
  arrow fade in and out as before, but the header used to draw its name, count and icon again on every frame of that
  fade, so the board could stop for up to a tenth of a second each time the pointer came onto a header or left it.
- Return at the end of a heading that ends a description no longer scrolls the page by a line.
- On the Mac, the pointer goes down the Inbox smoothly. The notification under it lights up and shows its two buttons
  as before, but the buttons now lie over the end of its lines, which fade out under them, instead of the lines moving
  aside. The row used to draw its avatar, its icon and every line again on every frame of that fade and build the
  buttons anew each time, so the Inbox could stop for up to a tenth of a second; now the longest pause is about 15 ms.
- On the Mac, a long board column scrolls more smoothly, most of all past sub-issues and epics' headers. A column
  builds each card as it scrolls into view, and a card was up to four views: the card, the lines from its parent, the
  edge of the sub-issues folded into it and the slot it leaves while dragged. Now the card draws all of that in one
  go, and an epic's header has fewer parts, so scrolling misses a frame of a 120 Hz display less than half as often.
  The board looks exactly as before.
- On the Mac, a long board column scrolls more smoothly still, past epics' headers most of all. A column measured each
  card as it came into view and stacked it under the one before; now it knows how tall every card is before drawing
  any, puts each in its place, and a card or header scrolling in takes over the view of one that scrolled out instead
  of being built anew. Scrolling takes about a quarter less work and misses a frame of a 120 Hz display half as often.
  The board looks exactly as before, and VoiceOver goes through every card of a column as before, scrolling to it.
- On the Mac, dragging an issue in the list moves it again. The drag stopped as soon as it began and left an empty
  space where the issue had been, so the issue seemed gone until you went to another list and back. Now the issue
  lifts off as a card and lands where you let go, and the same goes for an epic's header with its issues.

## [1.0.0] - 2026-10-20

Issues now plans the work as well as tracking it, in a window built like Mail and Notes. In the App Store this version
follows 0.2.0: 0.3.0 went to TestFlight only, so its changes reach the App Store with this one.

### Added

- **New labels from the picker.** Type a label the repository doesn't have and the picker offers **Create label
  “…”**: the label is made in the repository, in one of GitHub's colours, and goes on the issue, or on every issue you
  picked. It works in every label picker on the Mac (a card, the inspector, ⌘K, the right-click menu and the new-issue
  dialog) and in the Labels sheet on iPhone and iPad. A name that differs only in case picks the label that is there,
  and offline the new label waits with your other changes.
- **My Issues, filtered and grouped your way.** My Issues has the filter chips and Display options of a project's
  view now. Press `F` to filter it by project, status, priority, label, milestone, due date, last change, or open or
  closed, and `⇧V` to group it by status, project, priority or due date and to order it by priority, due date, last
  change, creation or as the boards have it. Status and priority mean the same in every project: "In Review" and
  "Doing" are both in progress, "P0" and "Urgent" both urgent. Grouped by project, the rows leave out the project's
  name. On iPhone and iPad the filter is a line under the title, and the "…" menu has Filter…, Group By and Order By.
  What you choose stays on the device, as GitHub has no view behind My Issues.
- **Writing Markdown as in a notes app.** Bold, italics, code and strikethrough turn on and off: Bold again inside
  bold text takes the bold off, at the end of it leaves it so you type on plainly, and just behind it goes back in;
  with the caret in a word it makes the word bold. A style's marks come and go as a pair: Delete behind bold text
  deletes its letters and leaves the `**` in place until the last letter goes, and deleting one mark removes the other.
  Return at the end of bold text leaves it for the next line (in the middle, the bold goes on there), continues a list
  with the next bullet, number or checkbox, and ends it on an empty item. `-` at the start of a line makes a bullet
  with its space, `- []` a checkbox, and Tab and ⇧Tab move a list item in and out. On the Mac, and on iPad with a
  keyboard, `⌘B`, `⌘I`, `⌘E` and `⌘⇧X` make text bold, italic, code or struck through, and `⌘⇧7`, `⌘⇧8` and `⌘⇧9`
  make a numbered list, bullets or a checklist.
- **Buttons for where the caret is, above the iPhone and iPad keyboard.** On the left of the bar, buttons come in for
  what the caret is in: its style, tinted, which a tap takes off; the checkbox of its line, to tick; moving a list item
  in or out; and opening the link it is on. The bar also turns a line into a bulleted list now.
- **An icon for each project.** A project shows a glyph instead of a coloured square: GitHub's table in grey until
  you pick another. Right-click the project at the top of the sidebar and choose **Change Icon…** (or **Change Project
  Icon…** in the command palette) for one of 257 glyphs in one of GitHub's eight colours; on iPhone and iPad it is in a
  project's "…" menu, in the menu of the project at the top of the iPad sidebar, and on a long press in Projects. The
  glyphs come in twelve groups, from Work and Code to Animals and Sports and Leisure, and a search field finds them by
  name in your language or in English. A colour keeps the picker open, a glyph closes it. GitHub has no icons for
  projects, so the icon is kept in iCloud: your Mac, iPhone and iPad show the same one, and nobody else sees it.
- **Milestones.** A board's next two milestones are listed under Milestones in the sidebar, the one it works towards
  with a filled diamond that turns red once its day has passed. Each opens the board's columns with only its issues,
  or a list of them grouped by epic, with what it is about, how much is done and the day it is due on top; click the
  date to change it. Press `⇧M` to put the issues you point at or picked into a milestone, or use the right-click
  menu, the command palette or the selection bar; **New Milestone…** at the end of the list makes one right there. A
  board's milestones are GitHub's milestones of its repositories: those of the same name count as one, and a
  repository that has none of that name yet gets it when an issue of it goes in. When the day has come or everything
  is done, **Complete** closes the milestone on GitHub and offers to move what isn't done to the next one; the message
  that follows undoes it. Cards and list rows name their milestone.
- **Epics.** An epic is an issue with the label "epic" (or, in organisations that have it, the issue type Epic) whose
  sub-issues are its work, like a project in Linear. Make one with **Make Epic** in any issue's right-click menu or
  **New Epic** on the roadmap; the label is made in the repository the first time. `M` then `E` puts an issue into an
  epic. Epics leave the board and the lists for the roadmap. Where two or more issues of an epic share a column, they
  stand together under a header with the epic's name, one level in, as sub-issues hang under their parent: on the
  board and in the list, on the Mac, iPhone and iPad. A click on the header opens the epic, and its arrow folds the
  issues away under it; on the board a long name takes up to three lines. Drag the header to another column, or
  another place in its column, and all of the epic's issues there go along, with a message that undoes it; **Move
  Issues To** in its right-click menu, or when you touch and hold it, does the same without dragging. Drop a card
  between two issues of an epic and it joins that epic; a single issue of an epic names it on its card instead. An epic's page shows how far it is, in a part per milestone, and its sub-issues by milestone, each with a plus for a
  new one there. Starting work on an issue of an epic still in the backlog starts the epic too; Settings › Epics turns
  that off.
- **A roadmap.** Each board with milestones or epics has a Roadmap under its milestones in the sidebar (`G` then `R`,
  or `⌘4`): its epics as bars over the milestones their unfinished issues are in, on a timeline of months or quarters,
  or as a list under the milestone that comes next for each. Drag a bar onto another milestone and the epic moves
  there with all of its unfinished issues; drag it to Later to take them out of their milestones, and a message undoes
  either. Drag a milestone's diamond to change its day. In the list, drag an epic into another milestone's group.
- **Planning on iPhone and iPad.** The Projects tab lists a board's next milestones and its roadmap under it, and the
  iPad sidebar has them as entries. A milestone opens as a list grouped by epic, on a wide iPad also as the board's
  columns; the roadmap is a list on iPhone and the timeline on iPad, where a bar is dragged with a finger. The
  milestone is a chip on every issue, a submenu when you touch and hold one, and a choice in a new issue.
- **A project's views, in the sidebar.** The sidebar is about one project at a time, as Linear's is about one
  workspace: the project sits at its top, with the sync dot on its colour, and its menu switches to another and holds
  your account (Sync Now, appearance, settings, signing out). Under it are the views the project has on GitHub, such
  as "This week" or a list of open bugs, then its next milestones with the roadmap, and its repositories. A view shows
  what its filter finds, as a board or as a list grouped by the field GitHub groups it by. `⌃Tab` goes to the next
  one, and **Go to View…** in the command palette to any view of any project. The filter is a row of chips over the
  issues: press `F` or click **Filter** to add one for a status, an assignee, a label, a milestone, an iteration or
  any field of the project, click a chip to change it or turn "is" into "is not", or edit the filter in GitHub's own
  words. A changed filter is yours until you click **Save** (`⌘S`), which saves it to the view on GitHub for everyone;
  **Reset** takes it back. **Display** (`⇧V`) switches a view between board and list, its columns, groups and order,
  and the fields its cards show, such as the iteration; **Save for Everyone** puts board or list and the fields on
  GitHub too. **New View** under the views makes one, starting from the one open; double-click a view to rename it,
  and its right-click menu duplicates, deletes or opens it on GitHub. A new issue made in a view gets what its filter
  asks for, such as this iteration. On the iPad the sidebar works the same way; on the iPhone the views are capsules
  over the project, and the filter a line under them that opens a sheet. Everything is GitHub's own: a view looks the
  same on github.com.
- **Views that show what they are for.** How a view looks follows from how it is set up on GitHub, in any project.
  Grouped by parent issue, milestone or iteration, each group shows how far it is, as a bar and "4/6" in its header,
  and a group with nothing under way starts folded, so a view of work packages opens as an overview of what is left.
  Grouped by assignee, each person's bar is what they have open, the part under way in yellow. A view filtered to one
  iteration, such as "This week" with `iteration:@current`, shows that cycle on top: its dates, the days left, how
  much is done, and arrows to the one before and after, which change the filter until you save it. A roadmap view is a
  timeline, grouped as the view is: each issue a bar from its start to its target date, or across its iteration, or a
  mark on its milestone's day, with today and the milestones marked; click a name to open the issue. **Display**
  shows it as a list or board instead. The same on iPhone and iPad, the timeline on the iPad.

### Changed

- **Text eases into its new look as you type.** Bold text thickens, a heading grows, and a style's marks fade back
  over a fifth of a second instead of snapping (not with Reduce Motion). Every line of a description that isn't a
  heading is as tall as any other, whatever it holds (bold, code, an emoji or nothing), so nothing jumps while you type
  or delete; a blank line between paragraphs is a full line now, as in other Markdown editors.
- **A Mac app like Mail and Notes, with Linear's pickers kept.** The window has the system's sidebar and a toolbar in
  Liquid Glass: back and forward, the title of the page with its project and when it last synced, Board and List in
  the middle (`⌘1`, `⌘2`), the page's own buttons such as Filter and Display, a milestone's progress and date or the
  roadmap's Months and Quarters, and a magnifying glass that opens the command palette (`⌘K`). An open issue is a page
  of its own, with the field for a new comment at the bottom, and its properties in an inspector on the right that
  `⌃⌘I` or the toolbar button hides; its sub-issues are a checklist. The Inbox reads like Mail: the person's picture,
  what they did and the start of their comment on each entry, the selected one in the accent colour, For You and
  Watching in the middle of the toolbar and archive, snooze and read beside them. Board columns stand on soft grey
  lanes, labels are tinted capsules, and picked rows in the list are filled with the accent colour. The pickers,
  command palette, new issue and the bar for several issues are glass, and a picker's highlighted row a soft tint of
  the accent colour; they still open where you click, take what you type at once and close when you pick, or when you
  click what opened them again. The sidebar's selected row is the accent colour with white text.
- **Right-click menus as big as the pickers, with a search field.** Every right-click menu, on a card, a list row, a
  column, an epic's name or a sidebar entry, is a glass list with rows as big as a picker's instead of the system's
  small menu. Type to find any entry, also inside a submenu ("rev" finds Status › In Review), move with the arrow keys
  and pick with Return. Status, Priority, Assignee, Labels, Due Date and Milestone open the same picker as a click on
  the card, so a number key picks there too.
- **iPhone and iPad issues without boxes.** An issue's properties are glass chips under its title, its sub-issues a
  checklist with the status first, and its comments a conversation with each person's picture and the new ones
  marked. Lists have larger rows and hairlines between them, and the iPad board stands its columns on lanes as the
  Mac's does.
- **A new app icon: a card lifted off a board.** A card in the app's indigo with a done mark, turned a little as if
  just picked up, over a faint board of three columns and three rows of tiles. It follows light and dark mode.
  Settings on the Mac, and your account on iPhone and iPad, offer it on graphite or as a white card on indigo
  instead, and everyone starts from the card.
- **Cards leave out the repository.** A board is one project's, so on a project that spans several repositories its
  cards no longer put the repository's name next to the number. On the Mac, point at the number and it names the
  repository the way GitHub does, as in `acme/website#12`; a row's number in a list does the same. My Issues, which
  mixes projects, still says where each issue comes from.
- **My Issues puts the most urgent first** in each group, then what is due soonest, instead of each board's order,
  which said little once several projects were mixed. **Order by › Manual** brings the boards' order back.

### Fixed

- On the Mac, an issue and the Inbox read cleanly under the toolbar: what scrolls up fades out just below it, as above
  the comment field, and the toolbar lies on the page's own ground. Before, the text of an issue stayed sharp under the
  toolbar and ran through its title, "#9" and the project's name; over the Inbox the toolbar had a strip of another
  grey with a line under it, which the notifications showed through.
- Right-click menus on the Mac keep up with the pointer: the row under it lights up at once, and moving down a long
  menu no longer stutters. A submenu opens as soon as the pointer rests on its row or moves toward it, stays open
  while the pointer crosses other rows on the way to it, and opens faster. Before, every row with a submenu the
  pointer passed opened its submenu, and the menu's glass turned dim and back each time.
- The same goes for every other list that lights up under the pointer: the pickers for status, priority, people,
  labels, dates and the rest, the command palette, the project icon picker, the project's menu at the top of the
  sidebar, the Inbox's menus and the menus of a new view.
- The end of an issue reads cleanly above the field for a new comment, on the Mac, iPhone and iPad and in the Mac's
  Inbox: the page fades out just above the field, as it does under the toolbar. Before, the text behind showed through
  the field's glass, over "Leave a comment…", and peeked out in the strip below it.
- On iPhone and iPad the send button sits inside the comment field, as on the Mac and in Messages: a small circle that
  turns the accent colour once there is something to send. Before, it was a round button beside the field and taller
  than it.
- In a description, Return inside bold text no longer splits its `**` over two lines, and Bold next to bold text no
  longer piles up stars. A space typed in bold text no longer turns the bold off until the next letter, and
  `_**both**_` shows italics as well as bold.
- On the Mac, a two-finger swipe goes back or forward only when you mean it: it has to move clearly sideways, as in
  Safari, and far enough that its arrow fills before you lift your fingers. Before, a scroll that started a little to
  the side or a short flick could take you back. The arrow now grows inside the page in glass, instead of sliding out
  from behind the sidebar.
- On iPhone and iPad, tapping the status circle of a sub-issue on an issue's page opens a menu of its board's
  statuses, as the status chip does, with the current one checked. Before, the tap marked it done at once, and the
  circle had no way back. A sub-issue on none of your boards offers Open and Closed.
- A parent, sub-issue or blocker someone else sets or removes now shows up in the app within seconds, on a board
  and off one. Before, the app noticed only when something else about the issue changed, because GitHub doesn't
  count these as changes of the issue or its board.
- Someone else's new title, label or assignee no longer goes unnoticed when GitHub doesn't pass the change on to the
  board, which it sometimes skips.
- On the Mac board, a card that comes back to the very place it just left, such as one moved to another status and
  back, answers clicks, the pointer and drags again at once. Before, it ignored them until something else in its
  column moved.

## [0.3.0] - 2026-10-11

### Added

- **Sub-issues under their parent.** When an issue and some of its sub-issues have the same status, the sub-issues
  hang indented right under it, in the list and on the board, with a line from the parent. A parent you work on
  together with its sub-issues reads as one, instead of as separate cards side by side in the same column. A
  sub-issue whose parent has another status stays where its status is and names its parent ("#9 Drag cards…"); a
  click there changes the parent. The arrow beside the parent folds its sub-issues in, and a folded card shows the
  edge of a second card under it; the right-click menu does the same, and each device remembers what is folded.
  Other cards never land between a parent and its sub-issues, and a parent moved within its column takes them along.
  On iPhone and iPad, tap the arrow left of the status in the list or at the card's top left on the board, or touch
  and hold.
- **A parent is done with its last sub-issue.** Finish the last open sub-issue of an issue and the parent moves to
  Done as well, on every board it's on, with a notice that says so, as Linear can. It's on unless you turn it off in
  Settings › Sub-issues. Changes made on GitHub don't do this.
- **Assignments made with your own account in the Inbox.** When your own GitHub account assigns you to an issue
  outside the app, with `gh`, a script, a coding agent such as Claude Code signed in as you, or on github.com, the
  issue now shows up in the Inbox: "New issue, assigned to you" when it was opened that way, else "You were assigned".
  GitHub never notifies you of what your own account does, so the app looks for these itself, about once a minute.
  Assigning yourself in the app, on any of your devices, doesn't show up: to GitHub the two look the same, so the app
  notes its own assignments in iCloud for a week. Read, archive and snooze work as for notifications, kept in iCloud
  like due issues. Pull requests are left out, and only assignments from the first launch of this version on count.
- **Nine languages.** The app speaks German, French, Spanish, Portuguese (Brazil), Russian, Japanese, Korean and
  Chinese (Simplified) as well as English, on the Mac, iPhone and iPad. It follows the device's language; to use
  another one for Issues alone, pick it under Settings › Apps › Issues on iPhone and iPad, or System Settings ›
  General › Language & Region › Applications on the Mac. Columns and priorities named in these languages are
  understood too: an "Erledigt" or "完了" column closes issues as "Done" does, "In Arbeit" counts as started and
  "Hoch" as high. The due date field reads dates typed in the app's language ("morgen", "nächsten Fr", "in 3 Tagen",
  "明日", "来週の金曜", "через 3 дня") besides English. What comes from GitHub, such as titles, columns and labels,
  stays as your team wrote it. The website and the App Store listing are in the same languages.
- **Due issues in the Inbox.** On the day an issue assigned to you is due, it joins the Inbox at the time of the
  reminder ("Due today"), and the morning after, if it is still open, once more ("Overdue since yesterday"), with a
  calendar instead of an avatar. Opened, it offers the reminder's buttons: Start, Mark as Done and Move to Tomorrow.
  Read, archive and snooze work as for notifications, kept in iCloud with your other Inbox records, since GitHub
  doesn't know these entries; they count towards the unread number. Turning reminders off in Settings takes them
  away too.
- **Sub-issues and blockers, as in Linear.** The plus beside an issue's sub-issues now finds issues that exist already,
  by title or number, and makes them sub-issues; what you type can also start a new one with that title. Right-click
  any issue for **Set Parent Issue…** to put it under another one, move it to another parent or take it out of its
  parent, for several picked issues at once too; the command palette and `M` then `P` do the same, and the issue's
  sidebar has a Parent row. Issues can be marked as blocked by others or as blocking them: **Mark As** in the
  right-click menu, `M` then `B` or `M` then `X` as in Linear, or the Blocked by and Blocking rows in the sidebar. The
  issue lists what blocks it and what it blocks, each a click away, and a blocked issue carries a red flag on its card
  and list row that lists its blockers when clicked. These are GitHub's own sub-issues and issue dependencies, so
  github.com shows the same. On iPhone and iPad they are in the long-press menu, behind the plus beside the
  sub-issues and in the issue's properties.
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
- The fastlane lanes turn on iCloud for the App ID before they fetch the App Store profiles, add a language that is
  new in `fastlane/metadata` to the listing with its name and subtitle (deliver leaves those out), and stop with the
  reason while an earlier version of either platform is still in review.

### Fixed

- Turning an iPad from portrait to landscape could quit the app when the sidebar appeared.
- HTML comments such as the hints issue templates leave (`<!-- … -->`) no longer show in comments and the peek;
  GitHub hides them too.
- Renaming a column, adding one and the token field on the sign-in screen take the keyboard focus straight away,
  so you can type without clicking into them first.
- On iPad, a card dragged onto the board in another window of the app lands there. Before, that window refused it,
  or moved the card it had last dragged itself instead. A card of one project can't be dropped on another's board.
- Deleting issues follows GitHub's rules in organizations too: besides admin rights in the repository, it needs the
  owners' permission for repository admins to delete issues, and Delete is unavailable without it. When your rights
  change, the app notices at the next ⌘R or pull-to-refresh, or within half an hour, without anything on the issues
  changing.

## [0.2.0] - 2026-10-06

### Added

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

[Unreleased]: https://github.com/lukaskaibel/issues-for-github/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/lukaskaibel/issues-for-github/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/lukaskaibel/issues-for-github/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/lukaskaibel/issues-for-github/releases/tag/v0.1.0
