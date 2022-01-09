#!/bin/sh
set -eu
[ -z "${RUDY_TRACE-}" ] || set -x

USBIP_DEVICE_ID_SEPARATOR="${USBIP_DEVICE_ID_SEPARATOR:-,}"
USBIP_SID_REGEX="${USBIP_SID_REGEX:-false}"
rc_missing_arg=11

#
# Common base script providing a skeleton and utility functions for a service.
# A service is considered complete when it sources this script and additionally
# provides the following functions.
#
# Required:
#   start()
#     Description:     Starts the service.
#     Arguments:       none
#     Expected output: none
#   stop()
#     Description:     Stops the service.
#     Arguments:       none
#     Expected output: none
#   get_id_map()
#     Description:     Returns mappings between Bus-ID and Device-ID.
#     Arguments:       args[1..n] of find_bus_ids()
#     Expected output: A newline-separated list of mappings.
#                      Each mapping has the format busid=<bus-id>#usbid=<device-id>#
#                      Example: `busid=1-1.1#usbid=1111:1111#\nbusid=2-2.2#usbid=2222:2222#`
#   find_serial()
#     Description:     Finds the serial of a device matching a given request.
#     Arguments:       Bus-ID of the device, serial query string, args[1..n] of find_bus_ids()
#     Expected output: If the serial of the device with the given bus id matches the query:
#                      the serial and return code 0; no output and non-success return code otherwise.
#
# Optional:
#   on_error()
#     Description:     Handles an error.
#     Arguments:       args[0]: category, args[1..n]: error messages
#     Expected output: none
#

run_dir=/var/run/rudy
pid_file="${run_dir}/main.pid"
daemon_file="${run_dir}/daemons.pid"
log_file=/dev/stderr

log()  {
  local level="${1}"
  shift
  printf '%s\n' "${@}" | while IFS=$'\n' read line; do
    printf "%s: %s\n" "${level}" "${line}" >"${log_file}"
  done
}

debug() {
  [ -z "${RUDY_DEBUG-}" ] || log "DEBUG" "${@}"
}

info() {
  log "INFO " "${@}"
}

warn() {
  log "WARN " "${@}"
}

cancel() {
  local rc="${1}" category="${2}" && shift 2
  log "ERROR [${category}]" "${@}"
  ! type on_error >/dev/null || on_error "${category}" "${@}"
  return "${rc}"
}

info_about() {
  # jumping through hoops to fail on error in a POSIX shell:
  set -eu            # shell options from above are not set because we are in a subshell and options do not get inherited
  local output       # return code of subcommand would get lost when 'local' would be declared and assigned in one step
  output="$("${@}")"
  [ -z "${output}" ] || info "${output}"
  echo "${output}"
}

find_local_serial() {
  set -eu
  local bus_id="${1}" serial_query="${2}" file serial comparison match
  file="/sys/bus/usb/devices/${bus_id}/serial"
  if [ -r "${file}" ]; then
    serial="$(cat "${file}")"
    [ "${USBIP_SID_REGEX}" = 'true' ] && comparison='-e' || comparison='-F'
    if match="$(echo "${serial}" | grep "${comparison}" "${serial_query}")"; then
      echo "${match}"
      debug "Serial '${serial}' of local device ${bus_id} matches '${serial_query}'"
      return 0
    else
      debug "Serial '${serial}' of local device ${bus_id} doesn't match '${serial_query}'"
    fi
  else
    info "Local device ${bus_id} has no serial."
  fi
  return 1
}

resolve_bus_ids_for_device() {
  set -eu
  local devices="${1}" id="${2}" device_id serial_query serial message
  shift 2
  device_id="$(echo "${id}" | cut -c 1-9)"
  serial_query="$(echo "${id}" | cut -c 11-)"

  debug "Resolving bus id for device id '${id}'"
  echo "${devices}" \
  | sed -nE "s/^busid=([^#]+)#usbid=${device_id}#$/\1/p" \
  | while read bus_id; do
    message="Resolved bus id ${bus_id} for device id '${id}'"
    if [ -z "${serial_query}" ]; then
      echo "${bus_id}"
      info "${message}"
    elif serial="$(find_serial "${bus_id}" "${serial_query}" "${@}")"; then
      echo "${bus_id}"
      info "${message} matching serial '${serial}'"
      [ "${USBIP_SID_REGEX}" = 'true' ] || return 0
    fi
  done
}

resolve_bus_ids() {
  set -eu
  local fail_on_missing="${1:-true}" devices
  [ "${#}" -lt 1 ] || shift
  devices="$(get_id_map "${@}")"
  echo "${USBIP_DEVICE_IDS}" \
  | tr "${USBIP_DEVICE_ID_SEPARATOR}" '\n' \
  | while read id; do
    bus_ids="$(resolve_bus_ids_for_device "${devices}" "${id}" "${@}")"
    if [ -n "${bus_ids}" ]; then
      echo "${bus_ids}"
    elif [ "${fail_on_missing}" = 'true' ]; then
      cancel "${rc_missing_arg}" server "No bus id found for device id '${id}'"
    fi
  done
}

find_bus_ids() {
  set -eu
  local bus_ids
  debug "Detecting bus ids"

  [ -n "${USBIP_DEVICE_IDS-}" ] || \
  [ -n "${USBIP_BUS_IDS-}"    ] || \
  cancel "${rc_missing_arg}" config \
    "One of the environment variables [USBIP_BUS_IDS, USBIP_DEVICE_IDS] must be set."

  if [ -n "${USBIP_DEVICE_IDS-}" ]; then
    debug "Resolving bus ids for device ids '${USBIP_DEVICE_IDS}'"
    bus_ids="$(resolve_bus_ids "${@}")"
  fi
  if [ -n "${USBIP_BUS_IDS-}" ]; then
    bus_ids="$(printf "${bus_ids:+${bus_ids}\n}$(echo "${USBIP_BUS_IDS}" | tr ',' '\n')")"
  fi

  if [ -n "${bus_ids}" ]; then
    bus_ids="$(echo "${bus_ids}" | sort | uniq)"
    debug "Found bus ids: $(echo "${bus_ids}" | xargs)"
    echo "${bus_ids}"
  fi
}

reload() {
  info "Reloading..."
  stop
  load
}

shutdown() {
  info "Shutting down..."
  stop
}

load() {
  local rc
  mkdir -p "${run_dir}"
  echo "$$">"${pid_file}"
  if start; then
    wait $(xargs -a "${daemon_file}")
    info "Shutdown."
  else
    rc="$?"
    shutdown
    return "${rc}"
  fi
}

on_trap() {
  rc="$?"
  if [ ! "${rc}" -gt 0 ]; then
    warn "Trapped with unexpected signal ${rc}"
    return "${rc}"
  fi
  local signal_value="$((${rc} - 128))"
  local signal_name="$(kill -l "${signal_value}")"
  info "Caught signal ${signal_name}"
  case "${signal_name}" in
    HUP|SIGHUP)   reload   ;;
    INT|SIGINT)   shutdown ;;
    TERM|SIGTERM) shutdown ;;
  esac
}

main() {
  trap on_trap HUP TERM INT
  load
}
