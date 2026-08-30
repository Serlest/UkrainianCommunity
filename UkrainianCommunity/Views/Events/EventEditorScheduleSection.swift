import SwiftUI

extension EventEditorView {
        var occurrencesCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: editorCardSpacing) {
                    editorSectionTitle(ContentPublishingStrings.multipleDates)

                    ForEach(Array(viewModel.additionalOccurrences.enumerated()), id: \.element.id) { index, occurrence in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label {
                                    Text(verbatim: "\(ContentPublishingStrings.multipleDates) \(index + 2)")
                                } icon: {
                                    Image(systemName: "calendar.badge.clock")
                                }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Spacer()
                                Button(role: .destructive) {
                                    viewModel.removeOccurrence(id: occurrence.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .frame(width: AppTheme.minimumInteractiveTarget, height: AppTheme.minimumInteractiveTarget)
                                }
                                .accessibilityLabel(ContentPublishingStrings.removeOccurrence)
                            }

                            DatePicker(
                                AppStrings.Events.fieldStartDate,
                                selection: occurrenceStartBinding(occurrence),
                                displayedComponents: occurrence.isAllDay ? [.date] : [.date, .hourAndMinute]
                            )
                            Toggle(AppStrings.Events.hasEndDate, isOn: occurrenceHasEndBinding(occurrence))
                            if occurrence.endDate > occurrence.startDate {
                                DatePicker(
                                    AppStrings.Events.fieldEndDate,
                                    selection: occurrenceEndBinding(occurrence),
                                    in: occurrence.startDate...,
                                    displayedComponents: occurrence.isAllDay ? [.date] : [.date, .hourAndMinute]
                                )
                            }
                            Toggle(AppStrings.Events.allDay, isOn: occurrenceAllDayBinding(occurrence))
                        }
                        .padding(.vertical, 6)

                        if index < viewModel.additionalOccurrences.count - 1 {
                            editorDivider
                        }
                    }

                    Button {
                        viewModel.addOccurrence()
                    } label: {
                        Label(ContentPublishingStrings.addOccurrence, systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: AppTheme.minimumInteractiveTarget)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.allOccurrences.count >= EventEditorViewModel.maximumOccurrenceCount)

                    Text("\(viewModel.allOccurrences.count)/\(EventEditorViewModel.maximumOccurrenceCount)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }

        func occurrenceStartBinding(_ occurrence: EventOccurrence) -> Binding<Date> {
            Binding(
                get: { viewModel.additionalOccurrences.first(where: { $0.id == occurrence.id })?.startDate ?? occurrence.startDate },
                set: { newValue in
                    let duration = occurrence.endDate.timeIntervalSince(occurrence.startDate)
                    let newEndDate = duration > 0 ? newValue.addingTimeInterval(duration) : newValue
                    viewModel.updateOccurrence(id: occurrence.id, startDate: newValue, endDate: newEndDate)
                }
            )
        }

        func occurrenceHasEndBinding(_ occurrence: EventOccurrence) -> Binding<Bool> {
            Binding(
                get: {
                    let current = viewModel.additionalOccurrences.first(where: { $0.id == occurrence.id }) ?? occurrence
                    return current.endDate > current.startDate
                },
                set: { hasEndDate in
                    let current = viewModel.additionalOccurrences.first(where: { $0.id == occurrence.id }) ?? occurrence
                    let endDate = hasEndDate
                        ? Calendar.current.date(byAdding: .hour, value: 1, to: current.startDate) ?? current.startDate
                        : current.startDate
                    viewModel.updateOccurrence(
                        id: occurrence.id,
                        endDate: endDate,
                        hasExplicitEndDate: hasEndDate
                    )
                }
            )
        }

        func occurrenceEndBinding(_ occurrence: EventOccurrence) -> Binding<Date> {
            Binding(
                get: { viewModel.additionalOccurrences.first(where: { $0.id == occurrence.id })?.endDate ?? occurrence.endDate },
                set: { viewModel.updateOccurrence(id: occurrence.id, endDate: $0) }
            )
        }

        func occurrenceAllDayBinding(_ occurrence: EventOccurrence) -> Binding<Bool> {
            Binding(
                get: { viewModel.additionalOccurrences.first(where: { $0.id == occurrence.id })?.isAllDay ?? occurrence.isAllDay },
                set: { viewModel.updateOccurrence(id: occurrence.id, isAllDay: $0) }
            )
        }

        var dateTimeCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: editorCardSpacing) {
                    editorSectionTitle(AppStrings.Events.dateSectionTitle)
                    EventDatePickerRow(systemImage: "calendar", title: AppStrings.Events.fieldStartDate, value: dateValue(viewModel.startDate)) {
                        activeDatePicker = .startDate
                    }
                    if !viewModel.isAllDay {
                        editorDivider
                        EventDatePickerRow(systemImage: "clock", title: AppStrings.Events.startTime, value: timeValue(viewModel.startDate)) {
                            activeDatePicker = .startTime
                        }
                    }
                    editorDivider
                    explicitEndDateRow
                    if viewModel.hasExplicitEndDate {
                        editorDivider
                        EventDatePickerRow(systemImage: "calendar", title: AppStrings.Events.fieldEndDate, value: dateValue(viewModel.endDate)) {
                            activeDatePicker = .endDate
                        }
                        if !viewModel.isAllDay {
                            editorDivider
                            EventDatePickerRow(systemImage: "clock", title: AppStrings.Events.endTime, value: timeValue(viewModel.endDate)) {
                                activeDatePicker = .endTime
                            }
                        }
                    }
                    editorDivider
                    allDayRow
                }
            }
        }

        var explicitEndDateRow: some View {
            HStack(spacing: AppTheme.dashboardSpacing) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                Text(AppStrings.Events.hasEndDate)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer(minLength: AppTheme.eventsMetadataSpacing)

                Toggle("", isOn: $viewModel.hasExplicitEndDate)
                    .labelsHidden()
            }
            .frame(minHeight: 48)
        }

        var allDayRow: some View {
            HStack(spacing: AppTheme.dashboardSpacing) {
                Image(systemName: "sun.max")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                Text(AppStrings.Events.allDay)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer(minLength: AppTheme.eventsMetadataSpacing)

                Toggle("", isOn: Binding(
                    get: { viewModel.isAllDay },
                    set: { viewModel.setAllDay($0) }
                ))
                    .labelsHidden()
            }
            .frame(minHeight: 48)
        }

        func dateValue(_ date: Date) -> String {
            LocalizationStore.dateString(from: date, dateStyle: .medium, timeStyle: .none)
        }

        func timeValue(_ date: Date) -> String {
            LocalizationStore.dateString(from: date, dateStyle: .none, timeStyle: .short)
        }

        func dateBinding(for picker: EventEditorDatePicker) -> Binding<Date> {
            switch picker {
            case .startDate:
                Binding(
                    get: { viewModel.startDate },
                    set: { viewModel.setStartDateComponent($0) }
                )
            case .startTime:
                Binding(
                    get: { viewModel.startDate },
                    set: { viewModel.setStartTimeComponent($0) }
                )
            case .endDate:
                Binding(
                    get: { viewModel.endDate },
                    set: { viewModel.setEndDateComponent($0) }
                )
            case .endTime:
                Binding(
                    get: { viewModel.endDate },
                    set: { viewModel.setEndTimeComponent($0) }
                )
            }
        }

    enum EventEditorDatePicker: Identifiable {
        case startDate
        case startTime
        case endDate
        case endTime

        var id: String {
            switch self {
            case .startDate:
                "startDate"
            case .startTime:
                "startTime"
            case .endDate:
                "endDate"
            case .endTime:
                "endTime"
            }
        }

        var title: String {
            switch self {
            case .startDate:
                AppStrings.Events.fieldStartDate
            case .startTime:
                AppStrings.Events.startTime
            case .endDate:
                AppStrings.Events.fieldEndDate
            case .endTime:
                AppStrings.Events.endTime
            }
        }

        var displayedComponents: DatePickerComponents {
            switch self {
            case .startDate, .endDate:
                .date
            case .startTime, .endTime:
                .hourAndMinute
            }
        }
    }

    struct EventDatePickerRow: View {
        let systemImage: String
        let title: String
        let value: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(alignment: .center, spacing: AppTheme.dashboardSpacing) {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                        .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    Text(value)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(minHeight: 48)
        }
    }

    struct EventDatePickerSheet: View {
        @Environment(\.dismiss) var dismiss
        let title: String
        @Binding var selection: Date
        let displayedComponents: DatePickerComponents

        var body: some View {
            NavigationStack {
                VStack {
                    DatePicker(title, selection: $selection, displayedComponents: displayedComponents)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .padding(.top, AppTheme.sectionSpacing)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .background(AppBackgroundView())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppStrings.Common.done) {
                            dismiss()
                        }
                    }
                }
            }
            .presentationDetents([.height(340)])
            .presentationDragIndicator(.visible)
        }
    }
}
