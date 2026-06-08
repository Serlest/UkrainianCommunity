import SwiftUI

/// Shared glass back control for pushed screens.
///
/// Main tab screens may keep app brand/logo headers. Pushed, admin, and editor
/// screens should use this control instead of repeating local chevron styling.
struct AppBackButton: View {
    @Environment(\.dismiss) private var dismiss
    let accessibilityLabel: String
    let action: (() -> Void)?

    init(accessibilityLabel: String = AppStrings.Common.back, action: (() -> Void)? = nil) {
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        AppGlassIconButton(systemImage: "chevron.left", accessibilityLabel: accessibilityLabel) {
            if let action {
                action()
            } else {
                dismiss()
            }
        }
    }
}

/// Header for pushed/detail/admin/editor screens.
///
/// This deliberately has no app logo. Future migrations should replace
/// `AppCenteredBrandHeader` on pushed/admin/editor screens with this header or
/// one of the shells below, one screen at a time.
struct PushedScreenHeader<TrailingContent: View>: View {
    let title: String
    let subtitle: String?
    let showsBackButton: Bool
    let backAction: (() -> Void)?
    @ViewBuilder let trailingContent: TrailingContent

    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = true,
        backAction: (() -> Void)? = nil,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsBackButton = showsBackButton
        self.backAction = backAction
        self.trailingContent = trailingContent()
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.pushedScreenHeaderSpacing) {
            if showsBackButton {
                AppBackButton(action: backAction)
            }

            VStack(alignment: .leading, spacing: AppTheme.pushedScreenHeaderTextSpacing) {
                Text(title)
                    .font(AppTheme.pushedScreenTitleFont)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppTheme.pushedScreenSubtitleFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, showsBackButton ? AppTheme.pushedScreenHeaderTitleTopOffset : 0)

            trailingContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PushedScreenHeader where TrailingContent == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = true,
        backAction: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            showsBackButton: showsBackButton,
            backAction: backAction
        ) {
            EmptyView()
        }
    }
}

/// Shared shell for pushed/detail screens.
///
/// It provides only visual chrome: background, header, scroll padding, and
/// optional tab-bar visibility. It does not load data, push routes, or change
/// navigation behavior. Migrate screens individually.
struct PushedScreenShell<Content: View, TrailingContent: View>: View {
    let title: String
    let subtitle: String?
    let showsBackButton: Bool
    let tabBarHidden: Bool
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let contentSpacing: CGFloat
    let backAction: (() -> Void)?
    @ViewBuilder let trailingContent: TrailingContent
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = true,
        tabBarHidden: Bool = false,
        topPadding: CGFloat = AppTheme.pushedScreenTopPadding,
        bottomPadding: CGFloat = AppTheme.pushedScreenBottomPadding,
        contentSpacing: CGFloat = AppTheme.pushedScreenContentSpacing,
        backAction: (() -> Void)? = nil,
        @ViewBuilder trailingContent: () -> TrailingContent,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsBackButton = showsBackButton
        self.tabBarHidden = tabBarHidden
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.contentSpacing = contentSpacing
        self.backAction = backAction
        self.trailingContent = trailingContent()
        self.content = content()
    }

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: contentSpacing) {
                    PushedScreenHeader(
                        title: title,
                        subtitle: subtitle,
                        showsBackButton: showsBackButton,
                        backAction: backAction
                    ) {
                        trailingContent
                    }

                    content
                }
                .padding(.horizontal, AppTheme.pushedScreenHorizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
            }
        }
        .tint(AppTheme.accentPrimary)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(tabBarHidden ? .hidden : .visible, for: .tabBar)
        .scrollDismissesKeyboard(.interactively)
        .observesKeyboardDismissTaps()
    }
}

extension PushedScreenShell where TrailingContent == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = true,
        tabBarHidden: Bool = false,
        topPadding: CGFloat = AppTheme.pushedScreenTopPadding,
        bottomPadding: CGFloat = AppTheme.pushedScreenBottomPadding,
        contentSpacing: CGFloat = AppTheme.pushedScreenContentSpacing,
        backAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            showsBackButton: showsBackButton,
            tabBarHidden: tabBarHidden,
            topPadding: topPadding,
            bottomPadding: bottomPadding,
            contentSpacing: contentSpacing,
            backAction: backAction
        ) {
            EmptyView()
        } content: {
            content()
        }
    }
}

