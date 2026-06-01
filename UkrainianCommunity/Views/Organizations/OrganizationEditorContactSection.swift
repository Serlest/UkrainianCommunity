import SwiftUI

extension OrganizationEditorView {
    var contactCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle(AppStrings.Organizations.contactSectionTitle)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.eventsMetadataSpacing) {
                    iconTextField(systemImage: "envelope", placeholder: AppStrings.Organizations.fieldContactEmail, text: $viewModel.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    iconTextField(systemImage: "phone", placeholder: AppStrings.Organizations.phonePlaceholder, text: $viewModel.phone)
                        .keyboardType(.phonePad)
                }

                iconTextField(systemImage: "globe", placeholder: AppStrings.Organizations.fieldWebsite, text: $viewModel.website)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                iconTextField(systemImage: "paperplane", placeholder: AppStrings.Organizations.fieldTelegramURL, text: $viewModel.telegramURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                iconTextField(systemImage: "heart", placeholder: AppStrings.Organizations.fieldDonationURL, text: $viewModel.donationURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                iconTextField(systemImage: "person.crop.circle", placeholder: AppStrings.Organizations.fieldContactPerson, text: $viewModel.contactPerson)
                    .textInputAutocapitalization(.words)

                VStack(alignment: .leading, spacing: 7) {
                    Text(AppStrings.Organizations.socialLinksTitle)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    iconTextField(systemImage: "person.2", placeholder: AppStrings.Organizations.fieldFacebookURL, text: $viewModel.facebookURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    iconTextField(systemImage: "camera", placeholder: AppStrings.Organizations.fieldInstagramURL, text: $viewModel.instagramURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    iconTextField(systemImage: "phone.bubble", placeholder: AppStrings.Organizations.fieldWhatsAppURL, text: $viewModel.whatsappURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    iconTextField(systemImage: "play.rectangle", placeholder: AppStrings.Organizations.fieldYouTubeURL, text: $viewModel.youtubeURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    iconTextField(systemImage: "briefcase", placeholder: AppStrings.Organizations.fieldLinkedInURL, text: $viewModel.linkedinURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        }
    }
}
