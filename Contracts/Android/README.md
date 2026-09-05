# Общие контракты UAC для Android

Снимок исходников от 2026-09-02, HEAD `c9c2a692cacc190318dbf6b38b93a276d497da19`. Это реестр существующего контракта, не новая серверная схема и не миграция production.

## Где искать точное поле или операцию

`source-catalog.json` содержит:

| Раздел | Содержимое |
| --- | --- |
| sources | 405 исходных файлов с SHA-256: Swift, backend, Rules, indexes; без пользовательских данных/секретов |
| swiftDeclarations | 2054 объявления типов/полей/enum cases, включая DTO и callable requests/responses; `?` означает optional в модели, не автоматически необязательное поле записи |
| repositoryOperations | 1586 строк методов: протоколы, live/mock реализации, сервисы; это не число функций продукта |
| wireMappings | 1362 точных строк чтения/записи wire keys, collection/doc, where/order/limit/cursor и callable dispatch |
| serverTypes | 240 полных TypeScript interfaces/type aliases с required/optional полями |
| endpoints | 114 declarations callable/HTTP/trigger/scheduler и фабрик, включая тело handler/config вызова; не все доступны клиенту |
| rules / indexes | 452 определения функций/путей/allow плюс полный существующий index manifest |

Каждая запись указывает путь и строку. Для wire-контракта приоритет: **серверный parser/Rules → serialization/query → DTO → UI model**. Нельзя напрямую сериализовать весь Swift DTO: часть полей (`likeState`, `isBookmarked`, comments) вычисляется из других документов. Вытяжка строк — навигационный индекс, не формально сгенерированная JSON Schema; сложные guards и defaults читать в указанном исходнике. Проверка drift: из Android `node scripts/catalog-contracts.mjs --check`. Обновлять снимок только после объяснённого review изменившихся контрактов.

## Хранилища и обязательность

