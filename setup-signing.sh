#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="MaCopy Dev"

if security find-identity -v -p codesigning | grep -q "$IDENTITY_NAME"; then
    echo "→ identity '$IDENTITY_NAME' уже есть в keychain"
    exit 0
fi

echo "→ создаю self-signed cert '$IDENTITY_NAME'"
TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

cat > "$TMPDIR/cert.conf" <<EOF
[req]
distinguished_name = req_dn
x509_extensions = v3_req
prompt = no

[req_dn]
CN = $IDENTITY_NAME

[v3_req]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = critical, CA:FALSE
EOF

openssl req -x509 -newkey rsa:2048 -sha256 \
    -keyout "$TMPDIR/key.pem" \
    -out "$TMPDIR/cert.pem" \
    -days 3650 -nodes -config "$TMPDIR/cert.conf" 2>/dev/null

P12_PASS="temp"
openssl pkcs12 -export \
    -inkey "$TMPDIR/key.pem" \
    -in "$TMPDIR/cert.pem" \
    -out "$TMPDIR/identity.p12" \
    -passout pass:"$P12_PASS" \
    -name "$IDENTITY_NAME" \
    -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES

security import "$TMPDIR/identity.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$P12_PASS" \
    -T /usr/bin/codesign \
    -A

security set-key-partition-list \
    -S "apple-tool:,apple:,codesign:" \
    -s \
    -k "" \
    "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 || true

echo "→ добавляю trust для code signing (может спросить пароль)"
security add-trusted-cert -r trustRoot -p codeSign \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    "$TMPDIR/cert.pem"

echo "→ готово. Далее build-app.sh подпишет приложение этим сертификатом."
echo "→ Accessibility permission нужно будет выдать один раз - оно запомнится по сертификату."
