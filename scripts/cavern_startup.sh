#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.

echo "--- Debugging Cavern Startup Script ---"

# Test if log4j.properties is readable at expected path
echo "Checking /config/log4j.properties permissions and content:"
ls -l /config/log4j.properties || echo "log4j.properties not found or no permissions."
echo "--- Start of /config/log4j.properties content ---"
cat /config/log4j.properties || echo "Failed to cat /config/log4j.properties"
echo "--- End of /config/log4j.properties content ---"

# Test content of resource-caps.properties
echo '--- resource-caps.properties content (as seen by container): ---'
ls -l /config/reg/resource-caps.properties || echo "resource-caps.properties not found or no permissions."
cat /config/reg/resource-caps.properties || echo "Failed to cat /config/reg/resource-caps.properties"
echo '--- End of resource-caps.properties content ---'

# Original startup script logic follows:
# REMOVED: Function to wait for a host:port to be open using /dev/tcp (pure bash)
# wait_for_tcp_service() {
#   local host="$1"
#   local port="$2"
#   local service_name="$3"
#   local timeout=60 # seconds
#   local start_time=$(date +%s)
#
#   echo "Waiting for $service_name on $host:$port (using /dev/tcp)..."
#   while ! timeout 1 bash -c "cat < /dev/null > /dev/tcp/$host/$port"; do
#     current_time=$(date +%s)
#     elapsed=$((current_time - start_time))
#     if (( elapsed >= timeout )); then
#       echo "Error: $service_name on $host:$port did not become available within $timeout seconds."
#       exit 1 # Exit the script with an error if timeout reached
#     fi
#     echo "$service_name not yet available. Retrying..."
#     sleep 2
#   done
#   echo "$service_name is available."
# }

# --- REMOVED: Use the new TCP wait function for your services ---

# REMOVED: Wait for PostgreSQL
# wait_for_tcp_service postgres_cavern 5432 "PostgreSQL Cavern"

# REMOVED: Wait for PosixMapper Proxy HTTP port
# wait_for_tcp_service posixmapper-proxy 8080 "PosixMapper Proxy HTTP"

# REMOVED: Loop until posixmapper-proxy capabilities endpoint returns 200 OK (HTTP)
# echo "Waiting for posixmapper proxy capabilities endpoint (HTTP 200)..."
# until curl -s --fail http://posixmapper-proxy:8080/posix-mapper/capabilities > /dev/null; do
#   echo 'PosixMapper proxy capabilities not yet responsive. Retrying...';
#   sleep 2;
# done;
# echo 'PosixMapper capabilities endpoint is responsive via Proxy HTTP.';

# Start Cavern's Tomcat application
echo "Starting Cavern Tomcat application..."
exec /usr/bin/cadc-tomcat-start
