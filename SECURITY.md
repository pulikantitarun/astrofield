# Security policy

## Supported versions

AstroField is pre-release software. Security fixes are applied to the current `main` branch only.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for this repository. Do not open a public issue containing credentials, authentication bypasses or remotely exploitable details.

Include affected commit/version, environment, reproduction steps and impact. Remove pairing tokens, Wi-Fi credentials, SSH keys, public IP addresses and precise observatory coordinates.

## Deployment guidance

- Generate a unique, long `ASTROFIELD_TOKEN` for every installation.
- Keep port `8765`, INDI and PHD2 on a trusted LAN or private VPN.
- Do not forward those ports directly from an internet router.
- Protect `/etc/astrofield-bridge.env` and rotate a token if it may have been exposed.
- Review commands before testing with a powered mount, focuser, rotator or cooled camera.

The current build-time token flow is suitable for prototype testing, not public distribution. Per-installation pairing, encrypted transport and revocable remote sessions remain required before production remote access.
