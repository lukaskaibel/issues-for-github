# App Store listing

The Mac, iPhone and iPad apps are one App Store app (`com.lukaskbl.GitIssues`, universal purchase), released with
fastlane (see [Releasing](#releasing) below). fastlane uploads:

- the texts in `fastlane/metadata`: name, subtitle, description, keywords, promotional text, URLs, categories,
  copyright and the notes for App Review;
- the age rating in `fastlane/rating.json`;
- the screenshots in `Design/screenshots/app-store`: 6.9-inch iPhone and 13-inch iPad from
  `Tools/app-store-screenshots.sh`, Mac at 2880 × 1800 from `Tools/mac-app-store-screenshots.sh`, all on the sample
  data (`bundle exec fastlane screenshots` runs both).

The contact for App Review and an optional review account are in `fastlane/.env.secret`, which is not checked in.

The links point to the website in `Website/` (published to GitHub Pages): privacy policy
`https://lukaskaibel.github.io/issues-for-github/privacy/`, support `…/support/` and marketing the home page. The
license agreement is Apple's standard EULA; the website's terms add to it.

## Once, in App Store Connect

fastlane can't do these; set them when the app is created.

| Where | What |
|---|---|
| Apps › New App | Platforms **iOS** and **macOS**, name **Issues – Project Board** ("Issues" alone is taken; under the icon the app is still called Issues), primary language English (U.S.), bundle ID `com.lukaskbl.GitIssues`, SKU `issues`. |
| App Privacy | **Data Not Collected.** The app talks only to GitHub with the user's own login and has no server, analytics or ads. GitHub is the service the user signs in to, not a third party the developer shares data with. |
| Pricing and Availability | **Free**, all countries and regions. |
| Certificates, Identifiers & Profiles › Identifiers › `com.lukaskbl.GitIssues` | **iCloud** turned on (key-value storage only, no CloudKit containers), for the Inbox's snoozes and unread marks. fastlane turns it on before it fetches the App Store profiles, if it's off; profiles made before that are invalid afterwards, and fastlane makes new ones. |
| Users and Access › Integrations | The App Store Connect API key fastlane uses (App Manager or Admin, with access to certificates, identifiers and profiles). The builds are signed with the team's Apple Distribution certificate, which has to be in the keychain of the Mac that builds them, and the Mac's package with a Mac Installer Distribution certificate, which fastlane creates there the first time. |

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

## Languages

The listing is in English (U.S., the primary language) and in German (`de-DE`), French (`fr-FR`), Spanish (`es-ES`
and `es-MX`, the same text, so Spain and Latin America both get it), Portuguese (`pt-BR`), Russian (`ru`),
Japanese (`ja`), Korean (`ko`) and Chinese (`zh-Hans`), the languages the app speaks.

- **Name:** "Issues – Project Board" in every language. App names are unique across the App Store, and a translated
  descriptor could be taken; the subtitle and keywords carry each language's words instead.
- **Subtitle, description, promotional text and keywords** are translated, in the words of `Design/glossary.md`.
  Keywords are each language's own search words (up to 100 characters), not a translation of the English list, and
  keep "github".
- **URLs** point at the website in that language (`…/de/`, `…/de/support/`, `…/de/privacy/`).
- **Screenshots** are only uploaded for English; the App Store shows them for every language that has none of its
  own. The pictures stay English on purpose.

## What's New

The first version has none. From the second version on, write it in `fastlane/metadata/en-US/release_notes.txt`, for
users, from the changelog, and translate it into `release_notes.txt` in every other language's folder.

## Releasing

Releases go through [fastlane](https://fastlane.tools), for the Mac, iPhone and iPad together. It signs in to App Store
Connect with an API key, so there are no Apple ID prompts, and signs the builds with your team's Apple Distribution
certificate from the keychain and App Store profiles it fetches with the key. The first Mac build also creates a Mac
Installer Distribution certificate for the package; macOS then asks once whether it may be used (Always Allow). Once:

1. Create the app in App Store Connect for iOS and macOS with the bundle identifier `com.lukaskbl.GitIssues`, and set
   the few things fastlane can't ([Once, in App Store Connect](#once-in-app-store-connect) lists them).
2. Copy `fastlane/.env.secret.example` to `fastlane/.env.secret` and fill in the API key and the contact for App Review.
3. Set `GITHUB_CLIENT_ID` in `Config/Local.xcconfig`, so the builds offer "Sign in with GitHub".
4. Run `bundle install`.

Then:

```bash
bundle exec fastlane screenshots   # the App Store screenshots of the iPhone, iPad and Mac apps, on the sample data
bundle exec fastlane beta          # build the Mac, iPhone and iPad apps and upload them to TestFlight
bundle exec fastlane submit        # submit those builds for review once they're tested in TestFlight
bundle exec fastlane release       # or all in one: build, upload texts and screenshots, and submit
```

The texts are in `fastlane/metadata`; `bundle exec fastlane metadata` uploads them with the screenshots and nothing
else. `bundle exec fastlane ios <lane>` or `mac <lane>` does one platform. The Mac's App Store build runs in the App
Sandbox, as the Mac App Store requires, and leaves out the GitHub CLI sign-in, which can't work there; **Product ›
Archive** in Xcode makes the same build. Without an API key, `Tools/testflight.sh` and `Tools/testflight-mac.sh` upload
a build with the Apple ID under Xcode › Settings › Accounts.

Every change to the app on `main` also goes to TestFlight by itself, for the iPhone and iPad and for the Mac:
[`.github/workflows/testflight.yml`](../.github/workflows/testflight.yml) runs `bundle exec fastlane ios beta` and
`mac beta` on GitHub side by side, signed with certificates made for it (the workflow lists the secrets it needs). There
the Mac app is signed for the App Store from the start, so the Macs GitHub runs it on don't have to be registered with
the team. A TestFlight build carries the version it's on its way to and the date and time in Germany: once `v0.3.0` is
tagged, `0.4.0 (2026.1017.1047)` is the build of 17 October 2026 at 10:47. Its "What to Test" names the commit. So a
release goes: set its version in `Config/Shared.xcconfig`, let the builds of it reach TestFlight, `submit`, and tag it
after.

## A new version

While a version of either platform is waiting for review, in review or waiting to be released, App Store Connect keeps
the app's name, subtitle and languages locked, as both platforms share them, and takes no new version of that
platform. fastlane checks this first and stops with the reason; release the waiting version (or remove it from review)
and run it again. TestFlight builds (`bundle exec fastlane beta`) can go up at any time.

A language folder new in `fastlane/metadata` is added to the listing by the Fastfile itself, with its name, subtitle
and privacy policy, because deliver adds those only when a language the app already has changes.
