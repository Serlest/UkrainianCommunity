import Combine
import SwiftUI
import UIKit

struct SeasonalHeaderPresence:PreferenceKey {
    static let defaultValue=false
    static func reduce(value:inout Bool,nextValue:()->Bool) { value=value || nextValue() }
}
private struct SeasonalSectionActiveKey:EnvironmentKey { static let defaultValue=true }

enum SeasonalHeaderAnchor: Hashable { case pumpkin }
struct SeasonalHeaderAnchors: PreferenceKey {
    static let defaultValue: [SeasonalHeaderAnchor: Anchor<CGRect>] = [:]
    static func reduce(value: inout [SeasonalHeaderAnchor: Anchor<CGRect>], nextValue: () -> [SeasonalHeaderAnchor: Anchor<CGRect>]) {
        value.merge(nextValue(),uniquingKeysWith: { _,new in new })
    }
}
private struct SeasonalHeaderActiveKey: EnvironmentKey { static let defaultValue = false }
private struct SeasonalHeaderThemeKey: EnvironmentKey { static let defaultValue:SeasonalTheme? = nil }
extension EnvironmentValues {
    var seasonalSectionActive:Bool { get { self[SeasonalSectionActiveKey.self] } set { self[SeasonalSectionActiveKey.self]=newValue } }
    var seasonalHeaderTheme:SeasonalTheme? {
        get { self[SeasonalHeaderThemeKey.self] }
        set { self[SeasonalHeaderThemeKey.self] = newValue }
    }
    var seasonalHeaderActive: Bool {
        get { self[SeasonalHeaderActiveKey.self] }
        set { self[SeasonalHeaderActiveKey.self] = newValue }
    }
}

/// Overlay only: never inserts safe-area space or intercepts a content gesture.
struct SeasonalDecorationLayer: View {
    let theme: SeasonalTheme
    let anchors: [SeasonalHeaderAnchor: Anchor<CGRect>]
    var preview = false
    var embedsHeaderPumpkin = false
    var includesChrome = true
    var showsNavigation = true
    var hangingVisible = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var visible = false

    private var animated: Bool {
        visible && scenePhase == .active && !reduceMotion && !lowPower && !typeSize.isAccessibilitySize
            && theme.visibleElements.contains(where:\.needsAnimation)
    }
    private var customElements: [SeasonalElement] { theme.visibleElements.filter { $0.artwork == .image && $0.zone == nil } }

