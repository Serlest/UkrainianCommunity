import Foundation

enum GuideCategoryPresentation {
    static let publicTopLevelCategories: [GuideCategory] = [
        .firstSteps,
        .documents,
        .work,
        .business,
        .housing,
        .finance,
        .family,
        .education,
        .health,
        .transport,
        .law,
        .emergency,
        .lifeInAustria,
        .ukrainianCommunity
    ]

    static func publicTitle(for category: GuideCategory) -> String {
        switch category {
        case .firstSteps:
            return localized(uk: "Перші кроки", de: "Erste Schritte", en: "First Steps")
        case .documents:
            return localized(uk: "Документи та реєстрація", de: "Dokumente und Anmeldung", en: "Documents and Registration")
        case .work:
            return localized(uk: "Робота і кар'єра", de: "Arbeit und Karriere", en: "Work and Career")
        case .business:
            return localized(uk: "Бізнес і самозайнятість", de: "Business und Selbstständigkeit", en: "Business and Self-Employment")
        case .housing:
            return localized(uk: "Житло", de: "Wohnen", en: "Housing")
        case .finance:
            return localized(uk: "Фінанси та податки", de: "Finanzen und Steuern", en: "Finance and Taxes")
        case .family:
            return localized(uk: "Сім'я та діти", de: "Familie und Kinder", en: "Family and Children")
        case .education:
            return localized(uk: "Освіта", de: "Bildung", en: "Education")
        case .health:
            return localized(uk: "Медицина", de: "Medizin", en: "Healthcare")
        case .transport:
            return localized(uk: "Транспорт", de: "Verkehr", en: "Transport")
        case .law:
            return localized(uk: "Право", de: "Recht", en: "Law")
        case .emergency:
            return localized(uk: "Термінова допомога", de: "Nothilfe", en: "Emergency Assistance")
        case .lifeInAustria:
            return localized(uk: "Життя в Австрії", de: "Leben in Österreich", en: "Life in Austria")
        case .ukrainianCommunity:
            return localized(uk: "Українська громада", de: "Ukrainische Community", en: "Ukrainian Community")
        default:
            return category.title
        }
    }

    static var categoriesSectionTitle: String {
        localized(uk: "Категорії", de: "Kategorien", en: "Categories")
    }

    static var guideBadgeTitle: String {
        localized(uk: "Довідник", de: "Leitfaden", en: "Guide")
    }

    static var sectionBadgeTitle: String {
        localized(uk: "Розділ", de: "Abschnitt", en: "Section")
    }

    static var materialBadgeTitle: String {
        localized(uk: "Матеріал", de: "Artikel", en: "Material")
    }

    static var categoriesSectionSubtitle: String {
        localized(
            uk: "Оберіть напрямок, щоб перейти до структурованих розділів довідника",
            de: "Wählen Sie einen Bereich aus, um zu den strukturierten Abschnitten des Leitfadens zu gelangen",
            en: "Choose a topic to open the structured guide sections"
        )
    }

    static var regionPlaceholderTitle: String {
        localized(uk: "Регіон", de: "Region", en: "Region")
    }

    static var allRegionsTitle: String {
        localized(uk: "Усі регіони", de: "Alle Regionen", en: "All Regions")
    }

    static var savedPlaceholderTitle: String {
        localized(uk: "Збережені", de: "Gespeichert", en: "Saved")
    }

    static var savedMaterialsTitle: String {
        localized(uk: "Збережені матеріали", de: "Gespeicherte Artikel", en: "Saved Materials")
    }

    static var savedMaterialsSubtitle: String {
        localized(
            uk: "Матеріали, які ви зберегли для швидкого повернення",
            de: "Artikel, die Sie zum schnellen Wiederfinden gespeichert haben",
            en: "Materials you saved for quick access"
        )
    }

    static var savedMaterialsEmptyTitle: String {
        localized(uk: "Немає збережених матеріалів", de: "Keine gespeicherten Artikel", en: "No saved materials")
    }

    static var savedMaterialsEmptyMessage: String {
        localized(
            uk: "Збережіть матеріал у довіднику, щоб швидко повернутися до нього пізніше.",
            de: "Speichern Sie einen Artikel im Leitfaden, um später schnell darauf zurückzukommen.",
            en: "Save a guide material to return to it quickly later."
        )
    }

    static var saveActionFailedTitle: String {
        localized(uk: "Не вдалося зберегти", de: "Speichern fehlgeschlagen", en: "Could not save")
    }

