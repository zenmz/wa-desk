#!/bin/sh
# Buat sertifikat self-signed "WA Desk Signing" sekali, lalu build.sh memakainya otomatis.
# Dengan identitas yang stabil, macOS mengenali WA Desk sebagai app yang sama di setiap build:
# dialog Keychain "WebCrypto Master Key" dan izin kamera/mic/notifikasi tidak ditanya ulang tiap upgrade.
set -eu
NAME="${1:-WA Desk Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  echo "Identitas \"$NAME\" sudah ada."
  exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
subjectKeyIdentifier = hash
CNF
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12" \
  -passout pass:wadesk -name "$NAME" >/dev/null 2>&1
# Impor kunci + sertifikat ke keychain login; codesign boleh memakai kuncinya.
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P wadesk -T /usr/bin/codesign -T /usr/bin/security >/dev/null
# Percayai sertifikat untuk code signing (macOS akan minta password login sekali).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
echo "Selesai. Verifikasi:"
security find-identity -v -p codesigning | grep "$NAME" || { echo "Identitas belum terlihat; buka Keychain Access dan cek trust sertifikat."; exit 1; }
echo "Sekarang: ./build.sh (atau brew reinstall wa-desk). Saat codesign pertama kali memakai kunci ini, macOS mungkin minta izin sekali → Always Allow."
