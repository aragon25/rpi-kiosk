#!/bin/bash
##############################################
##                                          ##
##  kiosk init script                       ##
##                                          ##
##############################################

export LC_ALL=C
export LANG=C
USER_ID="$(id -u)"
USER_NAME="$(id -un)"
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
CONFIG_FILE="/etc/rpi-kiosk/kiosk.conf"
PID_FILE_MAIN="/run/user/$(id -u)/rpi-kiosk-app.pid"
PID_FILE_OSK="/run/user/$(id -u)/rpi-kiosk-osk.pid"
PID_FILE_PANEL="/run/user/$(id -u)/rpi-kiosk-panel.pid"
LOCK_FILE_LOGOUT="/run/user/$(id -u)/rpi-kiosk-logout.lock"
LOCK_FILE_ADMIN="/run/user/$(id -u)/rpi-kiosk-admin.lock"
LOCK_FILE_BROWSER="/run/user/$(id -u)/rpi-kiosk-browser.lock"
COM_FILE="/run/rpi-kiosk-com"
BASE_DIR="/usr/lib/rpi-kiosk"
CHECK_INTERVAL=5
EXEC_FILE_OSK="$(command -v onboard)"
EXEC_FILE_PANEL="$(command -v tint2)"
EXEC_FILE_BROWSER="$BASE_DIR/kiosk-browser/kiosk-browser.sh"
COMMANDS_MAIN=(curl wmctrl xset xmodmap feh numlockx "$EXEC_FILE_BROWSER")
COMMANDS_OSK=(onboard dconf xdpyinfo)
COMMANDS_PANEL=(tint2)
CONFIG_PANEL="$HOME/.config/tint2/kiosk-admin.tint2rc"
PANEL_CMD=(-c "$CONFIG_PANEL")
BROWSER_CMD=()
CMD="$1"
SERVICE_RUNNING="true"

config_read(){ # path, key, defaultvalue -> value
  local val=$( (grep -E "^${2}=" -m 1 "${1}" 2>/dev/null || echo "VAR=__UNDEFINED__") | head -n 1 | cut -d '=' -f 2-)
  #val=$(echo "${val}" | sed 's/ *$//g' | sed 's/^ *//g')
  val=$(echo "$val" | xargs)
  [ "${val}" == "__UNDEFINED__" ] && val="$3"
  printf -- "%s" "${val}"
}

config_read_all(){
  local first_username=$(getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody" { print $1; exit }')
  [ -z "$first_username" ] && first_username="pi"
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
  CONFIG_BROWSER_KIOSK_KIOSKMODE=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_KIOSKMODE false)
  CONFIG_BROWSER_KIOSK_FULLSCREEN=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_FULLSCREEN false)
  CONFIG_BROWSER_KIOSK_MAXIMIZED=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_MAXIMIZED true)
  CONFIG_BROWSER_KIOSK_PANEL_POSITION=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_PANEL_POSITION false)
  CONFIG_BROWSER_KIOSK_PANEL_TITLE=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_PANEL_TITLE "RPI-KIOSK")
  CONFIG_BROWSER_KIOSK_PANEL_HOME=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_PANEL_HOME false)
  CONFIG_BROWSER_KIOSK_PANEL_CLOSE=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_KIOSK_PANEL_CLOSE false)
  CONFIG_BROWSER_ADMIN_APPDATA=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_APPDATA false)
  CONFIG_BROWSER_ADMIN_KIOSKMODE=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_KIOSKMODE true)
  CONFIG_BROWSER_ADMIN_FULLSCREEN=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_FULLSCREEN true)
  CONFIG_BROWSER_ADMIN_MAXIMIZED=$(config_read "$CONFIG_FILE" CONFIG_BROWSER_ADMIN_MAXIMIZED false)
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
  local entry
  local test
  IFS=$'\n'
  test=($(find "$CONFIG_FILE.d" -maxdepth 1 -type f -name "*.conf" 2>/dev/null))
  if [ "${#test[@]}" != "0" ]; then
    for entry in ${test[@]}; do
      if [[ $(file -b --mime-type "$(readlink -f "$entry")" 2>/dev/null) =~ "text" ]]; then
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
      fi
    done
  fi
  unset IFS
  CONFIG_ADMIN_LOGINUSER=$(echo "$CONFIG_ADMIN_LOGINUSER" | sed 's/[[:blank:]]//g')
  CONFIG_KIOSK_USERNAME=$(echo "$CONFIG_KIOSK_USERNAME" | sed 's/[[:blank:]]//g')
  [[ ! $CONFIG_SCRNSVR =~ ^[0-9]+$ ]] && CONFIG_SCRNSVR=0
  [[ ! $CONFIG_SCRNBLK =~ ^[0-9]+$ ]] && CONFIG_SCRNBLK=0
  if ! is_valid_username "$CONFIG_KIOSK_USERNAME"; then
    CONFIG_KIOSK_USERNAME=kiosk
  fi
  CONFIG_CLICKLOCK="$(get_valid_bool $CONFIG_CLICKLOCK)"
  CONFIG_NUMLOCK="$(get_valid_bool $CONFIG_NUMLOCK)"
  CONFIG_REBOOT="$(get_valid_bool $CONFIG_REBOOT)"
  CONFIG_CURSOR_HIDE="$(get_valid_bool $CONFIG_CURSOR_HIDE)"
  CONFIG_OSK_KIOSK="$(get_valid_bool $CONFIG_OSK_KIOSK)"
  CONFIG_OSK_ADMIN="$(get_valid_bool $CONFIG_OSK_ADMIN)"
  CONFIG_BROWSER_KIOSK_APPDATA="${CONFIG_BROWSER_KIOSK_APPDATA%/}"
  CONFIG_BROWSER_KIOSK_KIOSKMODE="$(get_valid_bool $CONFIG_BROWSER_KIOSK_KIOSKMODE)"
  CONFIG_BROWSER_KIOSK_FULLSCREEN="$(get_valid_bool $CONFIG_BROWSER_KIOSK_FULLSCREEN)"
  CONFIG_BROWSER_KIOSK_MAXIMIZED="$(get_valid_bool $CONFIG_BROWSER_KIOSK_MAXIMIZED)"
  [ "$CONFIG_BROWSER_KIOSK_PANEL_POSITION" != "top-left" ] && [ "$CONFIG_BROWSER_KIOSK_PANEL_POSITION" != "top-right" ] && \
  [ "$CONFIG_BROWSER_KIOSK_PANEL_POSITION" != "bottom-left" ] && [ "$CONFIG_BROWSER_KIOSK_PANEL_POSITION" != "bottom-right" ] && CONFIG_BROWSER_KIOSK_PANEL_POSITION="false"
  #[ -z "$CONFIG_BROWSER_KIOSK_PANEL_TITLE" ] && CONFIG_BROWSER_KIOSK_PANEL_TITLE="RPI-KIOSK"
  CONFIG_BROWSER_KIOSK_PANEL_HOME="$(get_valid_bool $CONFIG_BROWSER_KIOSK_PANEL_HOME)"
  CONFIG_BROWSER_KIOSK_PANEL_CLOSE="$(get_valid_bool $CONFIG_BROWSER_KIOSK_PANEL_CLOSE)"
  CONFIG_BROWSER_ADMIN_APPDATA="${CONFIG_BROWSER_ADMIN_APPDATA%/}"
  CONFIG_BROWSER_ADMIN_KIOSKMODE="$(get_valid_bool $CONFIG_BROWSER_ADMIN_KIOSKMODE)"
  CONFIG_BROWSER_ADMIN_FULLSCREEN="$(get_valid_bool $CONFIG_BROWSER_ADMIN_FULLSCREEN)"
  CONFIG_BROWSER_ADMIN_MAXIMIZED="$(get_valid_bool $CONFIG_BROWSER_ADMIN_MAXIMIZED)"
  [ "$CONFIG_BROWSER_ADMIN_PANEL_POSITION" != "top-left" ] && [ "$CONFIG_BROWSER_ADMIN_PANEL_POSITION" != "top-right" ] && \
  [ "$CONFIG_BROWSER_ADMIN_PANEL_POSITION" != "bottom-left" ] && [ "$CONFIG_BROWSER_ADMIN_PANEL_POSITION" != "bottom-right" ] && CONFIG_BROWSER_ADMIN_PANEL_POSITION="false"
  #[ -z "$CONFIG_BROWSER_ADMIN_PANEL_TITLE" ] && CONFIG_BROWSER_ADMIN_PANEL_TITLE="RPI-KIOSK"
  CONFIG_BROWSER_ADMIN_PANEL_HOME="$(get_valid_bool $CONFIG_BROWSER_ADMIN_PANEL_HOME)"
  CONFIG_BROWSER_ADMIN_PANEL_CLOSE="$(get_valid_bool $CONFIG_BROWSER_ADMIN_PANEL_CLOSE)"
  CONFIG_ADMIN_ALLOW="$(get_valid_bool $CONFIG_ADMIN_ALLOW)"
  CONFIG_ADMIN_AUTOLOGOUT="$(get_valid_bool $CONFIG_ADMIN_AUTOLOGOUT)"
  CONFIG_ADMIN_PANEL="$(get_valid_bool $CONFIG_ADMIN_PANEL)"
  [ -z "$CONFIG_ADMIN_APPSTART" ] && CONFIG_ADMIN_APPSTART="false"
}

