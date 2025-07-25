#!/bin/sh
# wait-for-it.sh

# Source: https://github.com/vishnubob/wait-for-it/blob/master/wait-for-it.sh (simplified)
# Original script has more features, this is a minimal version.

TIMEOUT=${TIMEOUT:-15}
QUIET=${QUIET:-0}
HOST=$1
PORT=$2
CHECK_URL=${CHECK_URL:-} # NEW: Optional URL to check for HTTP 200
shift 2 # Shift removes HOST and PORT

wait_for_service() {
  local host="$1" port="$2" timeout="$3" check_url="$4" start_time=$(date +%s)
  local nc_cmd

  # NEW: Add DNS resolution check
  # This loop waits for the hostname to be resolvable via getent hosts
  while ! getent hosts "${host}" >/dev/null; do
    if [ $(( $(date +%s) - start_time )) -ge "${timeout}" ]; then
      echo "Error: Hostname ${host} not resolvable within ${timeout} seconds." >&2
      return 1 # Timeout on DNS resolution
    fi
    sleep 1
  done
  if [ "${QUIET}" -eq 0 ]; then
    echo "Hostname ${host} resolved."
  fi

  if type nc &>/dev/null; then
    # Use netcat for port check
    nc_cmd="nc -z ${host} ${port}"
  else
    echo "Error: 'nc' (netcat) is not available in the container. It is required for wait-for-it.sh." >&2
    exit 1
  fi

  while true; do
    # First, check if the port is open
    if eval "${nc_cmd}" 2>/dev/null; then
      # If port is open and CHECK_URL is provided, check HTTP readiness
      if [ -n "${check_url}" ]; then
        # Check if curl is available for HTTP readiness check
        if ! type curl &>/dev/null; then
          echo "Error: 'curl' is not available in the container. It is required for URL check." >&2
          exit 1
        fi
        # Use curl to check for HTTP 200 OK
        if curl -s -o /dev/null -w "%{http_code}" "${check_url}" | grep -q "200"; then
          return 0 # Success: HTTP 200
        fi
      else
        return 0 # Success: Port is open, no URL to check
      fi
    fi

    # If timeout is reached, return failure
    if [ $(( $(date +%s) - start_time )) -ge "${timeout}" ]; then
      return 1 # Timeout
    fi
    sleep 1
  done
  return 0 # Should not be reached
}

# The original arguments passed to the script start after HOST and PORT
ORIGINAL_COMMAND="$@"

# Call the wait_for_service function
if ! wait_for_service "${HOST}" "${PORT}" "${TIMEOUT}" "${CHECK_URL}"; then
  echo "Error: Host ${HOST}:${PORT} or URL ${CHECK_URL} not available within ${TIMEOUT} seconds."
  exit 1
fi

# If waiting was successful, print a message (if not quiet)
if [ "${QUIET}" -eq 0 ]; then
  echo "Host ${HOST}:${PORT} is available."
  if [ -n "${CHECK_URL}" ]; then
    echo "URL ${CHECK_URL} is returning HTTP 200 OK."
  fi
fi

# Execute the original command passed to wait-for-it.sh
exec "${ORIGINAL_COMMAND}"
