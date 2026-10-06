# Notes for Claude

[CONTRIBUTING.md](CONTRIBUTING.md) applies to you as to everyone. This file adds one duty that is easy to forget.

## Keep the repository in step with the app

The README, the changelog, the screenshots and the repository's page on GitHub describe the app to people who have
never run it. When a change alters what the app does or how it looks, update them on the same branch as the change,
without being asked. Before calling such a change done, go through this list and do what applies:

- **CHANGELOG.md:** a line under `[Unreleased]` (Added, Changed or Fixed) for everything a user would notice, written
  for users and in the style of the entries already there.
- **README.md:** the tour and "iPhone and iPad" (what a feature looks like and does), "What it does", the shortcut and
  gesture tables in "Using it" and "Using it on iPhone and iPad", "Not there yet" (take out what now exists), the
  requirements and setup steps, and "For contributors" when folders or tools change. Plain and specific, no hype.
- **Screenshots:** when a change shows in a picture the README has (board, drag, issue, command palette, new issue,
  list; the iPhone and iPad screens), take them again:
  - iPhone and iPad first, if they changed: `Tools/app-store-screenshots.sh`
  - then `Tools/readme-images.sh`, which records the Mac app on the sample data and lays out every README image, the
    website's pictures and `Design/social-preview.png`. It needs an unlocked screen and brings the app to the front for
    about two minutes. If it can't run (screen locked, no permission), say so; don't commit old pictures as if they
    were new.
  - Look at every image before committing it.
  - A headline feature may deserve its own picture: add a scene to `Tools/readme-images.sh` and
    `Tools/readme-images/build.py`, and a section with a light and a dark `<picture>` to the README, like the others.
- **Sample data** (`Store/DemoData.swift`): the screenshots and the App Store listing are taken on it, so a new feature
  needs something there to show it with.
- **Website** (`Website/`, published by `.github/workflows/website.yml`): the home page's tagline, the support page's
  answers (sign-in, what shows up, offline, removing data) and the privacy policy, which says the same as `PRIVACY.md`
  plus what the website does. When the app is in the App Store, the "Coming soon" note on the home page becomes
  Apple's badge linked to it (see the comment in `Website/index.html`).
- **App Store listing** (`fastlane/metadata`, see `Design/app-store.md`): the description when what the app does
  changes, and from the second version on the "What's New" in `release_notes.txt`. Retake the App Store screenshots
  when a change shows in them: `Tools/app-store-screenshots.sh` (iPhone, iPad) and `Tools/mac-app-store-screenshots.sh`
  (Mac; runs in the background, the window stays off screen).
- **The repository on GitHub:** when the app's scope changes (a platform, a headline feature), update the description
  and topics with `gh repo edit lukaskaibel/issues-for-github --description "…" --add-topic …` and say that you did.
  When `Design/social-preview.png` changed, tell the user to upload it under Settings › General › Social preview;
  GitHub has no API for it.
- **Releases:** the version in `Config/Shared.xcconfig`, the version badge in the README and the changelog heading
  change together, and the release gets a `v` tag.

In the pull request, say which of these you updated and which you left alone on purpose.
