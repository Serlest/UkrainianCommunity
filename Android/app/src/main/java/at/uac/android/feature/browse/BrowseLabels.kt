package at.uac.android.feature.browse

val regions =
    listOf(
        "burgenland" to "Burgenland / Бургенланд",
        "kaernten" to "Kärnten / Каринтія",
        "niederoesterreich" to "Niederösterreich / Нижня Австрія",
        "oberoesterreich" to "Oberösterreich / Верхня Австрія",
        "salzburg" to "Salzburg / Зальцбург",
        "steiermark" to "Steiermark / Штирія",
        "tirol" to "Tirol / Тіроль",
        "vorarlberg" to "Vorarlberg / Форарльберг",
        "wien" to "Wien / Відень",
    )
private val labels =
    mapOf(
        "news" to ("Nachrichten" to "Новини"),
        "event" to ("Veranstaltungen" to "Події"),
        "lawAndDocuments" to ("Recht und Dokumente" to "Право та документи"),
        "benefitsAndSupport" to ("Leistungen und Hilfe" to "Виплати та допомога"),
        "financeTaxesAndConsumerRights" to
            ("Finanzen und Verbraucherrechte" to "Фінанси та права споживачів"),
        "health" to ("Gesundheit" to "Здоров’я"),
        "safetyAndEmergencies" to ("Sicherheit" to "Безпека"),
        "work" to ("Arbeit" to "Робота"),
        "education" to ("Bildung" to "Освіта"),
        "housing" to ("Wohnen" to "Житло"),
        "transport" to ("Verkehr" to "Транспорт"),
        "communityAndIntegration" to ("Gemeinschaft und Integration" to "Спільнота та інтеграція"),
        "culture" to ("Kultur" to "Культура"),
        "other" to ("Sonstiges" to "Інше"),
        "unspecified" to ("Nicht angegeben" to "Не зазначено"),
        "meetups" to ("Treffen" to "Зустрічі"),
        "training" to ("Kurse" to "Курси"),
        "childrenAndFamily" to ("Kinder und Familie" to "Діти та сім’я"),
        "sportsAndWellness" to ("Sport und Wohlbefinden" to "Спорт та добробут"),
        "excursionsAndNature" to ("Ausflüge und Natur" to "Екскурсії та природа"),
        "music" to ("Musik" to "Музика"),
        "nightlifeAndParties" to ("Nachtleben" to "Вечірки"),
        "foodAndMarket" to ("Essen und Märkte" to "Їжа та ринки"),
        "festivalsAndFairs" to ("Festivals und Messen" to "Фестивалі та ярмарки"),
        "businessAndNetworking" to ("Business und Kontakte" to "Бізнес та знайомства"),
        "volunteering" to ("Ehrenamt" to "Волонтерство"),
        "supportAndIntegration" to ("Hilfe und Integration" to "Підтримка та інтеграція"),
        "celebration" to ("Feiern" to "Свята"),
        "saleAndPromotion" to ("Aktionen" to "Акції"),
        "community" to ("Gemeinschaft" to "Спільнота"),
        "business" to ("Unternehmen" to "Бізнес"),
        "restaurant" to ("Gastronomie" to "Заклад харчування"),
        "specialist" to ("Fachkraft" to "Фахівець"),
        "institution" to ("Einrichtung" to "Установа"),
        "mediaProject" to ("Medienprojekt" to "Медіапроєкт"),
        "everyone" to ("Alle" to "Для всіх"),
        "families" to ("Familien" to "Сім’ї"),
        "children" to ("Kinder" to "Діти"),
        "teens" to ("Jugendliche" to "Підлітки"),
        "adults" to ("Erwachsene" to "Дорослі"),
        "seniors" to ("Senioren" to "Літні люди"),
        "inStore" to ("Vor Ort" to "У закладі"),
        "pickup" to ("Abholung" to "Самовивіз"),
        "delivery" to ("Lieferung" to "Доставка"),
        "online" to ("Online" to "Онлайн"),
        "onSite" to ("Beim Kunden" to "З виїздом"),
        "monday" to ("Montag" to "Понеділок"),
        "tuesday" to ("Dienstag" to "Вівторок"),
        "wednesday" to ("Mittwoch" to "Середа"),
        "thursday" to ("Donnerstag" to "Четвер"),
        "friday" to ("Freitag" to "П’ятниця"),
        "saturday" to ("Samstag" to "Субота"),
        "sunday" to ("Sonntag" to "Неділя"),
    )

fun label(value: String, language: String): String =
    labels[value]?.let { tr(language, it.first, it.second) } ?: value

fun categories(kind: ContentKind) =
    when (kind) {
        ContentKind.NEWS ->
            listOf(
                "news",
                "event",
                "lawAndDocuments",
                "benefitsAndSupport",
                "financeTaxesAndConsumerRights",
                "health",
                "safetyAndEmergencies",
                "work",
                "education",
                "housing",
                "transport",
                "communityAndIntegration",
                "culture",
                "other",
            )
        ContentKind.EVENTS ->
            listOf(
                "unspecified",
                "meetups",
                "training",
                "culture",
                "education",
                "childrenAndFamily",
                "sportsAndWellness",
                "excursionsAndNature",
                "music",
                "nightlifeAndParties",
                "foodAndMarket",
                "festivalsAndFairs",
                "businessAndNetworking",
                "volunteering",
                "supportAndIntegration",
                "celebration",
                "saleAndPromotion",
                "other",
            )
        ContentKind.ORGANIZATIONS ->
            listOf(
                "community",
                "business",
                "restaurant",
                "specialist",
                "institution",
                "mediaProject",
            )
    }

fun failureText(reason: ReadFailure, language: String) =
    when (reason) {
        ReadFailure.OFFLINE ->
            tr(
                language,
                "Der lokale Emulator ist offline. Keine passende gespeicherte Seite verfügbar.",
                "Локальний емулятор недоступний. Відповідної збереженої сторінки немає.",
            )
        ReadFailure.DENIED ->
            tr(
                language,
                "Zugriff nicht erlaubt. Gespeicherte Inhalte werden nicht verwendet.",
                "Доступ заборонено. Збережені матеріали не використовуються.",
            )
        ReadFailure.INVALID ->
            tr(
                language,
                "Die Daten sind unvollständig oder ungültig.",
                "Дані неповні або некоректні.",
            )
        ReadFailure.MISSING ->
            tr(
                language,
                "Dieser Inhalt ist nicht mehr verfügbar.",
                "Цей матеріал більше недоступний.",
            )
        ReadFailure.INDEX ->
            tr(
                language,
                "Die Datenabfrage benötigt eine Backend-Prüfung.",
                "Запит даних потребує перевірки backend.",
            )
        ReadFailure.UNKNOWN ->
            tr(
                language,
                "Laden fehlgeschlagen. Bitte erneut versuchen.",
                "Не вдалося завантажити. Спробуйте ще раз.",
            )
    }
