#!/bin/bash
#
# Monta o RK G68.app e o CLI rkg68.
#
# O projeto é um pacote SwiftPM, então o bundle do app é montado à mão —
# assim não é preciso ter o Xcode completo instalado, só as Command Line Tools.
#
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="RK G68"
BUNDLE_ID="com.kauampinheiro.rkg68"
VERSION="1.0.0"
OUT="build"
APP="$OUT/$APP_NAME.app"

echo "▸ compilando ($CONFIG)…"
swift build -c "$CONFIG" --product RKG68App
swift build -c "$CONFIG" --product rkg68

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "▸ verificando o protocolo…"
"$BIN_DIR/rkg68" selftest

echo "▸ montando ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/RKG68App" "$APP/Contents/MacOS/RKG68App"

# Os layouts e a arte da RK vão direto para Contents/Resources/rk, que é o
# primeiro lugar onde RKResources.bundled() procura.
cp -R Sources/RKCore/Resources/rk "$APP/Contents/Resources/rk"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>      <string>RKG68App</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>         <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
    <!-- Justificativa exibida caso o macOS peça autorização de dispositivo. -->
    <key>NSHumanReadableCopyright</key> <string>GPL-3.0</string>
</dict>
</plist>
PLIST

# Assinar. O que está em jogo não é só abrir o bundle: o macOS amarra a
# autorização de Monitoramento de Entrada — sem a qual o IOKit recusa abrir o
# teclado — à identidade da assinatura. Com uma identidade de verdade o vínculo
# é o certificado, que não muda; com assinatura ad-hoc o único vínculo possível
# é o cdhash do bundle, e esse muda a cada alteração de código: a permissão do
# build anterior para de valer, mesmo continuando marcada na lista de Ajustes.
#
# Criar a identidade local uma vez (ver README) evita isso de vez.
SIGN_ID="${RKG68_SIGN_IDENTITY:-RK G68 Local Signing}"

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_ID"; then
    codesign --force --sign "$SIGN_ID" --timestamp=none "$APP" >/dev/null 2>&1 \
        && echo "▸ assinado com \"$SIGN_ID\" — a autorização sobrevive aos próximos builds" \
        || { echo "▸ aviso: codesign com \"$SIGN_ID\" falhou; caindo para ad-hoc"; SIGN_ID=""; }
else
    SIGN_ID=""
fi

if [ -z "$SIGN_ID" ]; then
    codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 \
        && echo "▸ assinado (ad-hoc)" \
        || echo "▸ aviso: codesign falhou — o app pode exigir liberação manual em Privacidade e Segurança"

    # Ad-hoc: a permissão do build anterior já não vale. Zerar o registro faz o
    # app pedir de novo, em vez de negar calado com a caixa parecendo marcada.
    if tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1; then
        echo "▸ autorização de Monitoramento de Entrada zerada — autorize o app ao abrir"
    fi
fi

cp "$BIN_DIR/rkg68" "$OUT/rkg68"

# O CLI precisa da árvore da RK e o bundle do SwiftPM fica para trás na pasta de
# build. Uma cópia ao lado do binário é o segundo lugar onde RKResources procura,
# então o `build/rkg68` funciona onde está.
rm -rf "$OUT/rk"
cp -R Sources/RKCore/Resources/rk "$OUT/rk"

echo
echo "✔ pronto:"
echo "   app:  $PWD/$APP"
echo "   cli:  $PWD/$OUT/rkg68"
echo
echo "abrir o app:        open \"$APP\""
echo "instalar o app:     cp -R \"$APP\" /Applications/"
echo "instalar o cli:     sudo cp \"$OUT/rkg68\" /usr/local/bin/ \\"
echo "                    && sudo mkdir -p /usr/local/share/rkg68 \\"
echo "                    && sudo cp -R \"$OUT/rk\" /usr/local/share/rkg68/rk"
