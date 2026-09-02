import SwiftUI

extension OrganizationEditorView {
    var directoryFeaturesCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle(AppStrings.Organizations.servicesSectionTitle)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 138, maximum: 260), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(OrganizationServiceMode.allCases) { mode in
                        Button {
                            viewModel.toggleServiceMode(mode)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: mode.systemImage)
                                    .frame(width: 20)
                                Text(mode.title)
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(viewModel.serviceModes.contains(mode) ? Color.white : AppTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(viewModel.serviceModes.contains(mode) ? AppTheme.accentPrimary : AppTheme.surfaceControl)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(AppTheme.borderSubtle, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                iconTextField(
                    systemImage: "map",
                    placeholder: AppStrings.Organizations.serviceAreaPlaceholder,
                    text: $viewModel.serviceArea
                )

                TextField(
                    AppStrings.Organizations.servicesPlaceholder,
                    text: $viewModel.services,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .font(.subheadline)
                .textInputAutocapitalization(.sentences)
                .organizationEditorCompactInputStyle(minHeight: summaryTextHeight)

                serviceSuggestionRow(language: .ukrainian)

                openingHoursEditor
            }
        }
    }

    private var openingHoursEditor: some View {
        VStack(alignment: .leading, spacing: editorCardSpacing) {
            editorSectionTitle(AppStrings.Organizations.hoursSectionTitle)

            ForEach(OrganizationWeekday.allCases) { day in
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(day.title, isOn: isWorkingDayBinding(day))
                        .font(.footnote.weight(.semibold))

                    if hasOpeningHours(for: day) {
                        HStack(spacing: 8) {
                            DatePicker(
                                AppStrings.Organizations.openingTimeAccessibilityLabel(for: day.title),
                                selection: timeBinding(for: day, opening: true),
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()

                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)

                            DatePicker(
                                AppStrings.Organizations.closingTimeAccessibilityLabel(for: day.title),
                                selection: timeBinding(for: day, opening: false),
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()

                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.surfaceControl, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(AppTheme.borderSubtle, lineWidth: 1)
                }
            }

            iconTextField(
                systemImage: "calendar.badge.exclamationmark",
                placeholder: AppStrings.Organizations.specialHoursPlaceholder,
                text: $viewModel.specialHoursNote
            )
        }
    }

    var directoryActionsCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle(AppStrings.Organizations.actionsSectionTitle)

                iconTextField(
                    systemImage: "bag",
                    placeholder: AppStrings.Organizations.orderURLPlaceholder,
                    text: $viewModel.orderURL
                )
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                iconTextField(
                    systemImage: "calendar.badge.plus",
                    placeholder: AppStrings.Organizations.bookingURLPlaceholder,
                    text: $viewModel.bookingURL
                )
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                editorSectionTitle(AppStrings.Organizations.offerSectionTitle)

                iconTextField(
                    systemImage: "tag",
                    placeholder: AppStrings.Organizations.offerTitlePlaceholder,
                    text: $viewModel.currentOfferTitle
                )

                TextField(
                    AppStrings.Organizations.offerDetailsPlaceholder,
                    text: $viewModel.currentOfferDetails,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .font(.subheadline)
                .organizationEditorCompactInputStyle(minHeight: summaryTextHeight)

                iconTextField(
                    systemImage: "link",
                    placeholder: AppStrings.Organizations.offerURLPlaceholder,
                    text: $viewModel.currentOfferURL
                )
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Toggle(
                    AppStrings.Organizations.offerValidUntil,
                    isOn: Binding(
                        get: { viewModel.currentOfferValidUntil != nil },
                        set: { viewModel.currentOfferValidUntil = $0 ? Date() : nil }
                    )
                )
                .font(.subheadline.weight(.semibold))

                if let validUntil = Binding($viewModel.currentOfferValidUntil) {
                    DatePicker(
                        AppStrings.Organizations.offerValidUntil,
                        selection: validUntil,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                }
            }
        }
    }

    var organizationDirectoryLocalizationCard: some View {
        editorCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: editorCardSpacing) {
                    Text(ContentPublishingStrings.germanFallbackHint)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)

                    iconTextField(
                        systemImage: "map",
                        placeholder: AppStrings.Organizations.serviceAreaPlaceholder,
                        text: $viewModel.germanServiceArea
                    )

                    TextField(AppStrings.Organizations.servicesPlaceholder, text: $viewModel.germanServices, axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.sentences)
                        .organizationEditorCompactInputStyle(minHeight: summaryTextHeight)

                    serviceSuggestionRow(language: .german)

                    iconTextField(
                        systemImage: "calendar.badge.exclamationmark",
                        placeholder: AppStrings.Organizations.specialHoursPlaceholder,
                        text: $viewModel.germanSpecialHoursNote
                    )

                    iconTextField(
                        systemImage: "tag",
                        placeholder: AppStrings.Organizations.offerTitlePlaceholder,
                        text: $viewModel.germanCurrentOfferTitle
                    )

                    TextField(AppStrings.Organizations.offerDetailsPlaceholder, text: $viewModel.germanCurrentOfferDetails, axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.sentences)
                        .organizationEditorCompactInputStyle(minHeight: summaryTextHeight)
                }
                .padding(.top, editorCardSpacing)
            } label: {
                Label(ContentPublishingStrings.germanOptional, systemImage: "globe.europe.africa")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .accessibilityIdentifier("organization.editor.directory.localization.german")
        }
    }

    private func hasOpeningHours(for day: OrganizationWeekday) -> Bool {
        guard let value = viewModel.regularHours[day.rawValue] else { return false }
        return value != "closed"
    }

    private func serviceSuggestionRow(language: PublishedContentLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ContentPublishingStrings.serviceSuggestions)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            AppHorizontalChipRow(spacing: 6) {
                ForEach(viewModel.suggestedServices(language: language), id: \.self) { suggestion in
                    Button {
                        viewModel.toggleSuggestedService(suggestion, language: language)
                    } label: {
                        AppInfoChip(
                            title: suggestion,
                            systemImage: viewModel.isSuggestedServiceSelected(suggestion, language: language) ? "checkmark" : "plus",
                            tint: viewModel.isSuggestedServiceSelected(suggestion, language: language) ? AppTheme.accentPrimaryForeground : AppTheme.textSecondary,
                            fill: viewModel.isSuggestedServiceSelected(suggestion, language: language) ? AppTheme.accentPrimary.opacity(0.14) : AppTheme.surfaceControl,
                            size: .small
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func isWorkingDayBinding(_ day: OrganizationWeekday) -> Binding<Bool> {
        Binding(
            get: { hasOpeningHours(for: day) },
            set: { isOpen in
                viewModel.setHours(isOpen ? "09:00-18:00" : "", for: day.rawValue)
            }
        )
    }

    private func timeBinding(for day: OrganizationWeekday, opening: Bool) -> Binding<Date> {
        Binding(
            get: { dateForStoredTime(day: day, opening: opening) },
            set: { newDate in
                let otherDate = dateForStoredTime(day: day, opening: !opening)
                let openingDate = opening ? newDate : otherDate
                let closingDate = opening ? otherDate : newDate
                viewModel.setHours(
                    "\(Self.timeFormatter.string(from: openingDate))-\(Self.timeFormatter.string(from: closingDate))",
                    for: day.rawValue
                )
            }
        )
    }

    private func dateForStoredTime(day: OrganizationWeekday, opening: Bool) -> Date {
        let fallback = opening ? "09:00" : "18:00"
        let value = viewModel.regularHours[day.rawValue] ?? "09:00-18:00"
        let parts = value.replacingOccurrences(of: "–", with: "-").split(separator: "-", maxSplits: 1)
        let selected = parts.indices.contains(opening ? 0 : 1) ? String(parts[opening ? 0 : 1]) : fallback
        return Self.timeFormatter.date(from: selected.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? Self.timeFormatter.date(from: fallback)
            ?? Date()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

enum OrganizationWeekday: String, CaseIterable, Identifiable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    var id: String { rawValue }

    var title: String {
        let ukrainian = LocalizationStore.language == .ukrainian
        return switch self {
        case .monday: ukrainian ? "Понеділок" : "Montag"
        case .tuesday: ukrainian ? "Вівторок" : "Dienstag"
        case .wednesday: ukrainian ? "Середа" : "Mittwoch"
        case .thursday: ukrainian ? "Четвер" : "Donnerstag"
        case .friday: ukrainian ? "П’ятниця" : "Freitag"
        case .saturday: ukrainian ? "Субота" : "Samstag"
        case .sunday: ukrainian ? "Неділя" : "Sonntag"
        }
    }
}
