#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Run this script as root (sudo ./install.sh)" >&2
  exit 1
fi

SCRIPT_SRC="sys-health-check.sh"
CONFIG_SRC="sys-health-check.conf"

SCRIPT_DST="/usr/local/bin/sys-health-check.sh"
CONFIG_DST="/etc/sys-health-check.conf"

SERVICE_FILE="/etc/systemd/system/sys-health-check.service"
TIMER_FILE="/etc/systemd/system/sys-health-check.timer"

if [ ! -f "$SCRIPT_SRC" ]; then
  echo "File not found: $SCRIPT_SRC" >&2
  exit 1
fi

if [ ! -f "$CONFIG_SRC" ]; then
  echo "File not found: $CONFIG_SRC" >&2
  exit 1
fi

install -m 0755 "$SCRIPT_SRC" "$SCRIPT_DST"

if [ ! -f "$CONFIG_DST" ]; then
  install -m 0640 "$CONFIG_SRC" "$CONFIG_DST"
else
  echo "Config already exists, not overwriting: $CONFIG_DST"
fi

cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=System health check
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_DST

[Install]
WantedBy=multi-user.target
EOF

cat >"$TIMER_FILE" <<EOF
[Unit]
Description=Daily system health check

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now sys-health-check.timer

echo "Installed sys-health-check:"
echo "  Script:  $SCRIPT_DST"
echo "  Config:  $CONFIG_DST"
echo "  Service: $SERVICE_FILE"
echo "  Timer:   $TIMER_FILE"
echo "Timer is enabled and will run daily."
echo "You can run a manual check with: sudo sys-health-check.sh"
