#!/bin/sh
set -eu

log_file=/dev/stderr

log() {
  echo >"${log_file}" "${@}"
}

error() {
  log "Error: ${@}"
}

detect_bus_ids() {
  local from_device_ids="${1}"

  local bus_ids
  if [ -n "${USBIP_BUS_IDS-}" ]; then
    bus_ids="${USBIP_BUS_IDS}"
    [ -z "${USBIP_DEVICE_IDS-}" ] || log "Ignoring USBIP_DEVICE_IDS for USBIP_BUS_IDS"
  elif [ -n "${USBIP_DEVICE_IDS-}" ]; then
    local device_ids
    device_ids="$(echo "${USBIP_DEVICE_IDS}" | tr ',' '|')"
    bus_ids="$("${from_device_ids}" "${device_ids}")"
    [ -n "${bus_ids}" ] || error "No bus ids found for device ids ${USBIP_DEVICE_IDS}"
  else
    error "One of [USBIP_BUS_IDS, USBIP_DEVICE_IDS] must be set as environment variable."
  fi
  if [ -z "${bus_ids-}" ]; then
    error "No bus ids found."
    return 2
  fi

  echo "${bus_ids}"
}

reload() {
  log "Reloading..."
  stop
  load
}

load() {
  start
  tail -f /dev/null &
  wait "${!}"
}

main() {
  trap reload HUP
  trap stop TERM INT
  load
}
