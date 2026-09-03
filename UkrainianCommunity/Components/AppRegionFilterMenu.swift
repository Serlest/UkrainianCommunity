import SwiftUI

/// The same native menu and themed chip as the neighboring catalog filters.
/// Keep all catalog screens on one region control, including its option order.
struct AppRegionFilterMenu: View {
    @Binding var selection: AustrianFederalState?

    private var selectedTitle: String {
        selection?.displayName ?? AppStrings.Home.regionAllAustria
    }

    var body: some View {
        Menu {
            Picker(AppStrings.Profile.region, selection: $selection) {
                Text(AppStrings.Home.regionAllAustria)
                    .tag(nil as AustrianFederalState?)
                ForEach(AustrianFederalState.allCases) { federalState in
                    Text(federalState.displayName)
                        .tag(Optional(federalState))
                }
            }
        } label: {
            AppFilterChip(
                title: selectedTitle,
                systemImage: "mappin.and.ellipse",
                isSelected: selection != nil,
                trailingSystemImage: "chevron.down"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.Profile.region)
        .accessibilityValue(selectedTitle)
    }
}

#Preview("Region · Light") {
    @Previewable @State var selection: AustrianFederalState? = nil
    AppRegionFilterMenu(selection: $selection)
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Region · Dark") {
    @Previewable @State var selection: AustrianFederalState? = .tirol
    AppRegionFilterMenu(selection: $selection)
        .padding()
        .preferredColorScheme(.dark)
}
