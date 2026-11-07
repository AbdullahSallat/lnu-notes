
#!/bin/bash
set -euo pipefail

VAULT_NAME="$1"
DB_HOST="$2"
STORAGE_ACCOUNT="$3"
SECRET_NAME="lnu-db-password"

echo "Starting Azure web server installation"

# 1. Download application from GitHub
git clone https://github.com/AbdullahSallat/lnu-notes.git /opt/lnu-notes

# 2. Install Python dependencies
python3 -m venv /opt/lnu-notes/.venv

/opt/lnu-notes/.venv/bin/pip install \
  -r /opt/lnu-notes/requirements-azure.txt

# 3. Retrieve database password from Azure Key Vault
DB_PASS=""

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

            if [[ "$DB_PASS" =~ ^[A-Za-z0-9]{24,64}$ ]]; then
                break
            fi
        fi
    fi

    DB_PASS=""
    sleep 10
done

if [ -z "$DB_PASS" ]; then
    echo "ERROR: Could not retrieve database password"
    exit 1
fi

# 4. Create application configuration
umask 077

cat > /etc/lnu-notes.env <<EOF
DB_HOST=${DB_HOST}
DB_PORT=3306
DB_USER=lnu
DB_PASS=${DB_PASS}
DB_NAME=lnunotes
AZURE_STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
AZURE_BLOB_CONTAINER=images
AZURE_REGION=austriaeast
EOF

chmod 600 /etc/lnu-notes.env
unset DB_PASS TOKEN

# 5. Install and start the application service
install -m 644 \
  /opt/lnu-notes/deploy/lnu-notes-azure.service \
  /etc/systemd/system/lnu-notes.service

systemctl daemon-reload
systemctl enable --now lnu-notes

echo "Azure web server setup completed"
