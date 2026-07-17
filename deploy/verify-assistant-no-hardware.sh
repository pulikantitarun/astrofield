#!/bin/sh
set -eu
token=$(sed -n 's/^ASTROFIELD_TOKEN=//p' /etc/astrofield-bridge.env)
curl -fsS -X POST \
  -H "Content-Type: application/json" \
  -H "X-AstroField-Token: $token" \
  -d '{"duration_seconds":60,"measure_backlash":true}' \
  http://127.0.0.1:8765/api/v1/phd2/assistant/start
printf '\n'
sleep 2
curl -fsS -H "X-AstroField-Token: $token" \
  http://127.0.0.1:8765/api/v1/phd2/assistant/status
printf '\n'
if pgrep -x phd2 >/dev/null; then
  echo 'UNEXPECTED_PHD2_START'
  exit 1
fi
systemctl restart astrofield-bridge
