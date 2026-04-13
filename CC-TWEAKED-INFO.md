# CC:Tweaked — Полный справочник для Minecraft Forge 1.20.1

## Что такое CC:Tweaked

CC:Tweaked (ComputerCraft: Tweaked) — активно поддерживаемый форк оригинального мода ComputerCraft. Добавляет в Minecraft программируемые компьютеры, черепах (Turtles), карманные компьютеры (Pocket Computers), мониторы, модемы и другую периферию. Программирование ведётся на языке **Lua** (рантайм Cobalt, основан на Lua 5.2 с элементами 5.3).

Автор и мейнтейнер — **SquidDev**. Поддерживает Forge и Fabric.

---

## Скачивание (Forge 1.20.1)

| Источник | Ссылка |
|---|---|
| **Modrinth (рекомендуется)** | https://modrinth.com/mod/cc-tweaked |
| Все версии Modrinth | https://modrinth.com/mod/cc-tweaked/versions |
| CurseForge (устаревшие версии) | https://www.curseforge.com/minecraft/mc-mods/cc-tweaked |
| GitHub Releases | https://github.com/cc-tweaked/CC-Tweaked/releases |

Актуальная версия для 1.20.1: **1.117.1** (февраль 2026).  
Файл: `cc-tweaked-1.20.1-forge-1.117.1.jar`

### Установка

