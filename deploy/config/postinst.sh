#!/bin/bash
function undo_changes(){
  /usr/bin/rpi-kiosk --install_remove >/dev/null 2>&1
  rm -rf "/usr/lib/rpi-kiosk" >/dev/null 2>&1
  rm -f "/etc/rpi-kiosk/kiosk.conf" >/dev/null 2>&1
  exit 1
}
echo "Configure lightdm ..."
mkdir -p "/usr/share/lightdm/lightdm.conf.d"
rm -f "/usr/share/lightdm/lightdm.conf.d/61-lightdm-gtk-greeter.conf" >/dev/null 2>&1
cat <<EOF | sudo tee /usr/share/lightdm/lightdm.conf.d/61-lightdm-gtk-greeter.conf >/dev/null 2>&1
[Seat:*]
greeter-session=lightdm-gtk-greeter
EOF
if [ -f "/usr/bin/rpi-kiosk" ]; then
  /usr/bin/rpi-kiosk --install_start >/dev/null 2>&1
  [ $? -ne 0 ] && undo_changes
fi
exit 0
