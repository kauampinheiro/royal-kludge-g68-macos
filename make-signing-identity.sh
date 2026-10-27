#!/bin/bash
#
# Cria, uma única vez, a identidade local com que o RK G68.app é assinado.
#
# Por que isso existe: o macOS só deixa abrir uma collection HID de um
# dispositivo que se declara teclado para quem tem Monitoramento de Entrada, e
# amarra essa autorização à identidade da assinatura do app. Com assinatura
# ad-hoc não há identidade — só o hash do bundle, que muda a cada alteração de
# código. Resultado: a permissão dada ao build anterior para de valer e o app
# volta a dizer que "o macOS negou o acesso ao dispositivo HID", mesmo com a
# caixa aparecendo marcada em Ajustes. Com um certificado próprio o vínculo é o
# certificado, que não muda, e a autorização vale para sempre.
#
# É um certificado autoassinado, confiado só no seu chaveiro de login: não
# serve para distribuir o app, só para o macOS reconhecer que todos os builds
# saem da mesma origem.
#
set -euo pipefail

NAME="${1:-RK G68 Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -qF "$NAME"; then
    echo "✔ a identidade \"$NAME\" já existe — nada a fazer."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF

echo "▸ gerando o certificado…"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

openssl pkcs12 -export -out "$WORK/id.p12" -inkey "$WORK/key.pem" \
    -in "$WORK/cert.pem" -passout pass:rkg68 -name "$NAME" 2>/dev/null

echo "▸ importando no chaveiro de login…"
# -A libera o uso da chave sem diálogo a cada assinatura.
security import "$WORK/id.p12" -k "$KEYCHAIN" -P rkg68 -T /usr/bin/codesign -A >/dev/null

echo "▸ marcando como confiável para assinatura de código…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo
security find-identity -v -p codesigning | grep -F "$NAME"
echo
echo "✔ pronto. Rode ./build-app.sh — ele passa a assinar com essa identidade."
echo "  Para remover: security delete-identity -c \"$NAME\" \"$KEYCHAIN\""
