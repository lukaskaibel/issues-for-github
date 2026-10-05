# App Store listing

The Mac, iPhone and iPad apps are one App Store app (`com.lukaskbl.GitIssues`, universal purchase), released with
fastlane (see "Releasing to the App Store" in the README). fastlane uploads:

- the texts in `fastlane/metadata`: name, subtitle, description, keywords, promotional text, URLs, categories,
  copyright and the notes for App Review;
- the age rating in `fastlane/rating.json`;
- the screenshots in `Design/screenshots/app-store`: 6.9-inch iPhone and 13-inch iPad from
  `Tools/app-store-screenshots.sh`, Mac at 2880 × 1800 from `Tools/mac-app-store-screenshots.sh`, all on the sample
  data (`bundle exec fastlane screenshots` runs both).

The contact for App Review and an optional review account are in `fastlane/.env.secret`, which is not checked in.

## Once, in App Store Connect

fastlane can't do these; set them when the app is created.

| Where | What |
|---|---|
| Apps › New App | Platforms **iOS** and **macOS**, name **Issues**, primary language English (U.S.), bundle ID `com.lukaskbl.GitIssues`, SKU `issues`. If the name is taken: "Issues – Project Board". |
| App Privacy | **Data Not Collected.** The app talks only to GitHub with the user's own login and has no server, analytics or ads. GitHub is the service the user signs in to, not a third party the developer shares data with. |
| Pricing and Availability | **Free**, all countries and regions. |
| Users and Access › Integrations | The App Store Connect API key fastlane uses (App Manager or Admin, with access to certificates, identifiers and profiles). |

## Why the answers are what they are

- **Name and subtitle** leave out "GitHub" and "Linear": other companies' trademarks don't belong there (Guidelines
  5.2.1 and 2.3.7). The keywords have "github", since the app is a client for it; the description says what it works
  with and that it isn't affiliated with or endorsed by GitHub.
- **Export compliance:** `ITSAppUsesNonExemptEncryption` is `NO` in the Info.plist; the app uses HTTPS only, through
  Apple's frameworks.
- **Content rights:** the app shows the user's own content from GitHub, under GitHub's terms.
- **Age rating:** none of the content questions apply. "User-generated content" is yes: issues and comments are written
  by people and shared with their collaborators.
- **Sign-in for App Review:** "Explore with Sample Data" on the first screen opens everything without a GitHub
  account, on every platform. Guideline 4.8 doesn't apply: the app is a client for GitHub and has no accounts of its own.

## What's New

The first version has none. From the second version on, write it in `fastlane/metadata/en-US/release_notes.txt`, for
users, from the changelog.
