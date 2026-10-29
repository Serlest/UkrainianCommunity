import SwiftUI
import UIKit

@MainActor enum SeasonalAssetImages {
    static let palm=cropped("SeasonalPalm",fraction:0.95)
    static let christmas=cropped("SeasonalChristmas",fraction:0.64)
    static let newYear=cropped("SeasonalNewYear",fraction:0.50)
    static func cropped(_ name:String,fraction:Double) -> UIImage? {
        guard let image=UIImage(named:name),let cg=image.cgImage,
              let crop=cg.cropping(to:CGRect(x:0,y:0,width:Double(cg.width)*fraction,height:Double(cg.height))) else { return nil }
        return UIImage(cgImage:crop,scale:image.scale,orientation:.up)
    }
}

struct SeasonalAmbientOrnaments:UIViewRepresentable {
    let elements:[SeasonalElement]
    var celebration:SeasonalCelebration?
    let animated:Bool
    let intensity:Double
    let preview:Bool
    var includesChrome=true
    var showsNavigation=true
    func makeUIView(context:Context) -> SeasonalAmbientView { SeasonalAmbientView() }
    func updateUIView(_ view:SeasonalAmbientView,context:Context) { view.configure(elements:elements,animated:animated,intensity:intensity,preview:preview);view.setCelebration(celebration);view.setVisibility(chrome:includesChrome,navigation:showsNavigation) }
    static func dismantleUIView(_ view:SeasonalAmbientView,coordinator:()) { view.stop() }
}

