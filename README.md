# BatteryBar

BatteryBar shows charger power, system power use, and battery charge in the macOS menu bar.

![BatteryBar detail panel](screenshot.png)

![BatteryBar menu bar](screenshot-menubar.png)

## Requirements

- An Apple Silicon MacBook (M1 or later)
- macOS 13 (Ventura) or later, including macOS 27

## Install

1. Download `BatteryBar.app.zip` from the [latest release](https://github.com/isolson/BatteryBar/releases/latest).
2. Open the ZIP file and drag `BatteryBar.app` to Applications.
3. Open BatteryBar from Applications. Its readings appear in the menu bar. Click them to open the detail panel.

Version 1.0.0 has a known signing fault ([issue #3](https://github.com/isolson/BatteryBar/issues/3)). If the latest release is still 1.0.0, build from source until the signed replacement is published. Do not change macOS security settings to open that download.

## Features

- Live charger wattage, system power use, and battery percentage
- Charging estimates and possible charger, cable, or temperature limits
- Voltage, current, temperature, cycle count, health, and time remaining
- Apps with high CPU use, as an estimate of energy use
- An update link when a newer GitHub release is available
- Polling that pauses during sleep and resumes on wake
- Crash recovery with a limit on repeated restarts

Measurements depend on the Mac and macOS version. Missing temperature or health values show **Unavailable**. Charging advice is an estimate.

## Build from source

Install Xcode Command Line Tools with `xcode-select --install`, then run:

```bash
git clone https://github.com/isolson/BatteryBar.git
cd BatteryBar
make build   # Create BatteryBar.app for local use
make run     # Build and open the app
make install # Copy the app to /Applications
make test    # Run the tests
```

Local builds use an ad hoc signature for use on your Mac. Public downloads use Developer ID signing and Apple's notarization service. See the [release guide](docs/releasing.md).

## How it works

BatteryBar reads the IOKit `AppleSmartBattery` registry every five seconds. It uses `SystemPowerIn` for charger input and voltage × current for battery power. On AC power, system use is charger input minus battery charging power. On battery power, it is battery discharge power.

Health uses the reported full-charge capacity divided by design capacity. BatteryBar reads these values from the top-level registry fields or the nested `BatteryData` fields.

Battery polling uses no command processes. The energy estimate runs `ps`; crash recovery uses a shell watcher. There are no third-party runtime packages. History is stored in `~/Library/Application Support/BatteryBar/history.json`.

## License

MIT
