import Foundation

enum GuideAuthoringPresentation {
    static var treeManagementTitle: String {
        localized(uk: "Керування довідником", de: "Leitfaden verwalten", en: "Guide Management")
    }

    static var treeManagementSubtitle: String {
        localized(
            uk: "Переглядайте категорії, розділи та матеріали довідника.",
            de: "Kategorien, Abschnitte und Artikel des Leitfadens verwalten.",
            en: "Browse guide categories, sections, and articles."
        )
    }

    static var categoriesTitle: String {
        localized(uk: "Категорії", de: "Kategorien", en: "Categories")
    }

    static var categoriesSubtitle: String {
        localized(
            uk: "Основні категорії довідника у публічному порядку.",
            de: "Öffentliche Hauptkategorien des Leitfadens in Produktionsreihenfolge.",
            en: "Approved public top-level categories."
        )
    }

    static var rootSectionsChip: String {
        localized(uk: "Розділи", de: "Abschnitte", en: "Sections")
    }

    static var addSection: String {
        localized(uk: "Додати розділ", de: "Abschnitt hinzufügen", en: "Add section")
    }

    static var createSection: String {
        localized(uk: "Створити розділ", de: "Abschnitt erstellen", en: "Create section")
    }

    static var createSubsection: String {
        localized(uk: "Створити підрозділ", de: "Unterabschnitt erstellen", en: "Create subsection")
    }

    static var editSection: String {
        localized(uk: "Редагувати розділ", de: "Abschnitt bearbeiten", en: "Edit section")
    }

    static var addMaterial: String {
        localized(uk: "Додати матеріал", de: "Artikel hinzufügen", en: "Add material")
    }

    static var createMaterial: String {
        localized(uk: "Створити матеріал", de: "Artikel erstellen", en: "Create material")
    }

    static var editMaterial: String {
        localized(uk: "Редагувати матеріал", de: "Artikel bearbeiten", en: "Edit material")
    }

    static var publishArchive: String {
        localized(uk: "Публікація / архів", de: "Veröffentlichen / archivieren", en: "Publish / archive")
    }

    static var deleteSection: String {
        localized(uk: "Видалити розділ", de: "Abschnitt löschen", en: "Delete section")
    }

    static var deleteMaterial: String {
        localized(uk: "Видалити матеріал", de: "Artikel löschen", en: "Delete material")
    }

    static var actionsTitle: String {
        localized(uk: "Дії", de: "Aktionen", en: "Actions")
    }

    static var contentSwitchTitle: String {
        localized(uk: "Вміст розділу", de: "Inhalt des Abschnitts", en: "Section content")
    }

    static var createSectionScreenTitle: String {
        localized(uk: "Створити розділ", de: "Abschnitt erstellen", en: "Create section")
    }

    static var editSectionScreenTitle: String {
        localized(uk: "Редагувати розділ", de: "Abschnitt bearbeiten", en: "Edit section")
    }

    static var createMaterialScreenTitle: String {
        localized(uk: "Створити матеріал", de: "Artikel erstellen", en: "Create article")
    }

    static var editMaterialScreenTitle: String {
        localized(uk: "Редагувати матеріал", de: "Artikel bearbeiten", en: "Edit article")
    }

    static var titleLabel: String {
        localized(uk: "Назва", de: "Titel", en: "Title")
    }

    static var shortDescriptionLabel: String {
        localized(uk: "Короткий опис", de: "Kurzbeschreibung", en: "Short description")
    }

    static var sectionDetailsTitle: String {
        localized(uk: "Основне", de: "Grundlagen", en: "Basics")
    }

    static var sectionDetailsSubtitle: String {
        localized(
            uk: "Створіть назву розділу та, за потреби, короткий опис.",
            de: "Geben Sie einen Titel und optional eine Kurzbeschreibung für den Abschnitt ein.",
            en: "Add the section title and optional short description."
        )
    }

    static var placementTitle: String {
        localized(uk: "Де буде розміщено", de: "Platzierung", en: "Placement")
    }

    static var placementHintLabel: String {
        localized(uk: "Розміщення", de: "Platzierung", en: "Placement")
    }

