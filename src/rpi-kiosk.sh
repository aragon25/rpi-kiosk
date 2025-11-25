#!/bin/bash
##############################################
##                                          ##
##  kiosk-service                           ##
##                                          ##
##############################################

#get some variables
SCRIPT_TITLE="Raspberry Pi Kiosk (rpi-kiosk)"
SCRIPT_VERSION="1.46"
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
mountpoint -q /STATIC && STATIC_DIR="/STATIC" || STATIC_DIR="/etc"
CONFIG_FILE="/etc/rpi-kiosk/kiosk.conf"
STATE_FILE="$STATIC_DIR/rpi-kiosk_states"
PID_FILE="/run/rpi-kiosk-service.pid"
COM_FILE="/run/rpi-kiosk-com"
BASE_DIR="/usr/lib/rpi-kiosk"
KHOME_DIR="$BASE_DIR/kiosk-home"
EXITCODE=0

#!!!RUN RESTRICTIONS!!!
#only for raspberry pi (rpi5|rpi4|rpi3|all) can combined!
raspi="rpi4|rpi3"
#only for Raspbian OS (bookworm|bullseye|all) can combined!
rasos="bookworm|bullseye"
#only for cpu architecture (i386|armhf|amd64|arm64) can combined!
cpuarch=""
#only for os architecture (32|64) can NOT combined!
bsarch=""
#this aptpaks need to be installed!
aptpaks=( lightdm lightdm-gtk-greeter lightdm-autologin-greeter openbox xorg curl wmctrl feh numlockx xserver-xorg-video-dummy x11-xserver-utils )

#check commands
for i in "$@"
do
  case $i in
    -m|--adminmode)
    [ -z "$CMD" ] && CMD="adminmode" || CMD="help";
    #shift # past argument
    ;;
    -a|--activate)
    [ -z "$CMD" ] && CMD="activate" || CMD="help";
    #shift # past argument
    ;;
    -d|--deactivate)
    [ -z "$CMD" ] && CMD="deactivate" || CMD="help";
    #shift # past argument
    ;;
    -s|--settings)
    [ -z "$CMD" ] && CMD="settings" || CMD="help";
    #shift # past argument
    ;;
    --install_update)
    [ -z "$CMD" ] && CMD="install_update" || CMD="help";
    #shift # past argument
    ;;
    --install_start)
    [ -z "$CMD" ] && CMD="install_start" || CMD="help";
    #shift # past argument
    ;;
    --install_remove)
    [ -z "$CMD" ] && CMD="install_remove" || CMD="help";
    #shift # past argument
    ;;
    --service_pre)
    [ -z "$CMD" ] && CMD="service_pre" || CMD="help";
    shift # past argument
    ;;
    --service)
    [ -z "$CMD" ] && CMD="service" || CMD="help";
    shift # past argument
    ;;
    -v|--version)
    [ -z "$CMD" ] && CMD="version" || CMD="help";
    #shift # past argument
    ;;
    -h|--help)
    CMD="help"
    #shift # past argument
    ;;
    *)
    if [ "$i" != "" ]
    then
      echo "Unknown option: $i"
      exit 1
    fi
    ;;
  esac
done
[ "$CMD" == "" ] && CMD="help"

function do_check_start() {
  #check if superuser
  if [ $UID -ne 0 ]; then
    echo "Please run this script with Superuser privileges!"
    exit 1
  fi
  #check if service is already running or create pidfile if needed
  if [[ "$CMD" =~ "service" ]] && [ -e "$PID_FILE" ] && ps -p $(<"$PID_FILE") >/dev/null 2>&1; then
    echo "Service is already running!"
    exit 1
  elif [ "$CMD" == "service" ]; then
    echo $$ > "$PID_FILE"
  fi
  #check if raspberry pi 
  if [ "$raspi" != "" ]; then
    raspi_v="$(tr -d '\0' 2>/dev/null < /proc/device-tree/model)"
    local raspi_res="false"
    [[ "$raspi_v" =~ "Raspberry Pi" ]] && [[ "$raspi" =~ "all" ]] && raspi_res="true"
    [[ "$raspi_v" =~ "Raspberry Pi 3" ]] && [[ "$raspi" =~ "rpi3" ]] && raspi_res="true"
    [[ "$raspi_v" =~ "Raspberry Pi 4" ]] && [[ "$raspi" =~ "rpi4" ]] && raspi_res="true"
    [[ "$raspi_v" =~ "Raspberry Pi 5" ]] && [[ "$raspi" =~ "rpi5" ]] && raspi_res="true"
    if [ "$raspi_res" == "false" ]; then
      echo "This Device seems not to be an Raspberry Pi ($raspi)! Can not continue with this script!"
      exit 1
    fi
  fi
  #check if raspbian
  if [ "$rasos" != "" ]
  then
    rasos_v="$(lsb_release -d -s 2>/dev/null)"
    [ -f /etc/rpi-issue ] && rasos_v="Raspbian ${rasos_v}"
    local rasos_res="false"
    [[ "$rasos_v" =~ "Raspbian" ]] && [[ "$rasos" =~ "all" ]] && rasos_res="true"
    [[ "$rasos_v" =~ "Raspbian" ]] && [[ "$rasos_v" =~ "bullseye" ]] && [[ "$rasos" =~ "bullseye" ]] && rasos_res="true"
    [[ "$rasos_v" =~ "Raspbian" ]] && [[ "$rasos_v" =~ "bookworm" ]] && [[ "$rasos" =~ "bookworm" ]] && rasos_res="true"
    if [ "$rasos_res" == "false" ]; then
      echo "You need to run Raspbian OS ($rasos) to run this script! Can not continue with this script!"
      exit 1
    fi
  fi
  #check cpu architecture
  if [ "$cpuarch" != "" ]; then
    cpuarch_v="$(dpkg --print-architecture 2>/dev/null)"
    if [[ ! "$cpuarch" =~ "$cpuarch_v" ]]; then
      echo "Your CPU Architecture ($cpuarch_v) is not supported! Can not continue with this script!"
      exit 1
    fi
  fi
  #check os architecture
  if [ "$bsarch" == "32" ] || [ "$bsarch" == "64" ]; then
    bsarch_v="$(getconf LONG_BIT 2>/dev/null)"
    if [ "$bsarch" != "$bsarch_v" ]; then
      echo "Your OS Architecture ($bsarch_v) is not supported! Can not continue with this script!"
      exit 1
    fi
  fi
  #check apt paks
  local apt
  local apt_res
  IFS=$' '
  if [ "${#aptpaks[@]}" != "0" ]; then
    for apt in ${aptpaks[@]}; do
      [[ ! "$(dpkg -s $apt 2>/dev/null)" =~ "Status: install" ]] && apt_res="${apt_res}${apt}, "
    done
    if [ "$apt_res" != "" ]; then
      echo "Not installed apt paks: ${apt_res%?%?}! Can not continue with this script!"
      exit 1
    fi
  fi
  unset IFS
  #check config files integrity
  [[ ! $(file -b --mime-type "$(readlink -f "$CONFIG_FILE")" 2>/dev/null) =~ "text" ]] && config_write_conffile
  [[ ! $(file -b --mime-type "$(readlink -f "$STATE_FILE")" 2>/dev/null) =~ "text" ]] && config_delete_statfile
  chown 0:0 "$STATE_FILE" >/dev/null 2>&1
  chmod 644 "$STATE_FILE" >/dev/null 2>&1
  chown 0:0 "$CONFIG_FILE" >/dev/null 2>&1
  chmod 644 "$CONFIG_FILE" >/dev/null 2>&1
  local entry
  local test
  IFS=$'\n'
  test=($(find "$CONFIG_FILE.d" -maxdepth 1 -type f -name "*.conf" 2>/dev/null))
  if [ "${#test[@]}" != "0" ]; then
    for entry in ${test[@]}; do
      chown 0:0 "$entry" >/dev/null 2>&1
      chmod 644 "$entry" >/dev/null 2>&1
    done
  fi
  unset IFS
  #wmctrl bookworm fix
  if [ -e "/lib/ld-linux-armhf.so.3" ] && [ ! -e "/lib/arm-linux-gnueabihf/ld-linux.so.3" ];then
    ln -s /lib/ld-linux-armhf.so.3 /lib/arm-linux-gnueabihf/ld-linux.so.3
  fi
}

function config_read(){ # path, key, defaultvalue -> value
  local val=$( (grep -E "^${2}=" -m 1 "${1}" 2>/dev/null || echo "VAR=__UNDEFINED__") | head -n 1 | cut -d '=' -f 2-)
  #val=$(echo "${val}" | sed 's/ *$//g' | sed 's/^ *//g')
  val=$(echo "$val" | xargs)
  [ "${val}" == "__UNDEFINED__" ] && val="$3"
  printf -- "%s" "${val}"
}

