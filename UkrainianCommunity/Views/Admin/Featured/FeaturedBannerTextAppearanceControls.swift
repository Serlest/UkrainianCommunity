import SwiftUI
import UIKit

struct FeaturedBannerEditorTextAppearanceSection: View {
    @ObservedObject var viewModel: FeaturedBannerEditorViewModel
    private let presets: [(name: String, hex: String)] = [
        ("white", "#FFFFFF"), ("black", "#000000"), ("blue", "#2458A6"),
        ("yellow", "#FFD43B"), ("red", "#E53935")
    ]
    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: BannerCountdownStrings.text("appearance.title"))
                colorControl("appearance.headingColor", id: "title", keyPath: \.titleColorHex)
                colorControl("appearance.descriptionColor", id: "subtitle", keyPath: \.subtitleColorHex)
                Text(BannerCountdownStrings.text("appearance.help"))
                    .font(.footnote).foregroundStyle(AppTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                Button(BannerCountdownStrings.text("appearance.reset")) { viewModel.textAppearance = .standard }
                    .buttonStyle(.bordered).disabled(viewModel.textAppearance == .standard)
                    .accessibilityIdentifier("bannerEditor.colors.reset")
            }
        }
    }
    private func colorControl(_ title: String, id: String,
                              keyPath: WritableKeyPath<FeaturedBannerTextAppearance, String?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
              ColorPicker(BannerCountdownStrings.text(title), selection: Binding(
                get: { FeaturedBannerTextColor.color(hex: viewModel.textAppearance[keyPath: keyPath], fallback: .white) },
                set: {
                    if let value = FeaturedBannerTextColor.hex(from: $0),
                       !(viewModel.textAppearance[keyPath: keyPath] == nil && value == "#FFFFFF") {
                        viewModel.textAppearance[keyPath: keyPath] = value
                    }
                }
            ), supportsOpacity: false)
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("bannerEditor." + id + "Color")
              Button { viewModel.textAppearance[keyPath: keyPath] = nil } label: {
                  Image(systemName: "arrow.counterclockwise").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44)
              }
              .buttonStyle(.plain).disabled(viewModel.textAppearance[keyPath: keyPath] == nil)
              .accessibilityLabel(BannerCountdownStrings.text("appearance.resetOne") + ", " + BannerCountdownStrings.text(title))
              .accessibilityIdentifier("bannerEditor." + id + "Color.reset")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(presets, id: \.name) { preset in
                        Button { viewModel.textAppearance[keyPath: keyPath] = preset.hex } label: {
                            Circle().fill(FeaturedBannerTextColor.color(hex: preset.hex, fallback: .white))
                                .overlay { Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1) }
                                .overlay {
                                    if viewModel.textAppearance[keyPath: keyPath] == preset.hex {
                                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(preset.name == "black" || preset.name == "blue" ? Color.white : Color.black)
                                    }
                                }
                                .frame(width: 28, height: 28).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(BannerCountdownStrings.text("appearance." + preset.name))
                        .accessibilityIdentifier("bannerEditor." + id + "Color." + preset.name)
                        .accessibilityAddTraits(viewModel.textAppearance[keyPath: keyPath] == preset.hex ? .isSelected : [])
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }
}
