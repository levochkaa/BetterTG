#!/usr/bin/env bash

resolve_connected_iphone_id() {
  local requested_id="${1:-}"
  local devices_json
  local matches_json
  local match_count

  if ! devices_json="$(xcrun devicectl list devices --quiet --json-output -)"; then
    echo "error: failed to discover devices through devicectl" >&2
    return 1
  fi

  matches_json="$(
    jq -c --arg requested "$requested_id" '
      [
        .result.devices[]?
        | {
            identifier: .identifier,
            name: (.properties.state.name // .deviceProperties.name // "iPhone"),
            reality: (.properties.hardware.reality // .hardwareProperties.reality),
            platform: (.properties.hardware.platform // .hardwareProperties.platform),
            deviceType: (.properties.hardware.deviceType // .hardwareProperties.deviceType),
            bootState: (.properties.state.bootState // .deviceProperties.bootState),
            pairingState: (.properties.connection.pairingState // .connectionProperties.pairingState),
            udid: (.properties.hardware.udid // .hardwareProperties.udid)
          }
        | select(
            .reality == "physical"
            and .platform == "iOS"
            and .deviceType == "iPhone"
            and .bootState == "booted"
            and .pairingState == "paired"
            and ((.udid | length) > 0)
          )
        | select(
            $requested == ""
            or .identifier == $requested
            or .udid == $requested
          )
      ]
    ' <<< "$devices_json"
  )"
  match_count="$(jq -r 'length' <<< "$matches_json")"

  if [[ "$match_count" == "0" ]]; then
    if [[ -n "$requested_id" ]]; then
      echo "error: physical iPhone '$requested_id' is not available; connect, unlock, trust this Mac, and enable Developer Mode" >&2
    else
      echo "error: no available paired physical iPhone; connect, unlock, trust this Mac, and enable Developer Mode" >&2
    fi
    return 1
  fi

  if [[ "$match_count" -gt 1 ]]; then
    local choices
    choices="$(jq -r 'map("\(.name) (\(.udid))") | join(", ")' <<< "$matches_json")"
    echo "error: multiple physical iPhones are available: $choices; pass --device-id ID" >&2
    return 1
  fi

  jq -r '.[0].udid' <<< "$matches_json"
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

  if [[ "$(jq -r '.result.deviceProperties.developerModeStatus // ""' <<< "$details_json")" != "enabled" ]]; then
    echo "error: Developer Mode is not enabled on the physical iPhone" >&2
    return 1
  fi

  if [[ "$(jq -r '.result.deviceProperties.ddiServicesAvailable == true' <<< "$details_json")" != "true" ]] ||
    [[ "$(jq -r '.result.connectionProperties.tunnelState // ""' <<< "$details_json")" != "connected" ]]; then
    echo "error: development services are unavailable; unlock the physical iPhone and keep its screen on" >&2
    return 1
  fi
}
