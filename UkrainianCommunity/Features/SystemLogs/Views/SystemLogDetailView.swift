import FirebaseAuth
import SwiftUI
import UIKit

struct SystemLogDetailView: View {
    let log: SystemLogEntry
    let isMarkingReviewed: Bool
    let reviewErrorMessage: String?
    let onMarkReviewed: () async -> Void
    @State private var didCopyDetails = false

    init(
        log: SystemLogEntry,
        isMarkingReviewed: Bool = false,
        reviewErrorMessage: String? = nil,
        onMarkReviewed: @escaping () async -> Void = {}
    ) {
        self.log = log
        self.isMarkingReviewed = isMarkingReviewed
        self.reviewErrorMessage = reviewErrorMessage
        self.onMarkReviewed = onMarkReviewed
    }

    var body: some View {
        PushedScreenShell(
            title: AppStrings.SystemLogs.detailTitle,
            subtitle: SystemLogDisplayFormatting.dateTime(log.createdAt)
        ) {
            AppGlassIconButton(
                systemImage: didCopyDetails ? "checkmark" : "doc.on.doc",
                accessibilityLabel: AppStrings.SystemLogs.copyDetails
            ) {
                UIPasteboard.general.string = copyText
                didCopyDetails = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    didCopyDetails = false
                }
            }
        } content: {
            if didCopyDetails {
                InlineMessageCard(style: .success, message: AppStrings.SystemLogs.detailsCopied)
            }

            DetailHeaderCard(title: SystemLogDisplayFormatting.summaryTitle(log.summary), subtitle: log.technicalMessage) {
                AppHorizontalChipRow(spacing: 8) {
                    AppInfoChip(
                        title: SystemLogDisplayFormatting.severityTitle(log.severity),
                        tint: SystemLogDisplayFormatting.severityTint(log.severity),
                        fill: SystemLogDisplayFormatting.severityFill(log.severity)
                    )
                    AppInfoChip(title: SystemLogDisplayFormatting.categoryTitle(log.category), systemImage: "folder")
                    AppInfoChip(title: log.isReviewed ? AppStrings.SystemLogs.reviewed : AppStrings.SystemLogs.notReviewed, systemImage: log.isReviewed ? "checkmark.seal" : "circle.badge.questionmark")
                }
            }

            reviewActionSection

            detailSection(AppStrings.SystemLogs.actorSection, rows: [
                (AppStrings.SystemLogs.nameLabel, nonEmpty(log.actorDisplayName)),
                (AppStrings.SystemLogs.roleLabel, SystemLogDisplayFormatting.actorRoleTitle(log.actorRole)),
                (AppStrings.SystemLogs.userIdLabel, nonEmpty(log.actorUserId))
            ])

            detailSection(AppStrings.SystemLogs.targetSection, rows: [
                (AppStrings.SystemLogs.typeLabel, targetTypeValue),
                (AppStrings.SystemLogs.titleLabel, nonEmpty(log.targetTitle)),
                (AppStrings.SystemLogs.targetIdLabel, nonEmpty(log.targetId))
            ])

            detailSection(AppStrings.SystemLogs.organizationSection, rows: [
                (AppStrings.SystemLogs.titleLabel, nonEmpty(log.organizationName)),
                (AppStrings.SystemLogs.organizationIdLabel, nonEmpty(log.organizationId))
            ])

            detailSection(AppStrings.SystemLogs.classificationSection, rows: [
                (AppStrings.SystemLogs.categoryLabel, SystemLogDisplayFormatting.categoryTitle(log.category)),
                (AppStrings.SystemLogs.severityLabel, SystemLogDisplayFormatting.severityTitle(log.severity)),
                (AppStrings.SystemLogs.eventLabel, SystemLogDisplayFormatting.eventTypeTitle(log.eventType)),
                (AppStrings.SystemLogs.outcomeLabel, log.outcome.map(SystemLogDisplayFormatting.outcomeTitle)),
                (AppStrings.SystemLogs.retentionLabel, log.retentionPolicy.map(SystemLogDisplayFormatting.retentionPolicyTitle)),
                (AppStrings.SystemLogs.retentionUntilLabel, retentionUntil.map(SystemLogDisplayFormatting.dateTime)),
                (AppStrings.SystemLogs.createdAtLabel, SystemLogDisplayFormatting.dateTime(log.createdAt))
            ])

            detailSection(AppStrings.SystemLogs.diagnosticsSection, rows: [
                (AppStrings.SystemLogs.errorCodeLabel, nonEmpty(log.errorCode)),
                (AppStrings.SystemLogs.moduleLabel, nonEmpty(log.moduleName)),
                (AppStrings.SystemLogs.screenLabel, nonEmpty(log.screenName)),
                (AppStrings.SystemLogs.operationLabel, nonEmpty(log.operationName))
            ])

            detailSection(AppStrings.SystemLogs.deviceSection, rows: [
                (AppStrings.SystemLogs.appVersionLabel, nonEmpty(log.appVersion)),
                (AppStrings.SystemLogs.osVersionLabel, nonEmpty(log.osVersion)),
                (AppStrings.SystemLogs.deviceLabel, nonEmpty(log.deviceModel))
            ])

            detailSection(AppStrings.SystemLogs.reviewSection, rows: [
                (AppStrings.SystemLogs.statusLabel, log.isReviewed ? AppStrings.SystemLogs.reviewed : AppStrings.SystemLogs.notReviewed),
                (AppStrings.SystemLogs.reviewedAtLabel, log.reviewedAt.map(SystemLogDisplayFormatting.dateTime)),
                (AppStrings.SystemLogs.reviewedByLabel, reviewerDisplayName)
            ])

            if !log.metadata.isEmpty {
                metadataSection
            }

            detailSection(AppStrings.SystemLogs.tracingSection, rows: [
                (AppStrings.SystemLogs.correlationIdLabel, nonEmpty(log.correlationId))
            ])
        }
    }

    private var retentionUntil: Date? {
        guard let retentionPolicy = log.retentionPolicy else { return nil }
        return Calendar.current.date(byAdding: .day, value: retentionPolicy.defaultRetentionDays, to: log.createdAt)
    }

    private var copyText: String {
        var lines = [
            "\(AppStrings.SystemLogs.detailTitle): \(log.id)",
            "\(AppStrings.SystemLogs.createdAtLabel): \(SystemLogDisplayFormatting.dateTime(log.createdAt))",
            "\(AppStrings.SystemLogs.severityLabel): \(SystemLogDisplayFormatting.severityTitle(log.severity))",
            "\(AppStrings.SystemLogs.categoryLabel): \(SystemLogDisplayFormatting.categoryTitle(log.category))",
            "\(AppStrings.SystemLogs.eventLabel): \(SystemLogDisplayFormatting.eventTypeTitle(log.eventType))",
            "\(AppStrings.SystemLogs.titleLabel): \(log.summary)"
        ]
        let optionalRows: [(String, String?)] = [
            (AppStrings.SystemLogs.errorCodeLabel, log.errorCode),
            (AppStrings.SystemLogs.moduleLabel, log.moduleName),
            (AppStrings.SystemLogs.operationLabel, log.operationName),
            (AppStrings.SystemLogs.userIdLabel, log.actorUserId),
            (AppStrings.SystemLogs.targetIdLabel, log.targetId),
            (AppStrings.SystemLogs.organizationIdLabel, log.organizationId),
            (AppStrings.SystemLogs.correlationIdLabel, log.correlationId),
            (AppStrings.SystemLogs.appVersionLabel, log.appVersion),
            (AppStrings.SystemLogs.osVersionLabel, log.osVersion),
            (AppStrings.SystemLogs.deviceLabel, log.deviceModel)
        ]
        lines.append(contentsOf: optionalRows.compactMap { title, value in
            nonEmpty(value).map { "\(title): \($0)" }
        })
        if !log.metadata.isEmpty {
            lines.append(contentsOf: log.metadata.keys.sorted().map { "\($0): \(log.metadata[$0] ?? "")" })
        }
        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private var reviewActionSection: some View {
        if !log.isReviewed {
            DetailCard {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    Text(AppStrings.SystemLogs.reviewStatusSection)
                        .font(AppTheme.sectionTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(AppStrings.SystemLogs.reviewInstruction)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                PrimaryActionButton(
                    title: AppStrings.SystemLogs.markReviewed,
                    loadingTitle: AppStrings.SystemLogs.markingReviewed,
                    isEnabled: true,
                    isLoading: isMarkingReviewed,
                    systemImage: "checkmark.seal"
                ) {
                    Task {
                        await onMarkReviewed()
                    }
                }

                if let reviewErrorMessage {
                    Label(reviewErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accentDestructiveForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func detailSection(_ title: String, rows: [(String, String?)]) -> some View {
        let visibleRows = rows.compactMap { title, value -> (String, String)? in
            guard let value = nonEmpty(value) else { return nil }
            return (title, value)
        }

        if !visibleRows.isEmpty {
            DetailCard {
                Text(title)
                    .font(AppTheme.sectionTitleFont)
                    .foregroundStyle(AppTheme.textPrimary)

                VStack(spacing: 10) {
                    ForEach(visibleRows, id: \.0) { row in
                        SystemLogDetailRow(title: row.0, value: row.1)
                    }
                }
            }
        }
    }

    private var metadataSection: some View {
        DetailCard {
            Text(AppStrings.SystemLogs.metadataSection)
                .font(AppTheme.sectionTitleFont)
                .foregroundStyle(AppTheme.textPrimary)

            VStack(spacing: 10) {
                ForEach(log.metadata.keys.sorted(), id: \.self) { key in
                    SystemLogDetailRow(title: key, value: log.metadata[key] ?? "")
                }
            }
        }
    }

    private var targetTypeValue: String? {
        switch log.targetType {
        case .none, .unknown:
            nil
        default:
            SystemLogDisplayFormatting.targetTypeTitle(log.targetType)
        }
    }

    private var reviewerDisplayName: String? {
        guard log.isReviewed, let reviewedByUserId = nonEmpty(log.reviewedByUserId) else { return nil }
        if reviewedByUserId == Auth.auth().currentUser?.uid {
            return nonEmpty(Auth.auth().currentUser?.displayName)
                ?? nonEmpty(Auth.auth().currentUser?.email)
                ?? AppStrings.SystemLogs.reviewedByCurrentUser
        }
        if reviewedByUserId == log.actorUserId, let actorDisplayName = nonEmpty(log.actorDisplayName) {
            return actorDisplayName
        }
        return AppStrings.SystemLogs.reviewedByAdmin
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

}

private struct SystemLogDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                titleLabel.frame(width: 104, alignment: .leading)
                valueLabel
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                titleLabel
                valueLabel
            }
        }
    }

    private var titleLabel: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
    }

    private var valueLabel: some View {
        Text(value)
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}