/// Shell for article/entity detail screens.
///
/// This is foundation-only. Future migrations should use it in this order:
/// News Detail, Event Detail, Organization Detail, Guide Material Detail, then
/// Guide Category/Section. It does not load data, mutate navigation paths, or
/// force any feature behavior.
struct DetailScreenShell<Content: View, HeaderActions: View>: View {
    let title: String?
    let subtitle: String?
    let tabBarHidden: Bool
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let contentSpacing: CGFloat
    let backAction: (() -> Void)?
    let refreshAction: (() async -> Void)?
    @ViewBuilder let headerActions: HeaderActions
    let content: (ScrollViewProxy) -> Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        tabBarHidden: Bool = false,
        topPadding: CGFloat = AppTheme.detailScreenTopPadding,
        bottomPadding: CGFloat = AppTheme.detailScreenBottomPadding,
        contentSpacing: CGFloat = AppTheme.detailScreenContentSpacing,
        backAction: (() -> Void)? = nil,
        refreshAction: (() async -> Void)? = nil,
        @ViewBuilder headerActions: () -> HeaderActions,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            tabBarHidden: tabBarHidden,
            topPadding: topPadding,
            bottomPadding: bottomPadding,
            contentSpacing: contentSpacing,
            backAction: backAction,
            refreshAction: refreshAction,
            headerActions: headerActions
        ) { _ in
            content()
        }
    }

    init(
        title: String? = nil,
        subtitle: String? = nil,
        tabBarHidden: Bool = false,
        topPadding: CGFloat = AppTheme.detailScreenTopPadding,
        bottomPadding: CGFloat = AppTheme.detailScreenBottomPadding,
        contentSpacing: CGFloat = AppTheme.detailScreenContentSpacing,
        backAction: (() -> Void)? = nil,
        refreshAction: (() async -> Void)? = nil,
        @ViewBuilder headerActions: () -> HeaderActions,
        @ViewBuilder scrollContent: @escaping (ScrollViewProxy) -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.tabBarHidden = tabBarHidden
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.contentSpacing = contentSpacing
        self.backAction = backAction
        self.refreshAction = refreshAction
        self.headerActions = headerActions()
        self.content = scrollContent
    }

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            GeometryReader { proxy in
                let contentWidth = max(proxy.size.width - (AppTheme.detailScreenHorizontalPadding * 2), 0)

                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: contentSpacing) {
                            DetailActionHeader(
                                title: title,
                                subtitle: subtitle,
                                backAction: backAction
                            ) {
                                headerActions
                            }

                            content(scrollProxy)
                        }
                        .frame(width: contentWidth, alignment: .leading)
                        .padding(.horizontal, AppTheme.detailScreenHorizontalPadding)
                        .padding(.top, topPadding)
                        .padding(.bottom, bottomPadding)
                    }
                    .frame(width: proxy.size.width)
                    .detailRefreshable(refreshAction)
                }
            }
        }
        .tint(AppTheme.accentPrimary)
        .navigationTitle(title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(tabBarHidden ? .hidden : .visible, for: .tabBar)
        .scrollDismissesKeyboard(.interactively)
        .observesKeyboardDismissTaps()
    }
}

extension DetailScreenShell where HeaderActions == EmptyView {
    init(
        title: String? = nil,
        subtitle: String? = nil,
        tabBarHidden: Bool = false,
        topPadding: CGFloat = AppTheme.detailScreenTopPadding,
        bottomPadding: CGFloat = AppTheme.detailScreenBottomPadding,
        contentSpacing: CGFloat = AppTheme.detailScreenContentSpacing,
        backAction: (() -> Void)? = nil,
        refreshAction: (() async -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            tabBarHidden: tabBarHidden,
            topPadding: topPadding,
            bottomPadding: bottomPadding,
            contentSpacing: contentSpacing,
            backAction: backAction,
            refreshAction: refreshAction
        ) {
            EmptyView()
        } content: {
            content()
        }
    }
}

