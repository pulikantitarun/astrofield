# Contributing to AstroField

Thank you for helping build a safer open-source mobile controller for Astroberry rigs.

## Before starting

- Search existing issues and open a focused issue for substantial features or equipment support.
- Never include passwords, pairing tokens, Wi-Fi credentials, FITS data containing private coordinates, SSH keys or device serials.
- Treat mount motion, cooling, focusing and unattended capture changes as safety-sensitive.

## Development workflow

1. Fork the repository and create a short feature branch.
2. Keep changes focused and document hardware assumptions.
3. Add or update tests where practical.
4. Run:

   ```bash
   dart format --output=none --set-exit-if-changed lib test
   flutter analyze
   flutter test
   python3 -m py_compile bridge/astrofield_bridge.py
   ```

5. Open a pull request using the template.

## Hardware changes

Include the Pi model and OS, KStars/Ekos/INDI/PHD2 versions, device names and drivers, network topology, expected behavior and observed behavior. State clearly whether the change was tested on real hardware, a simulator or source-only checks.

Commands that move a mount/focuser, change cooling, alter guiding parameters or resume an imaging sequence must use explicit limits and safe failure behavior. Mount-side setting changes require user confirmation.

## License

By submitting a contribution, you agree that it is licensed under AGPL-3.0-or-later, consistent with this repository.
