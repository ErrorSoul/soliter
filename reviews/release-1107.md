# Release-проверки после мержа — 2026-11-07

Исходная игра: `98d8c85` (master, опубликован; PR #2 merged, issue #1 closed).
Ветка проверок: `test/release-validation-1107`. Код игры и ассеты не менялись.
Release HTML5 собран `bash tools/defold-bundle.sh /private/tmp/shenzhen-release-1107 --variant release`.
[Лог сборки](release-1107/build.log), [хэши](release-1107/hashes.json).

Все браузерные проверки выполняются на Steam Deck, по одному браузеру,
headless Chromium / SwiftShader, viewport 960×540, DPR 1.

## Итог

**16/16 итоговых проверок PASS**: по 8 сценариев с COI и без COI — music,
boot, hittest, fullscreen, debugkeys, yasdk, tutorialsave, pickupfx.
Во всех итоговых отчётах 0 fatal / 0 failures.
[Сводка 16 результатов](release-1107/verification.json),
[матрица без COI](release-1107/no-coi/summary.json).

Сетевые отчёты всех сценариев подтверждают выбор движка: с COI загружался
`ShenzenSolitare_pthread.wasm`, без COI — `ShenzenSolitare.wasm`.
Сборка release, Python compile и git diff --check: PASS.
Lua заново не запускался: Lua-код не менялся, предыдущий результат 287/287
остаётся исторической проверкой исходного merge-коммита.

## Найденная проблема теста

Первоначальный `debugkeys` сравнивал весь игровой стол побайтно. Теперь
портреты животных анимируются в ожидании, поэтому такой снимок перестал быть
инвариантом: первый release-прогон заявил, что Space пересдал карты.
При этом production-код по-прежнему закрывает клавишу через
`debug_flags.enabled`, определяемый `sys.get_engine_info().is_debug`.

Оракул изменён на неподвижную верхнюю полосу первой строки tableau
(игровые x=100…860, y=348…372): там рамки и индексы, а не портреты.
Проверка успешного PLAY и контроль неподвижности до клавиш сохранены.
Флаг `--release` явно выбирает release-оракул даже на debug-бандле:
это позволяет проверить отрицательный контроль с реально работающим Space.
Проверки S/R остаются ограниченными: S не двигает карты, R зависит от
решаемости раздачи. Надёжный различитель — пересдача по Space.

## Проверка оракула

- Первый COI-прогон: 7 PASS / 1 FAIL (`debugkeys`, сравнение всего стола).
  [Сводка](release-1107/initial-coi/summary.json).
- Исправленный `debugkeys` на release: PASS, 0 fatal / 0 failures.
  [Отчёт](release-1107/debugkeys-fixed/report.json).
- Тот же release-оракул на debug-бандле `bundle-foundation`: ожидаемый FAIL
  на R и Space, 0 fatal. [Отрицательный контроль](release-1107/debug-negative-control/report.json).
  Это реальная debug-сборка с активными клавишами, а не мутация production-кода.

Семь других COI-сценариев не перепрогонялись после изменения только функции
`scenario_debugkeys`; их код не менялся. Первичный и финальный хэши харнесса
сохранены раздельно в hashes.json.

## Ограничения

Это не песочница Яндекс Игр: `yasdk` использует фальшивый SDK. Прогоны не
являются ручной проверкой тачскрина/геймпада, аппаратного FPS или мобильного
браузера. Исторические отчёты сохранены с их исходным объёмом доказательств.
