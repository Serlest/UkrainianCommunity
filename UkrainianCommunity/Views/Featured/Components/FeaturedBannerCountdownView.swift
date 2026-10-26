import SwiftUI

/// Only the visible timer redraws, at minute boundaries and exactly at completion.
struct FeaturedBannerCountdownSchedule: TimelineSchedule {
    let target: Date
    func entries(from startDate: Date, mode: Mode) -> AnySequence<Date> {
        AnySequence(sequence(first: startDate) { date in
            guard date < target else { return nil }
            let seconds = target.timeIntervalSince(date)
            let untilNextMinute = seconds.truncatingRemainder(dividingBy: 60)
            return min(target, date.addingTimeInterval(untilNextMinute > 0.01 ? untilNextMinute : 60))
        })
    }
}

struct FeaturedBannerCountdownView: View {
    let countdown: FeaturedBannerCountdown
    var overArtwork: Bool = true
    @Environment(\.locale) private var locale
    var body: some View {
        TimelineView(FeaturedBannerCountdownSchedule(target: countdown.targetDate)) { context in
            if let value = countdown.remaining(at: context.date) {
                badge(value: BannerCountdownStrings.remaining(value))
            } else if countdown.completion == .showStarted {
                badge(value: BannerCountdownStrings.text("started"))
            }
        }
    }
    private func badge(value: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            let label = countdown.label(for: AppLanguage.resolved(from: locale))
            if !label.isEmpty { Text(label).font(.caption2.weight(.medium)).lineLimit(overArtwork ? 2 : nil) }
            Text(value).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .foregroundStyle(overArtwork ? Color.white : AppTheme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(2)
        .shadow(color: overArtwork ? .black.opacity(0.9) : .clear, radius: 1, y: 1)
        .shadow(color: overArtwork ? .black.opacity(0.6) : .clear, radius: 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("featuredBanner.countdown")
    }
}

struct FeaturedBannerEditorCountdownSection: View {
    @ObservedObject var viewModel: FeaturedBannerEditorViewModel
    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                Toggle(BannerCountdownStrings.text("enabled"), isOn: $viewModel.hasCountdown)
                    .font(.headline).accessibilityIdentifier("bannerEditor.countdown.enabled")
                if viewModel.hasCountdown {
                    Text(BannerCountdownStrings.text("date")).font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    DatePicker(BannerCountdownStrings.text("date"), selection: $viewModel.countdownDate)
                        .labelsHidden().datePickerStyle(.compact).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .environment(\.timeZone, TimeZone(identifier: "Europe/Vienna")!)
                        .accessibilityIdentifier("bannerEditor.countdown.date")
                    Text(BannerCountdownStrings.text("help")).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    EditorTextField(BannerCountdownStrings.text("label"), text: $viewModel.countdownLabel, systemImage: "textformat", counterText: "\(viewModel.countdownLabel.utf16.count)/40")
                        .accessibilityIdentifier("bannerEditor.countdown.label")
                    EditorTextField(BannerCountdownStrings.text("germanLabel"), text: $viewModel.countdownGermanLabel, systemImage: "globe", counterText: "\(viewModel.countdownGermanLabel.utf16.count)/40")
                    Picker(BannerCountdownStrings.text("completion"), selection: $viewModel.countdownCompletion) {
                        ForEach(FeaturedBannerCountdown.Completion.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu).accessibilityIdentifier("bannerEditor.countdown.completion")
                    if viewModel.countdownCompletion == .hideBanner {
                        Text(BannerCountdownStrings.text("hideHelp")).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
        }
    }
}
