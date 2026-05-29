import SwiftUI

struct AppInfoChip: View {
    enum Size {
        case small
        case regular

        var font: Font {
            switch self {
            case .small:
                .caption2.weight(.semibold)
            case .regular:
                .caption.weight(.medium)
            }
        }

        var iconFont: Font {
            switch self {
            case .small:
                .caption2.weight(.semibold)
            case .regular:
                .caption.weight(.medium)
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small:
                8
            case .regular:
                10
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .small:
                4
            case .regular:
                8
            }
        }
    }

    let title: String
    let systemImage: String?
    let tint: Color
    let fill: Color
    let border: Color?
    let trailingSystemImage: String?
    let size: Size
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        title: String,
        systemImage: String? = nil,
        tint: Color = AppTheme.accentPrimary,
        fill: Color = AppTheme.badgeBlueFill,
        border: Color? = nil,
        trailingSystemImage: String? = nil,
        size: Size = .regular
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.fill = fill
        self.border = border
        self.trailingSystemImage = trailingSystemImage
        self.size = size
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(size.iconFont)
            }

            Text(title)
                .font(size.font)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(size.iconFont)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(
            reduceTransparency ? fill.opacity(0.95) : fill,
            in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
        )
        .background {
            if !reduceTransparency {
                RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay {
            if let border {
                RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                    .strokeBorder(border)
            }
        }
        .shadow(color: AppTheme.glassShadow(for: colorScheme).opacity(0.65), radius: 5, y: 2)
    }
}

struct AppFilterChip: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let trailingSystemImage: String?

    init(
        title: String,
        systemImage: String? = nil,
        isSelected: Bool = false,
        trailingSystemImage: String? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.trailingSystemImage = trailingSystemImage
    }

    var body: some View {
        AppInfoChip(
            title: title,
            systemImage: systemImage,
            tint: isSelected ? .white : AppTheme.textSecondary.opacity(0.92),
            fill: isSelected ? AppTheme.accentPrimary : AppTheme.surfaceGlass,
            border: isSelected ? AppTheme.accentPrimary.opacity(0.18) : AppTheme.borderSubtle,
            trailingSystemImage: trailingSystemImage,
            size: .regular
        )
        .frame(minHeight: AppTheme.iconButtonSize)
    }
}

struct AppHorizontalChipRow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = AppTheme.eventsMetadataSpacing, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                content
            }
            .padding(.horizontal, AppTheme.eventsMetadataSpacing)
            .padding(.vertical, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppHorizontalFilterRow<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        AppHorizontalChipRow {
            content
        }
    }
}

struct SelectableFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AppTheme.accentPrimary : AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? AppTheme.badgeBlueFill : AppTheme.surfacePrimary)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? AppTheme.borderSubtle : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
