#!/bin/bash
if [ -f "/usr/bin/rpi-kiosk" ]; then
  if [ "$1" == "remove" ]; then
    "/usr/bin/rpi-kiosk" --install_remove >/dev/null 2>&1
    rm -rf "/usr/lib/rpi-kiosk" >/dev/null 2>&1
    rm -f "/etc/rpi-kiosk/kiosk.conf" >/dev/null 2>&1
  else
    /usr/bin/rpi-kiosk --install_update >/dev/null 2>&1
  fi
fi
exit 0
