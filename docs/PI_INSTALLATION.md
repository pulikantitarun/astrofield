# Raspberry Pi / Astroberry installation

This is a developer installation procedure. Back up the Pi before changing services.

## Prerequisites

- Astroberry-compatible Raspberry Pi installation
- Python 3 and PyIndi
- KStars/Ekos and INDI
- PHD2
- `gdbus`
- Samba and Avahi for image sharing/discovery

## Copy files

Copy these repository files to `/tmp` on the Pi:

- `bridge/astrofield_bridge.py`
- `bridge/astrofield-bridge.service`
- `deploy/astrofield-avahi.service`
- `deploy/astrofield-samba.conf`
- `deploy/install-storage.sh`

Create the application directory and configuration:

```bash
sudo install -d -m 0755 /opt/astrofield-bridge
sudo install -m 0755 /tmp/astrofield_bridge.py /opt/astrofield-bridge/
token="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
printf 'ASTROFIELD_TOKEN=%s\nASTROFIELD_STORAGE_ROOT=/srv/astrofield/images\n' "$token" \
  | sudo tee /etc/astrofield-bridge.env >/dev/null
sudo chmod 0600 /etc/astrofield-bridge.env
sudo sh /tmp/install-storage.sh
sudo systemctl enable --now astrofield-bridge
```

Store the generated token securely and inject it only into a private development build. Do not commit it.

## Verify

```bash
sudo systemctl status astrofield-bridge --no-pager
sudo journalctl -u astrofield-bridge -n 100 --no-pager
curl http://127.0.0.1:8765/api/v1/health
```

The authenticated verification script reads the token locally without printing it:

```bash
sudo /opt/astrofield-bridge/verify-storage.sh
```

## Network

The development app checks:

- `http://astroberry.local:8765/api/v1`
- `http://10.42.0.1:8765/api/v1`

Keep the service on a trusted LAN. Do not create public router port forwards for AstroField, INDI or PHD2.
