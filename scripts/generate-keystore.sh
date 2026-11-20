#!/usr/bin/env bash
set -euo pipefail

KEYSTORE_FILE="keystore.p12"
ALIAS="fdroid"

if [ -f "$KEYSTORE_FILE" ]; then
  echo "Keystore $KEYSTORE_FILE already exists."
  exit 0
fi

echo "Generating new keystore ($KEYSTORE_FILE)..."
keytool -genkeypair \
  -keystore "$KEYSTORE_FILE" \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -storetype PKCS12 \
  -dname "CN=FDroidRepo, OU=Personal, O=Tau2C, C=PL"

echo ""
echo "Keystore created: $KEYSTORE_FILE"
echo "Encode this file to base64 for GitHub Secrets:"
echo "base64 -w 0 $KEYSTORE_FILE"
