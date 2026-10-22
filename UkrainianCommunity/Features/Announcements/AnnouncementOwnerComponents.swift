import SwiftUI

struct AnnouncementPeriodSummary: View {
    let item: UserAnnouncement
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label { Text(Date(timeIntervalSince1970: item.startsAt / 1000), format: .dateTime.day().month().year().hour().minute()) } icon: { Image(systemName: "calendar") }
            Label { Text(Date(timeIntervalSince1970: item.expiresAt / 1000), format: .dateTime.day().month().year().hour().minute()) } icon: { Image(systemName: "calendar.badge.checkmark") }
        }.font(.caption).foregroundStyle(.secondary)
            .environment(\.timeZone, TimeZone(identifier: "Europe/Vienna")!)
            .accessibilityElement(children: .combine)
    }
}

struct AnnouncementAudienceSummary: View {
    let item: UserAnnouncement
    let users: [AnnouncementUser]?
    var compact = false
    var peopleOnly = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !peopleOnly {
                if !item.groups.isEmpty { Label(item.groups.map { AnnouncementStrings.group($0) }.joined(separator: ", "), systemImage: "person.3") }
                Label(item.regions.isEmpty ? AnnouncementStrings.austria : item.regions.compactMap(AustrianFederalState.init(rawValue:)).map(\.displayName).joined(separator: ", "), systemImage: "mappin.and.ellipse")
            }
            if !item.userIds.isEmpty {
                Text("\(AnnouncementManagementText.value("selected")): \(item.userIds.count)")
                if !compact {
                    ForEach(item.userIds, id: \.self) { id in
                        if let user = users?.first(where: { $0.id == id }) { AnnouncementUserLabel(user: user) }
                        else { Text(id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                }
            }
        }.font(compact ? .caption : .body).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AnnouncementUserLabel: View {
    let user: AnnouncementUser
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(user.name).font(.body.weight(.medium))
            if let email = user.email, !email.isEmpty { Text(email).font(.caption).foregroundStyle(.secondary) }
            if let region = user.region.flatMap(AustrianFederalState.init(rawValue:)) { Text(region.displayName).font(.caption).foregroundStyle(.secondary) }
            if user.available == false { Text(AnnouncementManagementText.value("unavailable")).font(.caption).foregroundStyle(.orange) }
        }.accessibilityElement(children: .combine)
    }
}

struct AnnouncementStatisticsView: View {
    let item: UserAnnouncement
    let statistics: AnnouncementResponse
    private var pushState: String {
        if item.phase() == "cancelled" { return AnnouncementManagementText.value("cancelled") }
        if item.phase() == "completed" && ["pending", "running", "failed"].contains(statistics.pushState ?? "") { return AnnouncementManagementText.value("completed") }
        switch statistics.pushState {
        case "completed": return AnnouncementManagementText.value("delivered")
        case "pending", "running", "failed", "disabled": return AnnouncementManagementText.value(statistics.pushState!)
        default: return AnnouncementManagementText.value("unknown")
        }
    }
    var body: some View {
        AnnouncementSection(AnnouncementStrings.stats) {
            LabeledContent(AnnouncementStrings.shown, value: String(statistics.presented ?? 0))
            LabeledContent(AnnouncementStrings.confirmed, value: String(statistics.acknowledged ?? 0))
            LabeledContent(AnnouncementStrings.action, value: String(statistics.action ?? 0))
            if item.push {
                Divider()
                LabeledContent(AnnouncementManagementText.value("pushState"), value: pushState)
                LabeledContent(AnnouncementStrings.pushSent, value: String(statistics.pushSuccess ?? 0))
                LabeledContent(AnnouncementStrings.pushFailed, value: String(statistics.pushFailure ?? 0))
            }
            Text(AnnouncementManagementText.value("pushHelp")).font(.caption).foregroundStyle(.secondary).lineLimit(nil).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            if let shown = statistics.guestPresented, shown > 0 { LabeledContent(AnnouncementStrings.guestShown, value: String(shown)) }
            if let acknowledged = statistics.guestAcknowledged, acknowledged > 0 { LabeledContent(AnnouncementStrings.guestAck, value: String(acknowledged)) }
        }
    }
}

struct AnnouncementPreviewView: View {
    let item: UserAnnouncement
    var selectedUsers: [AnnouncementUser] = []
    var body: some View {
        NavigationStack {
            EditorScreenShell(title: AnnouncementStrings.preview, closeStyle: .cancel) {
                ForEach(["uk", "de"], id: \.self) { lang in
                    AnnouncementSection(lang == "uk" ? AppLanguage.ukrainian.title : AppLanguage.german.title) {
                        Text(lang == "uk" ? item.title.uk : item.title.de).font(.headline)
                        Text(lang == "uk" ? item.body.uk : item.body.de)
                    }
                }
                AnnouncementSection(AnnouncementStrings.audience) {
                    AnnouncementAudienceSummary(item: item, users: selectedUsers)
                    Text(AnnouncementManagementText.value("union")).font(.caption).foregroundStyle(.secondary).lineLimit(nil).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    AnnouncementPeriodSummary(item: item)
                }
            }.navigationTitle(AnnouncementStrings.preview)
        }
    }
}

struct AnnouncementSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                if let title { AppEditorSectionTitle(title: title) }
                content
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.tint(AppTheme.accentPrimaryForeground)
    }
}

struct AnnouncementSchedulePicker: View {
    let title: String
    @Binding var selection: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.medium))
            ViewThatFits(in: .horizontal) {
                HStack { date; time }
                VStack(alignment: .leading, spacing: 8) { date; time }
            }
        }
    }
    private var date: some View {
        DatePicker(title, selection: $selection, displayedComponents: .date)
            .labelsHidden().datePickerStyle(.compact).fixedSize().accessibilityLabel(title)
    }
    private var time: some View {
        DatePicker(title, selection: $selection, displayedComponents: .hourAndMinute)
            .labelsHidden().datePickerStyle(.compact).fixedSize().accessibilityLabel(title)
    }
}
