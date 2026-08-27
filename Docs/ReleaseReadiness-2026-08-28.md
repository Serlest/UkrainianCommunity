# UAC 1.0 — финальная техническая проверка перед App Review

Проверено 28.08.2026, Europe/Vienna. Это технический аудит, не юридическое заключение.
Build 51 загружен в TestFlight, но приложение **не отправлено** на App Review.

## Текущий результат

- Git: ветка `integration/local-product-progress`, build 51; изменения отправлены в GitHub.
- TestFlight 51: `VALID`, `APP_STORE_ELIGIBLE`, `IN_BETA_TESTING`, шифрование `false`.
- Версия 1.0: `PREPARE_FOR_SUBMISSION`, ручной выпуск (`MANUAL`). К версии всё ещё
  прикреплён build 37; build 51 следует выбрать только после финальной проверки.
- Firebase: новые категории выпущены; активный Firestore Rules SHA-256 совпадает
  с репозиторием. `saveOwnerContentDraft` ACTIVE, Node 22, `europe-west3`.
- Публичные privacy, terms, organization-rules, imprint,
  report-illegal-content и support возвращают HTTP 200.

## Что изменено и проверено

1. Добавлены категории новостей «Финансы, налоги и права потребителей» и
   «Безопасность и чрезвычайные ситуации»; категории событий «Экскурсии и
   природа», «Ночная жизнь и вечеринки», «Фестивали и ярмарки» — в приложении,
   локализациях, Rules, Functions, локальном content bridge и автоматизации.
2. Добавлена CI-проверка общего контракта категорий и уникальности индексов.
   Удалён один семантически дублирующийся индекс организаций.
3. Удалены неиспользуемые Firestore Rules helpers; Rules компилируются без
   предупреждений. Полный emulator-набор: 143 passed, 0 failed.
4. Полноразмерные сетевые изображения теперь декодируются с downsampling и
   учитывают реальную стоимость памяти в кэше. Это снижает риск memory pressure,
   зависаний и повторных перерисовок на главном экране.
5. Непредназначенные и не протестированные Mac Designed for iPhone/iPad и
   Vision Pro compatibility отключены; iPhone и iPad остаются поддерживаемыми.
6. Release static analyzer прошёл. iOS unit: 294 passed. Backend unit: 224 passed,
   17 skipped, 0 failed. Полный UI-прогон: 37/38; единственный сбой был на
   автопрокрутке Facebook-поля организации, точный повтор прошёл. Navigation
   stress, оба редактора, комментарии, App Lock, уведомления и accessibility прошли.
7. Архив build 51: bundle `at.serlest.UkrainianCommunity`, версия 1.0,
   `ITSAppUsesNonExemptEncryption=false`, 30 privacy manifests. Подпись валидна.
   UUID app dSYM точно совпадает с UUID бинарника.

## App Store Connect — заполнено

- de-DE и uk: название, подзаголовок, описание, ключевые слова, promo text,
  support URL и privacy URL заполнены.
- 16 снимков: по 4 iPhone 6.7 и 4 iPad 12.9 для каждого языка.
- Категории: Social Networking + News.
- Возрастная декларация заполнена с UGC, social media и messaging/chat.
- Контакты App Review, проверочный аккаунт и notes заполнены; секреты не выводились.
- Бесплатная цена сохранена с базовой территорией Austria.
- What to Test для build 51 сохранён на украинском и немецком.

## Блокеры перед завтрашней отправкой

1. `contentRightsDeclaration` отсутствует. Владелец должен фактически подтвердить
   права/разрешения на сторонний и пользовательский контент.
2. `appAvailabilityV2` отсутствует (`404`). Нужно выбрать и сохранить страны
   распространения. Нельзя угадывать Austria-only или глобальную доступность.
3. App Privacy не доступна публичному API. Нужна живая проверка опубликованной
   анкеты в авторизованном App Store Connect и сверка с финальным build 51.
4. Privacy 2026.12 остаётся черновиком и содержит операторские/юридические решения
   по биометрии, SDK diagnostics, региональным отчётам и срокам хранения.
5. На установленном build 51 выполнить финальный accepted/rejected comment path.
6. После этих проверок прикрепить build 51 к версии 1.0 и только по явной команде
   отправить на App Review. Публичный выпуск оставить ручным.

## dSYM

Собственный dSYM приложения полный и совпадает с бинарником. Xcode сообщил об
отсутствующих dSYM только для предсобранных Firebase/gRPC binary frameworks:
`FirebaseFirestoreInternal`, `absl`, `grpc`, `grpcpp`, `openssl_grpc`. Эти файлы
не генерируются настройкой app target; upload и обработка Apple завершились
успешно. Для устранения предупреждений требуются dSYM от поставщика соответствующих
binary packages, а не изменение `DEBUG_INFORMATION_FORMAT` приложения.
