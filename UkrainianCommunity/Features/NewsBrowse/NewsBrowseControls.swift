import SwiftUI

struct NewsTopicMenu: View {
    @Binding var selection: NewsCategory?
    var body: some View {
        Menu {
            Button(NewsBrowseStrings.text("allTopics")) { selection = nil }
            ForEach(NewsCategory.allCases) { topic in
                Button { selection = topic } label: {
                    if selection == topic { Label(NewsBrowseStrings.topic(topic), systemImage: "checkmark") }
                    else { Text(NewsBrowseStrings.topic(topic)) }
                }
            }
        } label: {
            AppFilterChip(title: selection.map { NewsBrowseStrings.topic($0) } ?? NewsBrowseStrings.text("topic"),
                          systemImage: "tag", isSelected: selection != nil, trailingSystemImage: "chevron.down")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.news.topic")
    }
}

struct NewsBrowseFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: NewsBrowseFilter
    let authenticated: Bool
    @State private var draft: NewsBrowseFilter
    init(selection: Binding<NewsBrowseFilter>, authenticated: Bool) {
        _selection = selection; self.authenticated = authenticated
        _draft = State(initialValue: selection.wrappedValue)
    }
    var body: some View {
        NavigationStack {
            EditorScreenShell(title: NewsBrowseStrings.text("filters"), closeStyle: .cancel,
                              closeAction: { dismiss() }, trailingContent: {
                Button(NewsBrowseStrings.text("apply")) { selection = draft; dismiss() }
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .accessibilityIdentifier("home.news.apply")
            }, bottomAction: { EmptyView() }) {
                AppEditorSectionCard { VStack(alignment: .leading, spacing: 12) {
                    AppEditorSectionTitle(title: NewsBrowseStrings.text("period"))
                    Picker(NewsBrowseStrings.text("period"), selection: $draft.period) {
                        ForEach(NewsBrowsePeriod.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.tint(AppTheme.accentPrimaryForeground).accessibilityIdentifier("home.news.period")
                    if draft.period == .custom {
                        DatePicker(NewsBrowseStrings.text("from"), selection: $draft.startDate, displayedComponents: .date)
                            .accessibilityIdentifier("home.news.from")
                        DatePicker(NewsBrowseStrings.text("to"), selection: $draft.endDate, in: draft.startDate..., displayedComponents: .date)
                            .accessibilityIdentifier("home.news.to")
                    }
                } }
                AppEditorSectionCard { VStack(alignment: .leading, spacing: 12) {
                    AppEditorSectionTitle(title: NewsBrowseStrings.text("sort"))
                    Picker(NewsBrowseStrings.text("sort"), selection: $draft.oldestFirst) {
                        Text(NewsBrowseStrings.text("newest")).tag(false)
                        Text(NewsBrowseStrings.text("oldest")).tag(true)
                    }.tint(AppTheme.accentPrimaryForeground).accessibilityIdentifier("home.news.sort")
                } }
                AppEditorSectionCard { VStack(alignment: .leading, spacing: 12) {
                    AppEditorSectionTitle(title: NewsBrowseStrings.text("source"))
                    Picker(NewsBrowseStrings.text("source"), selection: $draft.scope) {
                        ForEach(NewsBrowseScope.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.disabled(!authenticated).tint(AppTheme.accentPrimaryForeground).accessibilityIdentifier("home.news.scope")
                    if !authenticated { Text(NewsBrowseStrings.text("signIn")).font(.caption) }
                } }
                Button(NewsBrowseStrings.text("reset")) { draft = NewsBrowseFilter() }
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .accessibilityIdentifier("home.news.reset")
            }
            .environment(\.timeZone, NewsBrowseFilter.calendar.timeZone)
            .pickerStyle(.menu)
            .onChange(of: draft.startDate) { _, value in if draft.endDate < value { draft.endDate = value } }
        }
    }
}
