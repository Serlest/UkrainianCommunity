import SwiftUI
import UIKit

struct SeasonalZoneEditor:View {
    @Binding var element:SeasonalElement
    let importImage:() -> Void
    private var zone:SeasonalSceneZone { element.zone ?? .brand }
    var body:some View {
        Section {
            Toggle(zone.title,isOn:Binding(get:{element.isVisible},set:{element.isEnabled=$0}))
                .font(.headline).accessibilityIdentifier("seasonal.zone."+zone.rawValue+".enabled")
            if element.isVisible {
                Picker(SeasonalText.value("object","Objekt"),selection:Binding(get:{element.artwork},set:replaceArtwork)) {
                    ForEach(zone.artworks) { artwork in Text(SeasonalText.artwork(artwork)).tag(artwork) }
                }.accessibilityIdentifier("seasonal.zone."+zone.rawValue+".artwork")
                if element.artwork == .snowLedge {
                    Toggle(SeasonalText.value("accumulation","Schnee langsam ansammeln"),isOn:Binding(get:{element.accumulatesSnow ?? true},set:{element.accumulatesSnow=$0}))
                }
                if element.artwork == .image {
                    Button(action:importImage) { Label(SeasonalText.value("choosePNG","PNG auswählen"),systemImage:"photo") }
                        .accessibilityIdentifier("seasonal.zone."+zone.rawValue+".import")
                    Text(SeasonalText.value("pngHint","Transparente PNG-Dateien werden lokal verkleinert und mit der Szene gespeichert."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                VStack(alignment:.leading) {
                    Text(SeasonalText.value("size","Größe"))
                    Slider(value:$element.size,in:16...44).accessibilityLabel(zone.title+": "+SeasonalText.value("size","Größe"))
                }
                Picker(SeasonalText.value("effect","Animation"),selection:Binding(get:{element.effectiveMotion},set:{element.selectMotion($0)})) {
                    ForEach(element.motionChoices) { motion in Text(motion.title).tag(motion) }
                }.accessibilityIdentifier("seasonal.zone."+zone.rawValue+".motion")
                if element.effectiveMotion != .still && element.effectiveMotion != .glow && element.effectiveMotion != .frames {
                    Slider(value:Binding(get:{element.motionStrength},set:{value in
                        element.sway=value
                        if element.artwork == .spider || element.artwork == .web { element.spiderMotion=value }
                    }),in:0...1).accessibilityLabel(zone.title+": "+SeasonalText.value("sway","Bewegungsstärke"))
                }
                if element.artwork != .web && (element.effectiveMotion == .glow || zone == .brand || zone == .edges || zone == .corner || element.artwork == .sparkle) {
                    Toggle(SeasonalText.value("glow","Leuchten"),isOn:$element.glow)
                    ColorPicker(SeasonalText.value("accent","Lichtfarbe"),selection:Binding(get:{Color(uiColor:element.accentColor)},set:{color in
                        var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
                        guard UIColor(color).getRed(&r,green:&g,blue:&b,alpha:&a) else { return }
                        element.accentHex=String(format:"%02X%02X%02X",Int(min(1,max(0,r))*255),Int(min(1,max(0,g))*255),Int(min(1,max(0,b))*255))
                    }),supportsOpacity:false)
                }
            }
        } header: { Text(zone.title) }
    }
    private func replaceArtwork(_ artwork:SeasonalArtwork) {
        element.artwork=artwork;element.pngFrames=[];element.spiderMotion=nil;element.accumulatesSnow=nil
        if !element.motionChoices.contains(element.effectiveMotion) { element.motionStyle=element.motionChoices.first }
        if artwork == .spider || artwork == .keychain || artwork == .glassBauble { element.motionStyle = .swing }
        if artwork == .snowflake { element.motionStyle = .snow }
        if artwork == .bat { element.motionStyle = .flight }
    }
}
