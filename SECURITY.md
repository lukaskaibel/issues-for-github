# Security

The app handles a GitHub access token, so security reports are taken seriously.

Please report vulnerabilities privately through
[GitHub's private vulnerability reporting](https://github.com/lukaskaibel/git-issues-mac-app/security/advisories/new)
rather than in a public issue. You will get a reply as soon as possible.

What the app does with your token: it is kept in the keychain (in iCloud Keychain when your Mac, iPhone and iPad
share the login, or read from the GitHub CLI on a Mac when you chose that option) and sent only to `api.github.com`
and, during OAuth sign-in, `github.com`. See [PRIVACY.md](PRIVACY.md) for everything the app stores and sends.
