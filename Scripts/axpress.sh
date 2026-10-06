#!/bin/bash
# Нажать кнопку плеера в чужом окне через «Универсальный доступ».
# Имя кнопки берём из дерева, которое печатает NOTCH_AXDUMP.
#
# Запускать только из Терминала: внутри песочницы служба доступа недоступна.
set -e
cd "$(dirname "$0")/.."
out=/tmp/axpress.txt
NOTCH_AXPRESS="${1:-yandex}" NOTCH_AXLABEL="${2:-Нравится}" \
    ./build/Notch.app/Contents/MacOS/Notch > "$out" 2>&1 || true

# Что изменилось в плеере — видно только сравнением двух снимков.
awk '/^ax: плеер до нажатия:/{f=1;next} /^ax: нажатие:/{f=0} f' "$out" > /tmp/axbefore.txt
awk '/^ax: плеер после нажатия:/{f=1;next} /^ax: кнопка найдена заново:/{f=0} /^ax: после нажатия/{f=0} f' "$out" > /tmp/axafter.txt
grep -E '^ax: (нажатие|в плеере|не найден|после нажатия)' "$out" | cut -c1-120

# Состояние кнопки: до, сразу после и у заново найденного узла. Совпадение
# первых двух ни о чём не говорит — страница могла подменить сам узел.
echo "--- value/selected ---"
awk '/^ax: кнопка /{print} /^ax:   (value|selected|chromeaxnodeid|description)=/{print}' "$out"
echo "--- изменения в плеере ---"
diff /tmp/axbefore.txt /tmp/axafter.txt | cut -c1-200 || true