    static var categoryLabel: String {
        localized(uk: "Категорія", de: "Kategorie", en: "Category")
    }

    static var placementLabel: String {
        localized(uk: "Розміщення", de: "Platzierung", en: "Placement")
    }

    static var regionTitle: String {
        localized(uk: "Регіональність", de: "Region", en: "Region")
    }

    static var reviewTitle: String {
        localized(uk: "Перевірка актуальності", de: "Aktualitätsprüfung", en: "Review")
    }

    static var regionSubtitleSection: String {
        localized(
            uk: "Оберіть, чи цей розділ стосується всієї Австрії або окремої землі.",
            de: "Wählen Sie, ob dieser Abschnitt für ganz Österreich oder nur für ein Bundesland gilt.",
            en: "Choose whether this section applies to all Austria or one state."
        )
    }

    static var regionSubtitleMaterial: String {
        localized(
            uk: "Оберіть, чи цей матеріал стосується всієї Австрії або окремої землі.",
            de: "Wählen Sie, ob dieser Artikel für ganz Österreich oder nur für ein Bundesland gilt.",
            en: "Choose whether this article applies to all Austria or one state."
        )
    }

    static var allAustria: String {
        localized(uk: "Вся Австрія", de: "Ganz Österreich", en: "All Austria")
    }

    static var oneFederalState: String {
        localized(uk: "Окрема земля", de: "Ein Bundesland", en: "Specific federal state")
    }

    static var federalStateLabel: String {
        localized(uk: "Федеральна земля", de: "Bundesland", en: "Federal state")
    }

    static var selectFederalState: String {
        localized(uk: "Оберіть землю", de: "Bundesland wählen", en: "Select state")
    }

    static var advancedTitle: String {
        localized(uk: "Додатково", de: "Erweitert", en: "Advanced")
    }

    static var nodeAdvancedSubtitle: String {
        localized(
            uk: "Порядок, додаткові налаштування та службовий контекст.",
            de: "Reihenfolge, optionale Einstellungen und interner Kontext.",
            en: "Ordering, optional overrides, and internal context."
        )
    }

    static var materialAdvancedSubtitle: String {
        localized(
            uk: "Порядок, перегляд матеріалу та службовий контекст.",
            de: "Reihenfolge, Prüfintervalle und interner Kontext.",
            en: "Ordering, review settings, and internal context."
        )
    }

    static var sortOrderLabel: String {
        localized(uk: "Порядок", de: "Reihenfolge", en: "Sort order")
    }

    static var healthStatusOverrideLabel: String {
        localized(uk: "Стан актуальності", de: "Aktualitätsstatus", en: "Health status")
    }

    static var pathLabel: String {
        localized(uk: "Шлях", de: "Pfad", en: "Path")
    }

    static var createSectionButton: String {
        localized(uk: "Створити розділ", de: "Abschnitt erstellen", en: "Create section")
    }

    static var saveSectionButton: String {
        localized(uk: "Зберегти зміни", de: "Änderungen speichern", en: "Save changes")
    }

    static var createMaterialButton: String {
        localized(uk: "Створити матеріал", de: "Artikel erstellen", en: "Create article")
    }

    static var saveMaterialButton: String {
        localized(uk: "Зберегти зміни", de: "Änderungen speichern", en: "Save changes")
    }

    static var savingLabel: String {
        localized(uk: "Збереження…", de: "Wird gespeichert…", en: "Saving…")
    }

    static var cancelLabel: String {
        localized(uk: "Скасувати", de: "Abbrechen", en: "Cancel")
    }

    static var okLabel: String {
        localized(uk: "Добре", de: "OK", en: "OK")
    }

    static var contentTitle: String {
        localized(uk: "Основний текст", de: "Haupttext", en: "Main text")
    }

    static var contentSubtitle: String {
        localized(
            uk: "Напишіть основний текст матеріалу та додайте структуровані блоки.",
            de: "Schreiben Sie den Haupttext und ergänzen Sie strukturierte Blöcke.",
            en: "Write the body and add structured blocks."
        )
    }

    static var bodyLabel: String {
        localized(uk: "Основний текст", de: "Haupttext", en: "Body")
    }

