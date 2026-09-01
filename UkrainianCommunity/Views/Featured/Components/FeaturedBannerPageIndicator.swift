import SwiftUI

struct FeaturedBannerPageIndicator: View {
    private static let dotSize: CGFloat = 6
    private static let selectedDotWidth: CGFloat = 18
    private static let dotSpacing: CGFloat = 6

    let count: Int
    let selectedIndex: Int
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        count: Int,
        selectedIndex: Int,
        onIncrement: @escaping () -> Void = {},
        onDecrement: @escaping () -> Void = {}
    ) {
        self.count = count
        self.selectedIndex = selectedIndex
        self.onIncrement = onIncrement
        self.onDecrement = onDecrement
    }

    var body: some View {
        if count > 1 {
            HStack(spacing: Self.dotSpacing) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(index == selectedIndex ? AppTheme.accentPrimary : AppTheme.textSecondary.opacity(0.28))
                        .frame(width: index == selectedIndex ? Self.selectedDotWidth : Self.dotSize, height: Self.dotSize)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedIndex)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppStrings.Featured.bannerPageIndicator(current: selectedIndex + 1, total: count))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onIncrement()
                case .decrement: onDecrement()
                @unknown default: break
                }
            }
        }
    }
}
