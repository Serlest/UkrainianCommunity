import SwiftUI

/// At accessibility sizes each status receives the entire available width.
struct SystemLogStatusChips: View {
    let log: SystemLogEntry
    var compact = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        LazyVGrid(columns: typeSize.isAccessibilitySize
            ? [GridItem(.flexible(), alignment: .leading)]
            : [GridItem(.adaptive(minimum: compact ? 130 : 150), alignment: .leading)],
            alignment: .leading, spacing: 8) {
            AppInfoChip(title: SystemLogDisplayFormatting.severityTitle(log.severity),
                tint: SystemLogDisplayFormatting.severityTint(log.severity),
                fill: SystemLogDisplayFormatting.severityFill(log.severity), size: compact ? .small : .regular)
            AppInfoChip(title: SystemLogDisplayFormatting.categoryTitle(log.category), systemImage: "folder", size: compact ? .small : .regular)
            if !compact || !log.isReviewed {
                AppInfoChip(title: log.isReviewed ? AppStrings.SystemLogs.reviewed : AppStrings.SystemLogs.notReviewed,
                    systemImage: log.isReviewed ? "checkmark.seal" : "circle.badge.questionmark", size: compact ? .small : .regular)
            }
        }
    }
}
