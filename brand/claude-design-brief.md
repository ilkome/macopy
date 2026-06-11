# MaCopy — бриф для Claude Design

Скопируй текст ниже целиком в первый промпт на **claude.ai/design**. Прикрепи также 1-2 файла из `brand/` (логотип) и пару скриншотов приложения, если есть.

---

## Промпт для Claude Design

> Спроектируй одностраничный лендинг для open-source приложения **MaCopy** — менеджер буфера обмена для macOS. Стиль — **Apple-минимализм** (как apple.com / sketch.com / linear.app для мака): много воздуха, SF Pro / Inter, светлая тема по умолчанию + тёмный режим, тонкие тени, скруглённые карточки, без иллюстраций-стоков.
>
> Сделай два экрана: десктоп (1440px) и мобильный (390px). Дай готовый HTML/CSS на экспорт.

### Tone of voice

- Технический, спокойный, без маркетингового шума.
- Английская версия — основная, русская — второстепенная (переключатель в шапке).
- Никаких «революционно», «AI-powered», «boost productivity». Просто факты + одна шутка про то, что буфер обмена в macOS только один.

### Структура страницы

1. **Hero**
   - Логотип (squircle 96×96) + wordmark «MaCopy».
   - H1: *Your clipboard, but with a memory.*
   - Подзаголовок: *A native macOS clipboard manager. Lives in the menu bar. Opens with ⌘\` — pastes with Enter.*
   - Две кнопки: **Download .dmg** (primary, тёмная) и **View on GitHub** (secondary, outline).
   - Мелкий шрифт под кнопками: *macOS 14 Sonoma or newer · Free · Open source (MIT)*
   - Справа — большой скриншот плавающей панели на полупрозрачном фоне рабочего стола macOS.

2. **Фичи — сетка 2×3 карточек** (заголовок + 1 строка + SF Symbol)
   - **Smart type detection** — URLs, colors, images, code и обычный текст разбираются автоматически (вкладки Favorites / All / URLs / Images / Colors / Code).
   - **On-device OCR** — Vision сканирует скриншоты на русском и английском. Поиск работает по тексту с картинок.
   - **Fuzzy search** — ищет по содержимому, OCR-тексту, комментариям и имени приложения-источника.
   - **Link previews** — для URL подтягивает заголовок, описание и картинку через OpenGraph.
   - **Private data filter** — уважает `org.nspasteboard.ConcealedType`. Пароли из 1Password и Bitwarden никогда не попадают в историю.
   - **Doesn't steal focus** — `NSPanel` с `.nonactivatingPanel`. Курсор остаётся в исходном поле, ⌘V попадает куда надо.

3. **Hotkeys — таблица** (тёмный блок, шрифт monospace)

   | Key | Action |
   |---|---|
   | ⌘\` | Show / hide panel (configurable) |
   | ↑ ↓ | Navigate |
   | ← → | Switch tabs |
   | Enter | Paste into previous app |
   | ⇧+Enter | Copy without pasting |
   | ⌘D | Toggle favorite |
   | ⌘E | Edit comment |
   | ⌘⌫ | Delete from history |
   | Space | Quick Look for images |
   | Esc | Hide panel |

4. **How it works** — 3 шага в ряд, каждый с иконкой
   - Press ⌘\` to open. → Type to search. → Hit Enter — it pastes into the app you came from.

5. **Privacy** — короткий блок на тёмном фоне
   - *Everything stays on your Mac. No accounts, no telemetry, no cloud sync. OCR runs on-device via Apple's Vision framework. Source code is on GitHub.*

6. **Install** — три варианта в карточках
   - **Direct download**: `.dmg` с GitHub Releases. Кнопка.
   - **From source**: `git clone ... && ./build-app.sh`. Codeblock.
   - **Updates**: автоматически через Sparkle.

7. **Footer**
   - Логотип, версия (читать из appcast.xml), ссылки: GitHub, License (MIT), Releases, ilkome.com.
   - © 2026 ilkome.

### Визуальные референсы

- **apple.com** — типографика и плотность.
- **linear.app** — карточки фичей, плавные градиенты.
- **raycast.com** — секция хоткеев.
- **zed.dev** — тёмные акценты на светлом фоне.

### Цвета

- Бренд: индиго → фиолет (`#5E5CE6 → #BF5AF2`), системные цвета Apple.
- Текст: `#1C1C1E` на белом, `#F2F2F7` на тёмных секциях.
- Фон: чистый белый `#FFFFFF`, тёмные секции `#1C1C1E`.

### Шрифты

- Заголовки: **SF Pro Display** (fallback: **Inter**), web 700.
- Текст: **SF Pro Text** (fallback: **Inter**), 400/500.
- Хоткеи и код: **SF Mono** (fallback: **JetBrains Mono**).

### Что приложить в первом сообщении в Claude Design

1. Этот бриф целиком.
2. Один из логотипов: `brand/logo-text.svg` или `brand/logo-cards.svg`.
3. Скриншот плавающей панели приложения (сделать через ⌘⇧4 во время работы MaCopy).

### Дальнейшие итерации

После первого мокапа уточняй точечно:
- *«Сделай hero темнее, как на linear.app»*
- *«Замени иконки фичей на SF Symbols»*
- *«Добавь пятый шаг между Privacy и Install — Stack (что лежит под капотом: SwiftUI, SwiftData, Vision)»*