    static func saveActionErrorMessage(for error: AppError) -> String {
        switch error {
        case .permissionDenied:
            return localized(
                uk: "Для цієї дії потрібно увійти в акаунт.",
                de: "Für diese Aktion müssen Sie sich anmelden.",
                en: "You need to sign in to do this."
            )
        case .network:
            return localized(
                uk: "Не вдалося виконати дію через проблему з мережею.",
                de: "Die Aktion konnte wegen eines Netzwerkproblems nicht abgeschlossen werden.",
                en: "The action could not be completed because of a network issue."
            )
        case .validationFailed, .notFound, .unknown:
            return localized(
                uk: "Не вдалося оновити збереження матеріалу. Спробуйте ще раз.",
                de: "Der gespeicherte Status des Artikels konnte nicht aktualisiert werden. Bitte versuchen Sie es erneut.",
                en: "The saved state for this material could not be updated. Please try again."
            )
        }
    }

    static var searchResultsTitle: String {
        localized(uk: "Результати пошуку", de: "Suchergebnisse", en: "Search Results")
    }

    static var searchResultsSubtitle: String {
        localized(
            uk: "Знайдені категорії, розділи та матеріали у вибраному регіоні",
            de: "Gefundene Kategorien, Abschnitte und Artikel in der ausgewählten Region",
            en: "Found categories, sections, and materials for the selected region"
        )
    }

    static var searchCategoriesTitle: String {
        localized(uk: "Категорії", de: "Kategorien", en: "Categories")
    }

    static var searchNodesTitle: String {
        localized(uk: "Розділи", de: "Abschnitte", en: "Sections")
    }

    static var searchMaterialsTitle: String {
        localized(uk: "Матеріали", de: "Artikel", en: "Materials")
    }

    static var searchEmptyTitle: String {
        localized(uk: "Нічого не знайдено", de: "Nichts gefunden", en: "Nothing found")
    }

    static var searchEmptyMessage: String {
        localized(
            uk: "Спробуйте інший запит або змініть вибраний регіон.",
            de: "Versuchen Sie eine andere Suchanfrage oder wechseln Sie die ausgewählte Region.",
            en: "Try another search term or change the selected region."
        )
    }

    static var categoryEmptyMessage: String {
        localized(
            uk: "Для цієї категорії поки немає доступних розділів.",
            de: "Für diese Kategorie sind noch keine Abschnitte verfügbar.",
            en: "There are no available sections in this category yet."
        )
    }

    static var categorySectionsTitle: String {
        localized(uk: "Розділи", de: "Abschnitte", en: "Sections")
    }

    static var categorySectionsSubtitle: String {
        localized(
            uk: "Оберіть розділ, щоб перейти до підрозділів і матеріалів",
            de: "Wählen Sie einen Abschnitt aus, um zu Unterabschnitten und Artikeln zu gelangen",
            en: "Choose a section to open subsections and materials"
        )
    }

    static var nodeEmptyMessage: String {
        localized(
            uk: "У цьому розділі поки немає вкладених розділів або матеріалів.",
            de: "In diesem Abschnitt gibt es noch keine Unterabschnitte oder Artikel.",
            en: "There are no subsections or materials in this section yet."
        )
    }

    static var nodeSectionsTitle: String {
        localized(uk: "Підрозділи", de: "Unterabschnitte", en: "Subsections")
    }

    static var nodeSectionsSubtitle: String {
        localized(
            uk: "Підрозділи всередині цього розділу",
            de: "Unterabschnitte innerhalb dieses Abschnitts",
            en: "Subsections inside this section"
        )
    }

    static var nodeMaterialsTitle: String {
        localized(uk: "Матеріали", de: "Artikel", en: "Materials")
    }

    static var nodeMaterialsSubtitle: String {
        localized(
            uk: "Фінальні сторінки, які читатимуть користувачі",
            de: "Endgültige Seiten, die Nutzer lesen werden",
            en: "Final pages that users will read"
        )
    }

    static var feedbackSectionTitle: String {
        localized(uk: "Зворотний зв'язок", de: "Rückmeldung", en: "Feedback")
    }

    static var feedbackSectionSubtitle: String {
        localized(
            uk: "Помітили неточність або хочете запропонувати покращення? Надішліть коротке повідомлення команді.",
            de: "Haben Sie einen Fehler entdeckt oder einen Verbesserungsvorschlag? Senden Sie dem Team eine kurze Nachricht.",
            en: "Found an issue or have an improvement idea? Send a short note to the team."
        )
    }

    static var reportIssueActionTitle: String {
        localized(uk: "Повідомити про помилку", de: "Fehler melden", en: "Report an Issue")
    }

