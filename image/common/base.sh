#!/bin/sh
set -eu
[ -z "${RUDY_TRACE-}" ] || set -x

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
#   convert_device_ids_to_bus_ids()
#     Description:     Converts Device-IDs into Bus-IDs
#     Arguments:       A comma-separated list of Device-IDs, e.g. `0000:0000,1111:1111`
#     Expected output: A newline-separated list of Bus-IDs, e.g. `1-1.1\n2-2.2`
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

info() {
  log "INFO" "${@}"
}

warn() {
  log "WARNING" "${@}"
}

error() {
  local category="${1}" && shift
  log "ERROR [${category}]" "${@}"
  ! type on_error >/dev/null || on_error "${category}" "${@}"
}

info_about() {
  # jumping through hoops to fail on error in a POSIX shell:
  set -eu            # shell options from above are not set because we are in a subshell and options do not get inher>
  local output       # return code of subcommand would get lost when 'local' would be declared and assigned in one st>
  output="$("${@}")"
  [ -z "${output}" ] || info "${output}"
  echo "${output}"
}

find_bus_ids() {
  local bus_ids
  if [ -n "${USBIP_BUS_IDS-}" ]; then
    bus_ids="${USBIP_BUS_IDS}"
    [ -z "${USBIP_DEVICE_IDS-}" ] || info "Ignoring USBIP_DEVICE_IDS for USBIP_BUS_IDS"
  elif [ -n "${USBIP_DEVICE_IDS-}" ]; then
    info "Detecting bus ids from device ids ${USBIP_DEVICE_IDS}"
    local device_ids
    device_ids="$(echo "${USBIP_DEVICE_IDS}" | tr ',' '|')"
    bus_ids="$(convert_device_ids_to_bus_ids "${device_ids}")"
    [ -n "${bus_ids}" ] || error server "No bus ids found for device ids ${USBIP_DEVICE_IDS}"
  else
    error config "One of [USBIP_BUS_IDS, USBIP_DEVICE_IDS] must be set as environment variable."
  fi
  if [ -z "${bus_ids-}" ]; then
    error config "No bus ids found."
    return 2
  fi

  echo "${bus_ids}"
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
  mkdir -p "${run_dir}"
  echo "$$">"${pid_file}"
  start
  wait $(xargs -a "${daemon_file}")
  info "Shutdown."
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
