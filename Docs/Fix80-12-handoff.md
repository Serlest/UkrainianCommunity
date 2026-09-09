# Fix80 package 12 — Уведомления

Base: `fd58131d2c7c7c5f50b5d354473b91d271990565`.

## Scope and changed files

Изменены только четыре notification source-файла и этот handoff:

1. `UkrainianCommunity/ViewModels/NotificationInboxViewModel.swift`
2. `UkrainianCommunity/Services/Notifications/NotificationPopupCoordinatorService.swift`
3. `UkrainianCommunity/Views/Profile/NotificationInboxView.swift`
4. `UkrainianCommunity/Views/Profile/NotificationDetailView.swift`
5. `Docs/Fix80-12-handoff.md`

`ContentView`, `ProfileViews`, route handlers, shared screen chrome, feedback/backend files, `AppStrings`, localization catalog и project file не менялись.

## Исправлено

- Realtime listener после transient error делает fallback fetch и затем автоматически пересоздаётся с exponential backoff 1/2/4/8/16/30 s. Старые callbacks отсечены generation + session guards. Ручной Retry после ошибки также немедленно поднимает listener, если он отсутствует.
- Inbox больше не ограничен недоступными пользователю 50 строками: при появлении последней строки `LazyVStack` расширяет live query по 50 элементов и показывает progress. Логика работает и в Unread filter, где последняя видимая строка может отличаться от последней All.
- Первый inbox snapshot теперь ставит в очередь уже ожидающие eligible critical notifications, а не только помечает их seen.
- Critical popup остаётся открытым до успешной записи receipt. При ошибке сохраняются active notification и видимое существующее `updateFailed`; повторное нажатие является retry. Для Open сначала пишется read receipt, затем popup receipt, чтобы промежуточный listener snapshot не закрыл окно.
- `dismissActiveNotification(markRead:)` теперь возвращает `Bool`: `true` только после успешных receipts. Это подготовлено для условной маршрутизации в `ContentView`.
- Cached-list listener/load-more error теперь показывает существующую кнопку Retry, а не только inline message.
- Severity вынесена из одной горизонтальной строки с title. Длинный title получает доступную ширину и сохраняет полный вертикальный размер.
- В detail при accessibility Dynamic Type icon расположен над title; текст больше не теряет ширину из-за `Label`.

## Уже было исправлено в Build79 и не менялось

- Смена/logout session очищает inbox и badge; старые callbacks отсечены `sessionVersion`.
- Badge получает отдельный whole-inbox aggregation и не обнуляется при неудачном refresh.
- Read/unread/archive/delete/clear сохраняют локальную запись и сверяют session после async write.
- Inbox/detail уже имеют локализованные действия и accessibility identifiers.

## Обязательная зависимость координатора

`ContentView` входит в чужое владение и не менялся. В callback popup Open нужно использовать новый результат, чтобы destination не открывался при неудачном receipt:

```swift
Task {
    if await notificationPopupCoordinator.dismissActiveNotification(markRead: true) {
        handleNotificationTap(notification)
    }
}
```

Dismiss/OK может игнорировать возвращаемое значение: при ошибке coordinator сам оставляет popup и показывает `updateFailed`.

## Localization/AppStrings

Новых ключей и текстов не требуется. Использованы существующие `AppStrings.Action.retry`, `AppStrings.Common.loading` и `AppStrings.NotificationPopup.updateFailed`.

## Проверки для общего этапа

В этом пакете по запрету не запускались tests/build/Simulator/linters/dependencies.

Минимальная общая валидация:

- Compile Swift target после объединения с текущими изменениями `ContentView` и shared shell.
- Unit: listener error → fallback snapshot → delayed realtime callback после backoff; manual Retry немедленно пересоздаёт listener; logout отменяет pending reconnect; old-generation callback не меняет новый listener.
- Unit/UI: 55 notifications; scroll до последней строки запускает limit 100 и раскрывает IDs 51–55; повторный page размер меньше limit прекращает loading.
- Unit: initial eligible critical показывается; ineligible/expired/receipt-confirmed не показываются; receipt failure сохраняет active+error; retry success закрывает; concurrent tap не дублирует writes.
- UI: DE/UK long title в standard и AX XXXL для row/detail; проверить отсутствие узкой колонки и доступность menu/destination.
- Regression: read/unread/archive/delete/clear, whole-inbox badge, session switch, popup queue order.

## Остаточные ограничения

- Расширение live query идёт limit 50→100→150, а не Firestore cursor pages. Это сохраняет realtime для уже загруженного диапазона и решает недоступность старших записей, но очень большой inbox увеличивает размер listener snapshot. Если понадобится bounded-memory архив, потребуется отдельный repository cursor API и согласованная стратегия live head + paged history.
- Popup Open не должен переходить к destination при receipt failure; окончательное условие находится в coordinator-owned `ContentView`, как указано выше.
- URL/legal/feedback route fixes принадлежат координатору и намеренно не затронуты.
