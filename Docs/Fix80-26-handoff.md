# Fix80-26 — Баннеры

Дата: 2026-09-09  
Base: `fd58131d2c7c7c5f50b5d354473b91d271990565`  
Статус: product fixes внесены; сборки и тесты не запускались по границам делегации.

## Changed files

- `UkrainianCommunity/ViewModels/Featured/FeaturedBannerManagementViewModel.swift`
- `UkrainianCommunity/ViewModels/Featured/FeaturedBannerListViewModel.swift`
- `UkrainianCommunity/Repositories/Featured/FeaturedBannerRepository.swift`
- `UkrainianCommunity/Repositories/Featured/FirestoreFeaturedBannerRepository.swift`
- `UkrainianCommunity/Repositories/Featured/MockFeaturedBannerRepository.swift`
- `functions/src/featured/featuredBannerMutations.ts`
- `Docs/Fix80-26-handoff.md`

## Fixed

1. **Toggle → Edit сохраняет DE.** Локальная реконструкция `FeaturedBanner.settingActive` теперь переносит `localizations`, поэтому немедленный Edit после toggle больше не получает пустые немецкие поля.
2. **Starts/ends обновляются без 30-минутного ожидания.** Repository сохраняет в memory cache все подходящие active-кандидаты, включая scheduled и недавно expired документы. `FeaturedBannerListViewModel` фильтрует их относительно текущего времени и планирует локальное обновление на ближайшем `startsAt` или `endsAt`. На границе сеть не нужна; если cache уже протух, выполняется обычная загрузка.
3. **Новые stale targets блокируются сервером.** `saveFeaturedBanner` в той же Firestore transaction читает news/event/organization target и требует существующий документ с `moderationStatus == approved`. `setFeaturedBannerActive` выполняет ту же проверку перед активацией. Это совпадает с текущим iOS picker contract: его loaders уже предлагают только approved targets. Content deletion для news/events также уже деактивирует связанные баннеры.

## Already fixed outside this package

`ScreenChromeComponents.swift` уже содержит shared shell fix 2: заголовок management/editor входит в вертикальный scroll при Accessibility Dynamic Type, а нижнее editor action занимает реальное safe-area место. Поэтому отдельная правка `FeaturedBannerManagementRow` не внесена. Нужен runtime rerun длинной DE строки после объединения shared shell fix.

## Coordinator-owned callback request

`ContentView.swift` не редактировался. В `handleFeaturedBannerTap`, ветка `.openOrganization(id:)` сейчас делает silent `return`, если `organizationsViewModel.resolveOrganization(id:)` вернул `nil`.

Минимальная правка координатора без нового API/ключей:

```swift
case let .openOrganization(id):
    Task {
        guard let organization = await organizationsViewModel.resolveOrganization(id: id) else {
            showNotificationRouteUnavailable()
            return
        }
        selectTabIfNeeded(.organizations)
        organizationsNavigationPath = [OrganizationNavigationRoute(organizationID: organization.id)]
    }
```

Это переиспользует уже существующий alert state и `AppStrings.NotificationInbox.destinationUnavailableMessage`; новый localization key не требуется. Если coordinator хочет featured-specific текст, тогда отдельно нужны новые UK/DE keys в coordinator-owned `AppStrings`/catalog.

## Deliberately not changed

- Optimistic concurrency/versioning: текущий iOS/callable contract не содержит expected version. Добавление её затронет save/toggle/delete request DTO и серверную совместимость; для этого нужен отдельный контрактный пакет.
- Organization deletion cleanup: текущий `contentDeletion.ts` очищает featured targets для news/events, но organization path не вызывает аналогичную очистку. Файл вне разрешённой Functions-области; runtime fallback выше всё равно нужен для уже существующих stale данных.
- Shared shell, `ContentView`, localization catalog, project file, tests и Rules не изменялись.

## Dependencies and remaining verification

- Требуется deployment `saveFeaturedBanner` и `setFeaturedBannerActive` вместе из одного Functions build; в этом пакете deploy не выполнялся.
- Проверить build/typecheck и существующие featured mutation tests. Добавить/обновить coverage для approved, missing и non-approved targets, а также slash-containing target ID.
- Повторить runtime: toggle → immediate Edit с DE; startsAt/endsAt без pull-to-refresh; длинная DE строка при dark + Accessibility XXXL после shared shell merge; missing organization callback; create/update/activate с approved и stale targets.
- Проверить Home, Events и Organizations, поскольку они используют общий `FeaturedBannerListViewModel` и cache.

## Release

**RELEASE: YES — пакет Fix80-26 закончен в разрешённых границах и готов координатору для объединения и общей проверки.**
