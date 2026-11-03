# Classic UI — 2026-11-03

Ветка: `feat/classic-ui-1103`, основана на `e9c9eef`.

Стартовый экран показывает настоящие карты и отдельный вход в обучение.
Победа, учебная победа, панель обучения и игровой рельс оформлены в общей
палитре. Все подписи переведены на ru/en/tr. Обычная партия по-прежнему
сохраняется при входе в обучение и после него.

Контуры карт усилены отдельным спрайтом, контуры пустых ячеек заменены
на контрастные векторные. `sprite.max_count=256` покрывает 40 карт по три
спрайта и элементы поля. В первом браузерном прогоне обнаружены и исправлены
неправильная прозрачность учебной подложки и превышение старого лимита 128.

## Проверки финального кода

- Lua: **279/279**, exit 0.
- `tools/browser-test-selfcheck.py`: PASS.
- Debug desktop, Chrome, 960×540: **6/6** — hittest, menus, tutorialsave,
  i18n, pickupfx, win. Победа получена настоящим реплеем в 243 действия.
- Release mobile, Chrome, 844×390, DPR 3, CDP touch: **2/2** — hittest,
  tutorialsave. Это эмуляция телефона, не физическое устройство.
- Во всех восьми успешных сценариях: 0 ошибок движка, 0 проваленных проверок.
- `git diff --check`: PASS.

Итоги и выбранные настоящие скриншоты: [style-1103-classic/](style-1103-classic/).
Полные логи локально: `build/style-1103/classic/v4-desktop/` и
`build/style-1103/classic/mobile-release/` (build игнорируется git).
Бандлы: `/private/tmp/shenzhen-classic-ui-1103-v4/ShenzenSolitare` и
`/private/tmp/shenzhen-classic-ui-1103-release/ShenzenSolitare`.

Генерация интерфейса: `python3 tools/build-theme.py --theme classic`.
Исходники векторных элементов и их PNG находятся в `assets/ui/`.
Независимый merge-gate этих изменений ещё не запускался; слияния нет.
`plans/card-redesign-wip/` не изменён.
