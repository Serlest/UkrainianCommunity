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

## Отдельный Firebase SDK-прогон: подпись Simulator test-host

Для opt-in тестов с настоящим Firebase Auth недостаточно unsigned test products:
в прогоне 5 сентября 2026 `CODE_SIGNING_ALLOWED=NO` привёл к
`FIRAuthErrorDomain 17995 / SecItemAdd(-34018)` при сохранении сессии в Keychain.
Обычная unit-изоляция от Firebase при этом оставалась исправной.

Для SDK-прогона координатор собирает отдельные Debug products с полноценной
ad-hoc подписью Xcode. Ни исходный entitlement plist, ни production-код менять
не нужно. Команды ниже выполняются из проверяемого checkout; заранее задать
`UAC_SIMULATOR_ID` точным ID выделенного Simulator и `UAC_PACKAGE_CACHE` путём к
существующему каталогу SourcePackages для этой версии зависимостей.

```sh
: "${UAC_SIMULATOR_ID:?Set the dedicated Simulator ID}"
: "${UAC_PACKAGE_CACHE:?Set the existing SourcePackages directory}"
UAC_SDK_WORK=$(mktemp -d "${TMPDIR:-/tmp}/uac-sdk-signing.XXXXXX")
printf '%s\n' "$UAC_SDK_WORK"

xcodebuild -project UkrainianCommunity.xcodeproj \
  -scheme UkrainianCommunity -configuration Debug -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$UAC_SIMULATOR_ID" \
  -derivedDataPath "$UAC_SDK_WORK/DerivedData" \
  -clonedSourcePackagesDirPath "$UAC_PACKAGE_CACHE" \
  -testProductsPath "$UAC_SDK_WORK/UAC-sdk-signed.xctestproducts" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES \
  DEVELOPMENT_TEAM=438S639937 AppIdentifierPrefix=438S639937. \
  PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  build-for-testing > "$UAC_SDK_WORK/build.log" 2>&1
```

Продолжать только после успешного завершения сборки. Team/prefix соответствуют
текущему проекту UAC; не переносить их на другой проект. Не переопределять
`CODE_SIGN_ENTITLEMENTS` глобально: app и тестовые targets должны сохранить свои
настройки. Не добавлять provisioning updates, регистрацию устройств,
archive/export или destination физического iPhone.

DerivedData и test products намеренно находятся в системном временном каталоге,
вне Documents. В подтверждённом прогоне `com.apple.FinderInfo`/resource fork
повторно появлялись на generated SDK `.bundle` в Documents и ломали codesign
даже после адресной очистки extended attributes. Перенос только build artifacts
в temp устранил этот инфраструктурный блокер; исходники и package cache остались
на прежнем месте. Не очищать extended attributes массово в исходниках или
пользовательских каталогах. Сохранить путь temp и evidence до его уборки.

После сборки проверить именно новый Debug host:

```sh
UAC_SDK_APP="$UAC_SDK_WORK/UAC-sdk-signed.xctestproducts/Binaries/0/Debug-iphonesimulator/UkrainianCommunity.app"
codesign --verify --deep --strict "$UAC_SDK_APP"
codesign -dv "$UAC_SDK_APP"
codesign -d --entitlements - "$UAC_SDK_APP"
plutil -p "$UAC_SDK_WORK/DerivedData/Build/Intermediates.noindex/UkrainianCommunity.build/Debug-iphonesimulator/UkrainianCommunity.build/UkrainianCommunity.app-Simulated.xcent"
```

Xcode разделяет signing и simulated entitlements. В успешном прогоне signing
entitlements были `{}`, а `app-Simulated.xcent` содержал
`application-identifier=438S639937.at.serlest.UkrainianCommunity` вместе с
существующими aps/appattest значениями; simulated entitlements были внедрены
линкером. Явной `keychain-access-groups` не было. **Не требовать непустой
codesign plist или keychain-группы как условия PASS.** При этом одна подпись
линкера (`linker-signed`, `Info.plist=not bound`, `Sealed Resources=none`) у
старого unsigned host не равнозначна полноценной подписи app bundle.

Для `test-without-building` заново подготовить SDK `.xctestrun` из новых
products: `TestHostPath` должен разрешаться в новый Debug host, а
`TestBundlePath` — в его `PlugIns`. Сохранить opt-in
`UACFirebaseEmulators=1` в test environment и точный `only-testing`; не
переиспользовать `.xctestrun`, указывающий на старые unsigned products.
Сначала подготовить существующий отдельный localhost/demo fixture. SDK runner
и очисткой fixture владеет координатор; повтор не запускается параллельно UI.

Решающая проверка — завершённый Auth/SDK test, а не только `codesign --verify`.
5 сентября 2026 подписанный temp bundle прошёл actual repository cursor SDK test:
**1 passed / 0 failed / 0 skipped**, без изменения кода приложения. Сводки пакета
1.0.3: `evidence/ios-cursor-sdk-summary.json` и
`evidence/sdk-simulator-entitlements.json`; координатор также подтвердил cleanup
61 документов и Auth. Это локальное Simulator/emulator доказательство, не
проверка device signing, production Auth, APNs или App Attest.