    private var sceneTheme:SeasonalTheme {
        var result=theme
        result.elements=theme.visibleElements.filter { element in
            switch element.artwork {
            case .pumpkin,.bat,.spider,.keychain,.glassBauble:return true
            case .web:return !theme.isComposedScene || theme.visibleElements.contains{$0.artwork == .spider}
            case .image:return element.zone == .hanging
            default:return false
            }
        }
        if embedsHeaderPumpkin { result.elements.removeAll{$0.isHeader} }
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            let dock = anchors[.pumpkin].map { geometry[$0] }
            // The geometry extends to the top of the window, behind the system status region.
            let globalTop = geometry.frame(in: .global).minY
            let top = max(0,-globalTop)
            let placement = SeasonalScenePlacement(
                pumpkin: dock.map { CGPoint(x:$0.midX,y:$0.midY) } ?? CGPoint(x:geometry.size.width-30,y:top+80),
                webTop: top,
                descent: preview ? 116 : 180,
                objectScale: dock.map { min(1,$0.width/40) } ?? 0.85)
            ZStack(alignment:.topLeading) {
                if let web = theme.visibleElements.first(where: { $0.artwork == .web }) {
                    SeasonalStaticDecorations(element: web, top: top, dark: scheme == .dark, preview: preview, includeLeaves: !theme.isComposedScene)
                        .opacity(includesChrome ? 1:0)
                }
                SeasonalAmbientOrnaments(elements:theme.visibleElements,animated:animated,intensity:theme.intensity,preview:preview,includesChrome:includesChrome,showsNavigation:showsNavigation)
                if sceneTheme.elements.contains(where:{[SeasonalArtwork.pumpkin,.web,.bat,.spider,.keychain,.glassBauble].contains($0.artwork) || ($0.artwork == .image && $0.zone == .hanging)}) {
                    SeasonalScene(theme:sceneTheme,placement:placement,animated:animated && includesChrome && sceneTheme.elements.contains{ $0.motionStrength>0 || ($0.glow && $0.motionStyle != .still) || ($0.pngFrames.count>1 && $0.motionStyle != .still) },dark:scheme == .dark,preview:preview,hangingVisible:hangingVisible)
                        .frame(width:geometry.size.width,height:geometry.size.height)
                        .opacity(includesChrome ? 1:0)
                }
                if !customElements.isEmpty {
                    TimelineView(.animation(minimumInterval:0.1,paused:!animated || !includesChrome)) { context in
                        ForEach(Array(customElements.enumerated()),id:\.element.id) { index,element in
                            let point = CGPoint(x:placement.pumpkin.x+CGFloat(index)*18,y:placement.pumpkin.y)
                            SeasonalArtworkView(element:element,phase:animated ? context.date.timeIntervalSinceReferenceDate:0,animated:animated)
                                .position(point)
                        }
                    }.opacity(includesChrome ? 1:0)
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .onAppear { visible=true }
        .onDisappear { visible=false }
        .onReceive(NotificationCenter.default.publisher(for:.NSProcessInfoPowerStateDidChange)) { _ in
            lowPower=ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

struct SeasonalPreview: View {
    let theme: SeasonalTheme
    var body: some View {
        VStack(spacing:0) {
            AppBrandHeader { Image(systemName:"bell").foregroundStyle(AppTheme.accentPrimaryForeground).frame(width:28,height:44) }
                .padding(.horizontal,12).padding(.top,54)
            RoundedRectangle(cornerRadius:14).fill(AppTheme.accentPrimary.opacity(0.12)).frame(height:58).padding(12)
            HStack {
                ForEach(["newspaper.fill","calendar","building.2.fill","books.vertical.fill","person.circle.fill"],id:\.self) { symbol in
                    Image(systemName:symbol).font(.system(size:13)).frame(maxWidth:.infinity).frame(height:16)
                }
            }.padding(8).background(.thinMaterial,in:Capsule()).padding(.horizontal,14).padding(.bottom,10)
        }
        .dynamicTypeSize(.large)
        .environment(\.seasonalHeaderActive,theme.usesHeaderDock)
        .environment(\.seasonalHeaderTheme,theme)
        .overlayPreferenceValue(SeasonalHeaderAnchors.self) { anchors in
            SeasonalDecorationLayer(theme:theme,anchors:anchors,preview:true,embedsHeaderPumpkin:true)
        }
        .background { AppBackgroundView() }
        .clipShape(RoundedRectangle(cornerRadius:20))
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(SeasonalText.value("preview","Vorschau")+": "+theme.name)
        .accessibilityIdentifier("seasonal.preview")
    }
}

struct SeasonalRootDecoration: ViewModifier {
    @ObservedObject var store: SeasonalStore
    let section: SeasonalSection
    let isEligible: Bool
    var includesChrome = true
    var showsNavigationDecoration = true
    var headerOnly = false
    @State private var headerPresent=false
    @AppStorage("seasonalEffectsEnabled") private var enabled = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval:1,paused:scenePhase != .active || !isEligible || (!enabled && store.localPreview == nil) || (store.library.themes.isEmpty && store.localPreview == nil))) { context in
            let theme = (enabled || store.localPreview != nil) && isEligible && verticalSizeClass != .compact && !typeSize.isAccessibilitySize
                ? store.active(at:context.date,section:section) : nil
            content
                .environment(\.seasonalSectionActive,isEligible)
                .onPreferenceChange(SeasonalHeaderPresence.self) { headerPresent=$0 }
                .environment(\.seasonalHeaderActive,includesChrome && (theme?.usesHeaderDock ?? false))
                .environment(\.seasonalHeaderTheme,theme)
                .overlayPreferenceValue(SeasonalHeaderAnchors.self) { anchors in
                    if !headerOnly, let theme, !theme.visibleElements.isEmpty {
                        SeasonalDecorationLayer(theme:theme,anchors:anchors,embedsHeaderPumpkin:true,includesChrome:includesChrome,showsNavigation:showsNavigationDecoration,hangingVisible:headerPresent)
                            .ignoresSafeArea(.container,edges:[.top,.bottom])
                    }
                }
        }
    }
}
