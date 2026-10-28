# Contributing

Thanks for wanting to help. This is a small project with one maintainer, so a little coordination up front saves
everyone time.

## Before you start

- **Bugs:** open an issue with what you did, what you expected and what happened. Screenshots or a short recording
  help a lot for anything visual.
- **Features and larger changes:** open an issue first and describe the idea. The app is deliberately opinionated
  and small; not every feature fits, and it is better to find that out before you write the code.
- **Small fixes** (typos, obvious bugs): a pull request without an issue is fine.

## Making a change

1. Fork the repository and create a branch from `main`.
2. Build and run from Xcode (see the README). No setup is needed beyond signing in.
3. Run the tests: `cd Packages/GitIssuesKit && swift test`.
4. Open a pull request against `main`, describe what changed and how you checked it, and tick the box agreeing to the
   terms below.

Every pull request is reviewed and merged by the maintainer; nothing lands on `main` without that approval.

## Licensing your contribution

Issues is licensed under the GNU General Public License, version 3, with one additional permission, for linking with
elk-swift (see [License](README.md#license)). Lukas Kaibel holds the copyright in it, and that is why Issues can be on
TestFlight and the App Store: the GPL and Apple's terms don't fit together, so others can't put copies there, but the
copyright holder isn't bound by the GPL.

For that to stay true with your code in it, by opening a pull request you agree that:

1. your contribution is licensed under the same terms as the rest of Issues, the GPL version 3 with that additional
   permission; and
2. you also grant Lukas Kaibel a perpetual, worldwide, non-exclusive, royalty-free and irrevocable licence to use,
   copy, modify and distribute your contribution under other terms, including in builds for TestFlight, the App Store
   and other stores, free or paid, and in versions that aren't open source.

You keep the copyright in what you wrote, and you confirm that it is yours to give on these terms: you wrote it, or it
comes under a licence that allows this. The pull request template has a box to tick for it. If you'd rather not agree,
open an issue that describes the change instead.

## What to keep in mind

- **GitHub stays the source of truth.** Don't add state that teammates without the app would need.
- **Changes go through the queue.** Anything that writes to GitHub is a `Mutation` (see `Sync/Mutation.swift`), so
  that it works offline and can be re-applied on top of fresh data. If you add one, add a test for it.
- **Never write to a project you didn't create while testing.** `gi-cli selftest` and the debug remote refuse to
  touch anything but a project titled "Git Issues Sandbox"; keep it that way. Release builds don't show that project.
- **Every text is translated.** Never write English straight into a view: add the text to the String Catalog with a
  comment that says where it appears (`Tools/strings.py add`, or Xcode's catalog editor) and use its symbol, as in
  `Text(.newIssue)`. A new text needs all nine languages before it is merged, with the words in `Design/glossary.md`;
  if you can't translate it, say so in the pull request. `swift test` checks this.
- **Colours and animation timings come from `UI/Theme.swift`.** Every colour needs a light and a dark value.
- **Smoothness is a feature.** Lists and cards are drawn in one pass on purpose, and a card keeps its texts and colours
  from one paint to the next: what a new part of a card shows goes into its `CardText` or `CardInk`, so that it is kept
  by everything it depends on. A row of a board column is one view as well: the card paints what the column shows
  around it, because a column builds a row for every card that scrolls into view and each view in a row adds to that.
  A row of a board column or a list that animates something of its own, such as the hover fade of an epic's header or
  of a notification in the Inbox, ends with `.geometryGroup()` after what animates it: otherwise each of its texts
  takes on the animation and is drawn again on every frame of it. Buttons a row shows on hover are always in it and
  only fade in, over its texts rather than beside them: buttons put in on hover rebuild the row's layers each time, and
  texts that make room for them are drawn again on every frame. If you change any of this, time a board with a few
  hundred issues before and after: `Tools/board-timing.sh` moves the pointer over two long columns and scrolls one, and
  keeps each step with the layers it drew in `build/board-timing/`. The debug remote's `menusweep main` does the same
  over the window, for the Inbox.
- **Show what changed.** A change people will notice gets a line in `CHANGELOG.md` under "Unreleased", and the README
  follows: its feature sections, the shortcut tables, "Not there yet", and the screenshots (`Tools/readme-images.sh`
  for the Mac, `Tools/app-store-screenshots.sh` for iPhone and iPad).
- Match the style of the code around you. Comments explain why, not what.

## Releases

Versions follow semantic versioning. The version lives in `Config/Shared.xcconfig`; each release gets an entry in
`CHANGELOG.md` and a tag of the form `v0.1.0`.
