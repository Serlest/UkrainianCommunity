import Foundation
import UIKit

/// Stable slots are the vocabulary of downloadable scenes, not executable effects.
enum SeasonalSceneZone: String, Codable, CaseIterable, Identifiable {
    case brand, corner, hanging, edges, atmosphere, navigation
    var id:String { rawValue }
    var title:String { SeasonalText.value("zone."+rawValue,rawValue.capitalized) }
    var artworks:[SeasonalArtwork] {
        switch self {
        case .brand: [.pumpkin,.viceHeader,.christmasTree,.christmasGlobe,.newYearHeader,.image]
        case .corner: [.web,.palm,.pine,.star,.image]
        case .hanging: [.spider,.keychain,.glassBauble,.image]
        case .edges: [.leaves,.palm,.pine,.star,.image]
        case .atmosphere: [.bat,.snowflake,.sparkle,.image]
        case .navigation: [.leaves,.snowLedge,.palm,.star,.image]
        }
    }
}
enum SeasonalMotionStyle:String,Codable,CaseIterable,Identifiable {
    case still, glow, twinkle, float, rotate, swing, flight, snow, frames
    var id:String { rawValue }
    var title:String { SeasonalText.value("effect."+rawValue,rawValue.capitalized) }
}

extension SeasonalElement {
    var isVisible:Bool { isEnabled ?? true }
    var isHeader:Bool { zone == .brand || (zone == nil && (artwork == .pumpkin || artwork == .image)) }
    var effectiveMotion:SeasonalMotionStyle {
        if let motionStyle { return motionStyle }
        if artwork == .image && pngFrames.count>1 { return .frames }
        if zone == .hanging { return .swing }
        if artwork == .snowflake { return .snow }
        if artwork == .bat { return .flight }
        if glow { return .glow }
        return .still
    }
    var motionChoices:[SeasonalMotionStyle] {
        if artwork == .image && pngFrames.count>1 {
            switch zone {
            case .hanging:return [.still,.frames,.swing]
            case .corner,.edges,.navigation:return [.still,.frames,.glow]
            case .atmosphere:return [.still,.frames,.flight,.float,.rotate,.glow]
            default:return [.still,.frames,.float,.rotate,.glow]
            }
        }
        if artwork == .christmasTree { return [.still,.glow,.twinkle] }
        if artwork == .web { return [.still] }
        if artwork == .sparkle { return [.still,.glow] }
        if zone == .hanging { return [.still,.swing] }
        if zone == .atmosphere && artwork == .image { return [.still,.flight,.float,.rotate,.glow] }
        if artwork == .bat { return [.still,.flight] }
        if artwork == .snowflake { return [.still,.snow] }
        if zone == .corner || zone == .edges || zone == .navigation { return [.still,.glow] }
        if artwork == .pumpkin { return [.still,.glow] }
        return [.still,.glow,.float,.rotate]
    }
    var needsAnimation:Bool {
        if artwork == .snowLedge { return accumulatesSnow ?? true }
        guard motionStyle != .still else { return false }
        return motionStrength>0 || glow || pngFrames.count>1
    }
    mutating func selectMotion(_ style:SeasonalMotionStyle) {
        guard motionChoices.contains(style) else { return }
        motionStyle=style
        if style == .glow || style == .twinkle { glow=true }
    }
    var accentColor:UIColor {
        guard let accentHex,let value=UInt32(accentHex,radix:16) else { return UIColor(red:1,green:0.76,blue:0.32,alpha:1) }
        return UIColor(red:CGFloat((value>>16)&255)/255,green:CGFloat((value>>8)&255)/255,blue:CGFloat(value&255)/255,alpha:1)
    }
    static func scene(_ artwork:SeasonalArtwork,_ zone:SeasonalSceneZone,size:Double=34,motion:SeasonalMotionStyle = .still,glow:Bool=false,sway:Double=0.45,accent:String?=nil) -> Self {
        var element=Self(artwork:artwork,anchor:[SeasonalSceneZone.brand,.corner,.atmosphere].contains(zone) ? .leading:.trailing,size:size,sway:sway,glow:glow)
        element.zone=zone;element.motionStyle=motion;element.accentHex=accent
        return element
    }
}

extension SeasonalTheme {
    var isComposedScene:Bool { elements.contains{$0.zone != nil} }
    var visibleElements:[SeasonalElement] { elements.filter(\.isVisible) }
    var headerElements:[SeasonalElement] { visibleElements.filter(\.isHeader) }
    static func halloweenScene(now:Date=Date()) -> Self {
        var theme=halloween(now:now);theme.repeatsYearly=true
        theme.elements=[.scene(.pumpkin,.brand,size:40,motion:.glow,glow:true),
            .scene(.web,.corner,size:34),.scene(.spider,.hanging,size:34,motion:.swing),
            .scene(.leaves,.edges,size:30),.scene(.bat,.atmosphere,size:24,motion:.flight,sway:0.75),
            .scene(.leaves,.navigation,size:20)]
        return theme
    }
    /// The owner can upgrade an existing native theme locally, then explicitly Apply/Save/Publish.
    func arrangedInZones() -> Self {
        guard !isComposedScene else { return self }
        var result=self
        let recognized=elements.contains{[SeasonalArtwork.web,.palm,.pine,.star].contains($0.artwork)}
        let defaults:Self = elements.contains(where:{$0.artwork == .web}) ? .halloweenScene():
            elements.contains(where:{$0.artwork == .palm}) ? .gtaVI():
            elements.contains(where:{$0.artwork == .pine}) ? .christmas():.newYear()
        var converted:[SeasonalElement]=[]
        for old in elements {
            let used=Set(converted.compactMap(\.zone))
            let preferred=defaults.elements.first(where:{$0.artwork == old.artwork})?.zone
            guard let slot=(preferred.flatMap{used.contains($0) ? nil:$0} ?? SeasonalSceneZone.allCases.first(where:{$0.artworks.contains(old.artwork) && !used.contains($0)})) else { continue }
            var element=old;element.zone=slot
            element.anchor=[SeasonalSceneZone.brand,.corner,.atmosphere].contains(slot) ? .leading:.trailing
            element.motionStyle=nil
            if !element.motionChoices.contains(element.effectiveMotion) { element.motionStyle=element.motionChoices.first }
            if old.pngFrames.count>1 { element.motionStyle = .frames }
            converted.append(element)
        }
        for item in defaults.elements where !converted.contains(where:{$0.zone == item.zone}) {
            var item=item;if !recognized { item.isEnabled=false };converted.append(item)
        }
        if let web=elements.first(where:{$0.artwork == .web}),let index=converted.firstIndex(where:{$0.artwork == .spider}) {
            converted[index].size=web.size;converted[index].spiderMotion=web.motionStrength
        }
        result.elements=converted

        return result
    }
}

extension SeasonalTheme {
    /// Snow and the navigation cap can continue through details; header/tilt decorations stay on roots.
    func presentation(includesChrome:Bool,showsNavigation:Bool=true) -> Self {
        guard !includesChrome || !showsNavigation else { return self }
        var result=self
        result.elements=visibleElements.filter { element in
            (includesChrome || (element.artwork == .snowflake && (element.zone == .atmosphere || element.zone == nil)) || element.zone == .navigation)
                && (showsNavigation || element.zone != .navigation)
        }
        return result
    }
}

extension SeasonalArtwork {
    var requiresSceneZone:Bool {
        switch self {
        case .christmasTree,.viceHeader,.christmasGlobe,.newYearHeader,.keychain,.glassBauble,.snowLedge,.leaves,.spider,.sparkle:true
        default:false
        }
    }
}
