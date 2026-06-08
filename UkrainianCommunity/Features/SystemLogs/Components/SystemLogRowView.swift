import SwiftUI

struct SystemLogRowView: View {
    let log: SystemLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            severityIcon

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(SystemLogDisplayFormatting.summaryTitle(log.summary))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    Text(SystemLogDisplayFormatting.dateTime(log.createdAt))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                metadataLine
                contextLine

                HStack(spacing: 6) {
                    AppInfoChip(
                        title: SystemLogDisplayFormatting.severityTitle(log.severity),
                        tint: SystemLogDisplayFormatting.severityTint(log.severity),
                        fill: SystemLogDisplayFormatting.severityFill(log.severity),
                        size: .small
                    )

                    AppInfoChip(
                        title: SystemLogDisplayFormatting.categoryTitle(log.category),
                        systemImage: "folder",
                        size: .small
                    )

                    if !log.isReviewed {
                        AppInfoChip(
                            title: AppStrings.SystemLogs.notReviewed,
                            systemImage: "circle.badge.questionmark",
                            tint: Color.orange,
                            fill: Color.orange.opacity(0.12),
                            size: .small
                        )
                    }
                }
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

    private var severityIcon: some View {
        Image(systemName: log.severity == .critical ? "exclamationmark.triangle.fill" : "doc.text.magnifyingglass")
            .font(.headline.weight(.semibold))
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
            Image(systemName: "arrow.right")
                .font(.caption2.weight(.semibold))
            Text(log.targetTitle ?? SystemLogDisplayFormatting.targetTypeTitle(log.targetType))
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(AppTheme.textSecondary)
        .lineLimit(1)
    }

    @ViewBuilder
    private var contextLine: some View {
        if let text = rowContextText {
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
        }
    }

    private var rowContextText: String? {
        if log.category == .diagnostics || log.severity >= .error {
            var diagnosticParts: [String] = []
            if let errorCode = log.errorCode, !errorCode.isEmpty {
                diagnosticParts.append(errorCode)
            }
            if let combinedDiagnosticPath, !combinedDiagnosticPath.isEmpty {
                diagnosticParts.append(combinedDiagnosticPath)
            }

            return diagnosticParts.isEmpty ? SystemLogDisplayFormatting.eventTypeTitle(log.eventType) : diagnosticParts.joined(separator: " · ")
        }

        if log.category == .audit {
            let target = log.targetTitle ?? SystemLogDisplayFormatting.targetTypeTitle(log.targetType)
            return "\(SystemLogDisplayFormatting.outcomeTitle(log.outcome)) · \(target)"
        }

        return nil
    }

    private var combinedDiagnosticPath: String? {
        var parts: [String] = []
        if let moduleName = log.moduleName, !moduleName.isEmpty {
            parts.append(moduleName)
        }
        if let operationName = log.operationName, !operationName.isEmpty {
            parts.append(operationName)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

}
