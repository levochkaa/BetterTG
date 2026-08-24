#!/usr/bin/env bash

resolve_connected_iphone_id() {
  local requested_id="${1:-}"
  local devices_json

  if ! devices_json="$(xcrun devicectl list devices --quiet --json-output -)"; then
    echo "error: failed to discover devices through devicectl" >&2
    return 1
  fi

  BETTERTG_DEVICES_JSON="$devices_json" python3 - "$requested_id" <<'PY'
import json
import os
import sys

requested_id = sys.argv[1]
data = json.loads(os.environ["BETTERTG_DEVICES_JSON"])
matches = []

for device in data.get("result", {}).get("devices", []):
    properties = device.get("properties", {})
    hardware = properties.get("hardware", {})
    state = properties.get("state", {})
    connection = properties.get("connection", {})
    legacy_hardware = device.get("hardwareProperties", {})
    legacy_state = device.get("deviceProperties", {})
    legacy_connection = device.get("connectionProperties", {})

    reality = hardware.get("reality", legacy_hardware.get("reality"))
    platform = hardware.get("platform", legacy_hardware.get("platform"))
    device_type = hardware.get("deviceType", legacy_hardware.get("deviceType"))
    boot_state = state.get("bootState", legacy_state.get("bootState"))
    pairing_state = connection.get("pairingState", legacy_connection.get("pairingState"))
    udid = hardware.get("udid", legacy_hardware.get("udid"))
    identifier = device.get("identifier")
    name = state.get("name", legacy_state.get("name", "iPhone"))

    if reality != "physical" or platform != "iOS" or device_type != "iPhone":
        continue
    if boot_state != "booted" or pairing_state != "paired" or not udid:
        continue
    if requested_id and requested_id not in {identifier, udid}:
        continue
    matches.append((name, udid))

if not matches:
    if requested_id:
        raise SystemExit(
            f"error: physical iPhone {requested_id!r} is not available; "
            "connect, unlock, trust this Mac, and enable Developer Mode"
        )
    raise SystemExit(
        "error: no available paired physical iPhone; "
        "connect, unlock, trust this Mac, and enable Developer Mode"
    )

if len(matches) > 1:
    choices = ", ".join(f"{name} ({udid})" for name, udid in matches)
    raise SystemExit(
        f"error: multiple physical iPhones are available: {choices}; set DEVICE_ID"
    )

print(matches[0][1])
PY
}

validate_connected_iphone() {
  local device_id="$1"
  local details_json

  if ! details_json="$(
    xcrun devicectl device info details \
      --device "$device_id" \
      --quiet \
      --json-output -
  )"; then
    echo "error: failed to connect to physical iPhone $device_id" >&2
    return 1
  fi

  BETTERTG_DEVICE_DETAILS_JSON="$details_json" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["BETTERTG_DEVICE_DETAILS_JSON"])
result = data.get("result", {})
device = result.get("deviceProperties", {})
connection = result.get("connectionProperties", {})

if device.get("developerModeStatus") != "enabled":
    raise SystemExit("error: Developer Mode is not enabled on the physical iPhone")

if device.get("ddiServicesAvailable") is not True or connection.get("tunnelState") != "connected":
    raise SystemExit(
        "error: development services are unavailable; unlock the physical iPhone "
        "and keep its screen on"
    )
PY
}
