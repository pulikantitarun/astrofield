# Roadmap

This roadmap is directional and does not promise release dates.

## Before an alpha release

- Replace build-time shared tokens with per-installation pairing and revocation.
- Add encrypted remote connectivity through a private relay or supported VPN design.
- Split the Flutter application into testable feature modules and typed API models.
- Add bridge unit/integration tests and an API schema.
- Complete real-hardware validation for common INDI cameras, focusers, mounts and filter wheels.
- Add visible connection/command audit history and emergency stop behavior.

## Imaging and focusing

- Complete capture sequence editing, FITS naming/header validation and restart recovery.
- Validate cooling, dew-heater, gain and offset capability mapping across drivers.
- Expand autofocus metrics, adaptive focus and optical-train setting discovery.
- Add rotator-assisted and manual camera-rotation guidance.

## Guiding and polar alignment

- Complete PHD2 Assistant history, backlash graphing, seeing analysis and recommendation application safeguards.
- End-to-end two/three-point polar alignment with solve refresh and altitude/azimuth correction visualization.

## Sky and planning

- Offline catalogue packaging and updates.
- Live telescope overlay, framing assistant and rotation-aware mosaic panels.
- Session planner with visibility, meridian, moon and weather constraints.

## Distribution

- Signed Android alpha builds.
- Physical iPhone/iPad testing and TestFlight preparation.
- Reproducible Pi installer/updater with rollback.
- Contributor hardware compatibility matrix.
