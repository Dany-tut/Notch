#!/bin/bash
# Собирает готовую к раздаче версию: правит VERSION, ставит тег, кладёт
# рядом zip с приложением.
#
# Зачем скрипт, а не три команды руками: номер версии живёт сразу в трёх
# местах — в бандле, в теге репозитория и в имени архива. Стоит собрать
# «0.2.1», а тег поставить потом и забыть — и по присланному архиву уже
# не найти, из чего он собран. Здесь все три получаются из одного числа.
#
#   Scripts/release.sh 0.2.1   — поднять версию до 0.2.1 и собрать
#   Scripts/release.sh         — собрать то, что уже записано в VERSION
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Чистое дерево проверяем до всего остального: релиз из грязного дерева —
# это архив, к которому нет коммита. Тег указывает на один код, а
# собралось из другого, и найти по номеру версии исходники уже нельзя.
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "В дереве есть несохранённые правки. Сначала коммит, потом релиз." >&2
  git status --short
  exit 1
fi

# Бумп версии — отдельным коммитом, а не правкой поверх тега: иначе тег
# указывает на коммит, где в VERSION стоит ещё старый номер.
if [ $# -gt 0 ]; then
  NEXT="${1#v}"
  if ! [[ "$NEXT" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Версия задаётся как X.Y.Z, например 0.2.1 — а не «$1»." >&2
    exit 1
  fi
  if [ "$NEXT" != "$(tr -d ' \t\r\n' < VERSION)" ]; then
    printf '%s\n' "$NEXT" > VERSION
    git add VERSION
    git commit -m "Версия $NEXT" >/dev/null
    echo "VERSION поднят до $NEXT отдельным коммитом."
  fi
fi

VERSION="$(tr -d ' \t\r\n' < VERSION)"
TAG="v$VERSION"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Тег $TAG уже есть. Возьми следующий номер." >&2
  exit 1
fi

# Тег ставим до сборки: build-app.sh сверяет его с VERSION, и штамп в
# бандле указывает на тот самый коммит, что и тег.
git tag -a "$TAG" -m "Notch $TAG"

"$ROOT/Scripts/build-app.sh" release

# Есть Developer ID — подписываем им, нотаризуем и кладём рядом DMG.
# Нет — архив как раньше, с подсказкой про xattr.
NOTARIZED=0
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  "$ROOT/Scripts/notarize.sh"
  NOTARIZED=1
fi

DIST="$ROOT/dist"
ZIP="$DIST/Notch-$VERSION.zip"
mkdir -p "$DIST"
rm -f "$ZIP"
# ditto, а не zip: сохраняет ресурсные вилки и права, иначе подпись
# бандла по дороге ломается и система считает приложение испорченным.
ditto -c -k --sequesterRsrc --keepParent "$ROOT/build/Notch.app" "$ZIP"

echo
echo "Готово: $ZIP"
echo "Тег $TAG поставлен локально. Отправить: git push origin main $TAG"
echo
if [ "$NOTARIZED" = 1 ]; then
  echo "Нотаризовано: и zip, и dmg открываются на чужом Маке без xattr."
  exit 0
fi
# Единственная подсказка, которую нельзя вшить в интерфейс: до первого
# запуска приложения ещё нет, и сказать это некому. Поэтому она едет
# вместе с архивом.
cat <<'NOTE'
Что написать тому, кому отдаёшь архив:

  1. Распаковать и перенести Notch.app в «Программы».
  2. Приложение подписано сертификатом разработки и не нотаризовано,
     поэтому macOS его придержит. Снять карантин:
       xattr -dr com.apple.quarantine /Applications/Notch.app
  3. Остальное приложение расскажет само: раздел «Доступ» во вкладке
     «Приложение» в настройках панели.
NOTE
