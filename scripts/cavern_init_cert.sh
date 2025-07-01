#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status, unless specifically handled.

echo "DEBUG: cavern_init_cert.sh started."

CACERTS_PATH=$(dirname $(dirname $(readlink -f $(which java))))/lib/security/cacerts
CACERTS_PASSWORD=changeit

echo "DEBUG: CACERTS_PATH determined as $CACERTS_PATH (Note: -cacerts flag will be used where possible)."
echo 'Attempting to import haproxy.crt into Java cacerts...'

echo "DEBUG: Checking if certificate alias 'haproxy_cert' already exists by parsing keytool -list output."
if keytool -list -cacerts -storepass "$CACERTS_PASSWORD" -alias haproxy_cert 2>&1 | grep -q "Alias <haproxy_cert> does not exist"; then
    echo 'DEBUG: Certificate alias "haproxy_cert" not found, proceeding with import. Full keytool -import output follows:'
    # Use haproxy.crt directly for import, as it contains only the certificate
    keytool -import -trustcacerts -cacerts -storepass "$CACERTS_PASSWORD" -alias haproxy_cert -file /tmp/haproxy/haproxy.crt -noprompt # <--- CRITICAL CHANGE: -file /tmp/haproxy/haproxy.crt
    IMPORT_STATUS=$?
    if [ $IMPORT_STATUS -eq 0 ]; then
        echo 'DEBUG: Certificate import complete successfully.'
    else
        echo "ERROR: keytool import failed with exit status $IMPORT_STATUS."
        echo "DEBUG: Content of /tmp/haproxy/haproxy.crt (first 20 lines):" # <--- Updated to .crt
        head -n 20 /tmp/haproxy/haproxy.crt
        exit $IMPORT_STATUS # Exit with an error code if the import fails
    fi
else
    echo 'DEBUG: Certificate alias "haproxy_cert" already exists (or keytool -list did not indicate "does not exist"), skipping import.'
    echo "DEBUG: Original keytool -list output for reference:"
    keytool -list -cacerts -storepass "$CACERTS_PASSWORD" -alias haproxy_cert
fi

echo "DEBUG: Certificate initialization script finished successfully."

/usr/local/bin/cavern_startup.sh