    static var descriptionSectionTitle: String {
        localized(uk: "Опис", de: "Beschreibung", en: "Description")
    }

    static var descriptionSectionSubtitle: String {
        localized(
            uk: "Коротко поясніть, що це за матеріал і кому він допоможе.",
            de: "Beschreiben Sie kurz, worum es in diesem Artikel geht und wem er hilft.",
            en: "Briefly explain what this material is about and who it helps."
        )
    }

    static var stepsSectionTitle: String {
        localized(uk: "Кроки", de: "Schritte", en: "Steps")
    }

    static var checklistSectionTitle: String {
        localized(uk: "Чекліст / документи", de: "Checkliste / Dokumente", en: "Checklist / documents")
    }

    static var contactsSectionTitle: String {
        localized(uk: "Контакти", de: "Kontakte", en: "Contacts")
    }

    static var importantInformationSectionTitle: String {
        localized(uk: "Важлива інформація", de: "Wichtige Hinweise", en: "Important information")
    }

    static var knowledgeSectionsTitle: String {
        localized(uk: "Структуровані розділи", de: "Strukturierte Abschnitte", en: "Structured sections")
    }

    static var knowledgeSectionsSubtitle: String {
        localized(
            uk: "Заповніть лише ті розділи, які справді потрібні. Порожні блоки не будуть показані читачам.",
            de: "Füllen Sie nur die Abschnitte aus, die wirklich nötig sind. Leere Bereiche werden Lesern nicht angezeigt.",
            en: "Fill only the sections you need. Empty sections stay hidden from readers."
        )
    }

    static var addListItem: String {
        localized(uk: "Додати пункт", de: "Eintrag hinzufügen", en: "Add item")
    }

    static var addContact: String {
        localized(uk: "Додати контакт", de: "Kontakt hinzufügen", en: "Add contact")
    }

    static var emptyListHint: String {
        localized(uk: "Можна залишити порожнім.", de: "Kann leer bleiben.", en: "You can leave this empty.")
    }

    static var stepPlaceholder: String {
        localized(uk: "Наприклад: Подайте заявку онлайн", de: "Zum Beispiel: Antrag online stellen", en: "For example: Submit the application online")
    }

    static var checklistPlaceholder: String {
        localized(uk: "Наприклад: Паспорт або ID", de: "Zum Beispiel: Reisepass oder ID", en: "For example: Passport or ID")
    }

    static var importantInformationPlaceholder: String {
        localized(
            uk: "Додайте важливі винятки, попередження або уточнення.",
            de: "Fügen Sie wichtige Hinweise, Ausnahmen oder Warnungen hinzu.",
            en: "Add important notes, exceptions, or warnings."
        )
    }

    static var contactNameLabel: String {
        localized(uk: "Назва контакту", de: "Kontaktname", en: "Contact name")
    }

    static var contactDescriptionLabel: String {
        localized(uk: "Пояснення", de: "Beschreibung", en: "Description")
    }

    static var contactPhoneLabel: String {
        localized(uk: "Телефон", de: "Telefon", en: "Phone")
    }

    static var contactEmailLabel: String {
        localized(uk: "Email", de: "E-Mail", en: "Email")
    }

    static var contactWebsiteLabel: String {
        localized(uk: "Сайт", de: "Webseite", en: "Website")
    }

    static var sourcesTitle: String {
        localized(uk: "Джерела", de: "Quellen", en: "Sources")
    }

    static var sourcesSubtitle: String {
        localized(
            uk: "Додайте джерела та корисні посилання для читачів.",
            de: "Fügen Sie Quellen und hilfreiche Links für Leser hinzu.",
            en: "Add sources and helpful links for readers."
        )
    }

    static var officialSourceURLLabel: String {
        localized(uk: "Офіційне посилання", de: "Offizielle URL", en: "Official source URL")
    }

    static var sourceNameLabel: String {
        localized(uk: "Назва джерела", de: "Quellenname", en: "Source name")
    }

    static var officialSourcesRequiredLabel: String {
        localized(uk: "Потрібні офіційні джерела", de: "Offizielle Quellen erforderlich", en: "Official sources required")
    }

    static var sourceLinksLabel: String {
        localized(uk: "Джерела", de: "Quellen", en: "Sources")
    }

