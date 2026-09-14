# Check a release download

Run these checks on the exact draft ZIP before publication. Use an Apple Silicon Mac on macOS 15 and another on macOS 27. Record the OS build, app version, ZIP checksum, and results in the draft release notes. GitHub build checks do not replace tests on a Mac with a battery.

1. Download the draft ZIP and checksum in a browser. In the download directory, run `shasum -a 256 -c BatteryBar.app.zip.sha256`. It must report `OK`.
2. Open the ZIP in Finder. Before first launch, confirm that the app retains its download quarantine attribute with `xattr -p com.apple.quarantine BatteryBar.app`. Do not remove this attribute or change macOS security settings.
3. From the matching source revision, run `bash scripts/verify-app.sh /absolute/path/to/BatteryBar.app --release`. It must pass signature, Apple approval ticket, and Gatekeeper checks.
4. Drag the app to Applications, then open it. The normal downloaded-app confirmation is acceptable. A damaged-app warning or an unidentified-developer override is a failure.
5. Confirm that the menu reading appears and the panel opens. Check charging and battery power. Wait at least 15 seconds in each state to allow the display average to settle. Check that charge percentage agrees with macOS. Missing temperature or health must show **Unavailable**.
6. Put the Mac to sleep and wake it. Confirm that readings resume and the panel still opens. Check the panel in light and dark appearance, and collapse and expand Details.
7. Click **Quit**, wait at least 10 seconds, and confirm that the app stays closed. Reopen it and confirm that saved history still loads.
8. Repeat first launch from a fresh user account with network access disabled to check the attached approval ticket. Keep normal macOS security settings enabled.

After publication, check that version 1.0 shows **Update Available** and opens the v1.1.0 release page. Automatic checks can wait up to six hours after a previous successful check.

If any check fails, keep the release as a draft. Fix the fault and prepare a new version and tag; do not replace assets in an already published release.
