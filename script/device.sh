#!/usr/bin/env bash

resolve_connected_iphone_id() {
  local requested_id="${1:-}"
  local devices_json
  local matches_json
  local match_count

  if ! devices_json="$(xcrun xcdevice list --timeout 10)"; then
    echo "error: failed to discover devices through xcdevice" >&2
    return 1
  fi

  matches_json="$(
    jq -c --arg requested "$requested_id" '
      [
        .[]?
        | {
            identifier: .identifier,
            name: (.name // "iPhone"),
            modelCode: (.modelCode // ""),
            simulator: (.simulator // false),
            platform: (.platform // ""),
            available: (.available // false)
          }
        | select(
            .simulator == false
            and .platform == "com.apple.platform.iphoneos"
            and (.modelCode | startswith("iPhone"))
            and .available == true
            and ((.identifier | length) > 0)
          )
        | select(
            $requested == ""
            or .identifier == $requested
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
    choices="$(jq -r 'map("\(.name) (\(.identifier))") | join(", ")' <<< "$matches_json")"
    echo "error: multiple physical iPhones are available: $choices; pass --device-id ID" >&2
    return 1
  fi

  jq -r '.[0].identifier' <<< "$matches_json"
}