is_valid_username() {
  local re='^[[:lower:]_][[:lower:][:digit:]_.-]{1,15}$'
  local name="$1"
  [[ -z "$name" ]] && return 1
  (( ${#name} > 16 )) && return 1
  [[ $name =~ $re ]]
}

get_valid_bool() {
  local result_s="false"
  [ "$1" == "true" ] && result_s="true"
  [ "$1" == "1" ] && result_s="true"
  printf -- "%s\n" "$result_s" 
}

get_xsession_user() {
  local entry
  local test
  local result
  IFS=$'\n'
  test=($(who 2>/dev/null))
  if [ "${#test[@]}" != "0" ]; then
    for entry in ${test[@]}; do
      [[ "$entry" =~ "(:0)" ]] && result="$(echo "$entry" | cut -d' ' -f1)"
    done
  fi
  [ "$result" != "" ] && printf -- "%s\n" "$result"
  unset IFS
}

kill_old_all() {
  kill_old_main
  kill_old_osk
  kill_old_panel
}

kill_old_main() {
  if [ -e "$PID_FILE_MAIN" ]; then
    PID_MAIN=$(<"$PID_FILE_MAIN")
    if ps -p $PID_MAIN >/dev/null 2>&1; then
      local timeout=10
      kill $PID_MAIN >/dev/null 2>&1
      while kill -0 $PID_MAIN >/dev/null 2>&1 && (( timeout-- > 0 )); do
        sleep 1
      done
      if kill -0 $PID_MAIN 2>/dev/null; then
        kill -9 $PID_MAIN >/dev/null 2>&1 || true
      fi
    fi
    rm -f "$PID_FILE_MAIN" >/dev/null 2>&1
    unset PID_MAIN
  fi
}

kill_old_osk() {
  if [ -e "$PID_FILE_OSK" ]; then
    PID_OSK=$(<"$PID_FILE_OSK")
    if ps -p $PID_OSK >/dev/null 2>&1; then
      local timeout=10
      kill $PID_OSK >/dev/null 2>&1
      while kill -0 $PID_OSK >/dev/null 2>&1 && (( timeout-- > 0 )); do
        sleep 1
      done
      if kill -0 $PID_OSK 2>/dev/null; then
        kill -9 $PID_OSK >/dev/null 2>&1 || true
      fi
    fi
    rm -f "$PID_FILE_OSK" >/dev/null 2>&1
    unset PID_OSK
  fi
  local onboard_pids=$(pgrep -u "$USER_NAME" -x onboard)
  if [ -n "$onboard_pids" ]; then
    kill $onboard_pids >/dev/null 2>&1
    sleep 1
    onboard_pids=$(pgrep -u "$USER_NAME" -x onboard)
    [ -n "$onboard_pids" ] && kill -9 $onboard_pids >/dev/null 2>&1
  fi
}

kill_old_panel() {
  if [ -e "$PID_FILE_PANEL" ]; then
    PID_PANEL=$(<"$PID_FILE_PANEL")
    if ps -p $PID_PANEL >/dev/null 2>&1; then
      local timeout=10
      kill $PID_PANEL >/dev/null 2>&1
      while kill -0 $PID_PANEL >/dev/null 2>&1 && (( timeout-- > 0 )); do
        sleep 1
      done
      if kill -0 $PID_PANEL 2>/dev/null; then
        kill -9 $PID_PANEL >/dev/null 2>&1 || true
      fi
    fi
    rm -f "$PID_FILE_PANEL" >/dev/null 2>&1
    unset PID_PANEL
  fi
  local onboard_pids=$(pgrep -u "$USER_NAME" -x onboard)
  if [ -n "$onboard_pids" ]; then
    kill $onboard_pids >/dev/null 2>&1
    sleep 1
    onboard_pids=$(pgrep -u "$USER_NAME" -x onboard)
    [ -n "$onboard_pids" ] && kill -9 $onboard_pids >/dev/null 2>&1
  fi
}

check_commands_main() {
  if ! command -v zenity > /dev/null; then
      echo "zenity not found"
      return 1
  fi
  local entry
  IFS=$' '
  if [ "${#COMMANDS_MAIN[@]}" != "0" ]; then
    for entry in ${COMMANDS_MAIN[@]}; do
      if ! command -v $entry > /dev/null; then
        zenity --error --text="$entry not found!" --title="ERROR" --width=200 --height=100 --timeout=15
        unset IFS
        return 1
      fi
    done
  fi
  unset IFS
  return 0
}

check_commands_osk() {
  local entry
  IFS=$' '
  if [ "${#COMMANDS_OSK[@]}" != "0" ]; then
    for entry in ${COMMANDS_OSK[@]}; do
      if ! command -v $entry > /dev/null; then
        unset IFS
        return 1
      fi
    done
  fi
  unset IFS
  return 0
}

check_commands_panel() {
  local entry
  IFS=$' '
  if [ "${#COMMANDS_PANEL[@]}" != "0" ]; then
    for entry in ${COMMANDS_PANEL[@]}; do
      if ! command -v $entry > /dev/null; then
        unset IFS
        return 1
      fi
    done
  fi
  unset IFS
  return 0
}

is_exec_or_website() {
  local input="$1"
  local val="NONE"
  local realfile="$(readlink -f "$input" 2>/dev/null)"
  if [[ "$input" =~ ^https?:// ]]; then
    val="SITE"
  elif [ -d "$realfile" ]; then
    val="DIR"
  elif [ -f "$realfile" ]; then
    local filetype="$(file -b --mime-type "$realfile" 2>/dev/null)"
    case "$filetype" in
      *executable*|*script*)
        [[ -x "$realfile" ]] && val="EXEC" || val="FILE"
        ;;
      *html*)
        val="HTML"
        ;;
      *)
        case "$realfile" in
          *.desktop|*.sh|*.py)
            [[ -x "$realfile" ]] && val="EXEC" || val="FILE"
            ;;
        esac
        ;;
    esac
  fi
  printf -- "%s" "$val"
}

check_files_osk() {
  if [ ! -f "/usr/share/onboard/layouts/kiosk-osk.onboard" ] || [ ! -f "/usr/share/onboard/layouts/kiosk-osk-alpha.svg" ] || \
     [ ! -f "/usr/share/onboard/layouts/kiosk-osk-sidebar.svg" ] || [ ! -f "/usr/share/onboard/layouts/kiosk-osk-symbols.svg" ]; then
    return 1
  fi
  return 0
}

configure_browser() {
  if [ "$USER_ID" == "2001" ] && [ "$USER_NAME" == "$CONFIG_KIOSK_USERNAME" ]; then
    [ "$CONFIG_BROWSER_KIOSK_APPDATA" != "false" ] && BROWSER_CMD+=("--data-dir=$CONFIG_BROWSER_KIOSK_APPDATA")
    [ "$CONFIG_BROWSER_KIOSK_KIOSKMODE" == "true" ] && BROWSER_CMD+=(--kiosk)
    [ "$CONFIG_BROWSER_KIOSK_FULLSCREEN" == "true" ] && BROWSER_CMD+=(--fullscreen)
    [ "$CONFIG_BROWSER_KIOSK_MAXIMIZED" == "true" ] && BROWSER_CMD+=(--maximized)
    BROWSER_CMD+=("--panel_page_title=$CONFIG_BROWSER_KIOSK_PANEL_TITLE")
    [ "$CONFIG_BROWSER_KIOSK_PANEL_POSITION" != "false" ] && BROWSER_CMD+=(--panel_$CONFIG_BROWSER_KIOSK_PANEL_POSITION)
    [ "$CONFIG_BROWSER_KIOSK_PANEL_HOME" == "false" ] && BROWSER_CMD+=(--panel_hide_home)
    [ "$CONFIG_BROWSER_KIOSK_PANEL_CLOSE" == "false" ] && BROWSER_CMD+=(--panel_hide_close)
  elif [ "$USER_NAME" == "$CONFIG_ADMIN_LOGINUSER" ]; then
    [ "$CONFIG_BROWSER_ADMIN_APPDATA" != "false" ] && BROWSER_CMD+=("--data-dir=$CONFIG_BROWSER_ADMIN_APPDATA")
    [ "$CONFIG_BROWSER_ADMIN_KIOSKMODE" == "true" ] && BROWSER_CMD+=(--kiosk)
    [ "$CONFIG_BROWSER_ADMIN_FULLSCREEN" == "true" ] && BROWSER_CMD+=(--fullscreen)
    [ "$CONFIG_BROWSER_ADMIN_MAXIMIZED" == "true" ] && BROWSER_CMD+=(--maximized)
    BROWSER_CMD+=("--panel_page_title=$CONFIG_BROWSER_ADMIN_PANEL_TITLE")
    [ "$CONFIG_BROWSER_ADMIN_PANEL_POSITION" != "false" ] && BROWSER_CMD+=(--panel_$CONFIG_BROWSER_ADMIN_PANEL_POSITION)
    [ "$CONFIG_BROWSER_ADMIN_PANEL_HOME" == "false" ] && BROWSER_CMD+=(--panel_hide_home)
    [ "$CONFIG_BROWSER_ADMIN_PANEL_CLOSE" == "false" ] && BROWSER_CMD+=(--panel_hide_close)
  fi
}

configure_main() {
  # set desktop background
  [ -f "$CONFIG_BCKGRND" ] && feh --bg-scale "$CONFIG_BCKGRND"
  # set screensaver
  if [ "$CONFIG_SCRNSVR" == "0" ]; then
    xset s off
  else 
    xset s on
    xset s $CONFIG_SCRNSVR 300
    xset s noblank
  fi
  # set screen blanking
  if [ "$CONFIG_SCRNBLK" == "0" ]; then
    xset -dpms
  else
    xset +dpms
    xset dpms $CONFIG_SCRNBLK $CONFIG_SCRNBLK $CONFIG_SCRNBLK
  fi
  #prevent blind clicks on a blanked touchscreen. 
  if [ "$CONFIG_CLICKLOCK" == "true" ] && which clicklock >/dev/null && which xssstart >/dev/null; then
    xssstart "$(which clicklock)" &
  fi
  #turn on numlock
  if [ "$CONFIG_NUMLOCK" == "true" ]; then
    numlockx on
  elif which numlockx >/dev/null; then
    numlockx off
  fi
  #setup BROWSER_CMD
  configure_browser
  #finish here if kiosk is not active user
  [ "$USER_ID" != "2001" ] && return 0
  #Lock out right-click and menu button on keyboard
  xmodmap -e "pointer = 1 2 32 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31"
  xmodmap -e "keycode 135 ="
  #Lock out other special keys
  xmodmap -e "keycode 64 ="       #L-alt
  xmodmap -e "keycode 108 ="      #R-alt
  xmodmap -e "keycode 37 ="       #L-ctrl
  xmodmap -e "keycode 105 ="      #R-ctrl
  xmodmap -e "keycode 133 ="      #L-windows (meta key)
  xmodmap -e "keycode 134 ="      #R-windows (meta key)
  xmodmap -e "keycode 107 ="      #print-screen
  xmodmap -e "keycode 127 ="      #page-break
  #xmodmap -e "keycode 77 ="       #num-lock (problems with numlockx on)
  xmodmap -e "keycode 78 ="       #scroll-lock
  xmodmap -e "keycode 118 ="      #insert
  xmodmap -e "keycode 9 ="        #esc
  xmodmap -e "keycode 67 ="       #F1
  xmodmap -e "keycode 68 ="       #F2
  xmodmap -e "keycode 69 ="       #F3
  xmodmap -e "keycode 70 ="       #F4
  xmodmap -e "keycode 71 ="       #F5
  xmodmap -e "keycode 72 ="       #F6
  xmodmap -e "keycode 73 ="       #F7
  xmodmap -e "keycode 74 ="       #F8
  xmodmap -e "keycode 75 ="       #F9
  xmodmap -e "keycode 76 ="       #F10
  xmodmap -e "keycode 95 ="       #F11
  xmodmap -e "keycode 96 ="       #F12
}

configure_osk() {
  local disp_res=$(xdpyinfo | grep dimensions | awk '{print $2}')
  local disp_res_x=$(echo $disp_res | awk -Fx '{print $1}')
  local disp_res_y=$(echo $disp_res | awk -Fx '{print $2}')
  dconf reset -f /org/onboard/ >/dev/null 2>&1
  dconf write /org/onboard/layout "'/usr/share/onboard/layouts/kiosk-osk.onboard'" >/dev/null 2>&1
  dconf write /org/onboard/show-tooltips false >/dev/null 2>&1
  dconf write /org/onboard/theme "'/usr/share/onboard/themes/Droid.theme'" >/dev/null 2>&1
  dconf write /org/onboard/use-system-defaults false >/dev/null 2>&1
  dconf write /org/onboard/xembed-onboard true >/dev/null 2>&1
  dconf write /org/onboard/start-minimized true >/dev/null 2>&1
  dconf write /org/onboard/show-status-icon true >/dev/null 2>&1
  dconf write /org/onboard/status-icon-provider "'auto'" >/dev/null 2>&1
  dconf write /org/onboard/system-theme-tracking-enabled false >/dev/null 2>&1
  dconf write /org/onboard/keyboard/audio-feedback-enabled false >/dev/null 2>&1
  dconf write /org/onboard/keyboard/touch-input "'multi'" >/dev/null 2>&1
  dconf write /org/onboard/lockdown/disable-click-buttons true >/dev/null 2>&1
  dconf write /org/onboard/lockdown/disable-preferences true >/dev/null 2>&1
  dconf write /org/onboard/lockdown/disable-quit true >/dev/null 2>&1
  dconf write /org/onboard/theme-settings/color-scheme "'/usr/share/onboard/themes/Granite.colors'" >/dev/null 2>&1
  dconf write /org/onboard/window/docking-enabled false >/dev/null 2>&1
  dconf write /org/onboard/window/window-decoration false >/dev/null 2>&1
  dconf write /org/onboard/window/window-state-sticky true >/dev/null 2>&1
  dconf write /org/onboard/window/force-to-top true >/dev/null 2>&1
  dconf write /org/onboard/window/landscape/height 200 >/dev/null 2>&1
  dconf write /org/onboard/window/landscape/width 550 >/dev/null 2>&1
  dconf write /org/onboard/window/portrait/height 200 >/dev/null 2>&1
  dconf write /org/onboard/window/portrait/width 550 >/dev/null 2>&1
  dconf write /org/onboard/icon-palette/in-use true >/dev/null 2>&1
  [ "$USER_NAME" == "$CONFIG_ADMIN_LOGINUSER" ] && [ "$CONFIG_ADMIN_PANEL" == "true" ] && dconf write /org/onboard/icon-palette/in-use false >/dev/null 2>&1
  dconf write /org/onboard/icon-palette/landscape/height 45 >/dev/null 2>&1
  dconf write /org/onboard/icon-palette/landscape/width 45 >/dev/null 2>&1
  dconf write /org/onboard/icon-palette/portrait/height 45 >/dev/null 2>&1
  dconf write /org/onboard/icon-palette/portrait/width 45 >/dev/null 2>&1
  local onboard_width_landscape=$(dconf read /org/onboard/window/landscape/width | tr -d ' ')
  local onboard_height_landscape=$(dconf read /org/onboard/window/landscape/height | tr -d ' ')
  local icon_width_landscape=$(dconf read /org/onboard/icon-palette/landscape/width | tr -d ' ')
  local icon_height_landscape=$(dconf read /org/onboard/icon-palette/landscape/height | tr -d ' ')
  local onboard_width_portrait=$(dconf read /org/onboard/window/portrait/width | tr -d ' ')
  local onboard_height_portrait=$(dconf read /org/onboard/window/portrait/height | tr -d ' ')
  local icon_width_portrait=$(dconf read /org/onboard/icon-palette/portrait/width | tr -d ' ')
  local icon_height_portrait=$(dconf read /org/onboard/icon-palette/portrait/height | tr -d ' ')
  dconf write /org/onboard/window/landscape/x $(( ( disp_res_x / 2 ) - ( onboard_width_landscape / 2 ) )) >/dev/null 2>&1
  dconf write /org/onboard/window/landscape/y $(( disp_res_y - onboard_height_landscape )) >/dev/null 2>&1
  dconf write /org/onboard/icon-palette/landscape/x $(( disp_res_x - icon_width_landscape )) >/dev/null 2>&1
  dconf write /org/onboard/icon-palette/landscape/y $(( disp_res_y - icon_height_landscape )) >/dev/null 2>&1
  dconf write /org/onboard/window/portrait/x $(( ( disp_res_x / 2 ) - ( onboard_width_portrait / 2 ) )) >/dev/null 2>&1
  dconf write /org/onboard/window/portrait/y $(( disp_res_y - onboard_height_portrait )) >/dev/null 2>&1
  dconf write /org/onboard/icon-palette/portrait/x $(( disp_res_x - icon_width_portrait )) >/dev/null 2>&1
  dconf write /org/onboard/icon-palette/portrait/y $(( disp_res_y - icon_height_portrait )) >/dev/null 2>&1
  dconf write /org/onboard/window/window-handles "'M'" >/dev/null 2>&1
  dconf write /org/onboard/icon-palette/window-handles "''" >/dev/null 2>&1
}

configure_panel() {
  mkdir -p "$(dirname "$CONFIG_PANEL")"
  cat <<EOF | tee "$CONFIG_PANEL" >/dev/null 2>&1
gradient = radial
start_color = #000000 0
end_color = #000000 0
rounded = 0
border_width = 0
border_sides = TBLR
border_content_tint_weight = 0
background_content_tint_weight = 0
background_color = #000000 60
border_color = #000000 30
background_color_hover = #000000 60
border_color_hover = #000000 30
background_color_pressed = #000000 60
border_color_pressed = #000000 30
rounded = 4
border_width = 1
border_sides = TBLR
border_content_tint_weight = 0
background_content_tint_weight = 0
background_color = #777777 20
border_color = #777777 30
background_color_hover = #aaaaaa 22
border_color_hover = #eaeaea 44
background_color_pressed = #555555 4
border_color_pressed = #eaeaea 44
rounded = 4
border_width = 1
border_sides = TBLR
border_content_tint_weight = 0
background_content_tint_weight = 0
background_color = #777777 20
border_color = #ffffff 40
background_color_hover = #aaaaaa 22
border_color_hover = #eaeaea 44
background_color_pressed = #555555 4
border_color_pressed = #eaeaea 44
rounded = 4
border_width = 1
border_sides = TBLR
border_content_tint_weight = 0
background_content_tint_weight = 0
background_color = #aa4400 100
border_color = #aa7733 100
background_color_hover = #cc7700 100
border_color_hover = #aa7733 100
background_color_pressed = #555555 4
border_color_pressed = #aa7733 100
rounded = 1
border_width = 1
border_sides = TBLR
border_content_tint_weight = 0
background_content_tint_weight = 0
background_color = #222222 100
border_color = #333333 100
background_color_hover = #ffffaa 100
border_color_hover = #000000 100
background_color_pressed = #ffffaa 100
border_color_pressed = #000000 100
panel_items = LTSC
panel_size = 100% 35
panel_margin = 0 0
panel_padding = 2 0 2
panel_background_id = 1
wm_menu = 1
panel_dock = 0
panel_pivot_struts = 0
panel_position = bottom left horizontal
panel_layer = top
panel_monitor = all
panel_shrink = 0
autohide = 0
autohide_show_timeout = 0
autohide_hide_timeout = 0.5
autohide_height = 2
strut_policy = follow_size
panel_window_name = tint2
disable_transparency = 1
mouse_effects = 1
font_shadow = 0
mouse_hover_icon_asb = 100 0 10
mouse_pressed_icon_asb = 100 0 0
scale_relative_to_dpi = 0
scale_relative_to_screen_height = 0
taskbar_mode = single_desktop
taskbar_hide_if_empty = 0
taskbar_padding = 0 0 2
taskbar_background_id = 0
taskbar_active_background_id = 0
taskbar_name = 0
taskbar_hide_inactive_tasks = 0
taskbar_hide_different_monitor = 0
taskbar_hide_different_desktop = 0
taskbar_always_show_all_desktop_tasks = 0
taskbar_name_padding = 4 2
taskbar_name_background_id = 0
taskbar_name_active_background_id = 0
taskbar_name_font_color = #e3e3e3 100
taskbar_name_active_font_color = #ffffff 100
taskbar_distribute_size = 0
taskbar_sort_order = none
task_align = left
task_text = 1
task_icon = 1
task_centered = 1
urgent_nb_of_blink = 100000
task_maximum_size = 150 35
task_padding = 2 2 4
task_tooltip = 1
task_thumbnail = 0
task_thumbnail_size = 210
task_font_color = #ffffff 100
task_background_id = 2
task_active_background_id = 3
task_urgent_background_id = 4
task_iconified_background_id = 2
mouse_left = toggle_iconify
mouse_middle = none
mouse_right = none
mouse_scroll_up = none
mouse_scroll_down = none
systray_padding = 0 4 2
systray_background_id = 0
systray_sort = ascending
systray_icon_size = 24
systray_icon_asb = 100 0 0
systray_monitor = 1
systray_name_filter = 
launcher_padding = 2 4 2
launcher_background_id = 0
launcher_icon_background_id = 0
launcher_icon_size = 24
launcher_icon_asb = 100 0 0
launcher_icon_theme_override = 0
startup_notifications = 1
launcher_tooltip = 1
launcher_item_app = chromium-browser.desktop
launcher_item_app = /usr/share/applications/xfe.desktop
launcher_item_app = /usr/share/applications/lxterminal.desktop
launcher_item_app = /usr/share/applications/rpi-kiosk-browser.desktop
launcher_item_app = /usr/share/applications/rpi-kiosk-logout.desktop
time1_format = %H:%M
time2_format = %A %d %B
time1_timezone = 
time2_timezone = 
clock_font_color = #ffffff 100
clock_padding = 2 0
clock_background_id = 0
clock_tooltip = 
clock_tooltip_timezone = 
clock_lclick_command = 
clock_rclick_command = orage
clock_mclick_command = 
clock_uwheel_command = 
clock_dwheel_command = 
battery_tooltip = 1
battery_low_status = 10
battery_low_cmd = xmessage 'tint2: Battery low!'
battery_full_cmd = 
battery_font_color = #ffffff 100
bat1_format = 
bat2_format = 
battery_padding = 1 0
battery_background_id = 0
battery_hide = 101
battery_lclick_command = 
battery_rclick_command = 
battery_mclick_command = 
battery_uwheel_command = 
battery_dwheel_command = 
ac_connected_cmd = 
ac_disconnected_cmd = 
tooltip_show_timeout = 0.5
tooltip_hide_timeout = 0.1
tooltip_padding = 4 4
tooltip_background_id = 5
tooltip_font_color = #dddddd 100
EOF
}

exec_main() {
  if ! ps -p $PID_MAIN >/dev/null 2>&1; then
    kill_old_main
    if check_commands_main; then
      exec_type=$(is_exec_or_website "${CONFIG_APPSTART#file://}")
      if [ "${exec_type}" == "EXEC" ]; then
        "$CONFIG_APPSTART" &
      elif [ "${exec_type}" == "SITE" ]; then
        "$EXEC_FILE_BROWSER" "${BROWSER_CMD[@]}" "$CONFIG_APPSTART" &
      elif [ "${exec_type}" == "HTML" ]; then
        "$EXEC_FILE_BROWSER" "${BROWSER_CMD[@]}" "file://${CONFIG_APPSTART#file://}" &
      elif [ "${exec_type}" == "DIR" ]; then
        zenity --error --text="\'$CONFIG_APPSTART\' is a local directory! Can not start!" --title="ERROR" --width=350 --height=100 &
      elif [ "${exec_type}" == "FILE" ]; then
        zenity --error --text="File \'$CONFIG_APPSTART\' exists but is not executable or html-type file!" --title="ERROR" --width=350 --height=100 &
      elif [ "${exec_type}" == "NONE" ]; then
        zenity --error --text="Application or Website \'$CONFIG_APPSTART\' not found!" --title="ERROR" --width=350 --height=100 &
      fi
      PID_MAIN=$!
      echo "$PID_MAIN" > "$PID_FILE_MAIN"
      ps -p $PID_MAIN >/dev/null 2>&1
    fi
  fi
}

exec_osk() {
  if ! ps -p $PID_OSK >/dev/null 2>&1; then
    kill_old_osk
    if check_commands_osk && check_files_osk; then
      configure_osk
      sleep 2
      "$EXEC_FILE_OSK" &
      PID_OSK=$!
      echo "$PID_OSK" > "$PID_FILE_OSK"
      ps -p $PID_OSK >/dev/null 2>&1
    fi
  fi
}

exec_panel() {
  if ! ps -p $PID_PANEL >/dev/null 2>&1; then
    kill_old_panel
    if check_commands_panel; then
      configure_panel
      sleep 2
      "$EXEC_FILE_PANEL" "${PANEL_CMD[@]}" &
      PID_PANEL=$!
      echo "$PID_PANEL" > "$PID_FILE_PANEL"
      ps -p $PID_PANEL >/dev/null 2>&1
    fi
  fi
}

wait_for_xsession() {
  echo "wait_for_xsession for user: $USER_NAME"
  while [ "$(get_xsession_user | tail -1)" != "$USER_NAME" ]; do
    sleep $CHECK_INTERVAL
  done
}

sudo_get_rights() {
  if ! id "$CONFIG_ADMIN_LOGINUSER" >/dev/null 2>&1; then 
    zenity --error --text="Sorry, admin user config is not valid!" --title="ERROR" --width=200 --height=100 --timeout=15
    return 1
  fi
  SUDO_USER="$CONFIG_ADMIN_LOGINUSER"
  SUDO_PASSWORD="$(zenity --password --title="Admin password (user: ${CONFIG_ADMIN_LOGINUSER})" --timeout=30)"
  [ -z "$SUDO_PASSWORD" ] && return 1
  echo "$SUDO_PASSWORD" | /bin/su - "$CONFIG_ADMIN_LOGINUSER" -c "true" >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    unset SUDO_PASSWORD
    zenity --error --text="Sorry, wrong password! \n Try again!" --title="ERROR" --width=200 --height=100 --timeout=15
    return 1
  fi
}

sudo_cmd() {
  [ -z "$SUDO_PASSWORD" ] && return 1
  #echo "$SUDO_PASSWORD" | /bin/su - "$SUDO_USER" -c "$(printf 'bash -c %q' "$*")"
  echo "$SUDO_PASSWORD" | sudo -S "$@"
}

cmd_service() {
  local conf_active="false"
  local app_active="false"
  local osk_active="false"
  local panel_active="false"
  [ "$USER_ID" == "2001" ] && [ "$USER_NAME" == "$CONFIG_KIOSK_USERNAME" ] && app_active="true" && conf_active="true"
  [ "$USER_NAME" == "$CONFIG_ADMIN_LOGINUSER" ] && conf_active="true"
  [ "$USER_NAME" == "$CONFIG_ADMIN_LOGINUSER" ] && [ "$CONFIG_ADMIN_APPSTART" != "false" ] && CONFIG_APPSTART="$CONFIG_ADMIN_APPSTART" && app_active="true"
  [ "$USER_ID" == "2001" ] && [ "$USER_NAME" == "$CONFIG_KIOSK_USERNAME" ] && [ "$CONFIG_OSK_KIOSK" == "true" ] && osk_active="true"
  [ "$USER_NAME" == "$CONFIG_ADMIN_LOGINUSER" ] && [ "$CONFIG_OSK_ADMIN" == "true" ] && osk_active="true"
  [ "$USER_NAME" == "$CONFIG_ADMIN_LOGINUSER" ] && [ "$CONFIG_ADMIN_PANEL" == "true" ] && panel_active="true"
  wait_for_xsession
  echo "xsession started..."
  kill_old_all
  ! check_commands_main && app_active="false"
  ! check_commands_osk && osk_active="false"
  ! check_files_osk && osk_active="false"
  ! check_commands_panel && panel_active="false"
  [ "$conf_active" == "true" ] && configure_main
  [ "$app_active" == "true" ] && exec_main
  [ "$panel_active" == "true" ] && exec_panel
  [ "$osk_active" == "true" ] && exec_osk
  trap 'SERVICE_RUNNING="false"; kill_old_all' EXIT INT TERM
  while [ "$SERVICE_RUNNING" == "true" ]; do
    [ "$(get_xsession_user | tail -1)" != "$USER_NAME" ] && exit 0
    if [ "$app_active" == "true" ] && ! ps -p $PID_MAIN >/dev/null 2>&1; then
      kill_old_main
      if [ "$USER_ID" == "2001" ] && [ "$USER_NAME" == "$CONFIG_KIOSK_USERNAME" ]; then
        [ "$CONFIG_REBOOT" != "true" ] && echo "0815" > "$COM_FILE" || sudo /sbin/reboot
      fi
      [ "$USER_NAME" == "$CONFIG_ADMIN_LOGINUSER" ] && [ "$CONFIG_ADMIN_AUTOLOGOUT" == "true" ] && echo "1111" > "$COM_FILE"
      app_active="false"
    fi
    if [ "$panel_active" == "true" ] && ! ps -p $PID_PANEL >/dev/null 2>&1; then
      kill_old_panel
      ! check_commands_panel && panel_active="false"
      exec_panel
    fi
    if [ "$osk_active" == "true" ] && ! ps -p $PID_OSK >/dev/null 2>&1; then
      kill_old_osk
      ! check_commands_osk && osk_active="false"
      ! check_files_osk && osk_active="false"
      exec_osk
    fi
    sleep $CHECK_INTERVAL
  done
}

cmd_browser() {
  [ -f "$LOCK_FILE_BROWSER" ] && ps -p $(<"$LOCK_FILE_BROWSER") >/dev/null 2>&1 && return 0
  [ "$(get_xsession_user | tail -1)" != "$USER_NAME" ] && return 0
  echo $$ > "$LOCK_FILE_BROWSER"
  trap 'rm -f "$LOCK_FILE_BROWSER"' EXIT
  check_commands_main || return 0
  if [ "$USER_NAME" == "$CONFIG_ADMIN_LOGINUSER" ]; then
    USER_ID="2001"
    USER_NAME="$CONFIG_KIOSK_USERNAME"
    CONFIG_BROWSER_KIOSK_KIOSKMODE=false
    CONFIG_BROWSER_KIOSK_FULLSCREEN=false
    CONFIG_BROWSER_KIOSK_MAXIMIZED=true
    configure_browser
    if [ "$CONFIG_BROWSER_KIOSK_APPDATA" != "false" ]; then
      if sudo_get_rights; then
        trap 'rm -f "$LOCK_FILE_BROWSER"; [ -n "$CREATED_RUN" ] && sudo_cmd rm -rf "/run/user/$USER_ID"' EXIT
        if [ ! -d "/run/user/$USER_ID" ]; then
          CREATED_RUN="true"
          sudo_cmd mkdir -p "/run/user/$USER_ID"
          sudo_cmd chmod 700 "/run/user/$USER_ID"
          sudo_cmd chown -R "$USER_ID:$USER_ID" "/run/user/$USER_ID"
        fi
        xhost +SI:localuser:$CONFIG_KIOSK_USERNAME
        sudo_cmd XAUTHORITY="$HOME/.Xauthority" DISPLAY="$DISPLAY" sudo -u "$USER_NAME" "$EXEC_FILE_BROWSER" "${BROWSER_CMD[@]}"
        if [ -n "$CREATED_RUN" ]; then
          sudo_cmd rm -rf "/run/user/$USER_ID"
        fi
      fi
    else
      zenity --error --text="Sorry, kiosk-browser has no \n static data-dir for kiosk user!" --title="ERROR" --width=200 --height=100 --timeout=20
    fi
  else
    zenity --error --text="Sorry, you are not rpi-kiosk admin user!" --title="ERROR" --width=200 --height=100 --timeout=20
  fi
}

cmd_logout() {
  [ -f "$LOCK_FILE_LOGOUT" ] && ps -p $(<"$LOCK_FILE_LOGOUT") >/dev/null 2>&1 && return 0
  [ "$(get_xsession_user | tail -1)" != "$USER_NAME" ] && return 0
  echo $$ > "$LOCK_FILE_LOGOUT"
  trap 'rm -f "$LOCK_FILE_LOGOUT"' EXIT
  check_commands_main || return 0
  if [ "$USER_NAME" == "$CONFIG_ADMIN_LOGINUSER" ]; then
    choice=$(zenity --list \
      --title="Logout" \
      --text="What would you like to do?" \
      --radiolist \
      --column="Choice" --column="Action" \
      TRUE "Restart session" \
      FALSE "Logout to Kiosk" \
      --width=250 --height=180)
    case "$choice" in
      "Restart session")
        echo "0815" > /run/rpi-kiosk-com
        ;;
      "Logout to Kiosk")
        echo "1111" > /run/rpi-kiosk-com
        ;;
    esac
  elif [ "$USER_ID" == "2001" ] && [ "$USER_NAME" == "$CONFIG_KIOSK_USERNAME" ]; then
    echo "0815" > "$COM_FILE"
  else
    zenity --error --text="Sorry, you are not a valid rpi-kiosk user!" --title="ERROR" --width=200 --height=100 --timeout=20
  fi
}