    static var suggestChangeActionTitle: String {
        localized(uk: "Запропонувати зміну", de: "Änderung vorschlagen", en: "Suggest a Change")
    }

    static var feedbackSheetTitle: String {
        localized(uk: "Повідомлення для команди", de: "Nachricht an das Team", en: "Message for the Team")
    }

    static var feedbackSheetSubtitle: String {
        localized(
            uk: "Опишіть проблему або ідею покращення для цього матеріалу.",
            de: "Beschreiben Sie das Problem oder Ihre Verbesserungsidee für diesen Artikel.",
            en: "Describe the issue or improvement idea for this material."
        )
    }

    static var feedbackMaterialContextLabel: String {
        localized(uk: "Матеріал", de: "Artikel", en: "Material")
    }

    static var feedbackTypeFieldTitle: String {
        localized(uk: "Тип", de: "Typ", en: "Type")
    }

    static var feedbackTypeErrorTitle: String {
        localized(uk: "Помилка", de: "Fehler", en: "Issue")
    }

    static var feedbackTypeSuggestionTitle: String {
        localized(uk: "Пропозиція", de: "Vorschlag", en: "Suggestion")
    }

    static var feedbackMessagePlaceholder: String {
        localized(
            uk: "Що саме потрібно виправити або покращити?",
            de: "Was genau sollte korrigiert oder verbessert werden?",
            en: "What should be corrected or improved?"
        )
    }

    static var feedbackSubmitActionTitle: String {
        localized(uk: "Надіслати", de: "Senden", en: "Send")
    }

    static var feedbackSuccessTitle: String {
        localized(uk: "Дякуємо", de: "Danke", en: "Thank You")
    }

    static var feedbackSuccessMessage: String {
        localized(
            uk: "Повідомлення надіслано. Ми переглянемо його пізніше.",
            de: "Ihre Nachricht wurde gesendet. Wir werden sie später prüfen.",
            en: "Your message was sent. We will review it later."
        )
    }

    static var feedbackAuthRequiredMessage: String {
        localized(
            uk: "Для надсилання повідомлення потрібно увійти в акаунт.",
            de: "Zum Senden einer Nachricht müssen Sie sich anmelden.",
            en: "You need to sign in to send a message."
        )
    }

    static func feedbackSubmitErrorMessage(for error: AppError) -> String {
        switch error {
        case .permissionDenied:
            return feedbackAuthRequiredMessage
        case .network:
            return localized(
                uk: "Не вдалося надіслати повідомлення через проблему з мережею.",
                de: "Die Nachricht konnte wegen eines Netzwerkproblems nicht gesendet werden.",
                en: "The message could not be sent because of a network issue."
            )
        case .validationFailed, .notFound, .unknown:
            return localized(
                uk: "Не вдалося надіслати повідомлення. Спробуйте ще раз.",
                de: "Die Nachricht konnte nicht gesendet werden. Bitte versuchen Sie es erneut.",
                en: "The message could not be sent. Please try again."
            )
        }
    }

