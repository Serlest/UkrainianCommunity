import SwiftUI

struct NewsHomeFilterRow: View {
    @Binding var filter: NewsBrowseFilter
    @Binding var selectedFederalState: AustrianFederalState?
    let authenticated: Bool
    @State private var showsMoreFilters = false

    private enum Control: String {
        case topic, region, subscribed, saved, options
    }

    var body: some View {
        AppPrioritizedFilterRow(
            pinned: [.topic, .region],
            filters: [.subscribed, .saved, .options],
            isActive: isActive
        ) { control in
            filterControl(control)
                .accessibilityIdentifier("home.filter.\(control.rawValue)")
        }
        .accessibilityIdentifier("home.filters")
        .sheet(isPresented: $showsMoreFilters) {
            NewsBrowseFilterSheet(selection: $filter)
        }
    }

    private func isActive(_ control: Control) -> Bool {
        switch control {
        case .topic: filter.topic != nil
        case .region: selectedFederalState != nil
        case .subscribed: filter.scope == .subscribed
        case .saved: filter.scope == .saved
        case .options: filter.activeCount > 0
        }
    }

    @ViewBuilder private func filterControl(_ control: Control) -> some View {
        switch control {
        case .topic:
            NewsTopicMenu(selection: $filter.topic)
        case .region:
            AppRegionFilterMenu(selection: $selectedFederalState)
        case .subscribed:
            scopeButton(.subscribed, title: AppStrings.Home.filterSubscribed, systemImage: "person.2.fill")
        case .saved:
            scopeButton(.saved, title: AppStrings.Home.filterSaved, systemImage: "bookmark")
        case .options:
            Button { showsMoreFilters = true } label: {
                AppFilterChip(title: NewsBrowseStrings.text("filters") +
                    (filter.activeCount > 0 ? " (\(filter.activeCount))" : ""),
                    systemImage: "line.3.horizontal.decrease",
                    isSelected: filter.activeCount > 0)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.news.filters")
        }
    }

    private func scopeButton(_ scope: NewsBrowseScope, title: String, systemImage: String) -> some View {
        Button {
            filter.scope = filter.scope == scope ? .all : scope
        } label: {
            AppFilterChip(title: title, systemImage: systemImage, isSelected: filter.scope == scope)
        }
        .buttonStyle(.plain)
        .disabled(!authenticated)
        .accessibilityHint(authenticated ? "" : NewsBrowseStrings.text("signIn"))
    }
}
