---
name: screenshot-debug
description: Отладка через скриншоты — захват, пиксельный анализ, диагностика проблем рендеринга терминала
user-invocable: true
---

# screenshot-debug

Специализированный скилл для цикла «скриншот → анализ пикселей → диагноз». В отличие от `terminal-debug` (общая отладка), этот скилл фокусируется на визуальной диагностике: захват скриншота через CDP, извлечение пиксельных данных, сопоставление с DOM-состоянием, формирование гипотез.

## Когда использовать

- После изменения CSS/DOM структуры — проверить, не сломалось ли выделение
- При любом визуальном баге: призраки выделения, смещение текста, `$$$$` в углу
- Перед коммитом — быстрый визуальный diff
- Когда пользователь присылает скриншот — проанализировать и дать заключение

## Инструменты

### Захват

```bash
python3 scripts/cdp-screenshot.py              # screenshots/N.png (автоинкремент)
python3 scripts/cdp-screenshot.py name.png     # screenshots/name.png
python3 scripts/cdp-screenshot.py via-eval.png # скриншот + доп. JS перед захватом
```

### Пиксельный анализ (PIL)

```python
from PIL import Image
import numpy as np

img = Image.open('screenshots/N.png')
arr = np.array(img)

# Профиль яркости по столбцам (найти синие блоки выделения)
blue_mask = (arr[:,:,2] > 100) & (arr[:,:,0] < 80) & (arr[:,:,1] < 100)
blue_rows = blue_mask.any(axis=1)  # True где есть синий

# Профиль яркости текста по строкам
gray = np.mean(arr, axis=2)
luminance = gray.mean(axis=1)  # средняя яркость каждой строки

# Найти ряды текста: тёмный фон (~30) + светлый текст (~212) = luminance ~40-60
text_rows = (luminance > 35) & (luminance < 80)
```

### Диагностические JS-сниппеты

```js
// Проверить position у ключевых элементов
(() => {
  const els = {
    screen: document.querySelector('.xterm-screen'),
    selection: document.querySelector('.xterm-selection'),
    rows: document.querySelector('.xterm-rows'),
    helpers: document.querySelector('.xterm-helpers'),
    measure: document.querySelector('.xterm-char-measure-element'),
    textarea: document.querySelector('.xterm-helper-textarea'),
  };
  const result = {};
  for (const [name, el] of Object.entries(els)) {
    if (!el) { result[name] = null; continue; }
    const cs = getComputedStyle(el);
    result[name] = {
      position: cs.position,
      display: cs.display,
      visibility: cs.visibility,
      rect: el.getBoundingClientRect(),
    };
  }
  return JSON.stringify(result, null, 2);
})();
```

```js
// Проверить смещение между слоями selection и rows
(() => {
  const sel = document.querySelector('.xterm-selection');
  const rows = document.querySelector('.xterm-rows');
  if (!sel || !rows) return 'missing elements';
  const sr = sel.getBoundingClientRect();
  const rr = rows.getBoundingClientRect();
  return JSON.stringify({
    selection: { top: sr.top, left: sr.left, width: sr.width, height: sr.height },
    rows: { top: rr.top, left: rr.left, width: rr.width, height: rr.height },
    diffY: Math.round(sr.top - rr.top),
    diffX: Math.round(sr.left - rr.left),
  });
})();
```

## Паттерны диагностики

### Призрак выделения (два синих блока вместо одного)

**Симптом:** на скриншоте два синих прямоугольника — один на своём месте, второй смещён.
**Пиксельный признак:** две непересекающиеся группы синих пикселей с разными Y-координатами.
**Причина:** `.xterm-screen` потерял `position: relative` → selection-слой позиционируется от body, а не от screen.
**Проверка:** `getComputedStyle(screen).position` — должно быть `relative`.
**Исправление:** `styles.css` → `.xterm-screen { position: relative !important; }`

### Выделение не совпадает с текстом (сдвиг по Y)

**Симптом:** синий блок выше или ниже текста, который он должен покрывать.
**Пиксельный признак:** `diffY !== 0` между зоной синих пикселей и зоной текстовых пикселей.
**Причина:** selection top и rows top расходятся (обычно из-за helpers, занявшего место в потоке).
**Проверка:** сниппет «смещение между слоями» выше.
**Исправление:** `.xterm-helpers { position: absolute; top: 0; } !important`

### $$$$ в углу экрана

**Симптом:** четыре знака доллара в левом верхнем углу терминала.
**Пиксельный признак:** светлые пиксели в зоне (0,0)-(40,20) при отсутствии текста там.
**Причина:** `.xterm-char-measure-element` потерял `visibility: hidden`.
**Проверка:** `getComputedStyle(measure).visibility` — должно быть `hidden`.
**Исправление:** `.xterm-char-measure-element { visibility: hidden !important; }`

### Сплошная заливка (текст не виден сквозь выделение)

**Симптом:** синий прямоугольник непрозрачный, текст под ним не читается.
**Пиксельный признак:** внутри синей зоны нет светлых пикселей текста.
**Причина:** `background-color` сплошной (напр. `#264f78`), а не полупрозрачный.
**Проверка:** `getComputedStyle(selDiv).backgroundColor` — должен быть `rgba(38, 79, 120, 0.3)` или подобный.
**Исправление:** переопределить background-color у `.xterm-selection div` на rgba с прозрачностью.

## Цикл отладки

```
1. Собрал:       npm run build
2. Перезагрузил: python3 scripts/cdp-eval.py '...reload plugin...'
3. Настроил:     python3 scripts/cdp-eval.py '...открыть терминал + выделить...'
4. Скриншот:     python3 scripts/cdp-screenshot.py
5. Прочитал:     Read screenshots/N.png
6. Пиксели:      python3 -c "анализ PIL"
7. DOM:          python3 scripts/cdp-eval.py '...диагностика...'
8. Гипотеза:     сопоставить пиксели с DOM → найти причину
9. Исправил:     правка в styles.css или TerminalView.ts
10. Goto 1:      повторить для верификации
```

## Отчёт о скриншоте

При анализе скриншота всегда отвечай в структуре:

1. **Что видно:** конкретное описание (где синие блоки, где текст, есть ли перекрытие)
2. **Измерения:** пиксельные координаты, размеры, смещения
3. **Гипотезы:** ранжированные по вероятности, со ссылками на KB
4. **Рекомендация:** что делать, без автоматического применения

## Связанные ресурсы

- [[cdp-remote-debugging]] — настройка CDP, raw WebSocket, Origin
- [[obsidian-css-overrides-position]] — Obsidian сбрасывает position на static
- `/terminal-debug` — общая CDP-отладка (eval, reload, open terminal)
- `scripts/cdp-screenshot.py` — захват скриншота
- `scripts/cdp-eval.py` — выполнение JS
- `autodocs/archive/knowledge-base/selection-fix-log.md` — лог попыток исправления выделения
