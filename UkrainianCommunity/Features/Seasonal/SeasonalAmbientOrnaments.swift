import SwiftUI
import UIKit

@MainActor enum SeasonalAssetImages {
    // Crop only known transparent composition padding, once; preserve source pixels/alpha.
    static let palm = cropped("SeasonalPalm", fraction:0.95)
    static let christmas = cropped("SeasonalChristmas", fraction:0.64)
    static let newYear = cropped("SeasonalNewYear", fraction:0.50)
    static func cropped(_ name:String,fraction:Double) -> UIImage? {
        guard let image=UIImage(named:name),let cg=image.cgImage,
              let crop=cg.cropping(to:CGRect(x:0,y:0,width:Double(cg.width)*fraction,height:Double(cg.height))) else { return nil }
        return UIImage(cgImage:crop,scale:image.scale,orientation:.up)
    }
}

struct SeasonalAmbientOrnaments:UIViewRepresentable {
    let elements:[SeasonalElement]
    let animated:Bool
    let intensity:Double
    let preview:Bool
    func makeUIView(context:Context) -> SeasonalAmbientView { SeasonalAmbientView() }
    func updateUIView(_ view:SeasonalAmbientView,context:Context) {
        view.configure(elements:elements,animated:animated,intensity:intensity,preview:preview)
    }
    static func dismantleUIView(_ view:SeasonalAmbientView,coordinator:()) { view.stop() }
}

/// Cached still photographs + at most six compositor opacity animations and six live
/// snow particles. No display link, SwiftUI animation timeline, CoreMotion or 3D scene.
@MainActor final class SeasonalAmbientView:UIView {
    private var elements:[SeasonalElement]=[]
    private var ornaments:[(UIImageView,SeasonalElement)]=[]
    private var lights:[CALayer]=[]
    private var snow:CAEmitterLayer?
    private var animated=false,intensity=0.6,preview=false
    private var configured=false
    override init(frame:CGRect) { super.init(frame:frame);backgroundColor = .clear;isOpaque=false;isUserInteractionEnabled=false;isAccessibilityElement=false;clipsToBounds=true }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(elements:[SeasonalElement],animated:Bool,intensity:Double,preview:Bool) {
        let selected=elements.filter{[SeasonalArtwork.palm,.pine,.star,.snowflake].contains($0.artwork)}
        guard !configured || self.elements != selected || self.animated != animated || self.intensity != intensity || self.preview != preview else { return }
        configured=true;self.elements=selected;self.animated=animated;self.intensity=intensity;self.preview=preview
        stop();subviews.forEach{$0.removeFromSuperview()};ornaments=[]
        for element in selected where element.artwork != .snowflake {
            let image:UIImage? = switch element.artwork {
            case .palm: SeasonalAssetImages.palm
            case .pine: SeasonalAssetImages.christmas
            default: SeasonalAssetImages.newYear
            }
            let view=UIImageView(image:image);view.contentMode = .scaleAspectFit
            addSubview(view);ornaments.append((view,element))
            if element.glow {
                let color:UIColor=element.artwork == .palm ? (element.anchor == .leading ? .systemPink:.cyan):UIColor(red:1,green:0.78,blue:0.36,alpha:1)
                for index in 0..<min(2,max(0,6-lights.count)) {
                    let light=CALayer();light.backgroundColor=color.cgColor;light.cornerRadius=2;light.opacity=Float(0.45+intensity*0.3)
                    layer.addSublayer(light);lights.append(light)
                    if animated {
                        let breath=CABasicAnimation(keyPath:"opacity");breath.fromValue=0.10+intensity*0.18;breath.toValue=0.35+intensity*0.5
                        breath.duration=2.6+Double(index)*0.6;breath.autoreverses=true;breath.repeatCount = .infinity
                        breath.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut);light.add(breath,forKey:"seasonal.light")
                    }
                }
            }
        }
        if animated,let flake=selected.first(where:{$0.artwork == .snowflake && $0.sway>0}) {
            let emitter=CAEmitterLayer();emitter.emitterShape = .line;emitter.emitterMode = .surface;emitter.seed=17
            let cell=CAEmitterCell();cell.contents=Self.snowTexture;cell.birthRate=Float(min(0.30,(0.15+flake.sway*0.35)*intensity/0.6))
            cell.lifetime=18;cell.velocity=CGFloat(7+flake.sway*8);cell.velocityRange=3
            cell.emissionLongitude = .pi/2;cell.emissionRange=0.15;cell.scale=CGFloat(flake.size/100);cell.scaleRange=0.09
            cell.alphaSpeed = -0.025;emitter.emitterCells=[cell];layer.addSublayer(emitter);snow=emitter
        }
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews();CATransaction.begin();CATransaction.setDisableActions(true);defer{CATransaction.commit()}
        var nextLight=0
        for (index,item) in ornaments.enumerated() {
            let (view,element)=item,leading=element.anchor == .leading
            let width=CGFloat(element.size)*(preview ? 0.65:(element.artwork == .palm ? 1.7:1.25))
            let height=width / max(0.1,(view.image?.size.width ?? 1)/(view.image?.size.height ?? 1))
            let y:CGFloat = element.artwork == .star ? (preview ? 20:112)+height/2 : bounds.height*(leading ? 0.40:0.72)
            view.transform = .identity;view.frame=CGRect(x:leading ? -width*0.46:bounds.width-width*0.54,y:y-height/2,width:width,height:height)
            view.transform=CGAffineTransform(scaleX:leading ? 1:-1,y:1)
            if element.glow {
                for point in 0..<2 where nextLight<lights.count {
                    let light=lights[nextLight];nextLight += 1
                    light.frame=CGRect(x:leading ? 5+CGFloat(point)*5:bounds.width-10-CGFloat(point)*5,
                        y:max(12,y+CGFloat(point==0 ? -22:19)+CGFloat(index)*3),width:3,height:3)
                }
            }
        }
        snow?.frame=bounds;snow?.emitterPosition=CGPoint(x:bounds.midX,y:0);snow?.emitterSize=CGSize(width:bounds.width,height:1)
    }
    func stop() {
        lights.forEach{$0.removeAllAnimations();$0.removeFromSuperlayer()};lights=[]
        snow?.emitterCells=nil;snow?.removeFromSuperlayer();snow=nil
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop();configured=false }
        else if !configured { configure(elements:elements,animated:animated,intensity:intensity,preview:preview) }
    }
    private static let snowTexture:CGImage? = {
        let format=UIGraphicsImageRendererFormat();format.scale=1
        return UIGraphicsImageRenderer(size:CGSize(width:16,height:16),format:format).image { context in
            let colors=[UIColor.white.withAlphaComponent(0.8).cgColor,UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1])!
            context.cgContext.drawRadialGradient(gradient,startCenter:CGPoint(x:8,y:8),startRadius:0,
                endCenter:CGPoint(x:8,y:8),endRadius:8,options:[])
        }.cgImage
    }()
}
