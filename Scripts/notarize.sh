#!/bin/bash
# Подписывает собранный Notch.app сертификатом Developer ID, отправляет на
# нотаризацию в Apple, пришивает ответ (staple) и собирает DMG.
#
# Зачем: без нотаризации Gatekeeper на чужом Маке говорит «приложение
# повреждено», и человеку приходится снимать карантин через xattr. С ней
# приложение открывается двойным щелчком, как любое другое.
#
# Что нужно один раз:
#   1. Сертификат «Developer ID Application» в связке ключей (Apple
#      Developer Program, Xcode › Settings › Accounts › Manage Certificates).
#   2. Профиль notarytool в связке ключей:
#        xcrun notarytool store-credentials notch-notary \
#          --apple-id <почта> --team-id <TEAMID> --password <пароль приложения>
#      Пароль — «app-specific password» с appleid.apple.com, не основной.
#
#   Scripts/notarize.sh              — взять build/Notch.app
#   NOTARY_PROFILE=other Scripts/notarize.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Notch.app"
PROFILE="${NOTARY_PROFILE:-notch-notary}"
VERSION="$(tr -d ' \t\r\n' < "$ROOT/VERSION")"
DIST="$ROOT/dist"
DMG="$DIST/Notch-$VERSION.dmg"

IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
if [ -z "$IDENTITY" ]; then
  echo "Нет сертификата «Developer ID Application» в связке ключей — нотаризовать нечем." >&2
  exit 2
fi
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "Нет профиля notarytool «$PROFILE». Создать: xcrun notarytool store-credentials $PROFILE ..." >&2
  exit 2
fi
[ -d "$APP" ] || { echo "Нет $APP — сначала Scripts/build-app.sh release" >&2; exit 1; }

# Изнутри наружу: сначала вложенный framework, потом сам бандл. Hardened
# Runtime (--options runtime) и метка времени обязательны для нотаризации.
codesign --force --timestamp --options runtime --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign --force --timestamp --options runtime --sign "$IDENTITY" \
  --entitlements "$ROOT/Scripts/Notch.entitlements" \
  --identifier com.dany.notch "$APP"
codesign --verify --deep --strict "$APP"
echo "Подписано: $IDENTITY"

mkdir -p "$DIST"
ZIP="$(mktemp -d)/Notch.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "Отправляю на нотаризацию — обычно пара минут…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

# DMG с ярлыком «Программы» рядом: перетащил — установил.
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Notch $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

spctl --assess --type execute --verbose "$APP"
echo
echo "Готово: $DMG — открывается на любом Маке без xattr."