function config_write(){ # path, key, value
  [ ! -e "$1" ] && touch "$1"
  sed -i "/^$(echo $2 | sed -e 's/[]\/$*.^[]/\\&/g').*$/d" "$1"
  echo "$2=$3" >> "$1"
}

function config_read_all(){
  unset CONFIG_HASHES
  declare -gA CONFIG_HASHES
  [ -f "$CONFIG_FILE" ] && CONFIG_HASHES["$CONFIG_FILE"]="$(md5sum "$CONFIG_FILE" | awk '{print $1}')"
  [ -f "$STATE_FILE" ] && CONFIG_HASHES["$STATE_FILE"]="$(md5sum "$STATE_FILE" | awk '{print $1}')"
  local first_username=$(getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody" { print $1; exit }')
  [ -z "$first_username" ] && first_username="pi"
  CONFIG_NODISP_RES=$(config_read "$CONFIG_FILE" CONFIG_NODISP_RES "640x480")
  CONFIG_BCKGRND=$(config_read "$CONFIG_FILE" CONFIG_BCKGRND "$BASE_DIR/kiosk-wallpaper.png")
  CONFIG_SCRNSVR=$(config_read "$CONFIG_FILE" CONFIG_SCRNSVR "0")
  CONFIG_SCRNBLK=$(config_read "$CONFIG_FILE" CONFIG_SCRNBLK "0")
  CONFIG_CLICKLOCK=$(config_read "$CONFIG_FILE" CONFIG_CLICKLOCK false)
  CONFIG_NUMLOCK=$(config_read "$CONFIG_FILE" CONFIG_NUMLOCK false)
  CONFIG_REBOOT=$(config_read "$CONFIG_FILE" CONFIG_REBOOT false)
  CONFIG_CURSOR_HIDE=$(config_read "$CONFIG_FILE" CONFIG_CURSOR_HIDE false)
  CONFIG_OSK_KIOSK=$(config_read "$CONFIG_FILE" CONFIG_OSK_KIOSK false)
  CONFIG_OSK_ADMIN=$(config_read "$CONFIG_FILE" CONFIG_OSK_ADMIN false)
  CONFIG_BROWSER_KIOSK_APPDATA=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_APPDATA false)
  CONFIG_BROWSER_KIOSK_KIOSKMODE=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_KIOSKMODE true)
  CONFIG_BROWSER_KIOSK_FULLSCREEN=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_FULLSCREEN true)
  CONFIG_BROWSER_KIOSK_MAXIMIZED=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_MAXIMIZED false)
  CONFIG_BROWSER_KIOSK_PANEL_POSITION=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_PANEL_POSITION false)
  CONFIG_BROWSER_KIOSK_PANEL_TITLE=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_PANEL_TITLE "RPI-KIOSK")
  CONFIG_BROWSER_KIOSK_PANEL_HOME=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_PANEL_HOME false)
  CONFIG_BROWSER_KIOSK_PANEL_CLOSE=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_PANEL_CLOSE false)
  CONFIG_BROWSER_ADMIN_APPDATA=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_APPDATA false)
  CONFIG_BROWSER_ADMIN_KIOSKMODE=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_KIOSKMODE false)
  CONFIG_BROWSER_ADMIN_FULLSCREEN=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_FULLSCREEN false)
  CONFIG_BROWSER_ADMIN_MAXIMIZED=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_MAXIMIZED true)
  CONFIG_BROWSER_ADMIN_PANEL_POSITION=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_PANEL_POSITION false)
  CONFIG_BROWSER_ADMIN_PANEL_TITLE=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_PANEL_TITLE "RPI-KIOSK")
  CONFIG_BROWSER_ADMIN_PANEL_HOME=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_PANEL_HOME false)
  CONFIG_BROWSER_ADMIN_PANEL_CLOSE=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_PANEL_CLOSE false)
  CONFIG_APPSTART=$(config_read "$CONFIG_FILE" CONFIG_APPSTART "$BASE_DIR/kiosk-browser/index.html")
  CONFIG_ADMIN_ALLOW=$(config_read "$CONFIG_FILE" CONFIG_ADMIN_ALLOW true)
  CONFIG_ADMIN_LOGINUSER=$(config_read "$CONFIG_FILE" CONFIG_ADMIN_LOGINUSER "$first_username")
  CONFIG_ADMIN_APPSTART=$(config_read "$CONFIG_FILE" CONFIG_ADMIN_APPSTART false)
  CONFIG_ADMIN_AUTOLOGOUT=$(config_read "$CONFIG_FILE" CONFIG_ADMIN_AUTOLOGOUT false)
  CONFIG_ADMIN_PANEL=$(config_read "$CONFIG_FILE" CONFIG_ADMIN_PANEL true)
  CONFIG_KIOSK_USERNAME=$(config_read "$CONFIG_FILE" CONFIG_KIOSK_USERNAME kiosk)
  CONFIG_KIOSK_USERGROUPS=$(config_read "$CONFIG_FILE" CONFIG_KIOSK_USERGROUPS false)
  local entry
  local test
  IFS=$'\n'
  test=($(find "$CONFIG_FILE.d" -maxdepth 1 -type f -name "*.conf" 2>/dev/null))
  if [ "${#test[@]}" != "0" ]; then
    for entry in ${test[@]}; do
      if [[ $(file -b --mime-type "$(readlink -f "$entry")" 2>/dev/null) =~ "text" ]]; then
        CONFIG_NODISP_RES=$(config_read "$entry" CONFIG_NODISP_RES "640x480")
        CONFIG_BCKGRND=$(config_read "$entry" CONFIG_BCKGRND $CONFIG_BCKGRND)
        CONFIG_SCRNSVR=$(config_read "$entry" CONFIG_SCRNSVR $CONFIG_SCRNSVR)
        CONFIG_SCRNBLK=$(config_read "$entry" CONFIG_SCRNBLK $CONFIG_SCRNBLK)
        CONFIG_CLICKLOCK=$(config_read "$entry" CONFIG_CLICKLOCK $CONFIG_CLICKLOCK)
        CONFIG_NUMLOCK=$(config_read "$entry" CONFIG_NUMLOCK $CONFIG_NUMLOCK)
        CONFIG_REBOOT=$(config_read "$entry" CONFIG_REBOOT $CONFIG_REBOOT)
        CONFIG_CURSOR_HIDE=$(config_read "$entry" CONFIG_CURSOR_HIDE $CONFIG_CURSOR_HIDE)
        CONFIG_OSK_KIOSK=$(config_read "$entry" CONFIG_OSK_KIOSK $CONFIG_OSK_KIOSK)
        CONFIG_OSK_ADMIN=$(config_read "$entry" CONFIG_OSK_ADMIN $CONFIG_OSK_ADMIN)
        CONFIG_BROWSER_KIOSK_APPDATA=$(config_read "$entry" CONFIG_BROWSER_KIOSK_APPDATA $CONFIG_BROWSER_KIOSK_APPDATA)
        CONFIG_BROWSER_KIOSK_KIOSKMODE=$(config_read "$entry" CONFIG_BROWSER_KIOSK_KIOSKMODE $CONFIG_BROWSER_KIOSK_KIOSKMODE)
        CONFIG_BROWSER_KIOSK_FULLSCREEN=$(config_read "$entry" CONFIG_BROWSER_KIOSK_FULLSCREEN $CONFIG_BROWSER_KIOSK_FULLSCREEN)
        CONFIG_BROWSER_KIOSK_MAXIMIZED=$(config_read "$entry" CONFIG_BROWSER_KIOSK_MAXIMIZED $CONFIG_BROWSER_KIOSK_MAXIMIZED)
        CONFIG_BROWSER_KIOSK_PANEL_POSITION=$(config_read "$entry" CONFIG_BROWSER_KIOSK_PANEL_POSITION $CONFIG_BROWSER_KIOSK_PANEL_POSITION)
        CONFIG_BROWSER_KIOSK_PANEL_TITLE=$(config_read "$entry" CONFIG_BROWSER_KIOSK_PANEL_TITLE $CONFIG_BROWSER_KIOSK_PANEL_TITLE)
        CONFIG_BROWSER_KIOSK_PANEL_HOME=$(config_read "$entry" CONFIG_BROWSER_KIOSK_PANEL_HOME $CONFIG_BROWSER_KIOSK_PANEL_HOME)
        CONFIG_BROWSER_KIOSK_PANEL_CLOSE=$(config_read "$entry" CONFIG_BROWSER_KIOSK_PANEL_CLOSE $CONFIG_BROWSER_KIOSK_PANEL_CLOSE)
        CONFIG_BROWSER_ADMIN_APPDATA=$(config_read "$entry" CONFIG_BROWSER_ADMIN_APPDATA $CONFIG_BROWSER_ADMIN_APPDATA)
        CONFIG_BROWSER_ADMIN_KIOSKMODE=$(config_read "$entry" CONFIG_BROWSER_ADMIN_KIOSKMODE $CONFIG_BROWSER_ADMIN_KIOSKMODE)
        CONFIG_BROWSER_ADMIN_FULLSCREEN=$(config_read "$entry" CONFIG_BROWSER_ADMIN_FULLSCREEN $CONFIG_BROWSER_ADMIN_FULLSCREEN)
        CONFIG_BROWSER_ADMIN_MAXIMIZED=$(config_read "$entry" CONFIG_BROWSER_ADMIN_MAXIMIZED $CONFIG_BROWSER_ADMIN_MAXIMIZED)
        CONFIG_BROWSER_ADMIN_PANEL_POSITION=$(config_read "$entry" CONFIG_BROWSER_ADMIN_PANEL_POSITION $CONFIG_BROWSER_ADMIN_PANEL_POSITION)
        CONFIG_BROWSER_ADMIN_PANEL_TITLE=$(config_read "$entry" CONFIG_BROWSER_ADMIN_PANEL_TITLE $CONFIG_BROWSER_ADMIN_PANEL_TITLE)
        CONFIG_BROWSER_ADMIN_PANEL_HOME=$(config_read "$entry" CONFIG_BROWSER_ADMIN_PANEL_HOME $CONFIG_BROWSER_ADMIN_PANEL_HOME)
        CONFIG_BROWSER_ADMIN_PANEL_CLOSE=$(config_read "$entry" CONFIG_BROWSER_ADMIN_PANEL_CLOSE $CONFIG_BROWSER_ADMIN_PANEL_CLOSE)
        CONFIG_APPSTART=$(config_read "$entry" CONFIG_APPSTART "$CONFIG_APPSTART")
        CONFIG_ADMIN_ALLOW=$(config_read "$entry" CONFIG_ADMIN_ALLOW $CONFIG_ADMIN_ALLOW)
        CONFIG_ADMIN_LOGINUSER=$(config_read "$entry" CONFIG_ADMIN_LOGINUSER $CONFIG_ADMIN_LOGINUSER)
        CONFIG_ADMIN_APPSTART=$(config_read "$entry" CONFIG_ADMIN_APPSTART $CONFIG_ADMIN_APPSTART)
        CONFIG_ADMIN_AUTOLOGOUT=$(config_read "$entry" CONFIG_ADMIN_AUTOLOGOUT $CONFIG_ADMIN_AUTOLOGOUT)
        CONFIG_ADMIN_PANEL=$(config_read "$entry" CONFIG_ADMIN_PANEL $CONFIG_ADMIN_PANEL)
        CONFIG_KIOSK_USERNAME=$(config_read "$entry" CONFIG_KIOSK_USERNAME $CONFIG_KIOSK_USERNAME)
        CONFIG_KIOSK_USERGROUPS=$(config_read "$entry" CONFIG_KIOSK_USERGROUPS $CONFIG_KIOSK_USERGROUPS)
        CONFIG_HASHES["$entry"]="$(md5sum "$entry" | awk '{print $1}')"
      fi
    done
  fi
  unset IFS
  if [[ "$CONFIG_NODISP_RES" =~ ^([0-9]+)x([0-9]+)$ ]]; then
    local x_res=${BASH_REMATCH[1]}
    local y_res=${BASH_REMATCH[2]}
    (( x_res < 640 )) && x_res=640
    (( x_res > 3840 )) && x_res=3840
    (( y_res < 480 )) && y_res=480
    (( y_res > 2160 )) && y_res=2160
    CONFIG_NODISP_RES="${x_res}x${y_res}"
  else
    CONFIG_NODISP_RES="640x480"
  fi
  CONFIG_ADMIN_LOGINUSER=$(echo "$CONFIG_ADMIN_LOGINUSER" | sed 's/[[:blank:]]//g')
  CONFIG_KIOSK_USERNAME=$(echo "$CONFIG_KIOSK_USERNAME" | sed 's/[[:blank:]]//g')
  CONFIG_KIOSK_USERGROUPS=$(echo "$CONFIG_KIOSK_USERGROUPS" | sed 's/[[:blank:]]//g')
  [[ ! $CONFIG_SCRNSVR =~ ^[0-9]+$ ]] && CONFIG_SCRNSVR=0
  [[ ! $CONFIG_SCRNBLK =~ ^[0-9]+$ ]] && CONFIG_SCRNBLK=0
  if ! is_valid_username "$CONFIG_KIOSK_USERNAME"; then
    CONFIG_KIOSK_USERNAME=kiosk
  fi
  [ -z "$CONFIG_ADMIN_APPSTART" ] && CONFIG_ADMIN_APPSTART="false"
  CONFIG_BROWSER_KIOSK_APPDATA="${CONFIG_BROWSER_KIOSK_APPDATA%/}"
  CONFIG_BROWSER_ADMIN_APPDATA="${CONFIG_BROWSER_ADMIN_APPDATA%/}"
  KIOSK_ACTIVE=$(config_read "$STATE_FILE" KIOSK_ACTIVE false)
  KIOSK_ACTIVE="$(get_valid_bool $KIOSK_ACTIVE)"
  KIOSK_ADMINMODE=$(config_read "$STATE_FILE" KIOSK_ADMINMODE false)
  KIOSK_ADMINMODE="$(get_valid_bool $KIOSK_ADMINMODE)"
}

