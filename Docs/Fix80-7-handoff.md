# Fix80-7 — Recent views handoff

## Scope

Base: `fd58131` (Build 79). Изменены только:

- `UkrainianCommunity/Services/RecentViewsService.swift`
- `UkrainianCommunity/Views/Profile/ProfileRecentViewsView.swift`

Никакие build, test, lint, Simulator, install, commit, push или deploy не выполнялись. Retention и удаление истории не менялись.

## Исправления

1. **Stale порядок после detail → back.** Экран теперь принудительно обновляет recent views при каждом появлении. После успешной записи recorder публикует typed event для того же Firebase UID, а общий `RecentViewsViewModel` немедленно upsert-ит canonical row и пересортировывает её по `viewedAt`. Это закрывает окно, когда возврат происходил раньше следующего fetch.
2. **Late A→B response.** Refresh/delete/clear привязаны к generation и loaded UID. Ответ старой сессии больше не может заменить items/error новой сессии. Reset очищает pending UI flags.
3. **Organization visibility.** `RecentViewItem` получил backward-compatible optional `organizationID`. Producer записывает stable source organization ID для news/event и item ID для organization. Новый snapshot фильтруется через актуальную `ContentVisibilityPolicy`, включая `allowsOrganizationContent` во время blocklist verification. Counts используют только видимые rows.
4. **Legacy snapshots.** Старые news/event rows без `organizationID` остаются private historical entries; организация не угадывается по title. Их detail resolver продолжает применять общую visibility policy и не открывает закрытый target. Organization row уже имеет stable organization ID в `itemId`.
5. **Accessibility Dynamic Type.** На accessibility sizes row переходит на вертикальную компоновку, снимает line limits с title/subtitle/date и сохраняет отдельную delete action. Общий tab shell не менялся.

## Coordinator dependency: Firestore Rules

До объединения producer hunk требуется разрешить optional nullable `organizationID`. Точный минимальный hunk для coordinator-owned `Firebase/firestore.rules`:

```diff
 function recentViewFields() {
-  return ['itemId', 'itemType', 'title', 'subtitle', 'imageURL', 'viewedAt'];
+  return ['itemId', 'itemType', 'title', 'subtitle', 'imageURL', 'organizationID', 'viewedAt'];
 }

 function safeRecentViewWrite(uid, recentViewId) {
   ...
   && (!('imageURL' in request.resource.data) || request.resource.data.imageURL is string || request.resource.data.imageURL == null)
+  && (!('organizationID' in request.resource.data) || request.resource.data.organizationID is string || request.resource.data.organizationID == null)
   && request.resource.data.viewedAt is timestamp
   ...
 }
```

Если Rules hunk не входит в интеграцию, строки с новым полем будут отклоняться текущим `hasOnly(recentViewFields())`; в таком состоянии Swift producer hunk нельзя выпускать.

## Localization / dependencies

- UK keys: новых нет.
- DE keys: новых нет.
- EN keys: новых нет.
- Dependencies: новых пакетов и project references нет; используется уже импортированный `Combine`.
- Общие coordinator-owned `ContentView`, `ProfileViews`, routing, `AppStrings`, `Localizable.xcstrings` и project file не изменялись.

## Единый проверочный сценарий

1. Войти как A; blocklist verification должен быть successful и содержать blocked org B.
2. Открыть history с independent news, news/event от B, organization B, legacy news без `organizationID` и доступной organization C.
3. Проверить: новые B rows и organization B отсутствуют; counts их не включают; legacy row остаётся historical, но её detail не раскрывает blocked target; independent и C rows открываются.
4. Открыть старую доступную C row, дождаться detail load и вернуться Back. Без pull-to-refresh она должна стать первой, timestamp должен обновиться, дубля быть не должно.
5. Пока delayed fetch A удерживается, сменить account на B, завершить B fetch, затем A fetch. В UI остаются только B rows и B error state не заменяется ответом A.
6. Повторить шаг 4 при offline queued write и после reconnect/read-back: одна canonical row, новый порядок после подтверждённой записи.
7. UK и DE, light/dark, Accessibility XXXL: title/subtitle/date читаются в вертикальной row, list прокручивается до последней строки, row link и отдельная delete action hit-testable выше tab bar.
8. Проверить delete/clear success и failure: существующая история сохраняется при error; смена account во время pending mutation не меняет rows нового account.

## Review notes

- Historical snapshot остаётся UX policy, не классифицируется как privacy leak.
- Один screenshot с tab bar overlap не доказывает недостижимость нижнего контента; шаг 7 требует отдельного scroll/hit-test.
- Строгая server-side очистка deleted organization, target validation и retention policy находятся вне Fix80-7.
