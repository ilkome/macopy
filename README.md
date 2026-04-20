# ListTestSwiftUI

Минимальное macOS (15+) приложение на SwiftUI / Swift 6. Живёт в status bar, без Dock-иконки. Глобальная комбинация **⌘4** открывает/закрывает плавающую панель с полупрозрачным фоном и списком из 50 элементов.

## Требования

- macOS 15 Sequoia или новее
- Swift 6 toolchain (Xcode 16+)

## Сборка

```bash
swift build -c release
```

Бинарь окажется в `.build/release/ListTestSwiftUI`.

## Запуск

```bash
swift run -c release ListTestSwiftUI
```

Или напрямую:

```bash
./.build/release/ListTestSwiftUI
```

После запуска в строке меню появится иконка `L4`. Жмите её или используйте **⌘4** глобально, чтобы показать/спрятать панель.

## Управление

- **⌘4** — показать/скрыть панель
- **↑ / ↓** — сдвинуть выделение на 1 строку
- **Shift+↑ / Shift+↓** — сдвинуть выделение на 2 строки
- Клик по строке — выбрать её

При выходе выделения за видимую область список автоматически скроллится.

## Структура

```
Package.swift
Sources/ListTestSwiftUI/
  AppDelegate.swift   — status item, глобальный hotkey (Carbon RegisterEventHotKey)
  FloatingPanel.swift — NSPanel с NSVisualEffectView
  ContentView.swift   — SwiftUI список, onKeyPress
```

## Остановка

Приложение не имеет пункта меню "Quit" (минимализм). Остановить:

```bash
pkill -x ListTestSwiftUI
```

или `Ctrl+C` в терминале, из которого стартовали через `swift run`.
