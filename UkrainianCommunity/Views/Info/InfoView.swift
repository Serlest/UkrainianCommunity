import SwiftUI

struct InfoView: View {
    @ObservedObject var viewModel: InfoViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GradientHeroCard(title: AppStrings.Info.placeholderTitle, subtitle: AppStrings.Info.placeholderBody) {
                    EmptyView()
                }

                AdaptiveCardGrid(items: viewModel.items) { item in
                    CommunityCard {
                        Label(item.title, systemImage: item.systemImage)
                            .font(.headline)
                            .foregroundStyle(AppTheme.primaryBlue)
                        Text(item.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .background(AppTheme.subtleGradient.ignoresSafeArea())
        .navigationTitle(AppStrings.Info.title)
    }
}

#Preview {
    NavigationStack {
        InfoView(viewModel: InfoViewModel(repository: MockInfoRepository()))
    }
}
