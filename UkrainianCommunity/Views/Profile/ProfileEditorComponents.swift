import PhotosUI
import SwiftUI
import UIKit

struct ProfileAvatarEditorCard: View {
    let avatarURL: URL?
    let initials: String
    let previewImage: UIImage?
    @Binding var selectedPhoto: PhotosPickerItem?
    let isLoadingAvatar: Bool
    let isSavingAvatar: Bool

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .center, spacing: 16) {
                AvatarArtworkView(
                    avatarURL: avatarURL,
                    previewImage: previewImage,
                    initials: initials,
                    size: 84,
                    isLoading: isLoadingAvatar || isSavingAvatar,
                    isDecorative: true
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppStrings.Profile.profilePhoto)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(AppStrings.Profile.avatarSubtitle)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                        Label(AppStrings.Profile.changeAvatar, systemImage: "camera.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.accentPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSavingAvatar)
                    .accessibilityLabel(AppStrings.Profile.changeAvatar)

                    if isLoadingAvatar {
                        Text(AppStrings.Profile.avatarLoading)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if isSavingAvatar {
                        Text(AppStrings.Profile.avatarUploading)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}


struct ProfileEditorTextArea: View {
    let title: String
    @Binding var text: String
    let counterText: String

    var body: some View {
        AppEditorField(title: title, counterText: counterText) {
            TextEditor(text: $text)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 92)
                .padding(8)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                        .strokeBorder(AppTheme.borderSubtle)
                )
                .accessibilityLabel(title)
        }
    }
}


struct ProfileReadOnlyField: View {
    let title: String
    let value: String
    let systemImage: String
    let helperText: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: AppTheme.metadataIconSize)

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.inputHorizontalPadding)
            .frame(height: AppTheme.newsEditorInputHeight)
            .background(AppTheme.surfaceSecondary.opacity(0.68), in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                    .strokeBorder(AppTheme.borderSubtle)
            )

            Text(helperText)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}


struct ProfileEditorPickerRow<PickerContent: View>: View {
    let title: String
    let systemImage: String
    let picker: PickerContent

    init(title: String, systemImage: String, @ViewBuilder picker: () -> PickerContent) {
        self.title = title
        self.systemImage = systemImage
        self.picker = picker()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: AppTheme.metadataIconSize)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)

            Spacer(minLength: 8)

            picker
                .font(.subheadline)
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(height: AppTheme.newsEditorInputHeight)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }
}
