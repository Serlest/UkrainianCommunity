import SwiftUI

extension EventEditorView {
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
                    EventDatePickerRow(systemImage: "calendar", title: AppStrings.Events.fieldEndDate, value: dateValue(viewModel.endDate)) {
                        activeDatePicker = .endDate
                    }
                    if !viewModel.isAllDay {
                        editorDivider
                        EventDatePickerRow(systemImage: "clock", title: AppStrings.Events.endTime, value: timeValue(viewModel.endDate)) {
                            activeDatePicker = .endTime
                        }
                    }
                    editorDivider
                    allDayRow
                }
            }
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
                        .foregroundStyle(AppTheme.accentPrimary)
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
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
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