/// Photographic stills, bounded compositor animations and at most 48 snow particles.
/// No display link, SwiftUI per-frame updates, CoreMotion or 3D in this view.
@MainActor final class SeasonalAmbientView:UIView {
    private struct Ornament { let view:UIImageView;let element:SeasonalElement;let copy:Int }
    private var elements:[SeasonalElement]=[],ornaments:[Ornament]=[]
    private let festivities=SeasonalFestivitiesView()
    private var celebration:SeasonalCelebration?
    func setCelebration(_ value:SeasonalCelebration?) {
        celebration=value;festivities.configure(value,animated:animated,intensity:intensity,preview:preview)
        if festivities.superview == nil { addSubview(festivities) };festivities.setNeedsLayout();setNeedsLayout()
    }
    private var lights:[CALayer]=[],emitters:[CAEmitterLayer]=[]
    private var animated=false,intensity=0.6,preview=false,configured=false
    private var snowElement:SeasonalElement?
    private var snowParticles:[CALayer]=[]
    private var snowLayoutSize=CGSize.zero
    private weak var tabBar:UITabBar?
    private var flightSize=CGSize.zero
    private var chromeVisible=true,navigationVisible=true
    private(set) var snowGeneration=0
    func setVisibility(chrome:Bool,navigation:Bool) {
        chromeVisible=chrome;navigationVisible=navigation
        for item in ornaments { item.view.isHidden=item.element.zone == .navigation ? !navigation:!chrome }
        lights.forEach{$0.isHidden = !chrome};setNeedsLayout()
    }
    override init(frame:CGRect) {
        super.init(frame:frame);backgroundColor = .clear;isOpaque=false;isUserInteractionEnabled=false;isAccessibilityElement=false;clipsToBounds=false
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view:SeasonalAmbientView, _:UITraitCollection) in
            view.updateSnowAppearance()
        }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func updateSnowAppearance() {
        let dark=traitCollection.userInterfaceStyle == .dark
        for (index,particle) in snowParticles.enumerated() { particle.contents=(dark ? SeasonalSnowCrystals.dark:SeasonalSnowCrystals.light)[index%6] }
        for item in ornaments where item.element.artwork == .snowLedge {
            (item.view as? SeasonalSnowRim)?.configure(animated:animated,accumulate:item.element.accumulatesSnow ?? true,dark:dark)
        }
    }
    func configure(elements:[SeasonalElement],animated:Bool,intensity:Double,preview:Bool) {
        let selected=elements.filter { $0.isVisible && !($0.isHeader || $0.zone == .hanging || $0.artwork == .web || $0.artwork == .bat) }
        guard !configured || self.elements != selected || self.animated != animated || self.intensity != intensity || self.preview != preview else { return }
        configured=true;self.elements=selected;self.animated=animated;self.intensity=intensity;self.preview=preview
        stop();subviews.forEach{$0.removeFromSuperview()};ornaments=[]
        for element in selected where element.artwork != .snowflake && element.artwork != .sparkle {
            let count=element.zone == .edges || (element.zone == .navigation && element.artwork == .leaves) ? 2:1
            for copy in 0..<count {
                let view:UIImageView = element.artwork == .snowLedge ? SeasonalSnowRim(frame:.zero):UIImageView(image:SeasonalSceneImages.image(element));view.contentMode = .scaleAspectFit
                if element.artwork == .snowLedge {
                    (view as? SeasonalSnowRim)?.configure(animated:animated,accumulate:element.accumulatesSnow ?? true,dark:traitCollection.userInterfaceStyle == .dark)
                }
                if element.zone == .corner {
                    let fade=CAGradientLayer();fade.colors=[UIColor.white.cgColor,UIColor.white.withAlphaComponent(0.6).cgColor,UIColor.clear.cgColor]
                    fade.locations=[0,0.35,1];view.layer.mask=fade
                }
                view.accessibilityIdentifier="seasonal.artwork.\(element.zone?.rawValue ?? "legacy").\(copy)"
                addSubview(view);ornaments.append(Ornament(view:view,element:element,copy:copy))
                if animated,element.artwork == .image,element.effectiveMotion != .still {
                    let frames=SeasonalSceneImages.frames(element)
                    if frames.count>1 { view.animationImages=frames;view.animationDuration=element.frameDuration*Double(frames.count);view.startAnimating() }
                    animate(view,element:element)
                }
                if element.glow {
                    for point in 0..<min(2,max(0,6-lights.count)) {
                        let light=CALayer();light.backgroundColor=element.accentColor.cgColor;light.cornerRadius=2;light.opacity=Float(0.45+intensity*0.3)
                        layer.addSublayer(light);lights.append(light)
                        if animated && (element.zone == nil || element.effectiveMotion != .still) {
                            let breath=CABasicAnimation(keyPath:"opacity");breath.fromValue=0.12;breath.toValue=0.4+intensity*0.4
                            breath.duration=2.6+Double(point)*0.6;breath.autoreverses=true;breath.repeatCount = .infinity
                            breath.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut);light.add(breath,forKey:"seasonal.light")
                        }
                    }
                }
            }
        }
        if animated {
            for element in selected where element.motionStrength>0 {
                if element.artwork == .snowflake && element.effectiveMotion == .snow { addSnow(element) }
                if element.artwork == .sparkle && element.glow { addSparkles(element) }
            }
        }
        setNeedsLayout()
    }
    private func animate(_ view:UIImageView,element:SeasonalElement) {
        let key:String,amplitude:Double
        switch element.effectiveMotion {
        case .float:key="transform.translation.y";amplitude=4*element.sway
        case .rotate:key="transform.rotation.z";amplitude=0.08*element.sway
        case .glow:key="opacity";amplitude=0
        default:return
        }
        let animation=CABasicAnimation(keyPath:key);animation.fromValue=key == "opacity" ? 0.65:-amplitude;animation.toValue=key == "opacity" ? 1:amplitude
        animation.duration=3.4;animation.autoreverses=true;animation.repeatCount = .infinity
        animation.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut);view.layer.add(animation,forKey:"seasonal.custom")
    }
    private func addSnow(_ element:SeasonalElement) {
        snowElement=element;snowLayoutSize = .zero
    }
    private func layoutSnow() {
        guard let element=snowElement,bounds.width>0,bounds.height>0,snowLayoutSize != bounds.size else { return }
        snowParticles.forEach{$0.removeAllAnimations();$0.removeFromSuperlayer()};snowParticles=[];snowLayoutSize=bounds.size
        let count=max(18,min(38,Int(18+20*intensity)))
        snowGeneration += 1
        let clock=CACurrentMediaTime()
        for index in 0..<count {
            let depth=index%3
            let size=CGFloat([5.0,8.0,11.0,6.5,9.5,12.5][index%6])*CGFloat(element.size/18)
            let x=bounds.width*CGFloat((Double(index)*0.61803398875+0.13).truncatingRemainder(dividingBy:1))
            let speed=(preview ? 13.0:18.0)+Double(depth)*4+element.sway*16
            let duration=Double(bounds.height+40)/speed
            let particle=CALayer();particle.name="seasonal.snow";particle.contents=(traitCollection.userInterfaceStyle == .dark ? SeasonalSnowCrystals.dark:SeasonalSnowCrystals.light)[index%6]
            particle.bounds=CGRect(x:0,y:0,width:size,height:size);particle.opacity=Float(0.68+Double(depth)*0.13)
            particle.position=CGPoint(x:x,y:bounds.height*CGFloat(Double(index)/Double(count)))
            layer.addSublayer(particle);snowParticles.append(particle)
            let fall=CABasicAnimation(keyPath:"position.y");fall.fromValue = -20;fall.toValue=bounds.height+20
            fall.duration=duration;fall.repeatCount = .infinity
            fall.timeOffset=(clock+Double(index)*duration*0.271).truncatingRemainder(dividingBy:duration)
            particle.add(fall,forKey:"seasonal.fall")
            let drift=CAKeyframeAnimation(keyPath:"transform.translation.x")
            drift.values=[-5,3+index%4,7,-2,-5];drift.duration=5+Double(index%7);drift.repeatCount = .infinity
            drift.calculationMode = .cubic;drift.timeOffset=(clock+Double(index)).truncatingRemainder(dividingBy:drift.duration)
            particle.add(drift,forKey:"seasonal.drift")
            let turn=CABasicAnimation(keyPath:"transform.rotation.z");turn.fromValue=0;turn.toValue=index%2==0 ? Double.pi*2:-Double.pi*2
            turn.duration=14+Double(index%9);turn.repeatCount = .infinity;turn.timeOffset=Double(index%5)
            particle.add(turn,forKey:"seasonal.crystal")
        }
    }
    private func addSparkles(_ element:SeasonalElement) {
        let emitter=CAEmitterLayer();emitter.emitterShape = .rectangle;emitter.emitterMode = .volume;emitter.seed=23
        let cell=CAEmitterCell();cell.contents=SeasonalSnowCrystals.sparkle;cell.color=element.accentColor.withAlphaComponent(0.10+intensity*0.20).cgColor
        cell.birthRate=Float(0.12+intensity*0.16);cell.lifetime=9;cell.velocity=2;cell.velocityRange=2;cell.scale=CGFloat(element.size/60);cell.alphaSpeed = -0.025
        emitter.emitterCells=[cell];emitter.beginTime=CACurrentMediaTime()-7;layer.addSublayer(emitter);emitters.append(emitter)
    }
    override func layoutSubviews() {
        super.layoutSubviews();CATransaction.begin();CATransaction.setDisableActions(true);defer{CATransaction.commit()}
        if flightSize != bounds.size { ornaments.forEach{$0.view.layer.removeAnimation(forKey:"seasonal.flight")};flightSize=bounds.size }
        var lightIndex=0
        for (index,record) in ornaments.enumerated() {
            let view=record.view,element=record.element,copy=record.copy
            let leading=element.zone == .edges || (element.zone == .navigation && element.artwork == .leaves) ? copy==0:element.anchor == .leading
            let layoutScale:CGFloat=preview ? 1:CGFloat(SeasonalDecorationGeometry.layoutScale(width:bounds.width,height:bounds.height))
            let width=CGFloat(element.size)*(preview ? 0.65:(element.artwork == .palm ? 1.7:1.25))*layoutScale
            let ratio=max(0.1,(view.image?.size.width ?? 1)/(view.image?.size.height ?? 1))
            var rect:CGRect
            switch element.zone {
            case .corner:
                let w=min(bounds.width*0.29,CGFloat(element.size)*3)*layoutScale
                rect=CGRect(x:-w*0.45,y:-8,width:w,height:min(155,w/ratio))
                view.alpha=0.7
            case .edges:
                let h=min(preview ? 95:155,width/ratio)
                rect=CGRect(x:leading ? -width*0.48:bounds.width-width*0.52,y:bounds.height*(leading ? 0.46:0.72)-h/2,width:width,height:h)
            case .navigation:
                let bar=navigationFrame()
                if element.artwork == .snowLedge || element.artwork == .image {
                    if element.artwork == .snowLedge {
                        (view as? SeasonalSnowRim)?.configure(animated:animated,accumulate:element.accumulatesSnow ?? true,dark:traitCollection.userInterfaceStyle == .dark,cornerRadius:bar.height/2)
                        rect=CGRect(x:bar.minX,y:bar.minY-18,width:max(1,bar.width),height:58)
                    } else {
                        rect=CGRect(x:bar.minX,y:bar.minY-10,width:max(1,bar.width),height:14)
                    }
                } else {
                    let w=CGFloat(12+(element.size-16)*0.5)*(preview ? 0.65:1)
                    rect=CGRect(x:leading ? bar.minX-w*0.45:bar.maxX-w*0.55,y:bar.minY-w*0.4,width:w,height:w)
                }
                view.isHidden=bar.isEmpty || !navigationVisible
            case .atmosphere:
                rect=CGRect(x:bounds.width*0.62,y:bounds.height*0.35,width:width,height:width)
            default:
                let h=width/ratio,y=element.artwork == .star ? (preview ? 20:112)+h/2:bounds.height*(leading ? 0.40:0.72)
                rect=CGRect(x:leading ? -width*0.46:bounds.width-width*0.54,y:y-h/2,width:width,height:h)
            }
            view.transform = .identity;view.frame=rect
            if element.artwork != .snowLedge { view.layer.mask?.frame=view.bounds }
            if element.artwork == .snowLedge { view.layer.shadowPath=CGPath(roundedRect:view.bounds,cornerWidth:rect.height/3,cornerHeight:rect.height/3,transform:nil) }
            if !leading && element.zone != .navigation { view.transform=CGAffineTransform(scaleX:-1,y:1) }
            if animated && element.artwork == .image && element.effectiveMotion == .flight && view.layer.animation(forKey:"seasonal.flight") == nil && bounds.width>0 {
                let animation=CAKeyframeAnimation(keyPath:"position")
                let start=preview ? 12.0:32.0,total=preview ? 32.0:68.0
                let route=(0...120).map{SeasonalFlightPath.point(at:Double($0)/120,size:bounds.size,top:0,preview:preview)}
                animation.values=[NSValue(cgPoint:route[0])]+route.map{NSValue(cgPoint:$0)}+[NSValue(cgPoint:route[120])]
                animation.keyTimes=[NSNumber(value:0)]+(0...120).map{NSNumber(value:(start+8*Double($0)/120)/total)}+[NSNumber(value:1)]
                animation.duration=total;animation.repeatCount = .infinity;animation.calculationMode = .linear
                view.layer.add(animation,forKey:"seasonal.flight")
            }
            if element.glow {
                for point in 0..<2 where lightIndex<lights.count {
                    lights[lightIndex].frame=CGRect(x:leading ? 4+CGFloat(point)*5:bounds.width-9-CGFloat(point)*5,
                        y:max(12,rect.midY+CGFloat(point==0 ? -18:16)+CGFloat(index)),width:3,height:3)
                    lightIndex += 1
                }
            }
        }
        festivities.frame=bounds
        layoutSnow()
        for emitter in emitters {
            emitter.frame=bounds
            if emitter.emitterShape == .line { emitter.emitterPosition=CGPoint(x:bounds.midX,y:0);emitter.emitterSize=CGSize(width:bounds.width,height:1) }
            else { emitter.emitterPosition=CGPoint(x:bounds.midX,y:bounds.midY);emitter.emitterSize=CGSize(width:bounds.width*0.85,height:bounds.height*0.65) }
        }
    }
    private func navigationFrame() -> CGRect {
        if preview { return CGRect(x:14,y:bounds.height-42,width:max(0,bounds.width-28),height:32) }
        guard let window else { return .zero }
        var responder:UIResponder?=self
        while let current=responder {
            if let controller=current as? UIViewController,
               let nearest=(controller as? UITabBarController)?.tabBar ?? controller.tabBarController?.tabBar,
               nearest.window === window { tabBar=nearest;break }
            responder=current.next
        }
        if tabBar?.window !== window { tabBar=nil }
        if tabBar == nil {
            func find(_ parent:UIView) -> UITabBar? {
                if let bar=parent as? UITabBar,!bar.isHidden,bar.alpha>0.1 { return bar }
                for child in parent.subviews.reversed() { if let bar=find(child) { return bar } }
                return nil
            }
            tabBar=find(window)
        }
        guard let tabBar,!tabBar.isHidden,tabBar.alpha>0.1 else { return .zero }
        let frame=convert(tabBar.bounds,from:tabBar)
        // A floating bar's bounds span the screen in landscape. Its public
        // UIControl descendants describe the actual item group, including
        // language-dependent widths. Never depend on private UIKit class names.
        var items:[CGRect]=[]
        func collect(_ parent:UIView) {
            for child in parent.subviews where !child.isHidden && child.alpha>0.1 {
                if let control=child as? UIControl,
                   control.bounds.width>=20,control.bounds.width<=frame.width/2,
                   control.bounds.height>=16 {
                    let rect=convert(control.bounds,from:control)
                    if rect.intersects(frame) { items.append(rect) }
                } else { collect(child) }
            }
        }
        collect(tabBar)
        if let capsule=SeasonalDecorationGeometry.navigationCapsule(bar:frame,itemFrames:items,expectedCount:tabBar.items?.count ?? 0) { return capsule }
        // Do not draw a fictitious full-width bank when the floating group has
        // not laid out yet. Snowfall and the other decorations remain visible.
        return bounds.width>bounds.height ? .zero:frame.insetBy(dx:16,dy:0)
    }
    func stop() {
        festivities.stop()
        ornaments.forEach{($0.view as? SeasonalSnowRim)?.stop();$0.view.stopAnimating();$0.view.animationImages=nil;$0.view.layer.removeAllAnimations()}
        lights.forEach{$0.removeAllAnimations();$0.removeFromSuperlayer()};lights=[]
        emitters.forEach{$0.emitterCells=nil;$0.removeFromSuperlayer()};emitters=[]
        snowParticles.forEach{$0.removeAllAnimations();$0.removeFromSuperlayer()};snowParticles=[];snowElement=nil;snowLayoutSize = .zero
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop();configured=false;tabBar=nil }
        else { if !configured { configure(elements:elements,animated:animated,intensity:intensity,preview:preview);setCelebration(celebration) };DispatchQueue.main.async { [weak self] in self?.setNeedsLayout() } }
    }
    static let lightSnowTexture=SeasonalSnowCrystals.light[0]
    static let snowTexture=SeasonalSnowCrystals.dark[0]
}