function config_write_conffile(){
  rm -f "$CONFIG_FILE" >/dev/null 2>&1
  mkdir -p "$(dirname ""$CONFIG_FILE"")" >/dev/null 2>&1
  mkdir -p "$CONFIG_FILE.d" >/dev/null 2>&1
  cat <<EOF | sudo tee "$CONFIG_FILE" >/dev/null 2>&1
### DO NOT CHANGE THIS FILE!
### Any updates of rpi-kiosk app will reset these file, so changes may
### not be persistent.
EOF
  cat <<EOF | sudo tee "$(dirname ""$CONFIG_FILE"")/README" >/dev/null 2>&1
DO NOT CHANGE $(basename ""$CONFIG_FILE"") IN THIS FOLDER!
Any updates of rpi-kiosk app will reset these files, so changes may
not be persistent.
USE $CONFIG_FILE.d/ FOLDER INSTEAD!
EOF
  cat <<EOF | sudo tee "$CONFIG_FILE.d/README" >/dev/null 2>&1
Files in this directory are rpi-kiosk configuration files. 
rpi-kiosk scan this directory processing all files that end in '.conf'.
EOF
  local first_username=$(getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody" { print $1; exit }')
  [ -z "$first_username" ] && first_username="pi"
  config_write "$CONFIG_FILE" CONFIG_NODISP_RES "640x480"
  config_write "$CONFIG_FILE" CONFIG_BCKGRND "$BASE_DIR/kiosk-wallpaper.png"
  config_write "$CONFIG_FILE" CONFIG_SCRNSVR "0"
  config_write "$CONFIG_FILE" CONFIG_SCRNBLK "0"
  config_write "$CONFIG_FILE" CONFIG_CLICKLOCK false
  config_write "$CONFIG_FILE" CONFIG_NUMLOCK false
  config_write "$CONFIG_FILE" CONFIG_REBOOT false
  config_write "$CONFIG_FILE" CONFIG_CURSOR_HIDE false
  config_write "$CONFIG_FILE" CONFIG_OSK_KIOSK false
  config_write "$CONFIG_FILE" CONFIG_OSK_ADMIN false
  config_write "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_APPDATA false
  config_write "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_KIOSKMODE true
  config_write "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_FULLSCREEN true
  config_write "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_MAXIMIZED false
  config_write "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_PANEL_POSITION false
  config_write "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_PANEL_TITLE "RPI-KIOSK"
  config_write "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_PANEL_HOME false
  config_write "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_PANEL_CLOSE false
  config_write "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_APPDATA false
  config_write "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_KIOSKMODE false
  config_write "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_FULLSCREEN false
  config_write "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_MAXIMIZED true
  config_write "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_PANEL_POSITION false
  config_write "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_PANEL_TITLE "RPI-KIOSK"
  config_write "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_PANEL_HOME false
  config_write "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_PANEL_CLOSE false
  config_write "$CONFIG_FILE" CONFIG_APPSTART "$BASE_DIR/kiosk-browser/index.html"
  config_write "$CONFIG_FILE" CONFIG_ADMIN_ALLOW true
  config_write "$CONFIG_FILE" CONFIG_ADMIN_LOGINUSER "$first_username"
  config_write "$CONFIG_FILE" CONFIG_ADMIN_APPSTART false
  config_write "$CONFIG_FILE" CONFIG_ADMIN_AUTOLOGOUT false
  config_write "$CONFIG_FILE" CONFIG_ADMIN_PANEL true
  config_write "$CONFIG_FILE" CONFIG_KIOSK_USERNAME kiosk
  config_write "$CONFIG_FILE" CONFIG_KIOSK_USERGROUPS false
}

function config_changed {
  local reload_conf="false"
  local entry
  local test
  [[ -v CONFIG_HASHES["$CONFIG_FILE"] ]] && [ -f "$CONFIG_FILE" ] && [[ "${CONFIG_HASHES[$CONFIG_FILE]}" != "$(md5sum "$CONFIG_FILE" | awk '{print $1}')" ]] && reload_conf="true"
  [[ -v CONFIG_HASHES["$CONFIG_FILE"] ]] && [ ! -f "$CONFIG_FILE" ] && reload_conf="true"
  [[ ! -v CONFIG_HASHES["$CONFIG_FILE"] ]] && [ -f "$CONFIG_FILE" ] && reload_conf="true"
  [[ -v CONFIG_HASHES["$STATE_FILE"] ]] && [ -f "$STATE_FILE" ] && [[ "${CONFIG_HASHES[$STATE_FILE]}" != "$(md5sum "$STATE_FILE" | awk '{print $1}')" ]] && reload_conf="true"
  [[ -v CONFIG_HASHES["$STATE_FILE"] ]] && [ ! -f "$STATE_FILE" ] && reload_conf="true"
  [[ ! -v CONFIG_HASHES["$STATE_FILE"] ]] && [ -f "$STATE_FILE" ] && reload_conf="true"
  IFS=$'\n'
  test=($(find "$CONFIG_FILE.d" -maxdepth 1 -type f -name "*.conf" 2>/dev/null))
  if [ "${#test[@]}" != "0" ]; then
    for entry in ${test[@]}; do
      if [[ $(file -b --mime-type "$(readlink -f "$entry")" 2>/dev/null) =~ "text" ]]; then
        if [[ ! -v CONFIG_HASHES["$entry"] ]]; then
          reload_conf="true"
        elif [[ "${CONFIG_HASHES[$entry]}" != "$(md5sum "$entry" | awk '{print $1}')" ]]; then
          reload_conf="true"
        fi
      fi
    done
  fi
  unset IFS
  for entry in "${!CONFIG_HASHES[@]}"; do
    [[ ! -f "$entry" ]] && reload_conf="true"
  done
  [ "$reload_conf" == "true" ] && config_read_all
  [ "$reload_conf" == "true" ] && return 0 || return 1
}

function config_delete_statfile(){
  rm -f "$STATE_FILE" >/dev/null 2>&1
}

function config_write_statfile(){
  rm -f "$STATE_FILE" >/dev/null 2>&1
  config_write "$STATE_FILE" KIOSK_ACTIVE $KIOSK_ACTIVE
  config_write "$STATE_FILE" KIOSK_ADMINMODE $KIOSK_ADMINMODE
}

function start_lightdm() {
  if [[ ! "$(systemctl status display-manager 2>/dev/null)" =~ "lightdm.service" ]]
  then
    systemctl stop display-manager >/dev/null 2>&1
    systemctl disable display-manager >/dev/null 2>&1
    systemctl enable lightdm >/dev/null 2>&1
  fi
  if [ -f "/etc/X11/default-display-manager" ] && [ "$(<"/etc/X11/default-display-manager")" != "/usr/sbin/lightdm" ]
  then
    echo "/usr/sbin/lightdm" > "/etc/X11/default-display-manager"
  fi
  systemctl restart display-manager >/dev/null 2>&1
}

function get_xsession_user() {
  local entry
  local test
  local result
  IFS=$'\n'
  test=($(w -hs 2>/dev/null))
  if [ "${#test[@]}" != "0" ]; then
    for entry in ${test[@]}; do
      [[ "$entry" =~ " :0 " ]] && result="$(echo "$entry" | cut -d' ' -f1)"
    done
  fi
  [ "$result" != "" ] && printf -- "%s\n" "$result"
  unset IFS
}

function is_valid_username() {
  local re='^[[:lower:]_][[:lower:][:digit:]_.-]{1,15}$'
  local name="$1"
  [[ -z "$name" ]] && return 1
  (( ${#name} > 16 )) && return 1
  [[ $name =~ $re ]]
}

function is_valid_dirpath() {
  local path="$1"
  [[ -z "$path" ]] && return 1
  [[ "$path" != /* ]] && return 1
  [[ "$path" == *'//' ]] && return 1
  [[ "$path" != "/" ]] && path="${path%/}"
  [[ -e "$path" ]] && [[ ! -d "$path" ]] && return 1
  local base="$(dirname -- "$path")"
  [[ ! -d "$base" ]] && return 1
  local name="$(basename -- "$path")"
  [[ "$name" =~ ^[a-zA-Z0-9._\ -]+$ ]] || return 1
  name=$(echo "$name" | xargs)
  [[ -z "$name" ]] && return 1
  [[ -d "$path" && -w "$path" ]] && return 0
  [[ -d "$base" && -w "$base" ]] && return 0
  return 1
}

function get_valid_bool() {
  local result_s="false"
  [ "$1" == "true" ] && result_s="true"
  [ "$1" == "1" ] && result_s="true"
  printf -- "%s\n" "$result_s" 
}

function is_exec_or_website() {
  local input="$1"
  local val="NONE"
  local realfile="$(readlink -f "$input" 2>/dev/null)"
  if [[ "$input" =~ ^https?:// ]]; then
    val="SITE"
  elif [ -f "$realfile" ]; then
    local filetype="$(file -b --mime-type "$realfile" 2>/dev/null)"
    case "$filetype" in
      *executable*|*script*)
        [[ -x "$realfile" ]] && val="EXEC"
        ;;
      *html*)
        val="HTML"
        ;;
      *)
        case "$realfile" in
          *.desktop|*.sh|*.py)
            [[ -x "$realfile" ]] && val="EXEC"
            ;;
        esac
        ;;
    esac
  fi
  printf -- "%s" "$val"
}

function configure_system() {
  local lightdmconf="/etc/lightdm/lightdm.conf.d/zz-kiosk-login-auto.conf"
  local sudoers="/etc/sudoers.d/011_kiosk-reboot"
  local kiosk_logout="/usr/share/applications/rpi-kiosk-logout.desktop"
  local kiosk_browser="/usr/share/applications/rpi-kiosk-browser.desktop"
  local xorg_conf="/etc/X11/xorg.conf.d/10-DummyScreen.conf"
  local nodisp_x=$(echo "$CONFIG_NODISP_RES" | cut -d "x" -f 1)
  local nodisp_y=$(echo "$CONFIG_NODISP_RES" | cut -d "x" -f 2)
  local nodisp_modeline=$(cvt $nodisp_x $nodisp_y 60.00 | grep -oP '(?<=Modeline ).*')
  local nodisp_modename=$(echo "$nodisp_modeline" | awk '{print $1}' | tr -d '"')
  local dmrc="$KHOME_DIR/.dmrc"
  local gtk2="$KHOME_DIR/.gtkrc-2.0"
  local gtk3_cfg="$KHOME_DIR/.config/gtk-3.0"
  local gtk3="$gtk3_cfg/settings.ini"
  local openbox_cfg="$KHOME_DIR/.config/openbox"
  local rcxml="$openbox_cfg/rc.xml"
  local menuxml="$openbox_cfg/menu.xml"
  local environment="$openbox_cfg/environment"
  local login_username=$CONFIG_KIOSK_USERNAME
  local login_userid="2001"
  local xservercmd="X -bs -core"
  [ "$KIOSK_ADMINMODE" == "true" ] && login_username=$CONFIG_ADMIN_LOGINUSER && login_userid="$(id -u "$CONFIG_ADMIN_LOGINUSER" 2>/dev/null)"
  [ "$CONFIG_CURSOR_HIDE" == "true" ] && [ "$KIOSK_ADMINMODE" != "true" ] && xservercmd="$xservercmd -nocursor"
  rm -f "$lightdmconf" >/dev/null 2>&1
  rm -f "$sudoers" >/dev/null 2>&1
  rm -f "$kiosk_logout" >/dev/null 2>&1
  rm -f "$kiosk_browser" >/dev/null 2>&1
  rm -f "$xorg_conf" >/dev/null 2>&1
  rm -f "/usr/share/onboard/layouts/kiosk-osk.onboard" >/dev/null 2>&1
  rm -f "/usr/share/onboard/layouts/kiosk-osk-alpha.svg" >/dev/null 2>&1
  rm -f "/usr/share/onboard/layouts/kiosk-osk-sidebar.svg" >/dev/null 2>&1
  rm -f "/usr/share/onboard/layouts/kiosk-osk-symbols.svg" >/dev/null 2>&1
  rm -rf "$KHOME_DIR" >/dev/null 2>&1
  echo "" > "$COM_FILE" >/dev/null 2>&1
  chmod 666 "$COM_FILE" >/dev/null 2>&1
  [ "$KIOSK_ACTIVE" == "false" ] && return 0
  [ -e "$BASE_DIR/kiosk-osk/kiosk-osk.onboard" ] && ln -fs "$BASE_DIR/kiosk-osk/kiosk-osk.onboard" "/usr/share/onboard/layouts/kiosk-osk.onboard"
  [ -e "$BASE_DIR/kiosk-osk/kiosk-osk-alpha.svg" ] && ln -fs "$BASE_DIR/kiosk-osk/kiosk-osk-alpha.svg" "/usr/share/onboard/layouts/kiosk-osk-alpha.svg"
  [ -e "$BASE_DIR/kiosk-osk/kiosk-osk-sidebar.svg" ] && ln -fs "$BASE_DIR/kiosk-osk/kiosk-osk-sidebar.svg" "/usr/share/onboard/layouts/kiosk-osk-sidebar.svg"
  [ -e "$BASE_DIR/kiosk-osk/kiosk-osk-symbols.svg" ] && ln -fs "$BASE_DIR/kiosk-osk/kiosk-osk-symbols.svg" "/usr/share/onboard/layouts/kiosk-osk-symbols.svg"
  
  if ! grep -q "connected" /sys/class/drm/card0-*/status 2>/dev/null; then
    mkdir -p "$(dirname "$xorg_conf")" >/dev/null 2>&1
    cat <<EOF | sudo tee "$xorg_conf" >/dev/null 2>&1
Section "Monitor"
    Identifier "VirtualMonitor"
    HorizSync 28.0-80.0
    VertRefresh 48.0-75.0
    Modeline $nodisp_modeline
    Option "PreferredMode" "$nodisp_modename"
EndSection

Section "Device"
    Identifier "DummyDevice"
    Driver "dummy"
    VideoRam 256000
EndSection

Section "Screen"
    Identifier "DummyScreen"
    Monitor "VirtualMonitor"
    Device "DummyDevice"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "$nodisp_modename"
        Virtual $nodisp_x $nodisp_y
    EndSubSection
EndSection

Section "ServerLayout"
    Identifier "DummyLayout"
    Screen 0 "DummyScreen" 0 0
EndSection
EOF
  fi
  create_user_services
  if id "$login_username" >/dev/null 2>&1; then
    cat <<EOF | sudo tee "$lightdmconf" >/dev/null 2>&1
[Seat:*]
greeter-session=lightdm-autologin-greeter
autologin-session=openbox
autologin-user=$login_username
pam-autologin-service=lightdm-autologin
xserver-command=$xservercmd
#session-setup-script=
#session-cleanup-script=
#greeter-setup-script=
EOF
  fi
  if [ "$KIOSK_ADMINMODE" == "true" ] && id "$CONFIG_ADMIN_LOGINUSER" >/dev/null 2>&1 && is_valid_dirpath "$CONFIG_BROWSER_ADMIN_APPDATA/kiosk-browser-$login_userid"; then
    mkdir -p "$CONFIG_BROWSER_ADMIN_APPDATA/kiosk-browser-$login_userid" >/dev/null 2>&1
    chown -R $login_userid:$login_userid "$CONFIG_BROWSER_ADMIN_APPDATA/kiosk-browser-$login_userid" >/dev/null 2>&1
  fi
  if is_valid_dirpath "$CONFIG_BROWSER_KIOSK_APPDATA/kiosk-browser-2001"; then
    mkdir -p "$CONFIG_BROWSER_KIOSK_APPDATA/kiosk-browser-2001" >/dev/null 2>&1
    chown -R 2001:2001 "$CONFIG_BROWSER_KIOSK_APPDATA/kiosk-browser-2001" >/dev/null 2>&1
  fi
  mkdir -p "$(dirname "$kiosk_logout")"
  cat <<EOF | tee "$kiosk_logout" >/dev/null 2>&1
[Desktop Entry]
Version=1.0
Type=Application
Name=Logout (rpi-kiosk)
GenericName=logout
Comment=Logout menu for rpi-kiosk
Icon=system-log-out
Exec=bash -c "exec '$BASE_DIR/kiosk-init.sh' --logout"
Categories=Settings;DesktopSettings;GTK;
StartupNotify=true
Terminal=false
EOF
  chmod +x "$kiosk_logout" >/dev/null 2>&1
  update-desktop-database >/dev/null 2>&1
  mkdir -p "$(dirname "$kiosk_browser")"
  cat <<EOF | tee "$kiosk_browser" >/dev/null 2>&1
[Desktop Entry]
Version=1.0
Type=Application
Name=Kiosk-Browser setup (rpi-kiosk)
GenericName=Kiosk-Browser
Comment=Configurate Kiosk-Browser for kiosk user
Icon=chromium-browser
Exec=bash -c "exec '$BASE_DIR/kiosk-init.sh' --browser"
Categories=Settings;DesktopSettings;GTK;
StartupNotify=true
Terminal=false
EOF
  chmod +x "$kiosk_browser" >/dev/null 2>&1
  update-desktop-database >/dev/null 2>&1
  [ "$KIOSK_ADMINMODE" == "true" ] && return 0
  mkdir -p "$KHOME_DIR/.config" >/dev/null 2>&1
  chown -R 2001:2001 "$KHOME_DIR" >/dev/null 2>&1
  mkdir -p "$openbox_cfg"
  mkdir -p "$gtk3_cfg"
  mkdir -p "/etc/lightdm/lightdm.conf.d"
  mkdir -p "/etc/sudoers.d"
  cat <<EOF | sudo tee "$sudoers" >/dev/null 2>&1
$CONFIG_KIOSK_USERNAME ALL = NOPASSWD: /sbin/reboot
EOF
  cat <<EOF | sudo tee "$dmrc" >/dev/null 2>&1
[Desktop]
Session=openbox
EOF
  cat <<EOF | sudo tee "$gtk2" >/dev/null 2>&1
gtk-icon-theme-name = "Clearlooks"
gtk-theme-name = "Clearlooks"
gtk-font-name = "DejaVu Sans 11"
EOF
  cat <<EOF | sudo tee "$gtk3" >/dev/null 2>&1
[Settings]
gtk-icon-theme-name = Adwaita
gtk-theme-name = Adwaita
gtk-font-name = DejaVu Sans 11
EOF
  cp -af /etc/xdg/openbox/rc.xml "$rcxml" >/dev/null 2>&1
  sed -i "/  <titleLayout>/c\  <titleLayout>LMC</titleLayout>" "$rcxml"
  sed -i "/  <number>/c\  <number>2</number>" "$rcxml"
  sed -i "s!<keybind key=\"Print\">!<keybind key=\"S-End\">!" "$rcxml"
  sed -i "s!<command>scrot</command>!<command>\"$BASE_DIR/kiosk-init.sh\" --admin</command>!" "$rcxml"
  cat <<EOF | sudo tee "$menuxml" >/dev/null 2>&1
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://openbox.org/
                file:///usr/share/openbox/menu.xsd">
<menu id="root-menu" label="Openbox 3">
  <item label="Exit">
    <action name="Exit" />
  </item>
</menu>
</openbox_menu>
EOF
  cat <<EOF | sudo tee "$environment" >/dev/null 2>&1
#EMPTY
EOF
  chown 0:0 "$lightdmconf" >/dev/null 2>&1
  chmod 644 "$lightdmconf" >/dev/null 2>&1
  chown 0:0 "$sudoers" >/dev/null 2>&1
  chmod 440 "$sudoers" >/dev/null 2>&1
  chown 0:0 "$xorg_conf" >/dev/null 2>&1
  chmod 644 "$xorg_conf" >/dev/null 2>&1
  chown 0:0 "$dmrc" >/dev/null 2>&1
  chmod 644 "$dmrc" >/dev/null 2>&1
  chown 0:0 "$gtk2" >/dev/null 2>&1
  chmod 644 "$gtk2" >/dev/null 2>&1
  chown 0:0 "$gtk3" >/dev/null 2>&1
  chmod 644 "$gtk3" >/dev/null 2>&1
  chown 0:0 "$rcxml" >/dev/null 2>&1
  chmod 644 "$rcxml" >/dev/null 2>&1
  chown 0:0 "$menuxml" >/dev/null 2>&1
  chmod 644 "$menuxml" >/dev/null 2>&1
  chown 0:0 "$environment" >/dev/null 2>&1
  chmod 755 "$environment" >/dev/null 2>&1
}

function check_service() {
  if ! systemctl list-unit-files "$1" >/dev/null 2>&1; then
    printf -- "%s\n" "__NOTFOUND__"
    return
  elif systemctl is-active "$1" >/dev/null 2>&1; then
    printf -- "%s\n" "__ACTIVE__"
  elif systemctl is-failed "$1" >/dev/null 2>&1; then
    printf -- "%s\n" "__FAILED__"
  else
    printf -- "%s\n" "__INACTIVE__"
  fi
  if systemctl is-enabled "$1" >/dev/null 2>&1; then
    printf -- "%s\n" "__ENABLED__"
  else
    printf -- "%s\n" "__DISABLED__"
  fi
}

function delete_user_services() {
  local user_uid
  for user_uid in $(loginctl list-users --no-legend | awk '{print $1}'); do
    sudo -u "#$user_uid" XDG_RUNTIME_DIR="/run/user/$user_uid" systemctl --user stop rpi-kiosk-init.service >/dev/null 2>&1
  done
  systemctl --global disable rpi-kiosk-init >/dev/null 2>&1
  if [ -e "/lib/systemd/user/rpi-kiosk-init.service" ]; then
    rm -f "/lib/systemd/user/rpi-kiosk-init.service" >/dev/null 2>&1
  fi
  for user_uid in $(loginctl list-users --no-legend | awk '{print $1}'); do
    sudo -u "#$user_uid" XDG_RUNTIME_DIR="/run/user/$user_uid" systemctl --user daemon-reload >/dev/null 2>&1
  done
}

function create_user_services() {
  local user_uid
  if [ ! -e "/lib/systemd/user/rpi-kiosk-init.service" ]; then
    cat <<EOF | sudo tee "/lib/systemd/user/rpi-kiosk-init.service" >/dev/null 2>&1
[Unit]
Description=Raspberry Pi Kiosk Init Service

[Service]
Type=simple
Environment=DISPLAY=:0
ExecStart="$BASE_DIR/kiosk-init.sh" --service
Restart=always

[Install]
WantedBy=default.target
Alias=rpi-kiosk-init.service
EOF
  fi
  systemctl --global enable rpi-kiosk-init >/dev/null 2>&1
  for user_uid in $(loginctl list-users --no-legend | awk '{print $1}'); do
    sudo -u "#$user_uid" XDG_RUNTIME_DIR="/run/user/$user_uid" systemctl --user daemon-reload >/dev/null 2>&1
    sudo -u "#$user_uid" XDG_RUNTIME_DIR="/run/user/$user_uid" systemctl --user restart rpi-kiosk-init.service >/dev/null 2>&1
  done
}

function delete_kiosk_service() {
  local service_status="$(check_service rpi-kiosk.service)"
  if [[ ! "$service_status" =~ "__NOTFOUND__" ]]; then
    systemctl stop rpi-kiosk >/dev/null 2>&1
    systemctl disable rpi-kiosk >/dev/null 2>&1
    rm -f "/lib/systemd/system/rpi-kiosk.service" >/dev/null 2>&1
    systemctl daemon-reload >/dev/null 2>&1
  fi
}

function create_kiosk_service() {
  local service_status="$(check_service rpi-kiosk.service)"
  if [[ "$service_status" =~ "__NOTFOUND__" ]]; then
    cat <<EOF | sudo tee /lib/systemd/system/rpi-kiosk.service >/dev/null 2>&1
[Unit]
Description=Raspberry Pi Kiosk Service
Before=systemd-user-sessions.service plymouth-quit.service 
After=plymouth-start.service

[Service]
Type=simple
ExecStartPre=/usr/bin/rpi-kiosk --service_pre
ExecStart=/usr/bin/rpi-kiosk --service
User=root
PIDFile=$PID_FILE
Restart=always
RestartSec=10

[Install]
WantedBy=basic.target
Alias=rpi-kiosk.service
EOF
    systemctl daemon-reload >/dev/null 2>&1
  fi
  [ "$(systemctl get-default)" != "graphical.target" ] && systemctl set-default graphical.target
  [ "$(systemctl is-active graphical.target)" != "active" ] && systemctl start graphical.target
  service_status="$(check_service rpi-kiosk.service)"
  [[ "$service_status" =~ "__DISABLED__" ]] && systemctl enable rpi-kiosk >/dev/null 2>&1
  [[ ! "$service_status" =~ "__ACTIVE__" ]] && systemctl start rpi-kiosk >/dev/null 2>&1
}

function delete_kioskuser(){
  local username="$(getent passwd 2001 | cut -d: -f1)"
  if [ "$username" != "" ]; then
    pkill -KILL -u "$username" >/dev/null 2>&1
    userdel -f "$username" >/dev/null 2>&1
    deluser --group "$username" >/dev/null 2>&1
  fi
}

function create_kioskuser(){
  local username_uid="$(getent passwd "$CONFIG_KIOSK_USERNAME" | cut -d: -f3)"
  local username="$(getent passwd 2001 | cut -d: -f1)"
  local homedir="$(getent passwd 2001 | cut -d: -f6)"
  local shell="$(getent passwd 2001 | cut -d: -f7)"
  local groups="$(groups ""$username"" 2>/dev/null)"
  local group
  if [ "$username_uid" != "2001" ] && [ "$username_uid" != "" ]; then
    printf -- "%s\n" "__USERNAMEALREADYEXISTS__"
    return
  fi
  if [ "$username" == "" ]; then
    useradd --no-create-home --home-dir "$KHOME_DIR" --shell "/usr/sbin/nologin" --uid 2001 "$CONFIG_KIOSK_USERNAME" >/dev/null 2>&1
    IFS=$','
    if [ "$CONFIG_KIOSK_USERGROUPS" != "false" ]; then
      for group in ${CONFIG_KIOSK_USERGROUPS[@]}; do
        [ "$(getent group ""$group"")" ] && usermod --append --groups "$group" "$CONFIG_KIOSK_USERNAME" >/dev/null 2>&1
      done
    fi
    unset IFS
    return
  fi
  if [ "$username" != "$CONFIG_KIOSK_USERNAME" ]; then
    killall -u "$username" >/dev/null 2>&1
    usermod --login "$CONFIG_KIOSK_USERNAME" "$username" >/dev/null 2>&1
    groupmod --new-name "$CONFIG_KIOSK_USERNAME" "$username" >/dev/null 2>&1
  fi
  if [ "$homedir" != "${KHOME_DIR}" ]; then
    killall -u "$CONFIG_KIOSK_USERNAME" >/dev/null 2>&1
    usermod --home "${KHOME_DIR}" "$CONFIG_KIOSK_USERNAME" >/dev/null 2>&1
  fi
  if [ "$shell" != "/usr/sbin/nologin" ]; then
    killall -u "$CONFIG_KIOSK_USERNAME" >/dev/null 2>&1
    usermod --shell "/usr/sbin/nologin" "$CONFIG_KIOSK_USERNAME" >/dev/null 2>&1
  fi
  usermod --groups "" "$CONFIG_KIOSK_USERNAME" >/dev/null 2>&1
  IFS=$','
  if [ "$CONFIG_KIOSK_USERGROUPS" != "false" ]; then
    for group in ${CONFIG_KIOSK_USERGROUPS[@]}; do
      [ "$(getent group ""$group"")" ] && usermod --append --groups "$group" "$CONFIG_KIOSK_USERNAME" >/dev/null 2>&1
    done
  fi
  unset IFS
}

function prepare_kiosk() {
  local graphical_target="$(systemctl is-active graphical.target)"
  local user_xsession="$(get_xsession_user)"
  if [ "$graphical_target" == "active" ]; then 
    if [ "$user_xsession" == "$CONFIG_KIOSK_USERNAME" ] || [ "$user_xsession" == "" ]; then
     systemctl stop display-manager >/dev/null 2>&1
    fi
  fi
  killall -KILL -u "$(getent passwd 2001 | cut -d: -f1)" >/dev/null 2>&1
  local createuser="$(create_kioskuser)"
  if [ "$createuser" != "" ]; then
    echo "Could not create kioskuser! Errorcode: $createuser"
    echo "Kiosk can not start without these user! Abort!"
    KIOSK_ACTIVE="false"
    config_write_statfile
  fi
  configure_system
  sleep 2
  if [ "$graphical_target" == "active" ]; then 
    if [ "$user_xsession" == "$CONFIG_KIOSK_USERNAME" ] || [ "$user_xsession" == "" ]; then
     start_lightdm
    fi
  fi
}

function cmd_service_pre() {
  prepare_kiosk
}

function cmd_service() {
  local wasadmin
  local wasactive
  local restart
  local com_cmd
  while [ -f "$PID_FILE" ]; do
    wasactive="$KIOSK_ACTIVE"
    wasadmin="$KIOSK_ADMINMODE"
    if [ -f "$COM_FILE" ]; then
      if [ -s "$COM_FILE" ]; then
        com_cmd="$(<"$COM_FILE")"
        case "$com_cmd" in
          4711)
            KIOSK_ACTIVE="true"
            KIOSK_ADMINMODE="true"
            config_write_statfile
            restart="y"
            ;;
          0815)
            restart="y"
            ;;
          1111)
            KIOSK_ACTIVE="true"
            KIOSK_ADMINMODE="false"
            config_write_statfile
            restart="y"
            ;;
          0000)
            KIOSK_ACTIVE="false"
            KIOSK_ADMINMODE="false"
            config_write_statfile
            restart="y"
            ;;
        esac
        echo "" > "$COM_FILE" >/dev/null 2>&1
        chmod 666 "$COM_FILE" >/dev/null 2>&1
      fi
    else
      echo "" > "$COM_FILE" >/dev/null 2>&1
      chmod 666 "$COM_FILE" >/dev/null 2>&1
    fi
    config_changed && restart="y"
    if [ "$wasactive" != "$KIOSK_ACTIVE" ] || [ "$wasadmin" != "$KIOSK_ADMINMODE" ]; then
      systemctl stop display-manager >/dev/null 2>&1
    fi
    [ "$restart" == "y" ] && prepare_kiosk
    restart=""
    sleep 3
  done
}

function cmd_install() {
  if [ "$CMD" == "install_remove" ] || [ "$CMD" == "install_update" ]; then
    echo "Cleaning up kiosk..."
    delete_kiosk_service >/dev/null 2>&1
    delete_user_services >/dev/null 2>&1
    KIOSK_ACTIVE="false"
    KIOSK_ADMINMODE="false"
    prepare_kiosk >/dev/null 2>&1
    delete_kioskuser >/dev/null 2>&1
    rm -f "$CONFIG_FILE" >/dev/null 2>&1
    [ "$CMD" == "install_remove" ] && config_delete_statfile >/dev/null 2>&1
  fi
  if [ "$CMD" == "install_start" ]; then
    echo "Create kiosk service..."
    create_kiosk_service >/dev/null 2>&1
  fi
}

function cmd_adminmode() {
  echo "Entering adminmode..."
  create_kiosk_service >/dev/null 2>&1
  echo "4711" > "$COM_FILE"
  ! id "$CONFIG_ADMIN_LOGINUSER" >/dev/null 2>&1 && echo "WARN: User '$CONFIG_ADMIN_LOGINUSER' not found!"
  sleep 3
}

function cmd_stop_kiosk() {
  echo "Stopping kiosk..."
  create_kiosk_service >/dev/null 2>&1
  echo "0000" > "$COM_FILE"
  sleep 3
}

function cmd_start_kiosk() {
  echo "Starting kiosk..."
  create_kiosk_service >/dev/null 2>&1
  echo "1111" > "$COM_FILE"
  sleep 3
}

function cmd_settings() {
  local usergroups="(OK)"
  local kioskuser="(OK)"
  local adminuser="(OK)"
  local kioskappdata="(OK)"
  local adminappdata="(OK)"
  local kioskpanel="(OK)"
  local adminpanel="(OK)"
  local screensaver="true (timout: $CONFIG_SCRNSVR)"
  local screenblank="true (timout: $CONFIG_SCRNBLK)"
  local background="(OK)"
  local nodisp_res="(OK)"
  local entry
  local test
  CONFIG_NODISP_RES=$(config_read "$CONFIG_FILE" CONFIG_NODISP_RES 640x480)
  CONFIG_KIOSK_USERNAME=$(config_read "$CONFIG_FILE" CONFIG_KIOSK_USERNAME kiosk)
  CONFIG_BROWSER_KIOSK_APPDATA=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_APPDATA false)
  CONFIG_BROWSER_ADMIN_APPDATA=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_APPDATA false)
  IFS=$'\n'
  test=($(find "$CONFIG_FILE.d" -maxdepth 1 -type f -name "*.conf" 2>/dev/null))
  if [ "${#test[@]}" != "0" ]; then
    for entry in ${test[@]}; do
      if [[ $(file -b --mime-type "$(readlink -f "$entry")" 2>/dev/null) =~ "text" ]]; then
        CONFIG_NODISP_RES=$(config_read "$entry" CONFIG_NODISP_RES 640x480)
        CONFIG_KIOSK_USERNAME=$(config_read "$entry" CONFIG_KIOSK_USERNAME $CONFIG_KIOSK_USERNAME)
        CONFIG_BROWSER_KIOSK_APPDATA=$(config_read "$entry" CONFIG_BROWSER_KIOSK_APPDATA false)
        CONFIG_BROWSER_ADMIN_APPDATA=$(config_read "$entry" CONFIG_BROWSER_ADMIN_APPDATA false)
      fi
    done
  fi
  unset IFS
  CONFIG_KIOSK_USERNAME=$(echo "$CONFIG_KIOSK_USERNAME" | sed 's/[[:blank:]]//g')
  CONFIG_BROWSER_KIOSK_APPDATA="${CONFIG_BROWSER_KIOSK_APPDATA%/}"
  CONFIG_BROWSER_ADMIN_APPDATA="${CONFIG_BROWSER_ADMIN_APPDATA%/}"
  [ "$CONFIG_KIOSK_USERGROUPS" == "false" ] && CONFIG_KIOSK_USERGROUPS="_NONE_"
  # nodisp resolution
  if [[ "$CONFIG_NODISP_RES" =~ ^([0-9]+)x([0-9]+)$ ]]; then
    [[ ${BASH_REMATCH[1]} -ge 640 && ${BASH_REMATCH[1]} -le 3840 && ${BASH_REMATCH[2]} -ge 480 && ${BASH_REMATCH[2]} -le 2160 ]] || nodisp_res="(FAIL:INVALID_SIZE)"
  else
    nodisp_res="(FAIL:INVALID_FORMAT)"
  fi
  # check groups
  IFS=$','
  if [ "$CONFIG_KIOSK_USERGROUPS" != "_NONE_" ]; then
    local usergroups_test=""
    for entry in ${CONFIG_KIOSK_USERGROUPS[@]}; do
      [ "$(getent group ""$entry"")" ] && usergroups_test="$usergroups_test$entry,"
    done
    [ "$CONFIG_KIOSK_USERGROUPS" != "${usergroups_test%?}" ] && usergroups="(FAIL)"
  fi
  unset IFS
  #check kiosk browser appdata
  if [ "$CONFIG_BROWSER_KIOSK_APPDATA" != "false" ] && ! is_valid_dirpath "$CONFIG_BROWSER_KIOSK_APPDATA/kiosk-browser-2001"; then
    kioskappdata="(FAIL:INVALID_OR_NOT_EXIST)"
  fi
  if [ "$CONFIG_BROWSER_ADMIN_APPDATA" != "false" ] && ! is_valid_dirpath "$CONFIG_BROWSER_ADMIN_APPDATA/kiosk-browser-$(id -u "$CONFIG_ADMIN_LOGINUSER" 2>/dev/null)"; then
    adminappdata="(FAIL:INVALID_OR_NOT_EXIST)"
  fi
  #check kiosk browser panel
  [ "$CONFIG_BROWSER_KIOSK_PANEL_POSITION" != "top-left" ] && [ "$CONFIG_BROWSER_KIOSK_PANEL_POSITION" != "top-right" ] && \
  [ "$CONFIG_BROWSER_KIOSK_PANEL_POSITION" != "bottom-left" ] && [ "$CONFIG_BROWSER_KIOSK_PANEL_POSITION" != "bottom-right" ] && \
  [ "$CONFIG_BROWSER_KIOSK_PANEL_POSITION" != "false" ] && kioskpanel="(FAIL)"
  [ "$CONFIG_BROWSER_ADMIN_PANEL_POSITION" != "top-left" ] && [ "$CONFIG_BROWSER_ADMIN_PANEL_POSITION" != "top-right" ] && \
  [ "$CONFIG_BROWSER_ADMIN_PANEL_POSITION" != "bottom-left" ] && [ "$CONFIG_BROWSER_ADMIN_PANEL_POSITION" != "bottom-right" ] && \
  [ "$CONFIG_BROWSER_ADMIN_PANEL_POSITION" != "false" ] && adminpanel="(FAIL)"
  #check kiosk username
  local username_uid="$(getent passwd "$CONFIG_KIOSK_USERNAME" | cut -d: -f3)"
  [ "$username_uid" != "2001" ] && [ "$username_uid" != "" ] && kioskuser="(FAIL:ALREADY_EXISTS)"
  if ! is_valid_username "$CONFIG_KIOSK_USERNAME"; then
    kioskuser="(FAIL:INVALID_USERNAME)"
  fi
  #check admin username
  if ! id "$CONFIG_ADMIN_LOGINUSER" >/dev/null 2>&1; then
    adminuser="(FAIL:USER_NOT_EXIST)"
  fi
  #check appstart
  local exec_type_kiosk=$(is_exec_or_website "${CONFIG_APPSTART#file://}")
  local exec_type_admin=$(is_exec_or_website "${CONFIG_ADMIN_APPSTART#file://}")
  local appstart_kiosk
  local appstart_admin
  if [ "${exec_type_kiosk}" != "NONE" ]; then
    appstart_kiosk="(${exec_type_kiosk}-OK)"
  else 
    appstart_kiosk="(FAIL:NOT_FOUND)"
  fi
  if [ "${exec_type_admin}" != "NONE" ]; then
    appstart_admin="(${exec_type_admin}-OK)"
  else 
    appstart_admin="(FAIL:NOT_FOUND)"
  fi
  #check screensaver
  [ "$CONFIG_SCRNSVR" == "0" ] && screensaver="false"
  #check screenblank
  [ "$CONFIG_SCRNBLK" == "0" ] && screenblank="false"
  #check background
  [ ! -f "$CONFIG_BCKGRND" ] && background="(FAIL:NOT_FOUND)"
  #print results
  echo "Current rpi-kiosk settings:"
  
  echo "CONFIG_NODISP_RES: $CONFIG_NODISP_RES $nodisp_res"
  echo "CONFIG_BCKGRND: $CONFIG_BCKGRND $background"
  echo "CONFIG_SCRNSVR: $screensaver"
  echo "CONFIG_SCRNBLK: $screenblank"
  echo "CONFIG_CLICKLOCK: $(get_valid_bool $CONFIG_CLICKLOCK)"
  echo "CONFIG_NUMLOCK: $(get_valid_bool $CONFIG_NUMLOCK)"
  echo "CONFIG_REBOOT: $(get_valid_bool $CONFIG_REBOOT)"
  echo "CONFIG_CURSOR_HIDE: $(get_valid_bool $CONFIG_CURSOR_HIDE)"
  echo "CONFIG_OSK_KIOSK: $(get_valid_bool $CONFIG_OSK_KIOSK)"
  echo "CONFIG_OSK_ADMIN: $(get_valid_bool $CONFIG_OSK_ADMIN)"
  echo "CONFIG_BROWSER_KIOSK_APPDATA: $CONFIG_BROWSER_KIOSK_APPDATA $kioskappdata"
  echo "CONFIG_BROWSER_KIOSK_KIOSKMODE: $(get_valid_bool $CONFIG_BROWSER_KIOSK_KIOSKMODE)"
  echo "CONFIG_BROWSER_KIOSK_FULLSCREEN: $(get_valid_bool $CONFIG_BROWSER_KIOSK_FULLSCREEN)"
  echo "CONFIG_BROWSER_KIOSK_MAXIMIZED: $(get_valid_bool $CONFIG_BROWSER_KIOSK_MAXIMIZED)"
  echo "CONFIG_BROWSER_KIOSK_PANEL_POSITION: $CONFIG_BROWSER_KIOSK_PANEL_POSITION $kioskpanel"
  echo "CONFIG_BROWSER_KIOSK_PANEL_TITLE: $CONFIG_BROWSER_KIOSK_PANEL_TITLE"
  echo "CONFIG_BROWSER_KIOSK_PANEL_HOME: $(get_valid_bool $CONFIG_BROWSER_KIOSK_PANEL_HOME)"
  echo "CONFIG_BROWSER_KIOSK_PANEL_CLOSE: $(get_valid_bool $CONFIG_BROWSER_KIOSK_PANEL_CLOSE)"
  echo "CONFIG_BROWSER_ADMIN_APPDATA: $CONFIG_BROWSER_ADMIN_APPDATA $adminappdata"
  echo "CONFIG_BROWSER_ADMIN_KIOSKMODE: $(get_valid_bool $CONFIG_BROWSER_ADMIN_KIOSKMODE)"
  echo "CONFIG_BROWSER_ADMIN_FULLSCREEN: $(get_valid_bool $CONFIG_BROWSER_ADMIN_FULLSCREEN)"
  echo "CONFIG_BROWSER_ADMIN_MAXIMIZED: $(get_valid_bool $CONFIG_BROWSER_ADMIN_MAXIMIZED)"
  echo "CONFIG_BROWSER_ADMIN_PANEL_POSITION: $CONFIG_BROWSER_ADMIN_PANEL_POSITION $adminpanel"
  echo "CONFIG_BROWSER_ADMIN_PANEL_TITLE: $CONFIG_BROWSER_ADMIN_PANEL_TITLE"
  echo "CONFIG_BROWSER_ADMIN_PANEL_HOME: $(get_valid_bool $CONFIG_BROWSER_ADMIN_PANEL_HOME)"
  echo "CONFIG_BROWSER_ADMIN_PANEL_CLOSE: $(get_valid_bool $CONFIG_BROWSER_ADMIN_PANEL_CLOSE)"
  echo "CONFIG_APPSTART: $CONFIG_APPSTART $appstart_kiosk"
  echo "CONFIG_ADMIN_ALLOW: $(get_valid_bool $CONFIG_ADMIN_ALLOW)"
  echo "CONFIG_ADMIN_LOGINUSER: $CONFIG_ADMIN_LOGINUSER $adminuser"
  echo "CONFIG_ADMIN_APPSTART: $CONFIG_ADMIN_APPSTART $appstart_admin"
  echo "CONFIG_ADMIN_AUTOLOGOUT: $(get_valid_bool $CONFIG_ADMIN_AUTOLOGOUT)"
  echo "CONFIG_ADMIN_PANEL: $(get_valid_bool $CONFIG_ADMIN_PANEL)"
  echo "CONFIG_KIOSK_USERNAME: $CONFIG_KIOSK_USERNAME $kioskuser"
  echo "CONFIG_KIOSK_USERGROUPS: $CONFIG_KIOSK_USERGROUPS $usergroups"
  unset IFS
}

