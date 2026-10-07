# Privacy

Issues is a client for GitHub. It has no server, no accounts of its own, no analytics and no advertising, and it
collects nothing about you.

## What the app stores, and where

- **Your GitHub login** (an access token) is kept in the keychain of your device. When you use the app on more than
  one of your devices, it is stored in iCloud Keychain so they all stay signed in; Apple encrypts it end to end.
- **A copy of your projects and issues**, and of your GitHub notifications about issues and pull requests (the
  Inbox), is kept in a database on your device, so the app opens instantly and works offline. Signing out deletes it.
- **Inbox entries you snoozed or marked unread**, and whether you read or archived an issue that was due, are kept in
  iCloud's key-value storage of your Apple account, so your devices agree; GitHub has no place for them. They hold
  the notification's number on GitHub (or the issue's id and the day it was due) and dates, nothing else, and are
  removed after 30 days. Only you and your devices can read them.
- **Preferences** such as the appearance, the app icon, the order of list sections and the time of reminders stay on
  your device.
- **Reminders** of issues that are due are notifications your device schedules itself from the due dates it has
  synced. They are not sent anywhere, and turning them off in Settings removes them.

## What is sent, and to whom

- The app talks to **GitHub** only: `api.github.com` to read and change your projects, issues and notifications,
  `github.com` while you sign in, and GitHub's image servers for avatars and pictures in issue descriptions.
- Snoozed and unread Inbox entries go to **your iCloud account**, through Apple, as described above.
- Your login is sent to nobody but GitHub. What GitHub does with your data is described in
  [GitHub's privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement).
- Nothing is sent to the developer of the app or to any other party.

## Sample data

"Explore with Sample Data" shows made-up projects stored on your device only. Nothing you do there is sent anywhere.

## On the website

The same policy is on the [website](https://lukaskaibel.github.io/issues-for-github/privacy/), together with what the
website itself does (it is hosted by GitHub Pages and sets no cookies) and your rights under the GDPR.

## Questions

Open an issue in the [repository](https://github.com/lukaskaibel/issues-for-github/issues). Security problems are
best reported privately, as described in [SECURITY.md](SECURITY.md).
