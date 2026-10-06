#!/bin/bash
# Создаёт самоподписанный сертификат «Notch Dev» в связке ключей.
#
# Зачем: без него build-app.sh подписывает ad-hoc, а такая подпись меняется
# при каждой сборке. Строка Notch в «Универсальном доступе» остаётся
# включённой, но система считает её чужой — кнопки молча не работают.
# С постоянным сертификатом разрешение переживает пересборку.
set -euo pipefail

if security find-identity -v -p codesigning | grep -q "Notch Dev"; then
  echo "Сертификат «Notch Dev» уже есть."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no
[ dn ]
CN = Notch Dev
[ v3 ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "Notch Dev" -out "$TMP/cert.p12" -passout pass:notch 2>/dev/null

# -A: связка не будет спрашивать пароль при каждой подписи.
security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P notch -T /usr/bin/codesign -A

echo "Готово. Дальше: Scripts/build-app.sh, потом один раз выдай доступ."
