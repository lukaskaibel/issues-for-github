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
4. Open a pull request against `main` and describe what changed and how you checked it.

Every pull request is reviewed and merged by the maintainer; nothing lands on `main` without that approval.

## What to keep in mind

- **GitHub stays the source of truth.** Don't add state that teammates without the app would need.
- **Changes go through the queue.** Anything that writes to GitHub is a `Mutation` (see `Sync/Mutation.swift`), so
  that it works offline and can be re-applied on top of fresh data. If you add one, add a test for it.
- **Never write to a project you didn't create while testing.** `gi-cli selftest` and the debug remote refuse to
  touch anything but a project titled "Git Issues Sandbox"; keep it that way.
- **Colours and animation timings come from `UI/Theme.swift`.** Every colour needs a light and a dark value.
- **Smoothness is a feature.** Lists and cards are drawn in one pass on purpose. If you change them, scroll a board
  with a few hundred issues before and after.
- **Show what changed.** A change people will notice gets a line in `CHANGELOG.md` under "Unreleased", and the README
  follows: its feature sections, the shortcut tables, "Not there yet", and the screenshots (`Tools/readme-images.sh`
  for the Mac, `Tools/app-store-screenshots.sh` for iPhone and iPad).
- Match the style of the code around you. Comments explain why, not what.

## Releases

Versions follow semantic versioning. The version lives in `Config/Shared.xcconfig`; each release gets an entry in
`CHANGELOG.md` and a tag of the form `v0.1.0`.
