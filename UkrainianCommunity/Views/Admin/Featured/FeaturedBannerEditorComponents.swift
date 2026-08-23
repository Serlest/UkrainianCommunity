import SwiftUI

struct FeaturedEditorValueRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        Label {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer(minLength: AppTheme.eventsMetadataSpacing)
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accentPrimary)
        }
    }
}
struct FeaturedBannerActionTargetSelectionField: View {
    let kind: FeaturedBannerActionTargetKind?
    let selectedItem: FeaturedBannerActionTargetItem?
    let targetID: String
    let isLoading: Bool
    let onSelect: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    Image(systemName: kind?.systemImage ?? "arrow.up.forward.app")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                        .frame(width: AppTheme.metadataIconSize)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedItem?.title ?? AppStrings.FeaturedEditor.selectTarget)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedItem == nil ? AppTheme.textSecondary : AppTheme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if let subtitle = selectedItem?.subtitle ?? selectedItem?.metadata {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)
                        } else if let rawID = nonEmpty(targetID) {
                            Text(AppStrings.FeaturedEditor.selectedTargetID(rawID))
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding(.horizontal, AppTheme.inputHorizontalPadding)
                .padding(.vertical, AppTheme.eventsMetadataSpacing)
                .frame(minHeight: AppTheme.newsEditorInputHeight)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                        .strokeBorder(AppTheme.borderSubtle)
                )
            }
            .buttonStyle(.plain)

            if selectedItem != nil || !targetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(role: .destructive, action: onClear) {
                    Label(AppStrings.FeaturedEditor.clearTarget, systemImage: "xmark.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct FeaturedBannerActionTargetPickerSheet: View {
    @ObservedObject var viewModel: FeaturedBannerEditorViewModel
    @Binding var searchText: String
    let onSelect: (FeaturedBannerActionTargetItem) -> Void
    @Environment(\.dismiss) private var dismiss

    private var items: [FeaturedBannerActionTargetItem] {
        viewModel.actionTargetItems(matching: searchText)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingCurrentActionTargets && items.isEmpty {
                    LoadingStateCard(title: AppStrings.FeaturedEditor.loadingTargets)
                        .padding(AppTheme.pageHorizontal)
                } else if let error = viewModel.actionTargetLoadError, items.isEmpty {
                    ErrorStateCard(
                        systemImage: "arrow.up.forward.app",
                        title: AppStrings.FeaturedEditor.targetPickerTitle(viewModel.actionTargetPickerKind?.title ?? ""),
                        message: error,
                        retryTitle: AppStrings.Action.retry
                    ) {
                        Task { await viewModel.refreshActionTargets() }
                    }
                    .padding(AppTheme.pageHorizontal)
                } else if items.isEmpty {
                    EmptyStateCard(
                        systemImage: "magnifyingglass",
                        title: AppStrings.FeaturedEditor.noTargetsFound,
                        message: AppStrings.FeaturedEditor.noTargetsFoundMessage
                    )
                    .padding(AppTheme.pageHorizontal)
                } else {
                    List(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            FeaturedBannerActionTargetPickerRow(
                                item: item,
                                isSelected: viewModel.actionTargetID == item.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(AppStrings.FeaturedEditor.targetPickerTitle(viewModel.actionTargetPickerKind?.title ?? ""))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Action.cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(AppStrings.Action.retry) {
                        Task { await viewModel.refreshActionTargets() }
                    }
                    .disabled(viewModel.isLoadingCurrentActionTargets)
                }
            }
            .searchable(text: $searchText, prompt: AppStrings.FeaturedEditor.targetPickerSearch)
            .task {
                await viewModel.loadActionTargetsIfNeeded()
            }
        }
    }
}

struct FeaturedBannerActionTargetPickerRow: View {
    let item: FeaturedBannerActionTargetItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.eventsControlGroupSpacing) {
            Image(systemName: item.kind.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: AppTheme.iconButtonSize, height: AppTheme.iconButtonSize)
                .background(AppTheme.badgeBlueFill, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }

                if let metadata = item.metadata {
                    Text(metadata)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.78))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: AppTheme.eventsMetadataSpacing)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.accentPrimary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

extension FeaturedBannerRegionScope {
    var editorTitle: String {
        switch self {
        case .allAustria:
            return AppStrings.Home.regionAllAustria
        case .federalState:
            return AppStrings.FeaturedEditor.regionScopeFederalState
        }
    }
}

extension FeaturedBannerVisibleSection {
    var editorTitle: String {
        switch self {
        case .home:
            return AppStrings.Tabs.home
        case .events:
            return AppStrings.Tabs.events
        case .organizations:
            return AppStrings.Tabs.organizations
        case .unsupportedLegacy:
            return AppStrings.FeaturedManagement.unsupportedLegacy
        }
    }
}

extension FeaturedBannerActionType {
    var editorHelperText: String {
        switch self {
        case .none:
            return AppStrings.FeaturedEditor.actionHelperNoTap
        case .news, .event, .organization:
            return AppStrings.FeaturedEditor.actionHelperTarget
        case .unsupportedLegacy:
            return AppStrings.FeaturedManagement.unsupportedLegacy
        case .externalURL:
            return AppStrings.FeaturedEditor.actionHelperExternalURL
        }
    }

    var editorTitle: String {
        switch self {
        case .none:
            return AppStrings.FeaturedManagement.actionNone
        case .news:
            return AppStrings.News.title
        case .event:
            return AppStrings.Tabs.events
        case .organization:
            return AppStrings.Tabs.organizations
        case .unsupportedLegacy:
            return AppStrings.FeaturedManagement.unsupportedLegacy
        case .externalURL:
            return AppStrings.FeaturedManagement.actionExternalURL
        }
    }
}
