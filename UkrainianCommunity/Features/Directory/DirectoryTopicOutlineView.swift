import SwiftUI

struct DirectoryTopicOutlineView: View {
    let titles: [String]
    let language: AppLanguage
    let onSelect: (Int) -> Void
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(titles.indices, id: \.self) { index in
                    Button {
                        isExpanded = false
                        onSelect(index)
                    } label: {
                        Text(titles[index])
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    if index < titles.count - 1 { Divider() }
                }
            }
        } label: {
            Label(DirectoryText(ukrainian: "Перейти до пункту", german: "Zu einem Abschnitt springen").value(for: language),
                  systemImage: "list.bullet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimaryForeground)
        }
        .padding(14)
        .appGlassCard()
    }
}
