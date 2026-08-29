#!/usr/bin/env bash
set -euo pipefail

SIMULATOR_ID=""
TIMEOUT_SECONDS=120

while [[ $# -gt 0 ]]; do
  case "$1" in
    --simulator-id)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --simulator-id requires a UDID" >&2
        exit 2
      fi
      SIMULATOR_ID="$2"
      shift
      ;;
    --timeout-seconds)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "error: --timeout-seconds requires a positive integer" >&2
        exit 2
      fi
      TIMEOUT_SECONDS="$2"
      shift
      ;;
    *)
      echo "error: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
  shift
done

if [[ -z "$SIMULATOR_ID" ]]; then
  echo "error: --simulator-id is required" >&2
  exit 2
fi
if [[ ! "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --timeout-seconds must be a positive integer" >&2
  exit 2
fi

bootstatus_pid=""
cleanup() {
  local exit_code=$?
  if [[ -n "$bootstatus_pid" ]] && kill -0 "$bootstatus_pid" >/dev/null 2>&1; then
    kill -TERM "$bootstatus_pid" >/dev/null 2>&1 || true
    wait "$bootstatus_pid" >/dev/null 2>&1 || true
  fi
  return "$exit_code"
}
trap cleanup EXIT INT TERM HUP

xcrun simctl bootstatus "$SIMULATOR_ID" -b &
bootstatus_pid=$!
deadline=$((SECONDS + TIMEOUT_SECONDS))

while kill -0 "$bootstatus_pid" >/dev/null 2>&1; do
  if [[ "$SECONDS" -ge "$deadline" ]]; then
    echo "error: simulator $SIMULATOR_ID did not become ready within ${TIMEOUT_SECONDS}s" >&2
    kill -TERM "$bootstatus_pid" >/dev/null 2>&1 || true
    wait "$bootstatus_pid" >/dev/null 2>&1 || true
    bootstatus_pid=""
    exit 70
  fi
  sleep 0.2
done

if wait "$bootstatus_pid"; then
  bootstatus_pid=""
  exit 0
else
  boot_status=$?
  bootstatus_pid=""
  exit "$boot_status"
fi
