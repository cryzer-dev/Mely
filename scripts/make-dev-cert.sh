#!/bin/zsh
# Creates a self-signed code-signing identity "Mely Dev" in the login keychain, once.
# A stable signature keeps macOS privacy grants (Full Disk Access, Accessibility,
# Calendars…) across rebuilds; ad-hoc signatures change on every build and lose them.
set -euo pipefail
NAME="Mely Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "“$NAME” already exists in the login keychain."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
PASS=$(uuidgen)
# -legacy: macOS's keychain only reads the older PKCS#12 encryption.
P12_FLAGS=()
/usr/bin/openssl version | grep -q '^OpenSSL 3' && P12_FLAGS=(-legacy)
/usr/bin/openssl pkcs12 -export "${P12_FLAGS[@]}" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/id.p12" -passout "pass:$PASS"

security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
echo "Created “$NAME”. Sign with: codesign -s \"$NAME\" …"
