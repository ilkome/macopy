# MaCopy brand assets

Логотип + бриф для лендинга через Claude Design.

## Логотип

| Файл | Назначение |
|---|---|
| [logo.svg](./logo.svg) | Исходник: стопка карточек = история буфера, на индиго-фиолетовом squircle. 1024×1024, корнер 229px (стандарт macOS). |
| [logo.png](./logo.png) | Растровая версия 256×256 для README. |
| [AppIcon.icns](./AppIcon.icns) | Иконка приложения. Подключена в `build-app.sh` (копируется в `Contents/Resources`, ключ `CFBundleIconFile`). |

Wordmark («MaCopy» рядом с иконкой) собирается живым шрифтом Oxanium в `logos.html`, отдельных SVG для него не держим.

### Пересобрать иконку из `logo.svg`

```bash
cd brand
ICONSET=AppIcon.iconset; mkdir "$ICONSET"
for s in 16 32 128 256 512; do
  rsvg-convert -w $s   -h $s   logo.svg -o "$ICONSET/icon_${s}x${s}.png"
  rsvg-convert -w $((s*2)) -h $((s*2)) logo.svg -o "$ICONSET/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$ICONSET" -o AppIcon.icns && rm -rf "$ICONSET"
rsvg-convert -w 256 -h 256 logo.svg -o logo.png
```

## Лендинг

Бриф для Claude Design: [claude-design-brief.md](./claude-design-brief.md). Открой [claude.ai/design](https://claude.ai/design), скопируй промпт, прикрепи логотип + скриншот приложения.

## Следующие шаги

1. Получить мокап лендинга → решить, хостить на GitHub Pages в `docs/` или отдельным репо.
