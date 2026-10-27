import SwiftUI

struct SystemLogRowView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let log: SystemLogEntry
    var isDeleting = false

    var body: some View {
        layout {
            severityIcon

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(SystemLogExplanation.title(log))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)

                    Spacer(minLength: 8)

                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(SystemLogDisplayFormatting.dateTime(log.createdAt))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)

                metadataLine
                contextLine

                SystemLogStatusChips(log: log, compact: true)
            }
        }
        .padding(AppTheme.rowCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassCard(
            cornerRadius: AppTheme.rowCardCornerRadius,
            shadowRadius: AppTheme.localCardShadowSmallRadius,
            shadowY: AppTheme.localCardShadowSmallY
        )
    }

    private var layout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }

    private var severityIcon: some View {
        Image(systemName: log.severity == .critical ? "exclamationmark.triangle.fill" : "doc.text.magnifyingglass")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(SystemLogDisplayFormatting.severityTint(log.severity))
            .frame(width: AppTheme.rowIconSurfaceSize, height: AppTheme.rowIconSurfaceSize)
            .background(
                SystemLogDisplayFormatting.severityFill(log.severity),
                in: RoundedRectangle(cornerRadius: AppTheme.smallIconSurfaceRadius, style: .continuous)
            )
    }

    private var metadataLine: some View {
        HStack(spacing: 6) {
            Text(log.actorDisplayName ?? SystemLogDisplayFormatting.actorRoleTitle(log.actorRole))
            if log.targetTitle != nil || (log.targetType != .none && log.targetType != .unknown) {
                Image(systemName: "arrow.right").font(.caption2.weight(.semibold))
                Text(log.targetTitle ?? SystemLogDisplayFormatting.targetTypeTitle(log.targetType))
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(AppTheme.textSecondary)
        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
    }

    @ViewBuilder
    private var contextLine: some View {
        if let text = rowContextText {
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
        }
    }

    private var rowContextText: String? {
        if SystemLogExplanation.isFailure(log) {
            return SystemLogExplanation.action(log)
        }

        if log.category == .audit {
            let target = log.targetTitle ?? SystemLogDisplayFormatting.targetTypeTitle(log.targetType)
            return "\(SystemLogDisplayFormatting.outcomeTitle(log.outcome)) · \(target)"
        }

        return nil
    }

}