cmd_admin_old() {
  [ -f "$LOCK_FILE_ADMIN" ] && ps -p $(<"$LOCK_FILE_ADMIN") >/dev/null 2>&1 && return 0
  [ "$(get_xsession_user | tail -1)" != "$USER_NAME" ] && return 0
  echo $$ > "$LOCK_FILE_ADMIN"
  trap 'rm -f "$LOCK_FILE_ADMIN"' EXIT
  check_commands_main || return 0
  if [ "$USER_ID" == "2001" ] && [ "$USER_NAME" == "$CONFIG_KIOSK_USERNAME" ] && [ "$CONFIG_ADMIN_ALLOW" == "true" ] && id "$CONFIG_ADMIN_LOGINUSER" >/dev/null 2>&1; then
    wmctrl -n 2
    wmctrl -s 1
    password="$(zenity --password --title="Admin password (user: ${CONFIG_ADMIN_LOGINUSER})" --timeout=30)"
    if [ "$password" != "" ]; then
      echo "$password" | /bin/su --command true - ${CONFIG_ADMIN_LOGINUSER} >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        echo "4711" > "$COM_FILE"
      else
        zenity --error --text="Sorry, wrong password! \n Try again!" --title="ERROR" --width=200 --height=100 --timeout=15
        wmctrl -s 0
        wmctrl -n 1
      fi
    else
      wmctrl -s 0
      wmctrl -n 1
    fi
  elif [ "$USER_ID" != "2001" ] || [ "$USER_NAME" != "$CONFIG_KIOSK_USERNAME" ]; then
    zenity --error --text="Sorry, you are not kiosk user!" --title="ERROR" --width=200 --height=100 --timeout=20
  elif [ "$CONFIG_ADMIN_ALLOW" != "true" ]; then
    wmctrl -n 2
    wmctrl -s 1
    zenity --error --text="Sorry, admin login is forbidden by config!" --title="ERROR" --width=200 --height=100 --timeout=20
    wmctrl -s 0
    wmctrl -n 1
  elif ! id "$CONFIG_ADMIN_LOGINUSER" >/dev/null 2>&1; then
    wmctrl -n 2
    wmctrl -s 1
    zenity --error --text="Sorry, admin user config is not valid!" --title="ERROR" --width=200 --height=100 --timeout=20
    wmctrl -s 0
    wmctrl -n 1
  fi
}

