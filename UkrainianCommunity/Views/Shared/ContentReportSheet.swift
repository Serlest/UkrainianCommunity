import SwiftUI

struct ContentReportSheet: View {
    let target: ContentReportTarget
    @ObservedObject var coordinator: ContentReportCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: ContentReportReason?
    @State private var details = ""
    @State private var legalBasis = ""
    @State private var evidence = ""
    @State private var goodFaithConfirmed = false
    @State private var isSubmitting = false
    @State private var receipt: ContentReportReceipt?
    @State private var errorMessage: String?

    private var normalizedDetails: String {
        let value = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    private var canSubmit: Bool {
        guard selectedReason != nil, !isSubmitting, receipt == nil else { return false }
        return normalizedDetails.count >= 20
            && details.count <= 5_000
            && legalBasis.count <= 1_000
            && evidence.count <= 5_000
            && goodFaithConfirmed
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
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: 42, height: 42)
                    .background(
                        AppTheme.accentPrimary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(target.targetType.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
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
                        Text("\(details.count)/5000")
                            .font(.caption)
                            .foregroundStyle(details.count > 1_000 ? AppTheme.accentDestructiveForeground : AppTheme.textSecondary)
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

                    if normalizedDetails.count < 20 {
                        Text(AppStrings.Safety.explanationRequired)
                            .font(.caption)
                            .foregroundStyle(AppTheme.accentDestructiveForeground)
                    }
                }
            }

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    reportTextArea(
                        title: AppStrings.Safety.legalBasisTitle,
                        placeholder: AppStrings.Safety.legalBasisPlaceholder,
                        text: $legalBasis,
                        limit: 1_000
                    )
                    Divider()
                    reportTextArea(
                        title: AppStrings.Safety.evidenceTitle,
                        placeholder: AppStrings.Safety.evidencePlaceholder,
                        text: $evidence,
                        limit: 5_000
                    )
                }
            }

            AppEditorSectionCard {
                Button {
                    goodFaithConfirmed.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: goodFaithConfirmed ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundStyle(goodFaithConfirmed ? AppTheme.accentPrimaryForeground : AppTheme.textSecondary)
                        Text(AppStrings.Safety.goodFaithDeclaration)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(goodFaithConfirmed ? AppStrings.Safety.goodFaithConfirmed : AppStrings.Safety.goodFaithNotConfirmed)
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
            message: AppStrings.Safety.submittedCase(receipt.caseNumber)
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
                    submission: ContentReportSubmission(
                        illegalExplanation: normalizedDetails,
                        legalBasis: normalizedValue(legalBasis),
                        evidence: normalizedValue(evidence),
                        goodFaithConfirmed: goodFaithConfirmed
                    )
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

    private func normalizedValue(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func reportTextArea(
        title: String,
        placeholder: String,
        text: Binding<String>,
        limit: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
                Spacer(minLength: 0)
                Text("\(text.wrappedValue.count)/\(limit)")
                    .font(.caption)
                    .foregroundStyle(text.wrappedValue.count > limit ? AppTheme.accentDestructiveForeground : AppTheme.textSecondary)
            }
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 14)
                }
                TextEditor(text: text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96)
                    .padding(8)
            }
            .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.borderSubtle))
        }
    }
}
