import Foundation

enum NewsBrowsePeriod: String, CaseIterable, Hashable {
    case all, today, week, month, custom
    var title: String { NewsBrowseStrings.text("period." + rawValue) }
}
enum NewsBrowseScope: String, CaseIterable, Hashable {
    case all, saved, subscribed
    var title: String { NewsBrowseStrings.text("scope." + rawValue) }
}
struct NewsBrowseFilter: Hashable {
    var topic: NewsCategory?
    var period: NewsBrowsePeriod = .all
    var oldestFirst = false
    var scope: NewsBrowseScope = .all
    var startDate = Date()
    var endDate = Date()

    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return value
    }
    func bounds(at reference: Date) -> (start: Date?, end: Date?) {
        let calendar = Self.calendar
        let today = calendar.startOfDay(for: reference)
        switch period {
        case .all: return (nil, nil)
        case .today: return (today, calendar.date(byAdding: .day, value: 1, to: today))
        case .week, .month:
            return (calendar.date(byAdding: .day, value: period == .week ? -6 : -29, to: today),
                    calendar.date(byAdding: .day, value: 1, to: today))
        case .custom:
            return (calendar.startOfDay(for: min(startDate, endDate)),
                    calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(startDate, endDate))))
        }
    }
    var activeCount: Int { (period == .all ? 0 : 1) + (oldestFirst ? 1 : 0) + (scope == .all ? 0 : 1) }
}
struct NewsBrowseQuery: Hashable {
    var filter: NewsBrowseFilter
    var region: AustrianFederalState?
    var search = ""
    var accountKey = "guest"
    // Resolve once per refresh, keeping page boundaries stable across midnight.
    var referenceDate: Date
    func matches(_ post: NewsPost) -> Bool {
        let bounds = filter.bounds(at: referenceDate)
        return (filter.topic == nil || post.category == filter.topic || post.additionalCategories.contains(where: { $0 == filter.topic }))
            && RegionVisibilityMatcher.isVisible(regionScope: post.regionScope, federalState: post.federalState, selectedFederalState: region)
            && (bounds.start == nil || post.publishedAt >= bounds.start!)
            && (bounds.end == nil || post.publishedAt < bounds.end!)
            && (search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || LocalSearchMatcher.matches(query: search, values: [post.localizedTitle, post.localizedSubtitle, post.localizedBody,
                    post.source.displayOrganizationName, post.authorName, post.city, AppStrings.News.title] + post.tags.map(Optional.some)))
    }
    func precedes(_ lhs: NewsPost, _ rhs: NewsPost) -> Bool {
        if lhs.publishedAt == rhs.publishedAt {
            return filter.oldestFirst ? lhs.id < rhs.id : lhs.id > rhs.id
        }
        return filter.oldestFirst ? lhs.publishedAt < rhs.publishedAt : lhs.publishedAt > rhs.publishedAt
    }
}
enum NewsBrowseStrings {
    static func text(_ suffix: String) -> String {
        switch suffix {
        case "topic": LocalizationStore.localizedString("news.browse.topic", defaultValue: "Тема")
        case "allTopics": LocalizationStore.localizedString("news.browse.allTopics", defaultValue: "Усі теми")
        case "general": LocalizationStore.localizedString("news.browse.general", defaultValue: "Загальні новини")
        case "eventNews": LocalizationStore.localizedString("news.browse.eventNews", defaultValue: "Новини про події")
        case "filters": LocalizationStore.localizedString("news.browse.filters", defaultValue: "Фільтри")
        case "period": LocalizationStore.localizedString("news.browse.period", defaultValue: "Період публікації")
        case "sort": LocalizationStore.localizedString("news.browse.sort", defaultValue: "Порядок")
        case "newest": LocalizationStore.localizedString("news.browse.newest", defaultValue: "Спочатку нові")
        case "oldest": LocalizationStore.localizedString("news.browse.oldest", defaultValue: "Спочатку старі")
        case "period.all": LocalizationStore.localizedString("news.browse.period.all", defaultValue: "За весь час")
        case "period.today": LocalizationStore.localizedString("news.browse.period.today", defaultValue: "Сьогодні")
        case "period.week": LocalizationStore.localizedString("news.browse.period.week", defaultValue: "Останні 7 днів")
        case "period.month": LocalizationStore.localizedString("news.browse.period.month", defaultValue: "Останні 30 днів")
        case "period.custom": LocalizationStore.localizedString("news.browse.period.custom", defaultValue: "Обрати дати")
        case "scope.all": LocalizationStore.localizedString("news.browse.scope.all", defaultValue: "Усі новини")
        case "scope.saved": LocalizationStore.localizedString("news.browse.scope.saved", defaultValue: "Збережені")
        case "scope.subscribed": LocalizationStore.localizedString("news.browse.scope.subscribed", defaultValue: "Підписані організації")
        case "source": LocalizationStore.localizedString("news.browse.source", defaultValue: "Джерела")
        case "from": LocalizationStore.localizedString("news.browse.from", defaultValue: "Від")
        case "to": LocalizationStore.localizedString("news.browse.to", defaultValue: "До")
        case "reset": LocalizationStore.localizedString("news.browse.reset", defaultValue: "Скинути фільтри")
        case "apply": LocalizationStore.localizedString("news.browse.apply", defaultValue: "Застосувати")
        case "signIn": LocalizationStore.localizedString("news.browse.signIn", defaultValue: "Увійдіть, щоб переглядати збережені новини та підписані організації.")
        case "error": LocalizationStore.localizedString("news.browse.error", defaultValue: "Не вдалося завантажити новини. Перевірте з’єднання та повторіть спробу.")
        case "empty": LocalizationStore.localizedString("news.browse.empty", defaultValue: "За обраною темою, регіоном і періодом новин не знайдено. Спробуйте змінити умови пошуку.")
        case "expandPeriod": LocalizationStore.localizedString("news.browse.expandPeriod", defaultValue: "Шукати за весь час")
        case "more": LocalizationStore.localizedString("news.browse.more", defaultValue: "Показати ще")
        case "continueHint": LocalizationStore.localizedString("news.browse.continueHint", defaultValue: "Серед перевірених новин збігів поки немає. Продовжити пошук у наступних публікаціях.")
        case "austria": LocalizationStore.localizedString("news.browse.austria", defaultValue: "Вся Австрія")
        default: suffix
        }
    }
    static func topic(_ category: NewsCategory) -> String {
        switch category {
        case .news: text("general")
        case .event: text("eventNews")
        default: category.title
        }
    }
}
