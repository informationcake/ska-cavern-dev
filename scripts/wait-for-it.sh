#!/usr/bin/env bash
# wait-for-it.sh

# Source: https://github.com/vishnubob/wait-for-it/blob/master/wait-for-it.sh (simplified)
# Original script has more features, this is a minimal version.

TIMEOUT=${TIMEOUT:-15}
QUIET=${QUIET:-0}
HOST=$1
PORT=$2
shift 2

wait_for_port() {
  local host="$1" port="$2" timeout="$3" start_time=$(date +%s)
  local nc_cmd

  if type nc &>/dev/null; then
    # Use netcat
    nc_cmd="nc -z ${host} ${port}"
  elif type bash &>/dev/null; then
    # Use bash's /dev/tcp
    nc_cmd="bash -c 'exec 3<>/dev/tcp/${host}/${port} && exec 3<&- && exec 3>&-'"
  else
    echo "Error: Neither 'nc' nor bash's /dev/tcp are available."
    exit 1
  fi

  while ! eval "${nc_cmd}" 2>/dev/null; do
    if (( $(date +%s) - start_time >= timeout )); then
      return 1 # Timeout
    fi
    sleep 1
  done
  return 0 # Success
}

if ! wait_for_port "${HOST}" "${PORT}" "${TIMEOUT}"; then
  echo "Error: Host ${HOST} or port ${PORT} not available within ${TIMEOUT} seconds."
  exit 1
fi

if [[ ${QUIET} -eq 0 ]]; then
  echo "Host ${HOST}:${PORT} is available."
fi

exec "$@" # Execute the original command