1. Установить [Minecraft Forge](https://files.minecraftforge.net/) для 1.20.1
2. Скачать jar с [Modrinth](https://modrinth.com/mod/cc-tweaked/versions) (фильтр: Forge + 1.20.1)
3. Положить jar в папку `mods/`
4. Запустить игру

Зависимостей нет — мод полностью standalone.

---

## Официальные ресурсы

| Ресурс | URL |
|---|---|
| GitHub | https://github.com/cc-tweaked/CC-Tweaked |
| Ветка mc-1.20.x | https://github.com/cc-tweaked/CC-Tweaked/tree/mc-1.20.x |
| Документация | https://tweaked.cc/ |
| Javadoc (1.20.x) | https://tweaked.cc/mc-1.20.x/javadoc/ |
| Wiki | https://wiki.computercraft.cc/CC:Tweaked |
| Lua совместимость | https://tweaked.cc/reference/feature_compat.html |

---

## Lua API

### Основные модули

| API | Назначение | Документация |
|---|---|---|
| `os` | События, таймеры, время | [os](https://tweaked.cc/module/os.html) |
| `fs` | Файловая система | [fs](https://tweaked.cc/module/fs.html) |
| `io` | Высокоуровневый I/O | [io](https://tweaked.cc/module/io.html) |
| `http` | HTTP-запросы, WebSocket | [http](https://tweaked.cc/module/http.html) |
| `redstone` | Управление сигналами редстоуна | [redstone](https://tweaked.cc/module/redstone.html) |
| `peripheral` | Поиск и работа с периферией | [peripheral](https://tweaked.cc/module/peripheral.html) |
| `turtle` | Движение, копка, инвентарь черепах | [turtle](https://tweaked.cc/module/turtle.html) |
| `pocket` | API карманных компьютеров | [pocket](https://tweaked.cc/module/pocket.html) |
| `term` | Терминал: текст, цвета, курсор | [term](https://tweaked.cc/module/term.html) |
| `window` | Виртуальные окна | [window](https://tweaked.cc/module/window.html) |
| `disk` | Управление дисками | [disk](https://tweaked.cc/module/disk.html) |
| `shell` | Оболочка, пути, алиасы | [shell](https://tweaked.cc/module/shell.html) |
| `multishell` | Многозадачность | [multishell](https://tweaked.cc/module/multishell.html) |
| `parallel` | Параллельное выполнение корутин | [parallel](https://tweaked.cc/module/parallel.html) |
| `textutils` | Сериализация, JSON, форматирование | [textutils](https://tweaked.cc/module/textutils.html) |
| `paintutils` | Рисование на мониторах | [paintutils](https://tweaked.cc/module/paintutils.html) |
| `colours`/`colors` | Константы 16 цветов | [colours](https://tweaked.cc/module/colours.html) |
| `keys` | Константы клавиш | [keys](https://tweaked.cc/module/keys.html) |
| `settings` | Хранение настроек | [settings](https://tweaked.cc/module/settings.html) |

### Модули `cc.*`

| Модуль | Назначение |
|---|---|
| `cc.completion` | Автодополнение |
| `cc.shell.completion` | Утилиты автодополнения shell |
| `cc.strings` | Работа со строками (включая `split` с 1.115) |
| `cc.pretty` | Красивый вывод таблиц |
| `cc.expect` | Проверка типов аргументов |
| `cc.image.nft` | Формат NFT-изображений |

---

## Периферия

| Устройство | Описание |
|---|---|
| **Monitor** | Внутриигровой дисплей; Advanced Monitor — цветной |
| **Wireless Modem** | Беспроводная связь; Ender Modem — глобальная |
| **Wired Modem** | Проводная связь (networking cable) |
| **Speaker** | Воспроизведение звуков и PCM-аудио |
| **Printer** | Печать страниц и книг |
| **Disk Drive** | Работа с дискетами |
| **Turtle upgrades** | Инструменты, модемы, динамики как апгрейды черепах |
| **Inventories** | Взаимодействие с любыми блоками-инвентарями через `peripheral.wrap` |

---

## История версий для 1.20.1

### 1.117.x (февраль 2026) — последняя
- Карманные компьютеры на кафедре подключают периферию снизу
- Цвет карты в деталях блоков/предметов
- Эффекты зелий в деталях предметов
- `getResponseHeaders()` для WebSocket
- Поддержка мыши для карманных компьютеров на кафедре

### 1.116.x (июнь–июль 2025)
- `turtle.getEquippedLeft()` / `turtle.getEquippedRight()`
- Теги предметов для дискет и карманных компьютеров
- Многострочные строки/комментарии в редакторе `edit`

### 1.115.x
- Ошибки внутри `parallel` содержат информацию об источнике
- Подсказки альтернативных ключей таблицы при nil
- `cc.strings.split`

### 1.110.x (март 2024)
- Переработка `/computercraft` — ванильные entity selectors
- Фикс монтирования дисков после включения компьютера
- Фикс обновления мониторов после выхода из чанка

### 1.109.x (февраль 2024)
- Первая версия для Minecraft 1.20.1

---

## Аддоны для Forge 1.20.1

### Advanced Peripherals (рекомендуется)

| | |
|---|---|
| Версия | 0.7.41r |
| CurseForge | https://www.curseforge.com/minecraft/mc-mods/advanced-peripherals |
| Modrinth | https://modrinth.com/mod/advancedperipherals |
| Документация | https://docs.advanced-peripherals.de/ |

Блоки: ME Bridge (AE2), RS Bridge (Refined Storage), Chat Box, Player Detector, Energy Detector, Environment Detector, Inventory Manager, NBT Storage, Block Reader, Geo Scanner, Redstone Integrator, AR Controller, Colony Integrator.

### Turtlematic

- Расширяет возможности черепах
- https://modrinth.com/mod/turtlematic/version/1.20.1-1.2.6
- Требует **Peripheralium**

### UnlimitedPeripheralWorks

- Периферия для маяков, жукбоксов, блоков нот, рельсов
- Интеграции: AE2, Refined Storage, Occultism, Integrated Dynamics
- https://modrinth.com/mod/unlimitedperipheralworks/version/1.20.1-1.3.0
- Требует **Peripheralium**

### Plethora Peripherals

- Старый аддон, проверяйте актуальность для 1.20.1
- https://www.curseforge.com/minecraft/mc-mods/plethora-peripherals
- https://plethora.madefor.cc/

---

## Для разработчиков модов

Maven-артефакт:
```
cc.tweaked:cc-tweaked-1.20.1-forge:<version>
```
- Maven: https://mvnrepository.com/artifact/cc.tweaked/cc-tweaked-1.20.1-forge/1.111.0
- Javadoc: https://tweaked.cc/mc-1.20.x/javadoc/

---

## Сообщество

| Ресурс | URL |
|---|---|
| Сайт ComputerCraft | https://www.computercraft.cc/ |
| Форумы | https://forums.computercraft.cc/ |
| Wiki | https://wiki.computercraft.cc/ |
| Discord | https://discord.com/invite/minecraft-computer-mods-477910221872824320 |
| GitHub Discussions | https://github.com/cc-tweaked/CC-Tweaked/discussions |
| CraftOS-PC (эмулятор) | https://www.craftos-pc.cc/ |

---

## Инструменты разработки

| Инструмент | URL |
|---|---|
| Lua Language Server для CC:T | https://github.com/nvim-computercraft/lua-ls-cc-tweaked |
| CraftOS-PC (эмулятор) | https://www.craftos-pc.cc/ |
| DeepWiki обзор | https://deepwiki.com/cc-tweaked/CC-Tweaked/1-overview |
