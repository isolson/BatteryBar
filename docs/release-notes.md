BatteryBar 1.1.0 supports Apple Silicon MacBooks with macOS 13 or later, including macOS 27.

- Fix battery health readings when macOS supplies capacity values in nested battery data.
- Read temperature from child battery packs on macOS 27 and correct the conversion to Celsius.
- Show **Unavailable** for missing temperature and health measurements.
- Clear stale readings after a failed battery read and resume on the next successful read.
- Keep charger input visible in the panel and menu bar while plugged in, including when battery charging stops.
- At 100%, show “Finishing charge” while macOS still reports charging and hide the time to full.
- Align the power readings and labels, place the status below the power diagram, and size the menu panel to its content.
- Include the menu panel update and crash recovery fixes made since version 1.0.0.
- Provide a Developer ID signed and notarized app with an attached Apple approval ticket. This addresses the damaged-app download reported in issue #3.

Download `BatteryBar.app.zip`, open the ZIP, and drag `BatteryBar.app` to Applications. Open the app and click its readings in the menu bar. The `.sha256` file is an optional download checksum.
