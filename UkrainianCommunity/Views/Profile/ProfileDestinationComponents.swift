import SwiftUI

struct ProfileDestinationLayout<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let introSubtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    AppCenteredBrandHeader {
                        AppGlassIconButton(systemImage: "chevron.left", accessibilityLabel: AppStrings.Common.back) {
                            dismiss()
                        }
                    } trailingContent: {
                        EmptyView()
                    }

                    AppGroupedContentPlane {
                        VStack(alignment: .leading, spacing: AppTheme.eventsControlGroupSpacing) {
                            ProfileDestinationIntroCard(
                                title: title,
                                subtitle: introSubtitle
                            )

                            content
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.sectionSpacing)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
            }
        }
        .tint(AppTheme.accentPrimary)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .observesKeyboardDismissTaps()
    }
}

private struct ProfileDestinationIntroCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        AppEditorSectionCard {
            SectionHeaderBlock(
                title: title,
                subtitle: subtitle
            )
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
    }
}

struct ProfileDestinationEmptyStateCard: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .center, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 128)
            .padding(.vertical, 4)
        }
    }
}
