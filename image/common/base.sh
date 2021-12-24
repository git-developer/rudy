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
#   get_id_map()
#     Description:     Returns mappings between Bus-ID and Device-ID.
#     Arguments:       none
#     Expected output: A newline-separated list of mappings.
#                      Each mapping has the format busid=<bus-id>#usbid=<device-id>#
#                      Example: `busid=1-1.1#usbid=1111:1111#\nbusid=2-2.2#usbid=2222:2222#`
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

get_bus_ids_from_device_ids() {
  info "Detecting bus ids from device ids ${USBIP_DEVICE_IDS}"
  id_map="$(get_id_map)"
  echo "${USBIP_DEVICE_IDS}" | tr ',' '\n' | while read device_id; do
    bus_id="$(echo "${id_map}" | sed -nE "s/busid=([^#].+)#usbid=${device_id}#/\1/p")"
    if [ -n "${bus_id}" ]; then
      echo "${bus_id}"
    else
      error config "No bus id found for device id '${device_id}'"
      return 3
    fi
  done
}

find_bus_ids() {
  set -eu
  local bus_ids

  if [ -z "${USBIP_DEVICE_IDS-}" ] && [ -z "${USBIP_BUS_IDS-}" ]; then
    error config "One of the environment variables [USBIP_BUS_IDS, USBIP_DEVICE_IDS] must be set."
    return 2
  fi

  if [ -n "${USBIP_DEVICE_IDS-}" ]; then
    bus_ids="$(get_bus_ids_from_device_ids)"
    info "Detected bus ids: $(echo "${bus_ids}" | xargs)"
  fi
  if [ -n "${USBIP_BUS_IDS-}" ]; then
    bus_ids="$(printf "${bus_ids:+${bus_ids}\n}$(echo "${USBIP_BUS_IDS}" | tr ',' '\n')" | sort | uniq)"
  fi

  if [ -n "${bus_ids}" ]; then
    info "Found bus ids: $(echo "${bus_ids}" | xargs)"
  else
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
