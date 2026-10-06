#!/bin/bash
# Собирает Notch.app из SwiftPM-сборки.
#
# Бандл нужен не для красоты: без Info.plist с описаниями доступа macOS не
# покажет запрос разрешений (Календарь, Автоматизация), а без подписи TCC
# не запомнит выданное разрешение между запусками.
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Notch.app"
# Номер версии лежит в одном месте — файле VERSION в корне. Отсюда он
# попадает в Info.plist, оттуда — в настройки, и с ним же сверяется тег
# релиза. Правится он только через Scripts/release.sh, чтобы номер в
# бандле, тег и имя архива не разъехались.
VERSION="$(tr -d ' \t\r\n' < "$ROOT/VERSION")"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION: ожидалось X.Y.Z, а там «$VERSION»" >&2
  exit 1
fi

# Штамп сборки. Номер версии между правками не меняется, и по нему нельзя
# понять, ту ли сборку смотришь. Штамп меняется всегда: время сборки и
# коммит, из которого она собрана, со звёздочкой, если в дереве были
# несохранённые правки. Он же печатается в подвале настроек.
BUILD="$(date +%y%m%d.%H%M)"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "nogit")"
if ! git -C "$ROOT" diff --quiet HEAD 2>/dev/null; then COMMIT="$COMMIT*"; fi
STAMP="$BUILD · $COMMIT"

# Если на текущем коммите висит тег релиза, он обязан совпасть с VERSION.
# Иначе собранный бандл говорит одно, а тег в репозитории — другое, и по
# номеру версии уже нельзя найти исходники, из которых он собран.
# `|| true`: без тега grep возвращает 1, а при `set -e` этого хватает,
# чтобы сборка молча оборвалась на ровном месте.
TAG="$(git -C "$ROOT" tag --points-at HEAD 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
if [ -n "$TAG" ] && [ "$TAG" != "v$VERSION" ]; then
  echo "Тег на этом коммите — $TAG, а в VERSION — $VERSION. Разошлись." >&2
  exit 1
fi

cd "$ROOT"
swift build -c "$CONFIG"
BIN_DIR="$ROOT/.build/$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/Notch" "$APP/Contents/MacOS/Notch"

# Ресурсный бандл SwiftPM (звуки) ищется рядом с исполняемым файлом
# и в Resources — кладём в Resources.
if [ -d "$BIN_DIR/Notch_Notch.bundle" ]; then
  cp -R "$BIN_DIR/Notch_Notch.bundle" "$APP/Contents/Resources/"
fi

