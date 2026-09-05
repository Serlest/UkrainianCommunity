# Android — визуальный эталон iPhone build 65

Эталон — текущий iOS source build65. Функциональные сценарии доводятся первыми; этот документ удерживает конкретный дизайн и отделяет уже проверенные компоненты от оставшейся работы.

## Проверенный прогресс 2026-09-03 03:27 UTC

Оригинальные logo/background/icon/startAnimation импортированы byte-identical из текущего iOS bundle, hashes в Android/BRAND_ASSETS.md. Единые theme/colors/type/insets, four-tab bottom navigation с независимыми историями, крупный logo-header и одноразовый startup gate уже интегрированы. Actual startup5 + native original-video codec/lifecycle1 PASS; chrome large-text3 и Main landscape/200%/IME/unsaved-draft1 PASS. Пять верхних вкладок больше не являются текущим UI.

Публичная compact ContentCard повторяет iOS HomeFeedCard:72dp thumbnail, green News/blue Event/purple Organization chip, title/summary/metadata/date badge; при крупном тексте переходит в вертикальный layout без усечения заголовка. Actual DE/UK × light/dark × normal/200% card matrix4 PASS на664 и745. Screenshots745 с корректными safe insets/gaps проверены; отдельный green-on-fill numeric contrast test PASS. Декоративный original background не заменяет непрозрачные читаемые карточки. Snapshot745 full Browse4/Personal1 regressions PASS.

Осталось: hero/banner и компактное расположение фильтров на Home; detail/forms/profile rows; authentic dark/uk iOS references; полная screen matrix, ручной accessibility и performance. Проверенные card screenshots не означают полного визуального паритета приложения.

## Проверено по исходникам

- `UkrainianCommunity/Views/ContentView.swift:495`: четыре основных вкладки **Home / Events / Organizations / Profile**. News открываются из Home/публичных маршрутов, не отдельная пятая главная вкладка. У каждой вкладки собственный NavigationStack; текущая Android navigation сохраняет эту структуру.
- `UkrainianCommunity/Utilities/AppTheme.swift`: основной brand fill RGB(0.10,0.26,0.56), примерно `#1A428F`; поддерживающий жёлтый RGB(0.93,0.76,0.23), примерно `#EDC23B`; destructive RGB(0.72,0.14,0.18). Текстовые foreground отдельно адаптируются к dark/increased contrast. Не переносить декоративный цвет в мелкий текст без контрастной проверки.
- Фон — спокойный grouped background; карточки и control surfaces отдельные. Glass имеет непрозрачный доступный fallback; не имитировать blur ценой читаемости/производительности.
- Основной горизонтальный отступ16, расстояние секций16; карточка padding18, detail20, читаемая ширина760, feed1040; карточки адаптивно320–500.
- Радиусы: card17, content plane26, hero22, image16, chip14; строка14, compact10, control12. Header logo160×56. Hero146, detail image220 (news hero260). Feed thumbnail58/radius13, events thumbnail62, organizations64.
- Типографика семантическая и масштабируемая: screen title bold title2, section header semibold title3, card headline semibold, body/system; detail title bold title, body callout +3 line spacing. Нельзя фиксировать высоты строк так, чтобы обрезать200% text. Android touch target проверять отдельно по платформенным требованиям, а не уменьшать до iOS44 автоматически.
- Hero gradient: primary92% → destructive82% → support68%, topLeading→bottomTrailing; не заменять произвольным сине-жёлтым градиентом. Нужны реальные visual comparisons перед применением.
- Брендовые оригиналы найдены на Desktop и в iOS bundle. logo2 совпадает по hash; logo1/startAnimation отличаются. Для импорта — версии current iOS build65; Desktop не перезаписывать.

## Порядок визуального пакета после функций

### Эталон снят на Mac, 2026-09-03 00:21–00:30 UTC

Изолированный Debug Simulator build текущего iOS source65, `-ui-testing`, guest mock content, de/light. Проверены снимки `outputs/ios-build65-reference-{home,events,organizations,profile-guest,login,news-detail}-de.jpg`. Фактический фон имеет мягкие брендовые геометрические плоскости; четыре вкладки в нижней плавающей панели; крупный logo-header, hero и горизонтальные компактные фильтры; на Home компактные карточки вместо больших форм. Отсутствующие demo remote hero изображения имеют fallback — это не причина заменять оригинальные assets. Для экономии ресурсов собственный iOS Simulator остановлен после снятия, его данные не стирались. Dark/uk/увеличенный шрифт, authenticated profile/inbox и полный Android comparison ещё не сняты.

1. Снять эталонные iOS light/dark Home, Event/Organization list/detail, Profile/Auth, Inbox с synthetic/demo content и без production mutations.
2. Перенести design tokens в единый Android theme/components; исходные logo/startAnimation. Проверить aspect ratio, contrast, cold launch, отсутствие чёрной паузы и поведение с уменьшенной анимацией.
3. Нижняя navigation4 tabs, отдельные back stacks/повторный tap, news search изHome; сохранить текущие deep links и все функциональные сценарии.
4. Довести hero/баннеры, компактные карточки, detail actions, profile rows/forms и уведомления. Перепроверить account isolation после вынесения общих компонентов.
5. Матрица скриншотов de/uk × light/dark × обычный/200% text, узкий/широкий экран; затем TalkBack/touch/keyboard/insets/rotation и performance. Не считать похожий screenshot доказательством функциональности.

Статус: базовые бренд/навигация/startup/compact cards выполнены и проверены; оставшийся визуальный пакет и полный аудит ещё не завершены.
