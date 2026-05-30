import SwiftUI
import UIKit

struct ImageCropView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: ImageCropViewModel
    let title: String
    let instructions: String
    let onCancel: () -> Void
    let onApply: (ProcessedImageSelection) -> Void

    init(
        sourceImage: UIImage,
        profile: ImageSelectionProfile,
        title: String,
        instructions: String,
        onCancel: @escaping () -> Void,
        onApply: @escaping (ProcessedImageSelection) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ImageCropViewModel(sourceImage: sourceImage, profile: profile))
        self.title = title
        self.instructions = instructions
        self.onCancel = onCancel
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.sectionSpacing) {
                Text(instructions)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppTheme.pageHorizontal)

                cropSurface

                if let errorMessage = viewModel.errorMessage {
                    InlineMessageCard(style: .error, message: errorMessage)
                        .padding(.horizontal, AppTheme.pageHorizontal)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, AppTheme.sectionSpacing)
            .background {
                AppBackgroundView()
                    .ignoresSafeArea()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Images.Crop.cancel) {
                        onCancel()
                        dismiss()
                    }
                    .disabled(viewModel.isProcessing)
                }

                ToolbarItem(placement: .principal) {
                    Button(AppStrings.Images.Crop.reset) {
                        viewModel.reset()
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(viewModel.isProcessing)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.Images.Crop.apply) {
                        applyCrop()
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(viewModel.isProcessing)
                }
            }
        }
    }

    private var cropSurface: some View {
        GeometryReader { proxy in
            let availableWidth = max(1, proxy.size.width - AppTheme.pageHorizontal * 2)
            let cropWidth = min(availableWidth, 720)
            let cropHeight = cropWidth / viewModel.targetAspectRatio
            let cropSize = CGSize(width: cropWidth, height: cropHeight)

            VStack(spacing: AppTheme.dashboardSpacing) {
                ZStack {
                    AppTheme.surfaceSecondary
                    Image(uiImage: viewModel.previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: viewModel.imageDisplaySize(in: cropSize).width,
                            height: viewModel.imageDisplaySize(in: cropSize).height
                        )
                        .offset(viewModel.offset)
                    Color.black.opacity(0.10)
                    ImageCropFrameView(cornerRadius: viewModel.profile.cropCornerRadius)
                }
                .frame(width: cropWidth, height: cropHeight)
                .clipShape(RoundedRectangle(cornerRadius: viewModel.profile.cropCornerRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: viewModel.profile.cropCornerRadius, style: .continuous))
                .gesture(dragGesture(in: cropSize))
                .simultaneousGesture(magnificationGesture(in: cropSize))
                .overlay {
                    if viewModel.isProcessing {
                        ProgressView()
                            .controlSize(.large)
                            .tint(AppTheme.accentPrimary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.black.opacity(0.18))
                    }
                }

                Text(AppStrings.Images.Crop.hint)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.top, AppTheme.dashboardSpacing)
            .onAppear {
                viewModel.setCropFrameSize(cropSize)
            }
            .onChange(of: cropSize) { _, newSize in
                viewModel.setCropFrameSize(newSize)
            }
        }
    }

    private func dragGesture(in frameSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                viewModel.updateDrag(translation: value.translation, in: frameSize)
            }
            .onEnded { _ in
                viewModel.endDrag(in: frameSize)
            }
    }

    private func magnificationGesture(in frameSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                viewModel.updateMagnification(value, in: frameSize)
            }
            .onEnded { _ in
                viewModel.endMagnification(in: frameSize)
            }
    }

    private func applyCrop() {
        Task {
            do {
                let processedImage = try await viewModel.applyCrop()
                onApply(processedImage)
                dismiss()
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}
