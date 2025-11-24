#!/bin/bash
##############################################
##                                          ##
##  kiosk browser starter                   ##
##                                          ##
##############################################

urlencode() {
    local LANG=C
    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "$c" ;;
            *) printf '%%%02X' "'$c"
        esac
    done
}

export LC_ALL=C
export LANG=C
USER_ID="$(id -u)"
USER_NAME="$(id -un)"
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
PID_APP_FILE="/run/user/$(id -u)/rpi-kiosk-browser.pid"
EXEC_FILE="$(command -v chromium-browser)"
[ -z "$EXEC_FILE" ] && EXEC_FILE="$(command -v chromium)"
[ -z "$EXEC_FILE" ] && EXEC_FILE="chromium-browser"
EXEC_CMD=(--noerrdialogs --disable-infobars --disable-session-crashed-bubble --disable-features=TranslateUI,NotificationIndicator --disable-pinch --overscroll-history-navigation=0 --no-first-run --disable-component-update --disable-sync --disable-translate)
CURL_CMD=(-A "Mozilla/5.0 (compatible; KioskChecker/1.0)" -s --fail --max-time 5)
BASE_DIR="/usr/lib/rpi-kiosk"
PAGE_APP="file://$SCRIPT_DIR/index.html"
PAGE_ERROR="file://$SCRIPT_DIR/error.html?site=$(urlencode "${PAGE_APP#file://}")"
FAIL_THRESHOLD=3
CHECK_WEBSITE_THRESHOLD=3
CHECK_INTERVAL=5


for i in "$@"
do
  case $i in
    --maximized)
    CMD_MAXIMIZED="true"
    ;;
    --kiosk)
    CMD_KIOSK="true"
    ;;
    --fullscreen)
    CMD_FULLSCREEN="true"
    ;;
    --panel_page_title=*)
    CMD_PANEL_TITLE="${i#*=}"
    ;;
    --panel_hide_home)
    CMD_PANEL_HOME="false"
    ;;
    --panel_hide_close)
    CMD_PANEL_CLOSE="false"
    ;;
    --panel_top-left)
    CMD_PANEL_POS="top-left"
    ;;
    --panel_top-right)
    CMD_PANEL_POS="top-right"
    ;;
    --panel_bottom-left)
    CMD_PANEL_POS="bottom-left"
    ;;
    --panel_bottom-right)
    CMD_PANEL_POS="bottom-right"
    ;;
    --data-dir=*)
    CMD_DATA_DIR="${i#*=}/kiosk-browser-$USER_ID"
    ;;
    -*|--*)
    test
    ;;
    *)
    PAGE_APP="$i"
    PAGE_ERROR="file://$SCRIPT_DIR/error.html?site=$(urlencode "${PAGE_APP#file://}")"
    ;;
  esac
done

is_valid_dirpath() {
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

is_local_network() {
  local host="$1"
  local ip
  host="${host#*://}" # removes i.e. https://
  host="${host%%/*}"  # removes after first /
  host="${host%%:*}"  # removes port
  case "$host" in
    localhost|*.lan|*.local) return 0;;
  esac
  for ip in $(host "$host" | awk '/has address/ { print $4 }' | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}'); do
    if ping -c1 -W1 "$ip" >/dev/null 2>&1; then
      host="$ip"
      break
    fi
  done
  if [[ $host =~ ^10\. ]] || [[ $host =~ ^192\.168\. ]] || [[ $host =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] ||
  [[ $host =~ ^127\. ]] || [[ $host =~ ^169\.254\. ]]; then
    return 0
  fi
  return 1
}

configure_cmd() {
  local page_app="$PAGE_APP"
  local page_error="$PAGE_ERROR"
  if is_local_network "$PAGE_APP"; then
    EXEC_CMD+=(--ignore-certificate-errors --allow-insecure-localhost --log-level=3 --no-message-box)
    CURL_CMD+=(--insecure)
  fi
  if [ -n "$CMD_PANEL_POS" ]; then
    page_app="file://$SCRIPT_DIR/loader.html?url=$(urlencode "${PAGE_APP}")&position=${CMD_PANEL_POS}"
    page_error="file://$SCRIPT_DIR/loader.html?url=$(urlencode "${PAGE_ERROR}")&position=${CMD_PANEL_POS}"
    if [ -n "$CMD_PANEL_TITLE" ]; then
      page_app="${page_app}&title=${CMD_PANEL_TITLE}"
      page_error="${page_error}&title=${CMD_PANEL_TITLE}"
    fi
    if [ "$CMD_PANEL_HOME" == "false" ]; then
      page_app="${page_app}&home=0"
      page_error="${page_error}&home=0"
    fi
    if [ "$CMD_PANEL_CLOSE" == "false" ]; then
      page_app="${page_app}&close=0"
      page_error="${page_error}&close=0"
    fi
  fi
  if [ "$CMD_KIOSK" == "true" ]; then
    if [ "$CMD_FULLSCREEN" == "true" ]; then
      EXEC_CMD+=(--kiosk)
      PAGE_APP_ARGS=("$page_app")
      PAGE_ERROR_ARGS=("$page_error")
    else
      [ "$CMD_MAXIMIZED" == "true" ] && EXEC_CMD+=(--start-maximized)
      PAGE_APP_ARGS=(--app="$page_app")
      PAGE_ERROR_ARGS=(--app="$page_error")
    fi
  else
    [ "$CMD_FULLSCREEN" != "true" ] && [ "$CMD_MAXIMIZED" == "true" ] && EXEC_CMD+=(--start-maximized)
    [ "$CMD_FULLSCREEN" == "true" ] && EXEC_CMD+=(--start-fullscreen)
    PAGE_APP_ARGS=("$page_app")
    PAGE_ERROR_ARGS=("$page_error")
  fi
  if [ -n "$CMD_DATA_DIR" ] && is_valid_dirpath "$CMD_DATA_DIR"; then
    mkdir -p "$CMD_DATA_DIR" >/dev/null 2>&1
    export HOME="$CMD_DATA_DIR/home" XDG_CONFIG_HOME="$CMD_DATA_DIR/config" XDG_CACHE_HOME="$CMD_DATA_DIR/cache" XDG_DATA_HOME="$CMD_DATA_DIR/data"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
    EXEC_CMD+=(--user-data-dir="$CMD_DATA_DIR")
  else
    if [ -n "$CMD_DATA_DIR" ]; then
      zenity --error --text="$CMD_DATA_DIR \n no access to directory! \n Using a temporary folder now..." --title="ERROR" --width=200 --height=100  --timeout=10
    fi
    export HOME="$CMD_DATA_DIR/home" XDG_CONFIG_HOME="$CMD_DATA_DIR/config" XDG_CACHE_HOME="$CMD_DATA_DIR/cache" XDG_DATA_HOME="$CMD_DATA_DIR/data"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
    tmp_data_dir=$(mktemp -d) && EXEC_CMD+=(--user-data-dir=$tmp_data_dir)
  fi
}

kill_old_app() {
  if [ -e "$PID_APP_FILE" ]; then
    PID_APP=$(<"$PID_APP_FILE")
    if ps -p $PID_APP >/dev/null 2>&1; then
      local timeout=10
      kill $PID_APP >/dev/null 2>&1
      while kill -0 $PID_APP >/dev/null 2>&1 && (( timeout-- > 0 )); do
        sleep 1
      done
      if kill -0 $PID_APP 2>/dev/null; then
        kill -9 $PID_APP >/dev/null 2>&1 || true
      fi
    fi
  fi
}

start_new_instance() {
  kill_old_app
  "$EXEC_FILE" "${EXEC_CMD[@]}" "${active_page_args[@]}" &
  PID_APP=$!
  echo "$PID_APP" > "$PID_APP_FILE"
  ps -p $PID_APP >/dev/null 2>&1
  sleep 2
}

check_commands() {
  if ! command -v zenity >/dev/null; then
      echo "zenity not found"
      return 1
  fi
  if ! command -v "$EXEC_FILE" >/dev/null; then
    zenity --error --text="$EXEC_FILE not found!" --title="ERROR" --width=200 --height=100
    return 1
  fi
  return 0
}

check_website() {
  ((check_website_count++))
  [ $check_website_count -lt $CHECK_WEBSITE_THRESHOLD ] && return 0
  if [[ "$PAGE_APP" == file://* ]]; then
    local localfile="${PAGE_APP#file://}"
    if [ -f "$localfile" ]; then
      if [ "${active_page}" != "${PAGE_APP}" ]; then
        active_page="${PAGE_APP}"
        active_page_args=("${PAGE_APP_ARGS[@]}")
        start_new_instance
      fi
    else
      if [ "${active_page}" != "${PAGE_ERROR}" ]; then
        active_page="${PAGE_ERROR}"
        active_page_args=("${PAGE_ERROR_ARGS[@]}")
        start_new_instance
      fi
    fi
  else
    if curl "${CURL_CMD[@]}" "$PAGE_APP" >/dev/null 2>&1; then
      fail_count=0
      if [ "${active_page}" != "${PAGE_APP}" ]; then
        active_page="${PAGE_APP}"
        active_page_args=("${PAGE_APP_ARGS[@]}")
        start_new_instance
      fi
    elif [ "${active_page}" == "none" ]; then
      active_page="${PAGE_ERROR}"
      active_page_args=("${PAGE_ERROR_ARGS[@]}")
      start_new_instance
    else
      ((fail_count++))
      if [ $fail_count -ge $FAIL_THRESHOLD ] && [ "${active_page}" != "${PAGE_ERROR}" ]; then
        active_page="${PAGE_ERROR}"
        active_page_args=("${PAGE_ERROR_ARGS[@]}")
        start_new_instance
      fi
    fi
  fi
}

# check if neccessary commands exists
check_commands || exit 1

# kill old remaining app if needed
kill_old_app

#application start
active_page="none"
active_page_args=()
fail_count=0
check_website_count=$CHECK_WEBSITE_THRESHOLD
configure_cmd
check_website
trap 'kill_old_app; [ -n "$tmp_data_dir" ] && [ -d "$tmp_data_dir" ] && rm -rf "$tmp_data_dir"' EXIT INT TERM
while ps -p $PID_APP >/dev/null 2>&1; do
  sleep $CHECK_INTERVAL
  check_website
done

exit 0