    static var addSourceLink: String {
        localized(uk: "Додати джерело", de: "Quelle hinzufügen", en: "Add source")
    }

    static var noSourceLinks: String {
        localized(uk: "Джерела можна додати пізніше.", de: "Quellen können später hinzugefügt werden.", en: "Sources can be added later.")
    }

    static var sourceTitleFieldLabel: String {
        localized(uk: "Назва", de: "Titel", en: "Title")
    }

    static var sourceURLFieldLabel: String {
        localized(uk: "URL", de: "URL", en: "URL")
    }

    static var reviewIntervalLabel: String {
        localized(uk: "Інтервал перегляду", de: "Prüfintervall", en: "Review interval")
    }

    static var reviewIntervalExplainTitle: String {
        localized(
            uk: "Нагадати перевірити інформацію через",
            de: "Zur Überprüfung erinnern in",
            en: "Remind to review in"
        )
    }

    static var reviewIntervalExplainSubtitle: String {
        localized(
            uk: "Це не приховує матеріал автоматично. Це лише нагадування для адміністраторів перевірити актуальність.",
            de: "Dadurch wird der Artikel nicht automatisch verborgen. Es ist nur eine Erinnerung für Administratoren, die Aktualität zu prüfen.",
            en: "This does not hide the material automatically. It is only a reminder for administrators to check whether the information is still current."
        )
    }

    static var lastReviewedLabel: String {
        localized(uk: "Останній перегляд", de: "Zuletzt geprüft", en: "Last reviewed")
    }

    static var nextReviewLabel: String {
        localized(uk: "Наступний перегляд", de: "Nächste Prüfung", en: "Next review")
    }

    static func materialPlacementDescription(_ path: String) -> String {
        localized(
            uk: "Матеріал буде створено в: \(path)",
            de: "Der Artikel wird hier erstellt: \(path)",
            en: "The article will be created in: \(path)"
        )
    }

    static var noSectionsYet: String {
        localized(uk: "У цій категорії ще немає розділів.", de: "In dieser Kategorie gibt es noch keine Abschnitte.", en: "No sections yet.")
    }

    static var noContentYet: String {
        localized(uk: "У цьому розділі ще немає підрозділів або матеріалів.", de: "In diesem Abschnitt gibt es noch keine Unterabschnitte oder Artikel.", en: "No content yet.")
    }

    static var noSubsectionsInSection: String {
        localized(uk: "У цьому розділі ще немає підрозділів.", de: "In diesem Abschnitt gibt es noch keine Unterabschnitte.", en: "There are no subsections in this section yet.")
    }

    static var noMaterialsInSection: String {
        localized(uk: "У цьому розділі ще немає матеріалів.", de: "In diesem Abschnitt gibt es noch keine Artikel.", en: "There are no materials in this section yet.")
    }

    static var deleteSectionTitle: String {
        localized(uk: "Видалити розділ?", de: "Abschnitt löschen?", en: "Delete section?")
    }

    static var deleteMaterialTitle: String {
        localized(uk: "Видалити матеріал?", de: "Artikel löschen?", en: "Delete material?")
    }

    static var deleteIrreversibleMessage: String {
        localized(uk: "Цю дію не можна скасувати.", de: "Diese Aktion kann nicht rückgängig gemacht werden.", en: "This action cannot be undone.")
    }

    static var deleteSectionBlockedMessage: String {
        localized(
            uk: "Спочатку видаліть матеріали та підрозділи всередині цього розділу.",
            de: "Löschen Sie zuerst die Artikel und Unterabschnitte in diesem Abschnitt.",
            en: "Delete materials and subsections inside this section first."
        )
    }

    static var deleteFailedTitle: String {
        localized(uk: "Не вдалося видалити", de: "Löschen nicht möglich", en: "Delete failed")
    }

    static var deletePermissionDenied: String {
        localized(
            uk: "У вас немає прав для видалення цього елемента.",
            de: "Sie haben keine Berechtigung, dieses Element zu löschen.",
            en: "You do not have permission to delete this item."
        )
    }

