import PhotosUI
import SwiftUI
import UIKit

struct ProfileAvatarEditorCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let avatarURL: URL?
    let initials: String
    let previewImage: UIImage?
    @Binding var selectedPhoto: PhotosPickerItem?
    let isLoadingAvatar: Bool
    let isSavingAvatar: Bool

    var body: some View {
        AppEditorSectionCard {
            (dynamicTypeSize.isAccessibilitySize
             ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
             : AnyLayout(HStackLayout(alignment: .center, spacing: 16))) {
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
                            .foregroundStyle(AppTheme.accentPrimaryForeground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSavingAvatar)
                    .accessibilityLabel(AppStrings.Profile.changeAvatar)
                    .accessibilityIdentifier("profile.edit.photo")

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    @Binding var text: String
    let counterText: String
    let maxLength: Int?

    init(
        title: String,
        text: Binding<String>,
        counterText: String,
        maxLength: Int? = nil
    ) {
        self.title = title
        _text = text
        self.counterText = counterText
        self.maxLength = maxLength
    }

    var body: some View {
        AppEditorField(title: title, counterText: counterText) {
            TextEditor(text: $text)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 180 : 92)
                .padding(8)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                        .strokeBorder(AppTheme.borderSubtle)
                )
                .accessibilityLabel(title)
                .onChange(of: text) { _, newValue in
                    guard let maxLength, newValue.count > maxLength else { return }
                    text = String(newValue.prefix(maxLength))
                }
        }
    }
}


struct ProfileEditorPickerRow<PickerContent: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let systemImage: String
    let picker: PickerContent

    init(title: String, systemImage: String, @ViewBuilder picker: () -> PickerContent) {
        self.title = title
        self.systemImage = systemImage
        self.picker = picker()
    }

    var body: some View {
        (dynamicTypeSize.isAccessibilitySize
         ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
         : AnyLayout(HStackLayout(spacing: 10))) {
            HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .frame(width: AppTheme.metadataIconSize)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)

            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            picker
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .padding(.vertical, 10)
        .frame(minHeight: AppTheme.newsEditorInputHeight)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }
}