function cmd_print_version() {
  echo "$SCRIPT_TITLE v$SCRIPT_VERSION"
}

function cmd_print_help() {
  echo "Usage: $SCRIPT_NAME [OPTION] [-y|--yes]"
  echo "$SCRIPT_TITLE v$SCRIPT_VERSION"
  echo "Adminmode switch hotkey: Shift+End"
  echo " "
  echo "Current states:"
  echo "Kiosk Active: $(config_read "$STATE_FILE" KIOSK_ACTIVE ???)"
  echo "Adminmode: $(config_read "$STATE_FILE" KIOSK_ADMINMODE ???)"
  echo " "
  echo "-m, --adminmode         start kiosk; enter adminmode"
  echo "-a, --activate          start kiosk; quit adminmode (if active)"
  echo "-d, --deactivate        stop kiosk; quit adminmode (if active)"
  echo "-s, --settings          print and test current active settings"
  echo "-v, --version           print version info and exit"
  echo "-h, --help              print this help and exit"
  echo " "
  echo "Only one option at same time is allowed!"
  echo " "
  echo "Author: aragon25 <aragon25.01@web.de>"
}

if [ "$CMD" != "version" ] && [ "$CMD" != "help" ]; then
  do_check_start
  config_read_all
fi
[[ "$CMD" == "version" ]] && cmd_print_version
[[ "$CMD" == "help" ]] && cmd_print_help
[[ "$CMD" =~ "install_" ]] && cmd_install
[[ "$CMD" == "service" ]] && cmd_service
[[ "$CMD" == "service_pre" ]] && cmd_service_pre
[[ "$CMD" == "deactivate" ]] && cmd_stop_kiosk
[[ "$CMD" == "activate" ]] && cmd_start_kiosk
[[ "$CMD" == "adminmode" ]] && cmd_adminmode
[[ "$CMD" == "settings" ]] && cmd_settings

exit $EXITCODE