private extension View {
    @ViewBuilder
    func detailRefreshable(_ action: (() async -> Void)?) -> some View {
        if let action {
            refreshable {
                await action()
            }
        } else {
            self
        }
    }
}

/// Shared no-logo detail top bar for back, bookmark, share, and overflow/admin
/// actions. Actions are passed as values/closures to avoid parent-capturing
/// computed opaque view patterns in detail screens.
struct DetailActionHeader<TrailingActions: View>: View {
    let title: String?
    let subtitle: String?
    let backAction: (() -> Void)?
    @ViewBuilder let trailingActions: TrailingActions

    init(
        title: String? = nil,
        subtitle: String? = nil,
        backAction: (() -> Void)? = nil,
        @ViewBuilder trailingActions: () -> TrailingActions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.backAction = backAction
        self.trailingActions = trailingActions()
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.detailScreenHeaderSpacing) {
            AppBackButton(action: backAction)

            titleBlock

            Spacer(minLength: 0)

            HStack(spacing: AppTheme.detailActionHeaderSpacing) {
                trailingActions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var titleBlock: some View {
        if title != nil || subtitle != nil {
            VStack(alignment: .leading, spacing: AppTheme.detailActionHeaderTitleSpacing) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(AppTheme.detailScreenTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppTheme.detailScreenSubtitleFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, AppTheme.pushedScreenHeaderTitleTopOffset)
        }
    }
}

extension DetailActionHeader where TrailingActions == EmptyView {
    init(
        title: String? = nil,
        subtitle: String? = nil,
        backAction: (() -> Void)? = nil
    ) {
        self.init(title: title, subtitle: subtitle, backAction: backAction) {
            EmptyView()
        }
    }
}

struct DetailHeaderActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let role: ButtonRole?
    let isDisabled: Bool
    let action: () -> Void

    init(
        systemImage: String,
        accessibilityLabel: String,
        role: ButtonRole? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.role = role
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        AppGlassIconButton(
            systemImage: systemImage,
            accessibilityLabel: accessibilityLabel,
            role: role
        ) {
            action()
        }
        .frame(width: AppTheme.detailActionButtonSize, height: AppTheme.detailActionButtonSize)
        .disabled(isDisabled)
    }
}

/// Admin and management shell with optional filter/search/metrics areas.
///
/// Admin screens should not show the app logo. The tab bar is hidden by
/// default, but migrations can override that per screen.
struct AdminScreenShell<FiltersContent: View, MetricsContent: View, Content: View, TrailingContent: View>: View {
    let title: String
    let subtitle: String?
    let showsBackButton: Bool
    let tabBarHidden: Bool
    let backAction: (() -> Void)?
    @ViewBuilder let filtersContent: FiltersContent
    @ViewBuilder let metricsContent: MetricsContent
    @ViewBuilder let trailingContent: TrailingContent
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = true,
        tabBarHidden: Bool = true,
        backAction: (() -> Void)? = nil,
        @ViewBuilder filters: () -> FiltersContent,
        @ViewBuilder metrics: () -> MetricsContent,
        @ViewBuilder trailingContent: () -> TrailingContent,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsBackButton = showsBackButton
        self.tabBarHidden = tabBarHidden
        self.backAction = backAction
        self.filtersContent = filters()
        self.metricsContent = metrics()
        self.trailingContent = trailingContent()
        self.content = content()
    }

    var body: some View {
        PushedScreenShell(
            title: title,
            subtitle: subtitle,
            showsBackButton: showsBackButton,
            tabBarHidden: tabBarHidden,
            backAction: backAction
        ) {
            trailingContent
        } content: {
            AppGroupedContentPlane {
                VStack(alignment: .leading, spacing: AppTheme.adminScreenContentSpacing) {
                    filtersContent
                    metricsContent
                    content
                }
            }
        }
    }
}

