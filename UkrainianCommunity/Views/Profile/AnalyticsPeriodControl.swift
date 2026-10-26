import SwiftUI

/// Buttons keep selection in SwiftUI rather than a UIKit segmented-control bridge
/// while the search field and its keyboard are being removed from the hierarchy.
struct AnalyticsPeriodControl: View {
    @Binding var selection: AnalyticsPeriod
    let identifier: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Picker(AppStrings.OwnerAnalytics.periodPicker, selection: $selection) {
                    ForEach(AnalyticsPeriod.allCases) { period in
                        Text(title(period)).tag(period)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 4) {
                    ForEach(AnalyticsPeriod.allCases) { period in
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            selection = period
                        } label: {
                            Text(title(period))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selection == period ? AppTheme.accentPrimaryForeground : AppTheme.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background {
                                    if selection == period {
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(AppTheme.accentPrimarySoft)
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == period ? [.isSelected] : [])
                    }
                }
                .padding(4)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .accessibilityIdentifier(identifier)
    }

    private func title(_ period: AnalyticsPeriod) -> String {
        period.analyticsTitle
    }
}
