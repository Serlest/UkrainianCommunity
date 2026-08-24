import SwiftUI

struct ContentReportSheet: View {
    let target: ContentReportTarget
    @ObservedObject var coordinator: ContentReportCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: ContentReportReason?
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var receipt: ContentReportReceipt?
    @State private var errorMessage: String?

    private var normalizedDetails: String? {
        let value = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var canSubmit: Bool {
        guard let selectedReason, !isSubmitting, receipt == nil else { return false }
        return details.count <= 1_000 && (selectedReason != .other || normalizedDetails != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    targetCard

                    if let receipt {
                        successCard(receipt)
                    } else {
                        reportForm
                    }
                }
                .padding(AppTheme.pageHorizontal)
                .padding(.bottom, AppTheme.sectionSpacing)
                .appCenteredContent()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.pageBackground)
            .navigationTitle(AppStrings.Safety.reportTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppStrings.Action.cancel) {
                        dismissReport()
                    }
                    .disabled(isSubmitting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if receipt == nil {
                    submitBar
                } else {
                    doneBar
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private var targetCard: some View {
        AppEditorSectionCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: target.targetType.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 42, height: 42)
                    .background(
                        AppTheme.accentPrimary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(target.targetType.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                        .textCase(.uppercase)

                    Text(target.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var reportForm: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(AppStrings.Safety.reasonTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Picker(AppStrings.Safety.reasonTitle, selection: $selectedReason) {
                        Text(AppStrings.Safety.reasonPlaceholder)
                            .tag(nil as ContentReportReason?)
                        ForEach(ContentReportReason.allCases) { reason in
                            Text(reason.title).tag(reason as ContentReportReason?)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppTheme.accentPrimary)
                }
            }

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(AppStrings.Safety.detailsTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer(minLength: 0)
                        Text("\(details.count)/1000")
                            .font(.caption)
                            .foregroundStyle(details.count > 1_000 ? AppTheme.accentDestructive : AppTheme.textSecondary)
                    }

                    ZStack(alignment: .topLeading) {
                        if details.isEmpty {
                            Text(AppStrings.Safety.detailsPlaceholder)
                                .font(.body)
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 14)
                        }

                        TextEditor(text: $details)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 120)
                            .padding(8)
                    }
                    .background(
                        AppTheme.surfaceSecondary,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.borderSubtle)
                    )

                    if selectedReason == .other && normalizedDetails == nil {
                        Text(AppStrings.Safety.otherDetailsRequired)
                            .font(.caption)
                            .foregroundStyle(AppTheme.accentDestructive)
                    }
                }
            }

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label(AppStrings.Safety.reviewTitle, systemImage: "shield.checkered")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(reviewMessage)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(AppStrings.Safety.emergencyNotice)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let errorMessage {
                InlineMessageCard(style: .error, message: errorMessage)
            }
        }
    }

    private var reviewMessage: String {
        guard let selectedReason else { return AppStrings.Safety.reviewStandard }
        return selectedReason.isUrgent ? AppStrings.Safety.reviewUrgent : AppStrings.Safety.reviewStandard
    }

    private func successCard(_ receipt: ContentReportReceipt) -> some View {
        UnifiedEmptyStateCard(
            systemImage: "checkmark.shield.fill",
            title: AppStrings.Safety.submittedTitle,
            message: receipt.wasDuplicate
                ? AppStrings.Safety.submittedDuplicate
                : AppStrings.Safety.submittedMessage
        )
    }

    private var submitBar: some View {
        VStack(spacing: 0) {
            Divider()
            PrimaryActionButton(
                title: isSubmitting ? AppStrings.Safety.submitting : AppStrings.Safety.submit,
                isEnabled: canSubmit,
                isLoading: isSubmitting,
                systemImage: "exclamationmark.bubble"
            ) {
                submit()
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.vertical, 12)
            .appCenteredContent()
        }
        .background(AppTheme.pageBackground)
    }

    private var doneBar: some View {
        VStack(spacing: 0) {
            Divider()
            PrimaryActionButton(title: AppStrings.Common.done, systemImage: "checkmark") {
                dismissReport()
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.vertical, 12)
            .appCenteredContent()
        }
        .background(AppTheme.pageBackground)
    }

    private func submit() {
        guard let selectedReason, canSubmit else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                receipt = try await coordinator.submit(
                    target: target,
                    reason: selectedReason,
                    details: normalizedDetails
                )
            } catch let error as ContentReportSubmissionError {
                errorMessage = message(for: error)
            } catch {
                errorMessage = AppStrings.Safety.errorUnknown
            }
            isSubmitting = false
        }
    }

    private func message(for error: ContentReportSubmissionError) -> String {
        switch error {
        case .authenticationRequired:
            AppStrings.Safety.errorAuthentication
        case .permissionDenied:
            AppStrings.Safety.errorPermission
        case .ownContent:
            AppStrings.Safety.errorOwnContent
        case .targetUnavailable:
            AppStrings.Safety.errorUnavailable
        case .network:
            AppStrings.Safety.errorNetwork
        case .unknown:
            AppStrings.Safety.errorUnknown
        }
    }

    private func dismissReport() {
        coordinator.dismiss()
        dismiss()
    }
}
