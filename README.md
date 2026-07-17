# AstroField

AstroField is an open-source, landscape-first Android and iOS controller for an astrophotography rig running Astroberry on a Raspberry Pi. The Flutter app communicates with a small authenticated Python bridge on the Pi and coordinates Ekos, INDI, PHD2, KStars, ASTAP and local image storage.

> **Development status:** AstroField is an early, hardware-tested prototype, not yet a production observatory controller. The Android application installs and runs on real hardware, and the bridge is deployed on the development Astroberry Pi. Hardware-dependent operations must be tested with each equipment combination before unattended use.

## Current capabilities

- Landscape control surface with Rig, Sky, Camera, Focus, Guide, Gear, Polar, System and Session workspaces.
- Phone location transfer to Astroberry with explicit permission and token authentication.
- Equipment profiles and INDI driver discovery for mounts, main/guide cameras, focusers, filter wheels and related devices.
- Main-camera exposure, gain, offset, cooling and filter-oriented control surfaces.
- Dedicated autofocus workspace with manual movement, absolute positioning, backlash, Ekos autofocus, temperature/time triggers and focus-run history.
- Safe autofocus orchestration: finish the current exposure, pause Capture, focus, resume after success, and remain paused after failure by default.
- PHD2 status/RPC integration and Guiding Assistant workflows, including backlash results and recommendations.
- Sky catalogue search, visible-target data, framing and mosaic planning foundations.
- Polar-alignment workflow foundations with correction direction and refresh support.
- Pi-hosted FITS storage status, browser/download endpoints, Samba sharing and Avahi discovery.
- System and ASTAP catalogue visibility for Pi maintenance workflows.

## Architecture

```text
Android / iOS Flutter app
          |
          | HTTP + X-AstroField-Token (local network)
          v
AstroField bridge on Raspberry Pi :8765
    |          |          |          |
   INDI      Ekos DBus    PHD2     filesystem/Samba
    |          |          |          |
 mount, cameras, focuser, guider, FITS images
```

The app tries `astroberry.local` and the Astroberry hotspot address `10.42.0.1`. The bridge binds to the Pi network interfaces and rejects protected requests unless the configured pairing token is supplied. See [Architecture](docs/ARCHITECTURE.md) for boundaries and safety behavior.

## Repository layout

| Path | Purpose |
| --- | --- |
| `lib/` | Flutter application and control workspaces |
| `android/`, `ios/` | Native mobile platform projects |
| `bridge/` | Python Astroberry/Ekos/INDI/PHD2 bridge and systemd unit |
| `deploy/` | Pi installation, Samba, Avahi and verification files |
| `assets/` | Splash and night-sky artwork |
| `test/` | Landscape Flutter widget tests |
| `docs/` | Architecture, Pi setup and roadmap |

## Build the mobile app

Requirements: Flutter with a Dart 3.12-compatible SDK, Android Studio/Android SDK for Android builds, and Xcode on macOS for iOS builds.

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --dart-define=ASTROFIELD_TOKEN=replace-with-a-unique-token
```

Never commit a real pairing token. Production pairing and secure remote access are still roadmap items; the current token is injected at build time and is intended for trusted local-network development.

## Install the Pi bridge

Read [Pi installation](docs/PI_INSTALLATION.md) before running commands. The bridge expects an Astroberry-style system with Python 3, KStars/Ekos, INDI, PHD2 and `gdbus`. PyIndi is optional for source-only checks but required for live INDI control.

At minimum, configure a unique token in `/etc/astrofield-bridge.env`:

```ini
ASTROFIELD_TOKEN=generate-a-long-random-value
ASTROFIELD_STORAGE_ROOT=/srv/astrofield/images
```

Do not expose port `8765`, INDI or PHD2 directly to the public internet. Use a private VPN or a properly authenticated relay when remote connectivity is implemented.

## Validation

The repository CI runs Flutter formatting, analysis, widget tests and Python syntax checks. Local validation:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
python3 -m py_compile bridge/astrofield_bridge.py
```

## Contributing

Issues and pull requests are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md), follow the [Code of Conduct](CODE_OF_CONDUCT.md), and report vulnerabilities according to [SECURITY.md](SECURITY.md). Hardware reports should include the Pi model/OS, KStars/INDI/PHD2 versions, optical train and exact device drivers, with credentials removed.

## License

AstroField is licensed under the [GNU Affero General Public License v3.0 or later](LICENSE). If you modify AstroField and make it available over a network, the AGPL requires you to offer the corresponding source code to users of that service.

Astroberry, KStars, Ekos, INDI, PHD2 and ASTAP are separate projects with their own trademarks and licenses. AstroField is not affiliated with or endorsed by their maintainers.
