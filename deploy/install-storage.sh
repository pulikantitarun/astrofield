#!/bin/sh
set -eu

install -d -o astroberry -g astroberry -m 2770 /srv/astrofield/images
install -d -m 0755 /etc/avahi/services
install -m 0644 /tmp/astrofield-avahi.service /etc/avahi/services/astrofield.service
install -m 0644 /tmp/astrofield-samba.conf /etc/samba/astrofield.conf
if ! grep -Fqx 'include = /etc/samba/astrofield.conf' /etc/samba/smb.conf; then
    printf '\ninclude = /etc/samba/astrofield.conf\n' >> /etc/samba/smb.conf
fi
testparm -s >/dev/null
install -m 0755 /tmp/astrofield_bridge.py /opt/astrofield-bridge/astrofield_bridge.py
if [ -f /tmp/astrofield-bridge.service ]; then
    install -m 0644 /tmp/astrofield-bridge.service /etc/systemd/system/astrofield-bridge.service
    systemctl daemon-reload
fi
systemctl restart astrofield-bridge
systemctl restart avahi-daemon
systemctl restart smbd nmbd
