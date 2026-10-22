# Как работать с кодом Mely

## Сборка

```sh
git clone https://github.com/cryzer-dev/Mely.git && cd Mely
scripts/make-dev-cert.sh              # один раз: свой сертификат подписи «Mely Dev»
scripts/build-app.sh --dev --install  # собрать «Mely Dev» и поставить рядом с основной Mely
scripts/test.sh                       # тесты
swift run mely-snapshots              # снимки всех состояний интерфейса в ./snapshots
swift run mely-snapshots --readme docs/images  # картинки для README
swift run mely-snapshots --matrix snapshots/matrix  # все варианты из проверок вёрстки
scripts/make-dmg.sh                   # установщик build/Mely-X.Y.Z.dmg
```

Нужны Xcode 26 или Command Line Tools со Swift 6.3.

### Mely Dev

Свои правки удобно проверять в **Mely Dev**: `scripts/build-app.sh --dev --install` ставит её в `/Applications/MelyDev.app`, не трогая основную Mely.

- У неё свой bundle id (`dev.mely.app.dev`) и нет автообновлений.
- При первой установке она берёт настройки основной Mely.
- Хуки Claude Code, сокет и `~/.mely` у двух копий общие, поэтому одновременно они не работают. Mely Dev при запуске закрывает основную Mely и запускает её снова, когда выходишь из Mely Dev.

`scripts/build-app.sh --install` без `--dev` заменяет основную Mely в `/Applications` — так собирают релиз, а не проверяют правки.

### Снимки вместо превью

SwiftUI Previews без Xcode не работают, поэтому каждое состояние интерфейса отрисовывается в PNG программой `mely-snapshots` (`Sources/MelySnapshots`). Поменял вид — добавь или обнови снимок и посмотри на него.

### Проверки вёрстки

`scripts/test.sh` раскладывает челку во всех вариантах (`LayoutMatrix` в `Sources/MelyFixtures`: экраны 14", 16" и без выреза; каждая страница с пустыми, обычными и переполненными данными; шапка во всех состояниях лимитов) и проверяет: ничего не выходит за свой контейнер, не наезжает друг на друга и на вырез, нет пустых капсул и обрезанного текста. Проверяются элементы, помеченные `layoutProbe` (в приложении он ничего не делает).

- Новый элемент панели, шапки или полоски выреза — пометь его `layoutProbe`: `inside:` — в чём он должен лежать, `row:` — с чем не должен пересекаться, `contains:` — что обязан содержать, `checksText: true` — для текста, который не должен срезаться по высоте.
- Новое состояние (пустое, длинное, ошибка) — добавь вариант в `LayoutMatrix`, данные — в `Fixtures`; их же используют снимки.
- Тест падает с именем варианта (`страница_экран_данные`) и элементов; посмотреть на вариант глазами — `swift run mely-snapshots --matrix snapshots/matrix`.

## Как выходят версии

- Коммиты пишутся по [Conventional Commits](https://www.conventionalcommits.org/ru/): `feat: …` — новое, `fix: …` — исправление, `feat!: …` — несовместимое изменение.
- Бот [release-please](https://github.com/googleapis/release-please) держит pull request «выпуск X.Y.Z» со следующим номером версии и списком изменений.
- Merge этого pull request выпускает версию: GitHub Actions прогоняет тесты, собирает и подписывает `.dmg`, кладёт его в релиз вместе с лентой обновлений `appcast.xml` и публикует релиз.
- Установленные Mely узнают о новой версии через [Sparkle](https://sparkle-project.org). Обновления подписаны ключом EdDSA, поэтому подменённый файл не установится.