# Адаптер MediaRemote (Vendor/MediaRemoteAdapter): framework, который
# системный perl грузит в себя, чтобы прочитать Now Playing — нашему
# процессу MediaRemote данные не отдаёт. cmake ради него не нужен:
# собираем clang'ом, и только когда исходники новее собранного.
ADAPTER_SRC="$ROOT/Vendor/MediaRemoteAdapter"
ADAPTER_FW="$ROOT/.build/adapter/MediaRemoteAdapter.framework"
ADAPTER_BIN="$ADAPTER_FW/Versions/A/MediaRemoteAdapter"
if [ ! -f "$ADAPTER_BIN" ] || [ -n "$(find "$ADAPTER_SRC" -newer "$ADAPTER_BIN" -type f | head -1)" ]; then
  rm -rf "$ADAPTER_FW"
  mkdir -p "$ADAPTER_FW/Versions/A/Resources"
  clang -dynamiclib -arch arm64 -arch x86_64 -mmacosx-version-min=15.0 \
    -fobjc-arc -fvisibility=default -w \
    -I"$ADAPTER_SRC/include" -I"$ADAPTER_SRC/src" \
    "$ADAPTER_SRC"/src/adapter/*.m "$ADAPTER_SRC"/src/private/*.m "$ADAPTER_SRC"/src/utility/*.m \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
    -o "$ADAPTER_BIN"
  ln -sfn A "$ADAPTER_FW/Versions/Current"
  ln -sfn Versions/Current/MediaRemoteAdapter "$ADAPTER_FW/MediaRemoteAdapter"
  ln -sfn Versions/Current/Resources "$ADAPTER_FW/Resources"
  cat > "$ADAPTER_FW/Versions/A/Resources/Info.plist" <<'FWPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
  <key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleName</key><string>MediaRemoteAdapter</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
</dict></plist>
FWPLIST
fi
mkdir -p "$APP/Contents/Frameworks"
cp -R "$ADAPTER_FW" "$APP/Contents/Frameworks/"
cp "$ADAPTER_SRC/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"

# Иконка приложения. Агент без Dock-иконки её почти не показывает, но
# Finder, Spotlight и «О программе» — показывают, и там до сих пор стоял
# системный бланк.
cp "$ROOT/Sources/Notch/Resources/Icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Notch</string>
  <key>CFBundleDisplayName</key><string>Notch</string>
  <key>CFBundleIdentifier</key><string>com.dany.notch</string>
  <key>CFBundleExecutable</key><string>Notch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>NotchBuildStamp</key><string>$STAMP</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>

  <!-- Имена чужих программ и устройств — на языке системы. Без этого
       своих .lproj у бандла нет, и система отдаёт всё по-английски:
       «Calculator» вместо «Калькулятор». -->
  <key>CFBundleAllowMixedLocalizations</key><true/>

  <!-- Агент: без иконки в Dock. -->
  <key>LSUIElement</key><true/>

  <!-- Тексты запросов разрешений. Без них система не спросит, а упадёт. -->
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>Notch показывает ближайшую встречу в панели у верхнего края экрана.</string>
  <key>NSRemindersFullAccessUsageDescription</key>
  <string>Notch показывает невыполненные напоминания в панели, отмечает их и добавляет новые.</string>
  <key>NSRemindersUsageDescription</key>
  <string>Notch показывает невыполненные напоминания в панели, отмечает их и добавляет новые.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Notch читает, что сейчас играет в Музыке и Spotify.</string>
  <key>NSLocationUsageDescription</key>
  <string>Notch показывает погоду там, где вы сейчас.</string>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>Notch показывает погоду там, где вы сейчас.</string>
  <key>NSCameraUsageDescription</key>
  <string>Notch показывает вас в Зеркале — посмотреть на себя перед звонком.</string>
</dict>
</plist>
PLIST

# Подпись. TCC запоминает разрешение по подписи, а у ad-hoc подписи она
# меняется при каждой сборке — поэтому «Универсальный доступ» после
# пересборки приходится выдавать заново. Если в связке ключей есть
# самоподписанный сертификат «Notch Dev», подписываем им: идентичность
# тогда постоянная и разрешение переживает пересборку.
# Порядок: свой «Notch Dev», потом Apple Development из Xcode — обе
# идентичности постоянные, поэтому TCC не забывает выданное. Ad-hoc —
# последнее средство: он меняется на каждой сборке.
IDENTITY="-"
IDENTITIES="$(security find-identity -v -p codesigning || true)"
if grep -q "Notch Dev" <<<"$IDENTITIES"; then
  IDENTITY="Notch Dev"
elif grep -q "Apple Development" <<<"$IDENTITIES"; then
  IDENTITY="$(sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' <<<"$IDENTITIES" | head -1)"
fi
# Вложенное подписывается раньше бандла: подпись бандла учитывает
# подписи всего, что лежит внутри.
codesign --force --sign "$IDENTITY" --timestamp=none "$APP/Contents/Frameworks/MediaRemoteAdapter.framework" >/dev/null 2>&1 || true
codesign --force --sign "$IDENTITY" --identifier com.dany.notch --timestamp=none "$APP" >/dev/null 2>&1 || true

if [ "$IDENTITY" = "-" ]; then
  echo "Подпись ad-hoc: после пересборки выключи и включи Notch в Универсальном доступе."
else
  echo "Подписано: $IDENTITY"
fi

echo "Сборка: $STAMP"
echo "Собрано: $APP"
