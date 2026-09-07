import SwiftUI

struct SystemLogsOverviewCards: View {
    let metrics: [SystemLogOverviewMetric]
    var onSelect: ((SystemLogOverviewMetric) -> Void)?

    var body: some View {
        AppAdaptiveGrid(minimumWidth: 150, maximumWidth: 260, spacing: 10) {
            ForEach(metrics) { metric in
                Button {
                    onSelect?(metric)
                } label: {
                    metricCard(metric)
                }
                .buttonStyle(.plain)
                .disabled(onSelect == nil)
                .accessibilityHint(onSelect == nil ? "" : AppStrings.SystemLogs.metricFilterHint)
            }
        }
    }

    private func metricCard(_ metric: SystemLogOverviewMetric) -> some View {
        SoftContentCard(padding: AppTheme.metricCardPadding) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: metric.systemImage)
                        .foregroundStyle(SystemLogDisplayFormatting.toneTint(metric.tone))
                    Text(metric.value).font(.title3.weight(.bold)).foregroundStyle(AppTheme.textPrimary)
                    Spacer(minLength: 0)
                    if onSelect != nil {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(AppTheme.textSecondary)
                    }
                }
                Text(metric.title).font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(metric.subtitle).font(.caption)
                    .foregroundStyle(AppTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
