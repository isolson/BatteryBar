# Release BatteryBar

Public releases require Xcode 26 or later for the layered app icon, a **Developer ID Application** certificate, and Apple notarization. An Apple Development certificate is not sufficient. Follow [Apple's signing requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## One-time setup

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/enroll/). After activation, create a **Developer ID Application** certificate in [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list). Use Keychain Access to create the certificate request, then install the certificate on the same Mac. Keep its private key.
2. In Keychain Access, export that certificate and private key as a password-protected `.p12` file. Create an [app-specific password](https://support.apple.com/en-us/102654) for your Apple Account. Find your Team ID in the developer account's membership details.
3. Add these repository secrets under **Settings → Secrets and variables → Actions**. Enter secrets there, not in source files or chat. See [GitHub's certificate setup](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications).

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64 of the `.p12` file; use `base64 -i certificate.p12 \| pbcopy` |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The `.p12` export password |
| `DEVELOPER_ID_APPLICATION` | Full `Developer ID Application: … (TEAMID)` name from `security find-identity -v -p codesigning` |
| `APPLE_ID` | Your Apple Account email |
| `APPLE_TEAM_ID` | Your Team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | The app-specific password |

The release job imports credentials into a temporary keychain and removes them when it ends. This app does not require a provisioning profile.

## Prepare and publish

1. Set the version and build number in `BatteryBar/Resources/Info.plist`. Update `docs/release-notes.md`. For this release, use version `1.1.0`, build `2`.
2. Run `make test build` and `bash scripts/test-release.sh`. Merge the change into `main` after the macOS 15 and 26 checks pass.
3. Tag that revision as `v1.1.0` and push the tag. **Prepare release** checks the tag, builds, signs, notarizes, attaches Apple's approval ticket, and verifies the extracted ZIP. It creates a draft release with `BatteryBar.app.zip` and `BatteryBar.app.zip.sha256`. A failed check stops the release.
4. Complete the [download checks](release-checks.md) on the exact draft assets. Publish the draft only after they pass. Keep previous releases. Version 1.0 will then find the new release through its existing update link.

## Release from this Mac

Store notarization credentials using the interactive prompt:

```bash
xcrun notarytool store-credentials BatteryBar
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE=BatteryBar RELEASE_TAG=v1.1.0 make release
```

The verified ZIP and checksum are written to `dist/`. For a profile in a separate keychain, also set `NOTARY_KEYCHAIN` to its path. A local release command does not publish to GitHub. If notarization fails, fix the reported error and run the command again; do not upload a local development build.
