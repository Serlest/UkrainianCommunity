import SwiftUI

struct BrandedScreenHeader<TrailingContent: View>: View {
    let title: String
    let subtitle: String?
    let brandAssetName: String?
    let showsBrandText: Bool
    let brandSize: CGSize
    let brandContentMode: BrandMarkView.ContentMode
    @ViewBuilder let trailingContent: TrailingContent

    init(
        title: String,
        subtitle: String? = nil,
        brandAssetName: String? = nil,
        showsBrandText: Bool = true,
        brandSize: CGSize = CGSize(width: 52, height: 52),
        brandContentMode: BrandMarkView.ContentMode = .fit,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.brandAssetName = brandAssetName
        self.showsBrandText = showsBrandText
        self.brandSize = brandSize
        self.brandContentMode = brandContentMode
        self.trailingContent = trailingContent()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BrandMarkView(
                size: brandSize.height,
                width: brandSize.width,
                assetName: brandAssetName,
                contentMode: brandContentMode
            )

            if showsBrandText {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
            }

            Spacer(minLength: 12)

            trailingContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension BrandedScreenHeader where TrailingContent == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

struct AppBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            Image("background")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay(readabilityOverlay)
        }
        .ignoresSafeArea()
    }

    private var readabilityOverlay: some View {
        LinearGradient(
            colors: colorScheme == .dark ? darkOverlayColors : lightOverlayColors,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var lightOverlayColors: [Color] {
        [
            Color.white.opacity(0.12),
            Color.white.opacity(0.08),
            AppTheme.accentSupport.opacity(0.06)
        ]
    }

    private var darkOverlayColors: [Color] {
        [
            Color(red: 0.015, green: 0.022, blue: 0.040).opacity(0.52),
            Color(red: 0.020, green: 0.030, blue: 0.055).opacity(0.58),
            Color(red: 0.010, green: 0.016, blue: 0.032).opacity(0.66)
        ]
    }
}

struct AppGroupedContentPlane<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(padding: CGFloat = AppTheme.contentPlanePadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassCard(
            cornerRadius: AppTheme.contentPlaneRadius,
            material: .ultraThinMaterial,
            surface: AppTheme.groupedPlaneSurface(for: colorScheme),
            borderOpacity: AppTheme.groupedPlaneBorderOpacity,
            shadowRadius: AppTheme.groupedPlaneShadowRadius,
            shadowY: AppTheme.groupedPlaneShadowY
        )
    }
}

struct AppSearchableBrandHeader: View {
    @Binding var isSearchPresented: Bool
    @Binding var searchText: String
    let placeholder: String
    let collapseToken: Int
    @FocusState private var isSearchFocused: Bool

    init(
        isSearchPresented: Binding<Bool>,
        searchText: Binding<String>,
        placeholder: String,
        collapseToken: Int = 0
    ) {
        _isSearchPresented = isSearchPresented
        _searchText = searchText
        self.placeholder = placeholder
        self.collapseToken = collapseToken
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            AppBrandHeader {
                AppGlassIconButton(
                    systemImage: showsCloseButton ? "xmark" : "magnifyingglass",
                    accessibilityLabel: showsCloseButton ? AppStrings.Search.close : AppStrings.Search.open
                ) {
                    toggleSearch()
                }
            }

            if isSearchPresented {
                searchField
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isSearchPresented)
        .onChange(of: isSearchPresented) { _, isPresented in
            isSearchFocused = isPresented
        }
        .onChange(of: isSearchFocused) { _, isFocused in
            guard !isFocused, isSearchPresented else { return }
            collapseSearchIfInactive()
        }
        .onChange(of: collapseToken) { _, _ in
            collapseSearch(clearText: true)
        }
        .onDisappear {
            collapseSearch(clearText: true)
        }
    }

    private var searchField: some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            TextField(placeholder, text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit {
                    endEditing()
                }

            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.Search.clear)
            }
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(height: AppTheme.searchControlHeight)
        .background(AppTheme.surfaceControl.opacity(0.45), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }

    private var hasActiveSearchText: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsCloseButton: Bool {
        isSearchPresented || hasActiveSearchText
    }

    private func toggleSearch() {
        if showsCloseButton {
            collapseSearch(clearText: true)
        } else {
            isSearchPresented = true
            isSearchFocused = true
        }
    }

    private func endEditing() {
        isSearchFocused = false
    }

    private func collapseSearch(clearText: Bool) {
        if clearText {
            searchText = ""
        }
        isSearchFocused = false
        isSearchPresented = false
    }

    private func collapseSearchIfInactive() {
        guard !hasActiveSearchText else { return }
        isSearchPresented = false
    }
}

enum LocalSearchMatcher {
    static func matches(query: String, values: [String?]) -> Bool {
        let tokens = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ")
            .map(String.init)

        guard !tokens.isEmpty else { return true }

        let searchableText = values
            .compactMap { value -> String? in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " ")
            .lowercased()

        return tokens.allSatisfy { searchableText.contains($0) }
    }
}
