import Foundation

enum EditorTranslationStrings {
    static var translateToUkrainian: String { LocalizationStore.localizedString("editor.translation.toUkrainian", defaultValue: "Перекласти українською") }
    static var overwriteUkrainian: String { LocalizationStore.localizedString("editor.translation.overwriteUkrainian", defaultValue: "Замінити наявний український текст перевіреним перекладом?") }
    static var translate: String { LocalizationStore.localizedString("editor.translation.translate", defaultValue: "Перекласти німецькою") }
    static var hint: String { LocalizationStore.localizedString("editor.translation.hint", defaultValue: "Перевірте й відредагуйте переклад перед застосуванням. Публікація виконується окремо.") }
    static var review: String { LocalizationStore.localizedString("editor.translation.review", defaultValue: "Перевірка перекладу") }
    static var apply: String { LocalizationStore.localizedString("editor.translation.apply", defaultValue: "Застосувати переклад") }
    static var overwrite: String { LocalizationStore.localizedString("editor.translation.overwrite", defaultValue: "Замінити наявний німецький текст перевіреним перекладом?") }
    static var changed: String { LocalizationStore.localizedString("editor.translation.changed", defaultValue: "Текст або акаунт змінився. Закрийте перегляд і повторіть переклад. Внесені зміни не замінено.") }
    static var error: String { LocalizationStore.localizedString("editor.translation.error", defaultValue: "Переклад недоступний. Спробуйте ще раз або заповніть переклад вручну.") }
    static var limit: String { LocalizationStore.localizedString("editor.translation.limit", defaultValue: "Ліміт перекладу вичерпано. Спробуйте пізніше або заповніть текст вручну.") }
}
