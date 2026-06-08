import SwiftUI

struct SystemLogsOverviewCards: View {
    let metrics: [SystemLogOverviewMetric]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
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
