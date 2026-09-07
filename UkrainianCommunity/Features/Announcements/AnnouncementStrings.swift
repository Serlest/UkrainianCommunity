import Foundation

enum AnnouncementStrings {
    static var title: String { LocalizationStore.localizedString("announcements.title", defaultValue: "Оповіщення користувачів") }
    static var history: String { LocalizationStore.localizedString("announcements.history", defaultValue: "Повідомлення UAC") }
    static var subtitle: String { LocalizationStore.localizedString("announcements.subtitle", defaultValue: "Повідомлення, аудиторія та результати") }
    static var create: String { LocalizationStore.localizedString("announcements.create", defaultValue: "Створити повідомлення") }
    static var save: String { LocalizationStore.localizedString("announcements.save", defaultValue: "Зберегти чернетку") }
    static var preview: String { LocalizationStore.localizedString("announcements.preview", defaultValue: "Попередній перегляд") }
    static var send: String { LocalizationStore.localizedString("announcements.send", defaultValue: "Надіслати / запланувати") }
    static var test: String { LocalizationStore.localizedString("announcements.test", defaultValue: "Надіслати тест собі") }
    static var cancel: String { LocalizationStore.localizedString("announcements.cancel", defaultValue: "Припинити показ") }
    static var registered: String { LocalizationStore.localizedString("announcements.registered", defaultValue: "Усі зареєстровані") }
    static var guests: String { LocalizationStore.localizedString("announcements.guests", defaultValue: "Усі гості (без обмеження регіону)") }
    static var organizationOwners: String { LocalizationStore.localizedString("announcements.organizationOwners", defaultValue: "Власники організацій") }
    static var appAdmins: String { LocalizationStore.localizedString("announcements.appAdmins", defaultValue: "Адміністратори застосунку") }
    static var organizationAdmins: String { LocalizationStore.localizedString("announcements.organizationAdmins", defaultValue: "Адміністратори організацій") }
    static var organizationModerators: String { LocalizationStore.localizedString("announcements.organizationModerators", defaultValue: "Модератори організацій") }
    static var audience: String { LocalizationStore.localizedString("announcements.audience", defaultValue: "Одержувачі") }
    static var people: String { LocalizationStore.localizedString("announcements.people", defaultValue: "Вибрати користувачів") }
    static var regions: String { LocalizationStore.localizedString("announcements.regions", defaultValue: "Регіон акаунту") }
    static var austria: String { LocalizationStore.localizedString("announcements.austria", defaultValue: "Уся Австрія") }
    static var regionHelp: String { LocalizationStore.localizedString("announcements.regionHelp", defaultValue: "Регіон застосовується до всіх вибраних акаунтів. Гості отримають повідомлення незалежно від регіону.") }
    static var headline: String { LocalizationStore.localizedString("announcements.headline", defaultValue: "Заголовок") }
    static var body: String { LocalizationStore.localizedString("announcements.body", defaultValue: "Текст повідомлення") }
    static var translate: String { LocalizationStore.localizedString("announcements.translate", defaultValue: "Перекласти на іншу мову") }
    static var overwrite: String { LocalizationStore.localizedString("announcements.overwrite", defaultValue: "Замінити переклад?") }
    static var review: String { LocalizationStore.localizedString("announcements.review", defaultValue: "Я перевірив обидві мовні версії та одержувачів") }
    static var translationReview: String { LocalizationStore.localizedString("announcements.translationReview", defaultValue: "Після редагування перевірте текст обома мовами перед надсиланням.") }
    static var mode: String { LocalizationStore.localizedString("announcements.mode", defaultValue: "Показ повідомлення") }
    static var once: String { LocalizationStore.localizedString("announcements.once", defaultValue: "Показати один раз") }
    static var acknowledge: String { LocalizationStore.localizedString("announcements.acknowledge", defaultValue: "Повторювати до підтвердження") }
    static var ack: String { LocalizationStore.localizedString("announcements.ack", defaultValue: "Ознайомився") }
    static var later: String { LocalizationStore.localizedString("announcements.later", defaultValue: "Пізніше") }
    static var close: String { LocalizationStore.localizedString("announcements.close", defaultValue: "Закрити") }
    static var push: String { LocalizationStore.localizedString("announcements.push", defaultValue: "Додатково надіслати push") }
    static var feedback: String { LocalizationStore.localizedString("announcements.feedback", defaultValue: "Кнопка звернення") }
    static var writeFeedback: String { LocalizationStore.localizedString("announcements.writeFeedback", defaultValue: "Написати через звернення") }
    static var start: String { LocalizationStore.localizedString("announcements.start", defaultValue: "Початок показу") }
    static var expiry: String { LocalizationStore.localizedString("announcements.expiry", defaultValue: "Завершення показу") }
    static var scheduleHelp: String { LocalizationStore.localizedString("announcements.scheduleHelp", defaultValue: "Час Австрії (Europe/Vienna). Максимальний термін — 90 днів.") }
    static var error: String { LocalizationStore.localizedString("announcements.error", defaultValue: "Не вдалося виконати дію. Перевірте з’єднання, права доступу та повторіть спробу.") }
    static var syncPending: String { LocalizationStore.localizedString("announcements.syncPending", defaultValue: "Підтвердження збережено на пристрої. Синхронізація буде повторена.") }
    static var loadMore: String { LocalizationStore.localizedString("announcements.loadMore", defaultValue: "Завантажити ще") }
    static var empty: String { LocalizationStore.localizedString("announcements.empty", defaultValue: "Повідомлень поки немає") }
    static var stats: String { LocalizationStore.localizedString("announcements.stats", defaultValue: "Результати (акаунти)") }
    static var shown: String { LocalizationStore.localizedString("announcements.shown", defaultValue: "Показано") }
    static var confirmed: String { LocalizationStore.localizedString("announcements.confirmed", defaultValue: "Підтверджено") }
    static var action: String { LocalizationStore.localizedString("announcements.action", defaultValue: "Перехід до звернення") }
    static var pushSent: String { LocalizationStore.localizedString("announcements.pushSent", defaultValue: "Push прийнято сервісом") }
    static var pushFailed: String { LocalizationStore.localizedString("announcements.pushFailed", defaultValue: "Помилки push") }
    static var count: String { LocalizationStore.localizedString("announcements.count", defaultValue: "Акаунтів за поточним вибором") }
    static var countAudience: String { LocalizationStore.localizedString("announcements.countAudience", defaultValue: "Порахувати одержувачів") }
    static var guestsUnknown: String { LocalizationStore.localizedString("announcements.guestsUnknown", defaultValue: "Кількість гостей заздалегідь невідома.") }
    static var sent: String { LocalizationStore.localizedString("announcements.sent", defaultValue: "Повідомлення збережено для надсилання.") }
    static var tested: String { LocalizationStore.localizedString("announcements.tested", defaultValue: "Тест створено для вашого акаунту.") }
    static var retry: String { LocalizationStore.localizedString("announcements.retry", defaultValue: "Оновити") }
    static var guestPush: String { LocalizationStore.localizedString("announcements.guestPush", defaultValue: "Дозволити push-повідомлення UAC") }
    static var guestPushHelp: String { LocalizationStore.localizedString("announcements.guestPushHelp", defaultValue: "Вікна в застосунку доступні і без дозволу на push.") }
    static var signIn: String { LocalizationStore.localizedString("announcements.signIn", defaultValue: "Увійти, щоб написати звернення") }
    static var draft: String { LocalizationStore.localizedString("announcements.draft", defaultValue: "Чернетка") }
    static var published: String { LocalizationStore.localizedString("announcements.published", defaultValue: "Опубліковано / заплановано") }
    static var cancelled: String { LocalizationStore.localizedString("announcements.cancelled", defaultValue: "Показ припинено") }
    static var search: String { LocalizationStore.localizedString("announcements.search", defaultValue: "Пошук серед завантажених користувачів") }
    static var sendConfirm: String { LocalizationStore.localizedString("announcements.sendConfirm", defaultValue: "Надіслати повідомлення вибраній аудиторії?") }
    static var saved: String { LocalizationStore.localizedString("announcements.saved", defaultValue: "Чернетку збережено") }
    static var guestShown: String { LocalizationStore.localizedString("announcements.guestShown", defaultValue: "Показано гостям (пристрої)") }
    static var guestAck: String { LocalizationStore.localizedString("announcements.guestAck", defaultValue: "Підтверджено гостями (пристрої)") }
    static func group(_ key: String) -> String { LocalizationStore.localizedString("announcements.\(key)", defaultValue: key) }
}
