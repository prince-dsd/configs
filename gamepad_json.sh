#!/bin/bash

# Path to joystick device
JOYSTICK_DEVICE="/dev/input/event13"  # Update as needed

# Kodi connection details
KODI_HOST=$(hostname -I | awk '{print $1}')
KODI_PORT=8080
KODI_URL="http://$KODI_HOST:$KODI_PORT/jsonrpc"
KODI_USER="kodi"
KODI_PASS="kodi"
AUTH_HEADER="-u $KODI_USER:$KODI_PASS"

# Function to send command and print info
send_kodi_command() {
  local method=$1
  echo "[INFO] Sending Kodi command: Input.${method}"
  curl -s $AUTH_HEADER -X POST -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"Input.${method}\",\"id\":1}" \
    "$KODI_URL" > /dev/null
}

send_button_event() {
  local button=$1
  local keymap=${2:-KB}
  local holdtime=${3:-0}

  local json=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "method": "Input.ButtonEvent",
  "params": {
    "button": "$button",
    "keymap": "$keymap",
    "holdtime": $holdtime
  },
  "id": 1
}
EOF
)

  echo "[INFO] Sending button event: button=$button keymap=$keymap holdtime=$holdtime"
  send_kodi_command "$json"
}
activate_window() {
  local window="$1"
  shift
  local parameters=("$@")

  # Build JSON params array
  local params_json="\"window\": \"$window\""
  if [ "${#parameters[@]}" -gt 0 ]; then
    local param_array=$(printf "\"%s\", " "${parameters[@]}")
    param_array="[${param_array%, }]"
    params_json+=", \"parameters\": $param_array"
  fi

  local json=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "method": "GUI.ActivateWindow",
  "params": {
    $params_json
  },
  "id": 1
}
EOF
)

  echo "[INFO] Activating window: $window with params: ${parameters[*]}"
  curl -s $AUTH_HEADER -X POST -H "Content-Type: application/json" \
    -d "$json" "$KODI_URL" > /dev/null

  echo "Window '$window' activated"
}

# Print startup message
echo "[INFO] Kodi joystick controller started"
echo "[INFO] Device: $JOYSTICK_DEVICE"
echo "[INFO] Kodi URL: $KODI_URL"
echo "[INFO] Listening for events..."

# Read events from device
evtest --grab "$JOYSTICK_DEVICE" 2>/dev/null | while read -r line; do

  # Handle button press events (EV_KEY)
  if [[ $line =~ type\ 1\ \(EV_KEY\),\ code\ [0-9]+\ \(([A-Z0-9_]+)\),\ value\ ([0-2]) ]]; then
    code="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"

    if [[ "$value" == "1" ]]; then
      case "$code" in
        BTN_SOUTH)       send_kodi_command "Select" ;;
        BTN_EAST)        send_kodi_command "Back" ;;
        BTN_NORTH)       send_kodi_command "Info" ;;
        BTN_WEST)        send_kodi_command "ContextMenu" ;;
        BTN_MODE)        send_kodi_command "Home" ;;
        BTN_TL)          activate_window "tvchannels" ;;
        BTN_TR)          activate_window "pvrosdchannels" ;;
        BTN_TL2)         send_kodi_command "PageUp" ;;
        BTN_TR2)         send_kodi_command "PageDown" ;;
        BTN_THUMBL)      send_kodi_command "Left" ;;
        BTN_THUMBR)      send_kodi_command "Right" ;;
        BTN_START)       send_kodi_command "ShowOSD" ;;
        BTN_SELECT)      send_kodi_command "Back" ;;
        BTN_DPAD_UP)     send_kodi_command "Up" ;;
        BTN_DPAD_DOWN)   send_kodi_command "Down" ;;
        BTN_DPAD_LEFT)   send_kodi_command "Left" ;;
        BTN_DPAD_RIGHT)  send_kodi_command "Right" ;;
        *) echo "[DEBUG] Unmapped button: $code" ;;
      esac
    fi

  # Handle D-Pad analog axes (EV_ABS)
  elif [[ $line =~ type\ 3\ \(EV_ABS\),\ code\ [0-9]+\ \((ABS_[A-Z0-9]+)\),\ value\ (-?[0-9]+) ]]; then
    axis="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"

     case "$axis" in
      # D-Pad (hat switch)
      ABS_HAT0Y)
        case "$value" in
          -1) send_kodi_command "Up" ;;
           1) send_kodi_command "Down" ;;
           0) ;;  # Neutral
        esac
        ;;
      ABS_HAT0X)
        case "$value" in
          -1) send_kodi_command "Left" ;;
           1) send_kodi_command "Right" ;;
           0) ;;  # Neutral
        esac
        ;;

      # Left analog stick
      ABS_Y)
        if (( value < -10000 )); then
          send_kodi_command "Up"
        elif (( value > 10000 )); then
          send_kodi_command "Down"
        fi
        ;;
      ABS_X)
        if (( value < -10000 )); then
          send_kodi_command "Left"
        elif (( value > 10000 )); then
          send_kodi_command "Right"
        fi
        ;;

      # Right analog stick
      ABS_RY)
        if (( value < -10000 )); then
          send_kodi_command "Up"
        elif (( value > 10000 )); then
          send_kodi_command "Down"
        fi
        ;;
      ABS_RX)
        if (( value < -10000 )); then
          send_kodi_command "Left"
        elif (( value > 10000 )); then
          send_kodi_command "Right"
        fi
        ;;

      # Optional: triggers (if reported as ABS_Z and ABS_RZ)
      ABS_Z)
        if (( value > 10000 )); then
          send_kodi_command "PageUp"
        fi
        ;;
      ABS_RZ)
        if (( value > 10000 )); then
          send_kodi_command "PageDown"
        fi
        ;;
    esac
  fi

done
