#!/bin/bash
set -euo pipefail

VAULT_NAME="$1"
SECRET_NAME="lnu-db-password"
DB_PASS=""

# Retry while Azure identity permissions become available.
for attempt in $(seq 1 60); do
    echo "Key Vault access attempt $attempt/60"

    if TOKEN=$(curl --noproxy "*" -fsS \
        -H "Metadata: true" \
        "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net" \
        | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])'); then

        if DB_PASS=$(curl -fsS \
            -H "Authorization: Bearer $TOKEN" \
            "https://${VAULT_NAME}.vault.azure.net/secrets/${SECRET_NAME}?api-version=7.4" \
            | python3 -c 'import sys,json; print(json.load(sys.stdin)["value"])'); then

            # Use a strong alphanumeric password for safe SQL setup.
            if [[ "$DB_PASS" =~ ^[A-Za-z0-9]{24,64}$ ]]; then
                break
            fi
        fi
    fi

    DB_PASS=""
    sleep 10
done

if [ -z "$DB_PASS" ]; then
    echo "ERROR: Could not retrieve a valid database password"
    exit 1
fi

echo "Key Vault secret retrieved successfully"

# Create the database and database user.
mysql <<SQL
CREATE DATABASE IF NOT EXISTS lnunotes;
CREATE USER IF NOT EXISTS 'lnu'@'10.0.%'
IDENTIFIED BY '${DB_PASS}';
ALTER USER 'lnu'@'10.0.%'
IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON lnunotes.* TO 'lnu'@'10.0.%';
FLUSH PRIVILEGES;
SQL

unset DB_PASS TOKEN

echo "MariaDB initialization completed successfully"
