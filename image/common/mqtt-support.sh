#!/bin/sh
set -eu
. "$(dirname "${0}")/base.sh"

MQTT_PUBLISH_OPTIONS="${MQTT_PUBLISH_OPTIONS:-${MQTT_OPTIONS-}}"
MQTT_SUBSCRIBE_OPTIONS="${MQTT_SUBSCRIBE_OPTIONS:-${MQTT_OPTIONS-}}"

mqtt_publish() {
  local subtopic="${1-}" message="${2-}"
  [ -n "${MQTT_PUBLISH_TO_TOPIC-}" ] || return 0
  [ -n "${subtopic}" ] || { error internal "Missing subtopic"; return 1; }

  local topic="${MQTT_PUBLISH_TO_TOPIC}/${subtopic}"
  { printf "%s\0" "-t" "${topic}"
    printf "%s\0" "-m" "${message}"
    printf "%s" "${MQTT_PUBLISH_OPTIONS}" | xargs printf "%s\0"
  } | xargs -0 mosquitto_pub
}

mqtt_subscribe() {
  [ -n "${MQTT_RELOAD_ON_TOPIC-}" ] || return 0
  info "Enabling reload hook on MQTT topic '${MQTT_RELOAD_ON_TOPIC}'"
  # use local variable instead of piping directly to xargs
  # to fail on config errors without running mosquitto_sub
  # (due to missing shell option 'pipefail' in POSIX sh)
  local args
  args="$(printf "%s\n" -t "${MQTT_RELOAD_ON_TOPIC}" "${MQTT_SUBSCRIBE_OPTIONS}")"
  printf %s "${args}" \
  | xargs printf "%s\0" \
  | xargs -0 mosquitto_sub -F %t \
  | while read -r output; do
    info "A message arrived on the MQTT reload topic '${output}'"
    env reload
  done &
  echo "${!}" >>"${daemon_file}"
}

on_error() {
  local category="${1}" && shift
  mqtt_publish "error/${category}" "${*}"
}
