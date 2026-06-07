import FirebaseAuth
import SwiftUI

struct SystemLogDetailView: View {
    let log: SystemLogEntry
    let isMarkingReviewed: Bool
    let reviewErrorMessage: String?
    let onMarkReviewed: () async -> Void

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
        DetailPageContainer {
            DetailHeaderCard(title: SystemLogDisplayFormatting.summaryTitle(log.summary), subtitle: log.technicalMessage) {
                HStack(spacing: 8) {
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
                (AppStrings.SystemLogs.roleLabel, SystemLogDisplayFormatting.actorRoleTitle(log.actorRole))
            ])

            detailSection(AppStrings.SystemLogs.targetSection, rows: [
                (AppStrings.SystemLogs.typeLabel, targetTypeValue),
                (AppStrings.SystemLogs.titleLabel, nonEmpty(log.targetTitle))
            ])

            detailSection(AppStrings.SystemLogs.organizationSection, rows: [
                (AppStrings.SystemLogs.titleLabel, nonEmpty(log.organizationName))
            ])

            detailSection(AppStrings.SystemLogs.classificationSection, rows: [
                (AppStrings.SystemLogs.categoryLabel, SystemLogDisplayFormatting.categoryTitle(log.category)),
                (AppStrings.SystemLogs.severityLabel, SystemLogDisplayFormatting.severityTitle(log.severity)),
                (AppStrings.SystemLogs.eventLabel, SystemLogDisplayFormatting.eventTypeTitle(log.eventType)),
                (AppStrings.SystemLogs.outcomeLabel, log.outcome.map(SystemLogDisplayFormatting.outcomeTitle)),
                (AppStrings.SystemLogs.retentionLabel, log.retentionPolicy.map(SystemLogDisplayFormatting.retentionPolicyTitle)),
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
        .background(AppBackgroundView())
        .navigationTitle(AppStrings.SystemLogs.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
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
                        .foregroundStyle(AppTheme.accentDestructive)
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
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 104, alignment: .leading)

            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