cmd_admin() {
  [ -f "$LOCK_FILE_ADMIN" ] && ps -p $(<"$LOCK_FILE_ADMIN") >/dev/null 2>&1 && return 0
  [ "$(get_xsession_user | tail -1)" != "$USER_NAME" ] && return 0
  echo $$ > "$LOCK_FILE_ADMIN"
  trap 'rm -f "$LOCK_FILE_ADMIN"' EXIT
  check_commands_main || return 0
  if [ "$USER_ID" == "2001" ] && [ "$USER_NAME" == "$CONFIG_KIOSK_USERNAME" ] && [ "$CONFIG_ADMIN_ALLOW" == "true" ]; then
    wmctrl -n 2
    wmctrl -s 1
    if sudo_get_rights; then
      echo "4711" > "$COM_FILE"
    else
      wmctrl -s 0
      wmctrl -n 1
    fi
  elif [ "$USER_ID" != "2001" ] || [ "$USER_NAME" != "$CONFIG_KIOSK_USERNAME" ]; then
    zenity --error --text="Sorry, you are not kiosk user!" --title="ERROR" --width=200 --height=100 --timeout=20
  elif [ "$CONFIG_ADMIN_ALLOW" != "true" ]; then
    wmctrl -n 2
    wmctrl -s 1
    zenity --error --text="Sorry, admin login is forbidden by config!" --title="ERROR" --width=200 --height=100 --timeout=20
    wmctrl -s 0
    wmctrl -n 1
  fi
}

config_read_all
[ "$CMD" == "--service" ] && cmd_service
[ "$CMD" == "--logout" ] && cmd_logout
[ "$CMD" == "--admin" ] && cmd_admin
[ "$CMD" == "--browser" ] && cmd_browser

exit 0
