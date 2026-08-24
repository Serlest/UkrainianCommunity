import SwiftUI

struct SystemLogsOverviewCards: View {
    let metrics: [SystemLogOverviewMetric]

    var body: some View {
        AppAdaptiveGrid(minimumWidth: 150, maximumWidth: 260, spacing: 10) {
            ForEach(metrics) { metric in
                SoftContentCard(padding: AppTheme.metricCardPadding) {
                    HStack(alignment: .top, spacing: AppTheme.compactCardInnerSpacing) {
                        Image(systemName: metric.systemImage)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(SystemLogDisplayFormatting.toneTint(metric.tone))
                            .frame(width: AppTheme.compactIconSurfaceSize, height: AppTheme.compactIconSurfaceSize)
                            .background(
                                SystemLogDisplayFormatting.toneFill(metric.tone),
                                in: RoundedRectangle(cornerRadius: AppTheme.metricIconSurfaceRadius, style: .continuous)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.value)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(AppTheme.textPrimary)

                            Text(metric.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)

                            Text(metric.subtitle)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }
}
