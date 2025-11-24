#!/bin/bash
if [ "$(which rpi-kiosk)" != "" ] && [ "$1" == "install" ]; then
  echo "The command \"rpi-kiosk\" is already present. Can not install this."
  echo "File: \"$(which rpi-kiosk)\""
  exit 1
fi
exit 0
