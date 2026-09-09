# Build 80 — пакет 4 «Мои мероприятия»

Дата: 2026-09-09  
Ветка: `codex/uac-1.1-build80`  
Base перед интеграционными изменениями: `fd58131` (Build 79)

## Изменённые файлы пакета

- `UkrainianCommunity/Views/Profile/ProfileRegistrationsView.swift`
- `UkrainianCommunity/ViewModels/MyRegistrationsViewModel.swift`
- `UkrainianCommunity/Views/Events/EventRegistrationSection.swift`
- `Docs/Fix80-4-handoff.md`

## Исправлено

1. Удалена мутация общего `EventsViewModel` из `RegisteredEventDetailContainer.init`.
   - Container больше не вызывает `cacheEvent` во время построения SwiftUI destination.
   - Переданная общая модель оформлена как `@ObservedObject`, а не как принадлежащий container `@StateObject`.
   - Immutable event seed кешируется только после появления destination и только если ID отсутствует. Это сохраняет offline-доступ к уже загруженной строке; при наличии общего события оно не перезаписывается stale seed.
   - Если seed недоступен visibility policy, detail загружает событие существующим `EventDetailView` lifecycle через repository.
   - Это устраняет подтверждённый цикл render/layout при открытии Profile → My Events.

2. Добавлена точечная очистка строки регистрации после owner cancel/delete.
   - `EventDetailView.onEventDeleted` теперь вызывает `MyRegistrationsViewModel.removeRegistrationEvent(id:)`.
   - Метод удаляет строку и отменяет/очищает возможную pending cancellation для этого event ID.
   - Остальные события не удаляются по отсутствию в потенциально частично загруженном общем feed.

3. Сохранена возможность отменить существующую регистрацию после смены participation mode.
   - Если `registrationState == .registered`, detail показывает Cancel Registration независимо от текущего `.none`/external/tickets/in-app mode.
   - Для `.none` строка «регистрация не требуется» не показывается одновременно с действующей регистрацией.
   - После отмены обычный action нового participation mode снова становится доступен через существующий state update.

## Уже было исправлено / не дублировалось

- `registrationButton(for:)` уже выбирал register/cancel по `registrationState`.
- Registration management card уже остаётся доступной менеджеру при `registeredCount > 0`, даже если текущий mode больше не требует in-app registration.
- Backend callable и editor validation не изменялись: пакет ограничен iOS lifecycle/UI.

## Self-review

- Проверено чтением diff: в `View.init` больше нет observable mutation; внешний observable не объявляется `@StateObject`.
- Delete callback удаляет только известный event ID и не трактует частичный shared feed как authoritative полный список.
- Registration action сохраняет существующие confirmation, pending-disable, error mapping, analytics и reminder flows.
- `git diff --check` пройден до подготовки handoff.
- По правилу координатора tests/builds/Simulator/linters не запускались.

## Координатору для общей проверки

Минимальные regression checks:

1. Profile → My Events стабилизируется и открывает detail без роста layout/CPU.
2. Cancel Registration обновляет detail и удаляет строку из My Events; после back/refresh/relaunch строка не возвращается.
3. Owner cancel/delete из detail закрывает detail и удаляет только соответствующую строку.
4. Event с существующей регистрацией после mode change на none/external/tickets всё ещё показывает Cancel Registration; после cancel показывает action нового mode.
5. Account switch во время pending cancellation не переносит state между пользователями.

## Remaining dependencies

- Новые localization keys/text не нужны.
- Изменения `Localizable.xcstrings`, `AppStrings.swift` и `project.pbxproj` для пакета 4 не требуются.
- Полный production invariant смены participation mode при `registeredCount > 0` остаётся отдельным backend/editor решением; этот пакет гарантирует доступность cancel для уже существующего iOS registration marker.
- Исправление Accessibility XXXL из аудита D04-06 не входит в этот узкий lifecycle-пакет и требует отдельного layout-прохода.
