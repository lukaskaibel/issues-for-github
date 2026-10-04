# Privacy

Git Issues is a client for GitHub. It has no server, no accounts of its own, no analytics and no advertising, and it
collects nothing about you.

## What the app stores, and where

- **Your GitHub login** (an access token) is kept in the keychain of your device. When you use the app on more than
  one of your devices, it is stored in iCloud Keychain so they all stay signed in; Apple encrypts it end to end.
- **A copy of your projects and issues** is kept in a database on your device, so the app opens instantly and works
  offline. Signing out deletes it.
- **Preferences** such as the appearance, the app icon and the order of list sections stay on your device.

## What is sent, and to whom

- The app talks to **GitHub** only: `api.github.com` to read and change your projects and issues, `github.com` while
  you sign in, and GitHub's image servers for avatars and pictures in issue descriptions.
- Your login is sent to nobody but GitHub. What GitHub does with your data is described in
  [GitHub's privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement).
- Nothing is sent to the developer of the app or to any other party.

## Sample data

"Explore with Sample Data" shows made-up projects stored on your device only. Nothing you do there is sent anywhere.

## Questions

Open an issue in the [repository](https://github.com/lukaskaibel/issues-for-github/issues). Security problems are
best reported privately, as described in [SECURITY.md](SECURITY.md).
