# MediaRemoteAdapter

Копия [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
(BSD 3-Clause, см. `LICENSE`), коммит `73f14ab` от 4 сентября 2026.
Взяты только исходники framework'а и perl-скрипт; тестовый клиент и
cmake не нужны — `Scripts/build-app.sh` собирает framework сам через clang.

Зачем: с macOS 15.4 `MediaRemote` не отдаёт метаданные процессам без
entitlement'а, а системный `/usr/bin/perl` (`com.apple.perl5`) его
получает. Скрипт грузит framework внутрь perl и печатает Now Playing
строками JSON — так Notch видит, что играет в браузере и любом другом
плеере.

Обновлять — копированием тех же папок из свежего клона; править здесь
ничего не надо.
