import SwiftUI

struct BannerMeasurementConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAgree: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                        .accessibilityHidden(true)

                    Text(AppStrings.Profile.bannerMeasurementSubtitle)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(AppStrings.Profile.bannerMeasurementDisclosure)
                        .font(.body)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: AppTheme.feedContentMaxWidth, alignment: .leading)
                .padding(AppTheme.pageHorizontal)
                .frame(maxWidth: .infinity)
            }
            .background(AppBackgroundView())
            .navigationTitle(AppStrings.Profile.bannerMeasurementTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppStrings.Action.cancel) { dismiss() }.accessibilityIdentifier("bannerConsent.cancel")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(AppStrings.Profile.bannerMeasurementAgree) {
                    dismiss()
                    onAgree()
                }
                .accessibilityIdentifier("bannerConsent.agree")
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primaryBlue)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.vertical, AppTheme.eventsMetadataSpacing)
                .background(.regularMaterial)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
