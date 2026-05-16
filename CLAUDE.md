# MaCopy — instructions for Claude

## Always relaunch after code changes

После любых изменений кода обязательно автоматически (без явной просьбы):

1. Собрать `.app` в release: `./build-app.sh` (он сам делает `swift build -c release` + переупаковку `.app` + codesign).
2. Завершить запущенный экземпляр: `pkill -f "MaCopy by ilkome.app/Contents/MacOS/MaCopy"`.
3. Запустить новую версию: `open "MaCopy by ilkome.app"`.

Причина: `swift build` собирает бинарь только в `.build/debug/`, не подменяя работающий `.app`. Без этих шагов пользователь продолжает пользоваться старой версией и не может проверить правки.

Предупреждать пользователя только если рестарт может потерять важное состояние; для буфера обмена это редкий случай.
