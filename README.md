# InputBattery

A small macOS menu bar app with a desktop widget that shows the battery level of
Bluetooth keyboards and mice and warns you before the batteries run out.

Built for UGREEN devices (K552 keyboard, M751 mouse) and AirPods, but it works with every Bluetooth
LE device that offers the standard Battery Service (0x180F) and every Apple accessory macOS
reports a battery level for (AirPods and case, AirPods Max, Magic Keyboard/Mouse/Trackpad,
Bluetooth headsets that report their battery over the hands-free profile).

## Features

- Menu bar: icon and percentage for every connected device, orange below the warning level, red below the critical level
- Notifications when a device drops below the warning level (default 20 %) and the critical level (default 10 %); the critical warning repeats every 12 hours
- Desktop/Notification Center widget (small and medium)
- Remembers the last known value when a device is switched off
- Open at login, English and German

## Requirements

- macOS 14 or later
- Devices must be connected via **Bluetooth**, not via the 2.4 GHz USB receiver
  (the receiver does not pass the battery level on to macOS)

## Build

Requires Xcode (the widget extension must be built by Xcode; a hand-assembled
bundle crashes on launch).

```sh
./build.sh
ditto build/InputBattery.app /Applications/InputBattery.app
open /Applications/InputBattery.app
```

On first launch macOS asks for Bluetooth and notification access.
Add the widget via right-click on the desktop › Edit Widgets › InputBattery.

## How it works

The app reads the Battery Level characteristic (0x2A19) through CoreBluetooth and
subscribes to change notifications. It writes the values to
`~/Library/Application Support/InputBattery/status.json`; the sandboxed widget reads
this file through a read-only file exception.

Devices running on AA/AAA batteries estimate the percentage from the voltage, so the
value tends to drop in steps.

Made with the help of Claude (Anthropic).

## License

MIT
