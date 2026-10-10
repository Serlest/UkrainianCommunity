import Foundation

extension DirectoryCatalog {
    static let supportCategories: [DirectoryCategory] = [
        category("finances", "Фінанси", "Finanzen",
                 summaryUK: "Рахунки, податки й пенсії", summaryDE: "Konten, Steuern und Pension",
                 symbol: "eurosign.circle.fill", topics: [
            topic("banking", "Банківський рахунок", "Bankkonto"),
            topic("taxes", "Податки", "Steuern"),
            topic("pension", "Пенсія", "Pension")
        ]),
        category("social-support", "Соціальна підтримка", "Soziale Unterstützung",
                 summaryUK: "Виплати й допомога у складних ситуаціях", summaryDE: "Leistungen und Hilfe in schwierigen Lagen",
                 symbol: "heart.text.square.fill", topics: [
            topic("benefits", "Соціальні виплати", "Sozialleistungen"),
            topic("family-benefits", "Виплати для сімей", "Familienleistungen"),
            topic("basic-support", "Базова підтримка", "Grundversorgung"),
            topic("aid-organizations", "Допомога організацій", "Hilfe von Organisationen")
        ]),
        category("legal", "Правова допомога", "Rechtshilfe",
                 summaryUK: "Консультації та захист прав", summaryDE: "Beratung und Schutz Ihrer Rechte",
                 symbol: "building.columns.fill", topics: [
            topic("legal-aid", "Юридичні консультації", "Rechtsberatung"),
            topic("authorities", "Державні установи", "Behörden"),
            topic("consumer-rights", "Права споживачів", "Verbraucherrechte"),
            topic("interpreting", "Переклад і супровід", "Dolmetschen & Begleitung")
        ]),
        category("communication", "Зв’язок", "Kommunikation",
                 summaryUK: "Телефон, інтернет і пошта", summaryDE: "Telefon, Internet und Post",
                 symbol: "wifi", topics: [
            topic("phone", "Мобільний зв’язок", "Mobilfunk"),
            topic("internet", "Інтернет", "Internet"),
            topic("postal", "Пошта", "Post")
        ]),
        category("digital", "Цифрові послуги", "Digitale Dienste",
                 summaryUK: "Онлайн-сервіси й цифрові документи", summaryDE: "Online-Dienste und digitale Dokumente",
                 symbol: "desktopcomputer", topics: [
            topic("online-services", "Цифрові державні послуги", "Digitale Behördendienste"),
            topic("digital-identity", "Цифрова ідентифікація", "Digitale Identität"),
            topic("online-safety", "Безпека в інтернеті", "Sicherheit im Internet")
        ]),
        category("community", "Громада", "Gemeinschaft",
                 summaryUK: "Місцеві служби й спільнота", summaryDE: "Lokale Angebote und Kontakte",
                 symbol: "person.3.fill", topics: [
            topic("local-services", "Місцеві служби", "Lokale Angebote"),
            topic("community", "Спільнота", "Gemeinschaft"),
            topic("volunteering", "Волонтерство", "Ehrenamt")
        ]),
        category("leisure", "Дозвілля", "Freizeit",
                 summaryUK: "Спорт, культура й відпочинок", summaryDE: "Sport, Kultur und Erholung",
                 symbol: "figure.run", topics: [
            topic("leisure", "Дозвілля", "Freizeit")
        ]),
        category("accessibility", "Доступність", "Barrierefreiheit",
                 summaryUK: "Послуги для людей з інвалідністю", summaryDE: "Angebote für Menschen mit Behinderung",
                 symbol: "figure.roll", topics: [
            topic("disability", "Підтримка людей з інвалідністю", "Unterstützung bei Behinderung"),
            topic("accessible-services", "Доступ до послуг і роботи", "Zugang zu Diensten und Arbeit"),
            topic("assistive-devices", "Допоміжні засоби", "Hilfsmittel")
        ]),
        category("care", "Догляд", "Pflege",
                 summaryUK: "Догляд удома й служби підтримки", summaryDE: "Pflege zu Hause und Pflegedienste",
                 symbol: "figure.walk", topics: [
            topic("home-care", "Догляд удома", "Pflege zu Hause"),
            topic("care-services", "Служби догляду", "Pflegedienste")
        ]),
        category("seniors", "Літнім людям", "Für Ältere",
                 summaryUK: "Послуги й підтримка літніх людей", summaryDE: "Angebote und Unterstützung für Ältere",
                 symbol: "figure.walk.motion", topics: [
            topic("seniors", "Допомога літнім людям", "Hilfe für Ältere")
        ])
    ]
}
