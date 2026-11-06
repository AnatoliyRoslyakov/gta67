# Малый квартал · 4

[Открыть квартал](https://anatoliyroslyakov.github.io/gta67/)

В стеклянном кубе работает участок города размером 100 × 100 м из ветки `3.0`. Водители, физика Jolt, светофоры и пешеходы используют контроллеры городской игры. Над кубом можно выбрать время суток и включить общий городской фон. Стрелки или перетаскивание вращают камеру. Колесо, щипок или кнопки меняют масштаб. Двойной щелчок приближает выбранную улицу. Home возвращает общий вид.

Для пересборки нужен Godot 4.7.2 с шаблоном Web и локальный POLYGON City в `Assets/Synty/PolygonCity`. Из корня проекта выполните:

```sh
godot --headless --import
godot --headless --script res://tools/bake_quarter.gd
godot --headless --export-release Web docs/index.html
python3 -m http.server 8000 --directory docs
```

Геометрия квартала, дорожная сетка и облегчённые текстуры готовятся до экспорта в локальной папке `Assets/WebQuarter`. В репозитории публикуется собранный сайт. Исходники купленного пака хранятся локально.

Фотография студии для отражений — [Studio Small 09, Sergej Majboroda](https://polyhaven.com/a/studio_small_09). Городской фон — [Berlin Balcony, danner](https://freesound.org/people/danner/sounds/427932/), адаптированный в 90-секундную петлю. Обе записи распространяются под CC0.
