import SwiftUI

struct ProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.user.fullName)
                        .font(.title3.weight(.bold))
                    Text(viewModel.user.bio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                MetadataRow(label: AppStrings.Profile.role, value: viewModel.user.role.title, systemImage: "person.badge.key")
                MetadataRow(label: AppStrings.Profile.accountStatus, value: viewModel.user.blockState.title, systemImage: "checkmark.shield")
                MetadataRow(label: AppStrings.Profile.memberSince, value: LocalizationStore.dateString(from: viewModel.user.joinedAt), systemImage: "calendar")
            }

            Section(AppStrings.Profile.capabilities) {
                ForEach(viewModel.capabilities, id: \.self) { capability in
                    Label(capability, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.primaryBlue)
                }
            }

            Section(AppStrings.Settings.title) {
                Picker(AppStrings.Settings.language, selection: $viewModel.settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }

                Picker(AppStrings.Settings.appearance, selection: $viewModel.settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }

                MetadataRow(label: AppStrings.Settings.privacyPolicy, value: AppStrings.Settings.placeholder, systemImage: "lock.doc")
                MetadataRow(label: AppStrings.Settings.terms, value: AppStrings.Settings.placeholder, systemImage: "doc.text")
            }
        }
        .navigationTitle(AppStrings.Profile.title)
    }
}

#Preview {
    NavigationStack {
        ProfileView(viewModel: ProfileViewModel(repository: MockUserRepository()))
    }
}
