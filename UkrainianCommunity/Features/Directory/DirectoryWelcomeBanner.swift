import SwiftUI

struct DirectoryWelcomeBanner: View {
    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .fill(AppTheme.surfaceHero)

            GeometryReader { proxy in
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: min(proxy.size.width * 0.37, 150)))
                    .foregroundStyle(.white.opacity(0.11))
                    .position(x: proxy.size.width * 0.83, y: proxy.size.height * 0.51)
                    .accessibilityHidden(true)
            }
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "book.closed.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
                Text(AppStrings.Tabs.directory)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text(DirectoryStrings.introduction)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 270, alignment: .leading)
            }
            .padding(22)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
