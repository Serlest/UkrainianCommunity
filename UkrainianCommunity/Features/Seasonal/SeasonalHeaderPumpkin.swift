import Combine
import SwiftUI

/// The scrolling UIKit/SwiftUI header owns this small viewport. Scroll motion is
/// composited with the logo instead of chasing a global anchor at animation FPS.
struct SeasonalHeaderPumpkin:View {
    let theme:SeasonalTheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var visible=false
    @State private var lowPower=ProcessInfo.processInfo.isLowPowerModeEnabled

    private var localTheme:SeasonalTheme {
        var result=theme;result.elements=theme.headerElements;return result
    }
    private var animated:Bool {
        visible && scenePhase == .active && !reduceMotion && !lowPower && !typeSize.isAccessibilitySize
            && localTheme.elements.contains{$0.motionStyle != .still && ($0.effectiveMotion != .glow || $0.glow) && ($0.effectiveMotion != .still || $0.pngFrames.count>1)}
    }
    var body:some View {
        Group {
            if let element=localTheme.elements.first,element.artwork != .pumpkin {
                SeasonalHeaderImage(element:element,animated:animated,intensity:theme.intensity)
            } else {
                GeometryReader { geometry in
                    let count=localTheme.elements.count
                    SeasonalScene(theme:localTheme,
                        placement:SeasonalScenePlacement(pumpkin:CGPoint(x:geometry.size.width/2+8,y:geometry.size.height/2),objectScale:min(1,geometry.size.width/40)),
                        animated:animated,dark:scheme == .dark)
                        .frame(width:geometry.size.width+16+CGFloat(max(0,count-1))*12,height:geometry.size.height)
                        .offset(x:-8)
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
