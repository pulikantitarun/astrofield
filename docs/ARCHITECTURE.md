# Architecture

## Components

### Flutter client

The Android/iOS client is landscape-first and organized around nine operational workspaces. It discovers the bridge at `astroberry.local` or `10.42.0.1`, transfers the phone location with permission, and sends authenticated local HTTP requests.

### AstroField bridge

`bridge/astrofield_bridge.py` is a Python 3 threaded HTTP service on port `8765`. Its responsibilities include:

- INDI device discovery and selected equipment control through PyIndi.
- Ekos Focus and Capture coordination through the KStars DBus interfaces.
- PHD2 JSON-RPC forwarding and Guiding Assistant calculations/history.
- Mount, framing catalogue, equipment profile and system status endpoints.
- Image storage inventory/download and Pi state persistence.

Mutable state is stored under `/var/lib/astrofield-bridge`; image data defaults to `/srv/astrofield/images`.

### External systems

AstroField integrates with existing astronomy software instead of replacing it:

- **INDI** owns device-driver communication.
- **KStars/Ekos** owns optical trains, capture sequencing, focus algorithms and plate-solving workflows.
- **PHD2** owns guiding, calibration and guide algorithms.
- **ASTAP** may provide local plate-solving catalogues.
- **Samba/Avahi** expose image storage and LAN discovery.

## Autofocus state flow

```text
manual / temperature / time trigger
                |
                v
       active capture sequence?
          | yes         | no
          v             v
finish current frame   configure focus
pause Ekos Capture          |
          +-----------------+
                v
          run Ekos focus
        / success    \ failure
       v              v
record result      record failure
resume Capture     remain paused by default
```

Temperature/time automation needs a successful focus result to establish its initial baseline. Temperature automation is enabled only when a compatible temperature source is reported.

## Trust boundaries

The current bridge uses a shared bearer-style token in `X-AstroField-Token`. This protects against accidental unauthenticated LAN control but does not encrypt traffic. Never expose the bridge to the public internet. Production remote access requires TLS, per-installation identity, revocable sessions and a private relay or VPN.

## Design principles

- The Pi remains authoritative so automation can continue if the phone sleeps.
- Finish an exposure before pausing a sequence where Ekos supports it.
- Default to remaining paused after failed autofocus.
- Require explicit confirmation before supported mount-side configuration changes.
- Clearly distinguish implemented, hardware-validated and planned functions.