| Документ/группа | Wire shape и важные ограничения | Авторитетный источник |
| --- | --- | --- |
| users/{uid} | identity/displayName/fullName/email/city/bio/avatarURL/telegramUsername/selectedFederalState; globalRole/accountStatus/blockState/requiresMultiFactorAuth; timestamps/legal receipts. Privileged fields не self-write | UserDTO, UserProfileService, Rules safe user create/update |
| publicProfiles/{uid} | Только displayName/avatarURL/city/federalState/updatedAt; не заменять приватным users read | PublicUserProfile, publicProfiles Rules |
| news/{id} | Reader требует title/body/createdAt/updatedAt/moderationStatus; summary → subtitle fallback; publishedAt → createdAt fallback. sourceType/organizationId, schemaVersion/localizations, regionScope/federalState/city, category/additionalCategories/tags, imageURL/mediaMetadata/externalAction, schedule/counters | FirestoreNewsRepository.makeNewsPostDTO; validNewsDocument |
| events/{id} | title/summary/details; source/author/location/contact; Timestamp startDate/endDate/occurrences/scheduledAt; participationMode/requiresRegistration/externalAction, price/pricing/capacity/count; cancellationState/moderationStatus | EventDTO, FirestoreEventRepository.makeEventDTO; validEventDocument |
| organizations/{id} | name/description and localized detail, ownerId/adminIds/moderatorIds, submittedByUserId/review fields, system-org marker, region/category, directoryProfile, image/photos/contact/counters | OrganizationDTO, makeOrganizationDTO, safeOrganizationCreate/update |
| organizations/{id}/photos/{photoId} | imageURL/uploadedBy/createdAt обязательны у reader; caption optional; callable mutation, media path separate | FirestoreOrganizationPhotoRepository, organizationPhotoMutations |
| likes/{id} | actor + one content reference; immutable action proof/deterministic identity, counter derived on backend | likeDocumentID helpers, validLikeCreate, counters/aggregation |
| registrations/{id} | eventId/userId and server registration state; writes только callable, count transactional | events/eventRegistration.ts, registrations Rules |
| news/events/organizations/{id}/comments/{commentId} | parentType/parentId/authorId/authorName/authorPhotoURL/text/createdAt/updatedAt/moderationStatus/isDeleted | saveComment; direct create/update denied |
| users/{uid}/newsBookmarks,eventBookmarks,organizationBookmarks | Content IDs + timestamps; own-only write | Bookmarks helpers + Rules |
| likes/organization_follow_{organizationId}_{uid} | id/subscribedOrganizationId/userId/createdAt; reverse listing по subscribedOrganizationId, own listing по userId; scoped Rules и publicProfiles для идентичностей | FirestoreOrganizationRepository.subscribeOrganization/subscriptionDocumentID + validOrganizationSubscriptionCreate |
| users/{uid}/newsViews,eventViews,recentViews,activityLog | per-user source IDs/type/date; immutable view proof vs mutable recent entry; no manual counter writes | repository view helpers + Rules |
| users/{uid}/notificationInbox | id/type/title/message/severity/sourceType/sourceId/createdAt/read/archive/delete/popup timestamps/actionType/actionTargetId/metadata; privateDelivery server-only | NotificationModels, notificationPayloads, inbox repository |
| users/{uid}/notificationPushTokens/{sha256} | id/token/registrationType/platform/deviceName/appVersion/createdAt/updatedAt; `token` field holds token OR FID according to type | pushRegistrations + validNotificationPushTokenWrite |
| users/{uid}/notificationPreferences/settings | notificationsEnabled=false, eventRemindersEnabled=true, reminderLeadMinutes=60 defaults | NotificationPreferences + Rules |
| feedback/{id}/messages/{id} | question/suggestion/bug/report; subject/message/status/user; replies, senderRole, unread; reportContext/dsaCase server owned | FeedbackDTO/MessageDTO, feedback Rules |
| dsaCases, users/{uid}/dsaStatements | Restricted case evidence/decision/appeal; не читать raw dsaCases клиентом | dsaCases.ts, legal evidence callables |
| legalDocuments и user acceptances | active/versioned/draft body and timestamps, document type/receipt/version/appVersion/locale/acceptedFromPlatform | LegalDocument, legalDocuments.ts, organizationRulesAcceptance.ts |
| users/{uid}/contentPlanningDrafts/{draftId} | schemaVersion/owner/kind/state/sourceReferences/verificationNotes/missingFields/newsDraft/eventDraft/generatedImage; lease/outcome/history/retention fields | OwnerContentDraft + ownerContentDrafts.ts |
| featuredBanners | localizations/actions/audience/region/start/end/active/order/media/accessibility; actionTargetID spelling differs from inbox actionTargetId | FeaturedBanner, featuredBannerMutations |
| appConfig/donation | Public read, owner-controlled configuration | DonationConfig, donation Rules |
| systemLogs/auditLogs | Actor/target/action/visibility/review/retention, sanitization; backend-owned sensitive fields | SystemLog models, clientDiagnostics, Rules |
| analytics* | Consent receipts/action proofs/rate limits/rollups/source states; owner-readable aggregates, private raw activity denied | AnalyticsFirestoreSchema, analytics/*.ts, Rules |

## Raw enum значения

Уточнение 3B от 2026-09-03: первоначальное описание `users/{uid}/organizationSubscriptions` было ошибкой сводного документа. Реальные iOS transactions и Rules используют детерминированные follow-документы в `likes`; схема backend не менялась. Аналогично каждую summary-строку перепроверять по source of truth перед записью.

- Языки: `uk`, `de`; интерфейс по умолчанию de, если язык устройства не uk. Localized content: requested → uk → имеющийся fallback; не сохранять перевод поверх оригинала. Для детерминированности неизвестный третий locale требует явного теста: Swift `values.first` не следует переносить как гарантированный порядок.
- globalRole: `owner`, `admin`, `user`; legacy `topAdmin` не elevated. Organization role: `communityOwner`, `communityAdmin`, `communityModerator`, `member`; authoritative роль из organization document, не cached memberships.
- accountStatus/blockState: `active`, `warned`, `suspendedUntil`, `bannedPermanent`, `deactivated`; legacy aliases читаются, но не выдаются как новые elevated значения.
- Moderation: `draft`, `pendingReview`, `needsRevision`, `approved`, `rejected`, `archived`. Не каждый тип допускает все состояния при записи. Внутренний `retentionDeleting` — серверный lifecycle, не пункт editor.
- RegionScope: `austria`, `federalState`, `city`; federalState: `burgenland`, `kaernten`, `niederoesterreich`, `oberoesterreich`, `salzburg`, `steiermark`, `tirol`, `vorarlberg`, `wien`.
- NewsCategory: `news`, `event`, `lawAndDocuments`, `benefitsAndSupport`, `financeTaxesAndConsumerRights`, `health`, `safetyAndEmergencies`, `work`, `education`, `housing`, `transport`, `communityAndIntegration`, `culture`, `other`.
- EventCategory: `unspecified` (legacy/display fallback), `meetups`, `training`, `culture`, `education`, `childrenAndFamily`, `sportsAndWellness`, `excursionsAndNature`, `music`, `nightlifeAndParties`, `foodAndMarket`, `festivalsAndFairs`, `businessAndNetworking`, `volunteering`, `supportAndIntegration`, `celebration`, `saleAndPromotion`, `other`. Дополнительных категорий максимум 2.
- EventAudience: `everyone`, `families`, `children`, `teens`, `adults`, `seniors`. Participation: `none`, `inAppRegistration`, `externalRegistration`, `externalTickets`. Occurrence status: `scheduled`, `cancelled`. Registration: raw cases из ContentModels, не HTTP/error status.
- OrganizationProfileKind: `community`, `business`, `restaurant`, `specialist`, `institution`, `mediaProject`; service modes `inStore`, `pickup`, `delivery`, `online`, `onSite`. `regularHours`: monday…sunday → `HH:mm-HH:mm` или `closed`; максимум 8 services, 2 secondary categories.
- Planning kind `news`/`event`; states `readyForReview`, `needsAttention`, `scheduled`, `publishing`, `failed`, `completed`, `archived`; outcomes `approved`, `pendingReview`, `scheduled`, `archived`, `unresolved`.
- Остальные enum, включая pricing, system log/analytics/legal/feedback/report/banners: точные cases в swiftDeclarations и serverTypes; новые unknown значения не должны расширять права или запускать внешние действия.

## Даты, локализации, числовые поля

Firestore использует Timestamp (seconds + nanoseconds), не строку UI. В Kotlin сохранять instant/precision для cursor; строковые ISO-8601 даты callable response (например acceptedAt/decidedAt) декодировать отдельно. Write timestamps — serverTimestamp где требует контракт. Отсутствие, null и FieldValue.delete не взаимозаменяемы.

Уточнение пакета 2: сам Firestore хранит время до микросекунд, отбрасывая более мелкую часть. Это подтверждено локальным read-back `123456789 → 123456000` nanoseconds и [официальным контрактом типов](https://firebase.google.com/docs/firestore/manage-data/data-types). Android сохраняет полученные seconds/nanoseconds без дополнительного округления до миллисекунд; общий fixture использует `.123456Z`, а отдельный codec/cursor unit test проверяет все 9 знаков.

News localization `{title,subtitle,body}`, event `{title,summary,details}`, org `{name,shortDescription,fullDescription,services,...}`. Wire root news использует `summary`, тогда как nested localized news — `subtitle`. mediaMetadata `{caption?,alternativeText?,credit?}`; externalAction `{title?,url}` только корректный HTTPS URL.

В текущих Event/Occurrence нет обязательного IANA timezone поля: start/end — абсолютные даты, UI местами пользуется Calendar.current. Analytics явно использует `Europe/Vienna`. Android не должен выдумывать persisted timezone/UTC offsets; до editor-пакета зафиксировать display policy и тесты DST Vienna/смены зоны устройства/all-day. Это открытое продуктовое уточнение, не основание менять backend сейчас.

Firestore integer читается как Long, дробные price/coordinates — Number/Double; проверить границы и преобразования, не усекать Timestamp. Currency code нормализуется uppercase, default EUR. Count не вычислять на клиенте с последующим overwrite.

## Запросы и пагинация (из live repositories, не mock)

| Список | Фильтры/порядок/cursor |
| --- | --- |
| News | sourceType=organization, moderationStatus=approved; publishedAt DESC, documentID DESC; cursor обоих полей; limit+1 |
| Events upcoming | sourceType=organization, approved, endDate>=now; endDate ASC, documentID ASC; cursor обоих полей; bounded limit+1 |
| Events recent past | endDate<now, endDate DESC + documentID DESC, approved organization source |
| Organizations | approved; createdAt DESC + documentID DESC; limit+1 |
| Region-scoped pages | OR regionScope=austria / federalState=selected; не заменять только федеральным фильтром |
| Planning | scheduled section ascending scheduled date; другие sections history/update date как repository; states filter и documentID tie-break |
| Comments | isDeleted=false, createdAt DESC, limit 100; realtime listener; cancellation/account switch |

Все оставшиеся query формы и chunking ID-list находятся в wireMappings. Cursor строится по последнему backend-документу, не по отсортированному/отфильтрованному UI. Mock events сортируют startDate, live pagination — endDate: переносить live-контракт, не mock-различие. Emulator не доказывает наличие composite indexes в cloud; существующий manifest не деплоился.

## Callable payloads и ошибки

Регион `europe-west3`. Использовать callable SDK envelope, не произвольный REST POST; auth/App Check middleware отдельны от request.data. Полные request/response формы и handler для каждой операции — serverTypes/endpoints + CloudFunctionsClient в swiftDeclarations. Примеры групп:

| Группа | Вход / важный результат |
| --- | --- |
| org role | organizationId, targetUserId, reason? → previousRole/newRole; transfer имеет отдельный response |
| org review | organizationId + message/reason по операции → статус/receipt, transactional review |
| user moderation | targetUserId, reason, duration/expiry по parser → status; self/owner/peer admin gates |
| registration | eventId, action proof при register → eventId/registrationState/registeredCount/didChange |
| legal | documentType, version, appVersion?, locale?, acceptedFromPlatform → acceptedAt; org rules отдельный request |
| push delete | userId, identifier, registrationType (`fid`/`token`) → deletedCount; never accept another uid |
| content cover | organizationId/content type/image payload по ContentCoverUploadRequest; validation/base64/JPEG limits на сервере |
| planning | draftId, attemptId → leaseId/contentId/expiresAt/already-exists; finalize/fail обязаны использовать актуальный lease |
| DSA | reportId, outcome, facts/basis/scope/duration/redress, humanReviewConfirmed; appeal reason, receipt deadlines |

Базовые категории: network, permissionDenied, validationFailed, notFound, unknown. Firebase codes различать: unauthenticated, permission-denied, invalid-argument, not-found, failed-precondition, already-exists, resource-exhausted, unavailable, deadline-exceeded, aborted. Business registration ошибки: full/registrationNotRequired/eventCancelled/eventPast. Не повторять мутации слепо после timeout; сначала idempotency/read-back. Не выдавать denied/MFA/invalid data за бесконечную загрузку или успешный пустой список.

Уточнение 3C от 2026-09-03: `saveComment` принимает только `parentType`, `parentId`, `text` и создаёт новый документ; существующего own-delete callable нет. `updateNewsComment`/`updateEventComment`/`updateOrganizationComment` в реальных Swift repositories явно бросают permissionDenied. Direct delete разрешён Rules только через соответствующий `canModerate*Comment`, а не всем авторам. Android не должен показывать неработающие own-edit/delete или выдумывать такой endpoint. Создание неидемпотентно: после неопределённого timeout не повторять автоматически.

## Уведомления и точные переходы

Типы: organizationRequestSubmitted, commentAdded, contentModerationChanged, eventParticipationChanged, feedbackSubmitted, feedbackReply, organizationRequestApproved, organizationRequestNeedsRevision, organizationRequestRejected, organizationRequestCleanupWarning, organizationRequestExpired, accountStatusChanged, legalDocumentsUpdated, organizationNewsPublished, organizationEventPublished, roleChanged, organizationRoleAssigned, organizationRoleRemoved, reportReviewed, eventUpdated, eventCancelled, eventRegistrationConfirmed, systemAnnouncement, contentDraftReady; unknown безопасно игнорировать.

Payload: notificationId/type/sourceType/sourceId/actionType/actionTargetId/route/routeTargetId. Target priority: routeTargetId → actionTargetId → sourceId (trim/nonempty). Source types: feedback/organization/account/legal/profile/event/system/contentDraft.

| Action | Экран и safety gate |
| --- | --- |
| openNews / openEvent / openOrganization | Fetch detail по target, проверить текущие права/удаление; не доверять push snapshot |
| openOrganizationRequest | Submitted → reviewer только при праве review; approved → organization; revision/rejected/expiry → applicant management |
| openFeedback / openDsaStatement | Своя/доступная conversation или statement; отсутствующий ID не угадывать |
| openLegalDocuments / openProfile | Соответствующий экран после auth/startup gate |
| openContentPlanning | Owner-only planning с optional draftId; не давать права из payload |
| openURL | Только проверенный HTTPS, пользовательский переход; unknown/unsafe URL не открывать |
| none / systemAnnouncement | Inbox/detail без скрытой мутации |

Inbox/read/unread/archive/delete и app badge — отдельны от подтверждения FCM. Push acceptance не доказывает показ. Protected notifications повторно проверяют role scope; deleted/missing target требует понятного состояния.
