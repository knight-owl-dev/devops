#!/usr/bin/env bash
# JSON helpers.

# Render a JSON string array from the given arguments.
#
# Examples:
#   json_array            -> []
#   json_array a          -> ["a"]
#   json_array a b        -> ["a","b"]
#
# Arguments:
#   $@ - Array elements (assumed free of characters needing JSON escaping,
#        e.g. image names)
#
# Outputs:
#   The JSON array on stdout
json_array() {
  local json="[]"
  if [[ $# -gt 0 ]]; then
    local joined
    joined="$(printf '"%s",' "$@")"
    json="[${joined%,}]"
  fi
  echo "${json}"
}
