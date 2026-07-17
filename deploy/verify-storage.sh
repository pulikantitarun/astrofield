#!/bin/sh
set -eu
python3 -m py_compile /opt/astrofield-bridge/astrofield_bridge.py
systemctl is-active astrofield-bridge avahi-daemon smbd nmbd
testparm -s 2>/dev/null | grep -A9 '^\[AstroField Images\]$'
token=$(sed -n 's/^ASTROFIELD_TOKEN=//p' /etc/astrofield-bridge.env)
curl -fsS -H "X-AstroField-Token: $token" http://127.0.0.1:8765/api/v1/storage/status
printf '\n'
curl -fsS -H "X-AstroField-Token: $token" http://127.0.0.1:8765/api/v1/phd2/assistant/status
printf '\n'
curl -fsS -H "X-AstroField-Token: $token" http://127.0.0.1:8765/api/v1/phd2/assistant/history
printf '\n'
curl -fsS -H "X-AstroField-Token: $token" http://127.0.0.1:8765/api/v1/focus/status
printf '\n'
curl -fsS -H "X-AstroField-Token: $token" http://127.0.0.1:8765/api/v1/focus/config
printf '\n'
curl -fsS -H "X-AstroField-Token: $token" http://127.0.0.1:8765/api/v1/focus/history
printf '\n'
curl -fsS http://127.0.0.1:8765/api/v1/equipment/profiles
printf '\n'