extension AdminScreenShell where FiltersContent == EmptyView, MetricsContent == EmptyView, TrailingContent == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = true,
        tabBarHidden: Bool = true,
        backAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            showsBackButton: showsBackButton,
            tabBarHidden: tabBarHidden,
            backAction: backAction
        ) {
            EmptyView()
        } metrics: {
            EmptyView()
        } trailingContent: {
            EmptyView()
        } content: {
            content()
        }
    }
}

enum EditorScreenCloseStyle {
    case back
    case cancel

    var systemImage: String {
        switch self {
        case .back:
            "chevron.left"
        case .cancel:
            "xmark"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .back:
            AppStrings.Common.back
        case .cancel:
            AppStrings.Common.cancel
        }
    }
}

/// Shared shell for editor screens.
///
/// Editors should not use app-logo headers. Choose `.cancel` for modal/sheet
/// editors and `.back` for pushed editors during each screen migration.
struct EditorScreenShell<Content: View, BottomActionContent: View, TrailingContent: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let subtitle: String?
    let closeStyle: EditorScreenCloseStyle
    let tabBarHidden: Bool
    let closeAction: (() -> Void)?
    @ViewBuilder let trailingContent: TrailingContent
    @ViewBuilder let bottomActionContent: BottomActionContent
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        closeStyle: EditorScreenCloseStyle,
        tabBarHidden: Bool = true,
        closeAction: (() -> Void)? = nil,
        @ViewBuilder trailingContent: () -> TrailingContent,
        @ViewBuilder bottomAction: () -> BottomActionContent,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.closeStyle = closeStyle
        self.tabBarHidden = tabBarHidden
        self.closeAction = closeAction
        self.trailingContent = trailingContent()
        self.bottomActionContent = bottomAction()
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.editorScreenContentSpacing) {
                    editorHeader
                    content
                }
                .padding(.horizontal, AppTheme.editorScreenHorizontalPadding)
                .padding(.top, AppTheme.editorScreenTopPadding)
                .padding(.bottom, AppTheme.editorScreenBottomPadding)
            }

            bottomActionContent
                .padding(.horizontal, AppTheme.editorScreenHorizontalPadding)
                .padding(.bottom, AppTheme.editorScreenBottomActionPadding)
        }
        .tint(AppTheme.accentPrimary)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(tabBarHidden ? .hidden : .visible, for: .tabBar)
        .scrollDismissesKeyboard(.interactively)
        .observesKeyboardDismissTaps()
    }

    private var editorHeader: some View {
        HStack(alignment: .top, spacing: AppTheme.editorScreenHeaderSpacing) {
            AppGlassIconButton(systemImage: closeStyle.systemImage, accessibilityLabel: closeStyle.accessibilityLabel) {
                if let closeAction {
                    closeAction()
                } else {
                    dismiss()
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.editorScreenHeaderTextSpacing) {
                Text(title)
                    .font(AppTheme.editorScreenTitleFont)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppTheme.editorScreenSubtitleFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, AppTheme.editorScreenHeaderTitleTopOffset)

            trailingContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension EditorScreenShell where BottomActionContent == EmptyView, TrailingContent == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        closeStyle: EditorScreenCloseStyle,
        tabBarHidden: Bool = true,
        closeAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            closeStyle: closeStyle,
            tabBarHidden: tabBarHidden,
            closeAction: closeAction
        ) {
            EmptyView()
        } bottomAction: {
            EmptyView()
        } content: {
            content()
        }
    }
}

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
            colors: AppTheme.screenBackgroundOverlayColors(for: colorScheme),
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct AppGroupedContentPlane<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(padding: CGFloat = AppTheme.groupedContentPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.groupedContentSpacing) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassCard(
            cornerRadius: AppTheme.groupedContentCornerRadius,
            material: AppTheme.groupedContentMaterial,
            surface: AppTheme.groupedPlaneSurface(for: colorScheme),
            borderOpacity: AppTheme.groupedContentBorderOpacity,
            shadowRadius: AppTheme.groupedContentShadowRadius,
            shadowY: AppTheme.groupedContentShadowY
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