    static func subtitle(for category: GuideCategory) -> String {
        switch category {
        case .firstSteps:
            return localized(
                uk: "Початкові кроки після приїзду: базові дії, пріоритети та порядок старту.",
                de: "Die ersten Schritte nach der Ankunft: grundlegende Aufgaben, Prioritäten und eine sinnvolle Reihenfolge.",
                en: "Your first steps after arrival: priorities, key tasks, and a practical starting order."
            )
        case .documents:
            return localized(
                uk: "Офіційні документи, реєстрація та ключові формальності для старту.",
                de: "Offizielle Dokumente, Meldungen und die wichtigsten Formalitäten für den Start.",
                en: "Official documents, registration, and key formalities to get started."
            )
        case .anmeldung:
            return localized(
                uk: "Адресна реєстрація, супровідні документи та що перевірити перед подачею.",
                de: "Wohnsitzmeldung, notwendige Unterlagen und was Sie vor der Einreichung prüfen sollten.",
                en: "Address registration, supporting documents, and what to check before submitting."
            )
        case .work:
            return localized(
                uk: "Працевлаштування, кар’єрні кроки та базові трудові питання.",
                de: "Arbeitsaufnahme, Karriereschritte und grundlegende Fragen rund um Beschäftigung.",
                en: "Employment, career steps, and basic work-related questions."
            )
        case .finance:
            return localized(
                uk: "Банкінг, податки, виплати та базові фінансові сценарії.",
                de: "Banking, Steuern, Leistungen und grundlegende finanzielle Alltagsthemen.",
                en: "Banking, taxes, benefits, and basic financial situations."
            )
        case .family:
            return localized(
                uk: "Сімейні сервіси, підтримка дітей і пов’язані щоденні процеси.",
                de: "Angebote für Familien, Unterstützung für Kinder und die wichtigsten Alltagsprozesse.",
                en: "Family services, child support, and related day-to-day processes."
            )
        case .health:
            return localized(
                uk: "Медичні послуги, страхування та основні сервіси для повсякденних потреб.",
                de: "Medizinische Versorgung, Versicherung und wichtige Angebote für den Alltag.",
                en: "Healthcare, insurance, and essential services for everyday needs."
            )
        case .housing:
            return localized(
                uk: "Житло, оренда, реєстрація адреси та супровід побутових кроків.",
                de: "Wohnen, Miete, Wohnsitzmeldung und die wichtigsten Schritte rund um den Alltag.",
                en: "Housing, renting, address registration, and related practical steps."
            )
        case .transport:
            return localized(
                uk: "Маршрути, перевізники та локальні транспортні системи по регіонах.",
                de: "Verbindungen, Verkehrsunternehmen und regionale Nahverkehrssysteme.",
                en: "Routes, carriers, and local transport systems by region."
            )
        case .education:
            return localized(
                uk: "Школи, курси, навчання та освітні сервіси.",
                de: "Schulen, Kurse, Ausbildung und wichtige Bildungsangebote.",
                en: "Schools, courses, studies, and education services."
            )
        case .law:
            return localized(
                uk: "Правові питання, базові права та орієнтири для звернення по допомогу.",
                de: "Rechtliche Fragen, grundlegende Rechte und Anlaufstellen für Unterstützung.",
                en: "Legal questions, basic rights, and guidance on where to get help."
            )
        case .emergency:
            return localized(
                uk: "Швидкі інструкції для термінових ситуацій і доступу до критичної допомоги.",
                de: "Schnelle Hinweise für Notfälle und den Zugang zu dringend benötigter Hilfe.",
                en: "Quick guidance for urgent situations and critical support."
            )
        case .ukrainianCommunity:
            return localized(
                uk: "Організації, спільноти та точки опори всередині української мережі.",
                de: "Organisationen, Gemeinschaften und wichtige Anlaufstellen innerhalb des ukrainischen Netzwerks.",
                en: "Organizations, communities, and support points within the Ukrainian network."
            )
        case .lifeInAustria:
            return localized(
                uk: "Побутові сценарії, адаптація та щоденні практичні теми життя в Австрії.",
                de: "Alltagssituationen, Orientierung und praktische Themen des Lebens in Österreich.",
                en: "Everyday situations, adaptation, and practical topics of life in Austria."
            )
        case .ams:
            return localized(
                uk: "Сервіси AMS, допомога з пошуком роботи та пов’язані формальності.",
                de: "AMS-Services, Unterstützung bei der Jobsuche und die dazugehörigen Formalitäten.",
                en: "AMS services, job search support, and related formalities."
            )
        case .medicine:
            return localized(
                uk: "Медичні теми, сервіси та базові пояснення для повсякденного використання.",
                de: "Medizinische Themen, Angebote und grundlegende Erklärungen für den Alltag.",
                en: "Medical topics, services, and basic explanations for everyday use."
            )
        case .children:
            return localized(
                uk: "Дитячі сервіси, навчання, медицина та пов’язані щоденні питання.",
                de: "Angebote für Kinder, Bildung, Gesundheit und wichtige Alltagsthemen.",
                en: "Children's services, education, healthcare, and related daily questions."
            )
        case .business:
            return localized(
                uk: "Підприємництво, реєстрація діяльності та базові бізнес-процеси.",
                de: "Selbstständigkeit, Unternehmensanmeldung und grundlegende Geschäftsprozesse.",
                en: "Entrepreneurship, business registration, and basic business processes."
            )
        case .contacts:
            return localized(
                uk: "Корисні контакти, служби підтримки та точки швидкого звернення.",
                de: "Wichtige Kontakte, Unterstützungsstellen und schnelle Anlaufpunkte.",
                en: "Useful contacts, support services, and quick points of contact."
            )
        }
    }

    private static func localized(uk: String, de: String, en: String) -> String {
        let identifier = LocalizationStore.locale.identifier.lowercased()
        if identifier.hasPrefix("uk") {
            return uk
        }
        if identifier.hasPrefix("de") {
            return de
        }
        return en
    }
}
