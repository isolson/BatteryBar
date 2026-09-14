BatteryBar 1.1.0 supports Apple Silicon MacBooks with macOS 13 or later, including macOS 27.

- Fix battery health readings when macOS supplies capacity values in nested battery data.
- Show **Unavailable** for missing temperature and health measurements.
- Clear stale readings after a failed battery read and resume on the next successful read.
- Include the menu panel update and crash recovery fixes made since version 1.0.0.
- Provide a Developer ID signed and notarized app with an attached Apple approval ticket. This addresses the damaged-app download reported in issue #3.

Download `BatteryBar.app.zip`, open the ZIP, and drag `BatteryBar.app` to Applications. Open the app and click its readings in the menu bar. The `.sha256` file is an optional download checksum.