    static var deleteUnknownError: String {
        localized(
            uk: "Зараз не вдалося видалити цей елемент.",
            de: "Dieses Element konnte gerade nicht gelöscht werden.",
            en: "Unable to delete this item right now."
        )
    }

    static var sectionsListTitle: String {
        localized(uk: "Розділи", de: "Abschnitte", en: "Sections")
    }

    static var sectionsListSubtitle: String {
        localized(
            uk: "Відкрийте розділ, щоб переглянути підрозділи, матеріали та службову інформацію.",
            de: "Öffnen Sie einen Abschnitt, um Unterabschnitte, Artikel und Verwaltungsdaten zu sehen.",
            en: "Open a section to inspect nested content."
        )
    }

    static var materialsListTitle: String {
        localized(uk: "Матеріали", de: "Artikel", en: "Materials")
    }

    static var materialsListSubtitle: String {
        localized(
            uk: "Фінальні матеріали, які читають користувачі.",
            de: "Endgültige Artikel, die Nutzer lesen werden.",
            en: "Final reader-facing articles."
        )
    }

    static var reviewQueueTitle: String {
        localized(uk: "Перевірка актуальності", de: "Aktualitätsprüfung", en: "Review Materials")
    }

    static var reviewQueueSubtitle: String {
        localized(
            uk: "Матеріали, які скоро потребуватимуть перевірки або вже прострочені.",
            de: "Artikel, die bald geprüft werden müssen oder bereits überfällig sind.",
            en: "Materials that are due soon for review or already overdue."
        )
    }

    static var dueSoonTitle: String {
        localized(uk: "Скоро перевірити", de: "Bald prüfen", en: "Due Soon")
    }

    static var overdueTitle: String {
        localized(uk: "Прострочено", de: "Überfällig", en: "Overdue")
    }

    static var reviewCurrentTitle: String {
        localized(uk: "Актуально", de: "Aktuell", en: "Current")
    }

    static var reviewArchivedTitle: String {
        localized(uk: "Архів", de: "Archiv", en: "Archived")
    }

    static var reviewQueueEmptyTitle: String {
        localized(uk: "Усе актуально", de: "Alles ist aktuell", en: "Everything Is Current")
    }

    static var reviewQueueEmptyMessage: String {
        localized(
            uk: "Зараз немає матеріалів, які потребують перевірки.",
            de: "Zurzeit gibt es keine Artikel, die geprüft werden müssen.",
            en: "There are no materials needing review right now."
        )
    }

    static var markAsReviewed: String {
        localized(uk: "Позначити як перевірений", de: "Als geprüft markieren", en: "Mark as reviewed")
    }

    static var reviewUpdatedTitle: String {
        localized(uk: "Перевірку оновлено", de: "Prüfung aktualisiert", en: "Review Updated")
    }

    static var reviewUpdatedMessage: String {
        localized(
            uk: "Матеріал позначено як перевірений.",
            de: "Der Artikel wurde als geprüft markiert.",
            en: "The material was marked as reviewed."
        )
    }

    static var reviewUpdateFailedTitle: String {
        localized(uk: "Не вдалося оновити", de: "Aktualisierung fehlgeschlagen", en: "Update Failed")
    }

    static func reviewUpdateErrorMessage(for error: AppError) -> String {
        switch error {
        case .permissionDenied:
            return localized(
                uk: "У вас немає прав для оновлення статусу перевірки.",
                de: "Sie haben keine Berechtigung, den Prüfstatus zu aktualisieren.",
                en: "You do not have permission to update the review status."
            )
        case .notFound:
            return localized(
                uk: "Матеріал більше не існує.",
                de: "Dieser Artikel existiert nicht mehr.",
                en: "This material no longer exists."
            )
        case .network:
            return localized(
                uk: "Помилка мережі. Спробуйте ще раз.",
                de: "Netzwerkfehler. Bitte versuchen Sie es erneut.",
                en: "Network error. Please try again."
            )
        case .validationFailed, .unknown:
            return localized(
                uk: "Не вдалося оновити статус перевірки.",
                de: "Der Prüfstatus konnte nicht aktualisiert werden.",
                en: "The review status could not be updated."
            )
        }
    }

    static func localized(uk: String, de: String, en: String) -> String {
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
