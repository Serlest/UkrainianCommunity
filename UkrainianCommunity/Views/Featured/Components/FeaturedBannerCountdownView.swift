import SwiftUI

/// Only the timer redraws; entries align to remaining seconds and the exact deadline.
struct FeaturedBannerCountdownSchedule: TimelineSchedule {
    let target: Date
    var isPaused: Bool = false
    func entries(from startDate: Date, mode: Mode) -> AnySequence<Date> {
        if isPaused { return AnySequence([startDate]) }
        return AnySequence(sequence(first: startDate) { date in
            guard date < target else { return nil }
            let seconds = target.timeIntervalSince(date)
            let untilNextSecond = seconds.truncatingRemainder(dividingBy: 1)
            return min(target, date.addingTimeInterval(untilNextSecond > 0.000_001 ? untilNextSecond : 1))
        })
    }
}

struct FeaturedBannerCountdownView: View {
    let countdown: FeaturedBannerCountdown
    var overArtwork: Bool = true
    var isRunning: Bool = true
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    var body: some View {
        TimelineView(FeaturedBannerCountdownSchedule(target: countdown.targetDate, isPaused: !isRunning || !isVisible || scenePhase != .active)) { context in
            if let value = countdown.remaining(at: context.date) {
                badge(value: BannerCountdownStrings.remaining(value))
            } else if countdown.completion == .showStarted {
                badge(value: BannerCountdownStrings.text("started"))
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
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
