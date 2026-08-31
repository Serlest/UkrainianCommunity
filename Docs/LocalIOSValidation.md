# Локальная проверка iOS перед выпуском

GitHub проверяет сборку, Swift unit-тесты, Firebase Functions и Rules. UI smoke,
accessibility, производительность и итоговые release-доказательства выполняются
на локальном Mac, где доступна стабильная Xcode/Simulator-среда.

## Гарантии runner

- Используется только отдельный Simulator `UAC Test iPhone 17 Pro` с точным
  runtime iOS 26.5. Существующие пользовательские Simulator не стираются и не
  сбрасываются.
- Автоматических повторов тестов нет. Каждый выбранный тест запускается ровно
  один раз, последовательно.
- Успешный процесс с нулём реально выполненных тестов считается ошибкой
  инфраструктуры, а не зелёным результатом.
- Ошибка приложения/теста отделена от ошибки запуска Simulator/test runner.
- Runner сохраняет логи, `.xcresult` и `manifest.json` в
  `outputs/test-evidence/<commit>/<UTC-время>-<режим>/`.
- `outputs/` игнорируется Git. Runner ничего оттуда автоматически не удаляет.
- UI-тесты используют существующий детерминированный `-ui-testing` режим
  приложения. Runner не разворачивает Firebase и не выполняет production-записи.

Конфигурация среды и список шести smoke-тестов находятся в
`scripts/ios_validation_config.json`. Изменение runner, конфигурации или его
unit-тестов включает полный CI и помечает локальную UI-проверку обязательной.

## Команды и разрешения

Каждая команда выполняется только после отдельного разрешения владельца.

### 1. Read-only preflight

```sh
python3 scripts/run_ios_validation.py preflight
```

Проверяет Xcode 26.6 (17F113), проект, runtime iOS 26.5 (23F77), тип устройства и наличие
выделенного Simulator. Ничего не создаёт, не загружает и не запускает.

### 2. Однократная подготовка Simulator

```sh
python3 scripts/run_ios_validation.py prepare
```

Создаёт выделенный Simulator, только если его ещё нет. Команда не загружает
приложение, не запускает тесты, не стирает и не удаляет устройства.

### 3. Точечная проверка во время разработки

```sh
python3 scripts/run_ios_validation.py targeted \
  --only-testing UkrainianCommunityUITests/UkrainianCommunityUITests/testStartupSplashTransitionsToMainInterface
```

Допускается несколько `--only-testing`. Нужен полный идентификатор
`Target/Class/testMethod`. Точечный режим разрешён в грязном рабочем дереве, но
manifest честно фиксирует это состояние.

### 4. Шесть UI smoke-тестов

```sh
python3 scripts/run_ios_validation.py smoke
```

Runner один раз собирает test products и один раз последовательно выполняет
ровно шесть тестов из конфигурации.

### 5. Итоговый локальный release gate

```sh
python3 scripts/run_ios_validation.py release
```

Release-режим требует чистое рабочее дерево точного commit и выполняет:

1. Debug `build-for-testing`.
2. Release build для iOS Simulator.
3. Все тесты target `UkrainianCommunityTests`.
4. Ровно шесть UI smoke-тестов.

Unit-тесты могут содержать явно объявленные skips; smoke-тесты не могут быть
пропущены. После запуска нужно приложить каталог evidence к release ledger и
отдельно записать физическое устройство, TestFlight и ручные accessibility/
performance-проверки. Этот runner их не подменяет.

## Статусы и коды завершения

| Код | Статус | Значение |
| --- | --- | --- |
| 0 | `PASSED` | Все ожидаемые проверки действительно выполнены |
| 2 | `PREFLIGHT_FAILED` | Среда, конфигурация или чистота release-worktree не соответствует контракту |
| 3 | `BUILD_FAILED` | Ошибка компиляции/сборки |
| 4 | `TEST_FAILED` | Реально запущенный тест приложения завершился ошибкой |
| 5 | `INFRASTRUCTURE_FAILED` | Simulator/test runner не стартовал, завис или не выполнил ожидаемый набор |

Повтор после `INFRASTRUCTURE_FAILED` не выполняется автоматически. Сначала
исследуется сохранённый log и manifest, затем владелец отдельно разрешает
следующее действие.
