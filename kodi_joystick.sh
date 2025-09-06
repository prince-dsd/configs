#!/bin/bash

# === Configuration ===

# Joystick identifier (partial name match from `evtest` or `udevadm`)
JOYSTICK_NAME="Controller"

# Kodi connection details
KODI_HOST=$(hostname -I | awk '{print $1}')
KODI_PORT=8080
KODI_URL="http://$KODI_HOST:$KODI_PORT/jsonrpc"
KODI_USER="kodi"
KODI_PASS="kappa"
AUTH_HEADER="-u $KODI_USER:$KODI_PASS"

# === Logging ===

log_info() {
  echo "[INFO] $*"
}

log_warn() {
  echo "[WARN] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

# === Device Discovery ===

find_joystick_device() {
  for event in /dev/input/event*; do
    if udevadm info --query=all --name="$event" | grep -q "$JOYSTICK_NAME"; then
      echo "$event"
      return 0
    fi
  done
  return 1
}

# === Kodi JSON-RPC ===

kodi_is_online() {
  curl -s --max-time 2 "$KODI_URL" > /dev/null
  return $?
}

kodi_rpc() {
  local payload="$1"

  if ! kodi_is_online; then
    log_warn "Kodi not reachable at $KODI_URL"
    return 1
  fi

  curl -s $AUTH_HEADER -X POST -H "Content-Type: application/json" \
    -d "$payload" "$KODI_URL" > /dev/null
}

kodi_command() {
  local method="$1"
  log_info "Sending Kodi command: Input.${method}"

  local json=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "method": "Input.${method}",
  "id": 1
}
EOF
)
  kodi_rpc "$json"
}

kodi_activate_window() {
  local window="$1"; shift
  local params=("$@")

  log_info "Activating window: $window with params: ${params[*]}"

  local param_json="\"window\": \"$window\""
  if [ "${#params[@]}" -gt 0 ]; then
    local joined=$(printf "\"%s\", " "${params[@]}")
    param_json+=", \"parameters\": [${joined%, }]"
  fi

  local json=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "method": "GUI.ActivateWindow",
  "params": {
    $param_json
  },
  "id": 1
}
EOF
)
  kodi_rpc "$json"
}



set_kodi_volume() {
  local volume="$1"

  # Validate input
  if [[ "$volume" =~ ^[0-9]+$ ]]; then
    # Ensure value is within 0-100
    if (( volume < 0 || volume > 100 )); then
      echo "[ERROR] Volume must be between 0 and 100" >&2
      return 1
    fi
    volume_json="$volume"
  elif [[ "$volume" == "increment" || "$volume" == "decrement" ]]; then
    volume_json="\"$volume\""
  else
    echo "[ERROR] Invalid volume input: must be integer, 'increment', or 'decrement'" >&2
    return 1
  fi

  local json=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "method": "Application.SetVolume",
  "params": { "volume": $volume_json },
  "id": 1
}
EOF
)

  kodi_rpc "$json"
}


kodi_prev_channel() {
  local json='{
    "jsonrpc": "2.0",
    "method": "Input.ExecuteAction",
    "params": { "action": "number0" },
    "id": 1
  }'

  kodi_rpc "$json"
}

# === Input Handling ===

handle_key_event() {
  local code="$1"
  local value="$2"

  [[ "$value" != "1" ]] && return 0  # Only handle key press

  case "$code" in
    BTN_SOUTH)       kodi_command "Select" ;;
    BTN_EAST)        kodi_command "Back" ;;
    BTN_NORTH)       kodi_command "Info" ;;
    BTN_WEST)        kodi_command "ContextMenu" ;;
    BTN_MODE)        kodi_command "Home" ;;
    BTN_TL)          kodi_activate_window "tvchannels" ;;
    BTN_TR)          kodi_activate_window "pvrosdchannels" ;;
    BTN_TL2)         kodi_command "PageUp" ;;
    BTN_TR2)         kodi_command "PageDown" ;;
    BTN_THUMBL)      kodi_command "Left" ;;
    BTN_THUMBR)      kodi_command "Right" ;;
    BTN_START)       kodi_command "ShowOSD" ;;
    BTN_SELECT)      kodi_prev_channel ;;
    BTN_DPAD_UP)     kodi_command "Up" ;;
    BTN_DPAD_DOWN)   kodi_command "Down" ;;
    BTN_DPAD_LEFT)   kodi_command "Left" ;;
    BTN_DPAD_RIGHT)  kodi_command "Right" ;;
    *) log_info "Unmapped button: $code" ;;
  esac
}

handle_axis_event() {
  local axis="$1"
  local value="$2"

  case "$axis" in
    ABS_HAT0Y)
      [[ "$value" == "-1" ]] && kodi_command "Up"
      [[ "$value" == "1"  ]] && kodi_command "Down"
      ;;
    ABS_HAT0X)
      [[ "$value" == "-1" ]] && kodi_command "Left"
      [[ "$value" == "1"  ]] && kodi_command "Right"
      ;;
    ABS_Y)
      (( value < -10000 )) && kodi_command "Up"
      (( value > 10000 ))  && kodi_command "Down"
      ;;
    ABS_X)
      (( value < -10000 )) && kodi_command "Left"
      (( value > 10000 ))  && kodi_command "Right"
      ;;
    ABS_RY)
      (( value < -10000 )) && set_kodi_volume "increment"
      (( value > 10000 ))  && set_kodi_volume "decrement"
      ;;
    ABS_RX)
      (( value < -10000 )) && kodi_command "Left"
      (( value > 10000 ))  && kodi_command "Right"
      ;;
    ABS_Z)
      (( value > 10000 )) && kodi_command "PageUp" ;;
    ABS_RZ)
      (( value > 10000 )) && kodi_command "PageDown" ;;
  esac
}

# === Main Daemon Loop ===

main() {
  local device
  device=$(find_joystick_device)

  if [ -z "$device" ]; then
    log_error "Joystick '$JOYSTICK_NAME' not found."
    exit 1
  fi

  log_info "Kodi joystick daemon started"
  log_info "Using device: $device"
  log_info "Kodi JSON-RPC: $KODI_URL"

  evtest --grab "$device" 2>/dev/null | while read -r line; do
    if [[ $line =~ type\ 1\ \(EV_KEY\),\ code\ [0-9]+\ \(([A-Z0-9_]+)\),\ value\ ([0-2]) ]]; then
      handle_key_event "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    elif [[ $line =~ type\ 3\ \(EV_ABS\),\ code\ [0-9]+\ \(([A-Z0-9_]+)\),\ value\ (-?[0-9]+) ]]; then
      handle_axis_event "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    fi
  done
}

main
