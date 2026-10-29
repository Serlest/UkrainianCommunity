import SwiftUI
import UIKit

/// Flat photographic ornaments need two tiny compositor layers, not a Metal scene/window target.
struct SeasonalPhotoHangers:UIViewRepresentable {
    let element:SeasonalElement
    let animated:Bool
    let reactsToTilt:Bool
    let intensity:Double
    let preview:Bool
    func makeUIView(context:Context)->SeasonalPhotoHangersView { SeasonalPhotoHangersView() }
    func updateUIView(_ view:SeasonalPhotoHangersView,context:Context) { view.configure(element,animated:animated,reactsToTilt:reactsToTilt,intensity:intensity,preview:preview) }
    static func dismantleUIView(_ view:SeasonalPhotoHangersView,coordinator:()) { view.stop() }
}
@MainActor private final class SeasonalPhotoTick:NSObject {
    weak var owner:SeasonalPhotoHangersView?
    @objc func tick(_ link:CADisplayLink) { owner?.tick(link.timestamp) }
}
@MainActor final class SeasonalPhotoHangersView:UIView {
    private var element:SeasonalElement?,animated=false,reactsToTilt=false,preview=false,intensity=0.6
    private let motion=SeasonalMotion(),target=SeasonalPhotoTick()
    private var link:CADisplayLink?,lastTime=0.0,elapsed=0.0,activeUntil=0.0,lastGravity=0.0
    private var updateInterval=1.0/30
    var displayClockRange:CAFrameRateRange { link?.preferredFrameRateRange ?? .default }
    private struct Part { let image:CALayer;let thread:CAShapeLayer;var pendulum=SeasonalPendulum() }
    private var parts:[Part]=[]
    private(set) var renderedFrameCount=0
    var partCount:Int { parts.count }
    override init(frame:CGRect) { super.init(frame:frame);target.owner=self;isUserInteractionEnabled=false;isAccessibilityElement=false;backgroundColor = .clear }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ element:SeasonalElement,animated:Bool,reactsToTilt:Bool,intensity:Double,preview:Bool) {
        guard self.element != element || self.animated != animated || self.reactsToTilt != reactsToTilt || self.intensity != intensity || self.preview != preview else { return }
        let rebuild=self.element != element
        self.element=element;self.animated=animated;self.reactsToTilt=reactsToTilt;self.intensity=intensity;self.preview=preview
        if rebuild {
            parts.forEach{$0.image.removeFromSuperlayer();$0.thread.removeFromSuperlayer()};parts=[];elapsed=0
            for _ in 0..<(element.artwork == .glassBauble ? 2:1) {
                let image=CALayer();image.contents=SeasonalSceneImages.image(element)?.cgImage;image.contentsGravity = .resizeAspect;image.anchorPoint=CGPoint(x:0.5,y:0)
                let thread=CAShapeLayer();thread.fillColor=nil;thread.lineWidth=0.45;thread.strokeColor=element.accentColor.withAlphaComponent(0.7).cgColor
                layer.addSublayer(thread);layer.addSublayer(image);parts.append(Part(image:image,thread:thread))
            }
        }
        let moving=animated && element.effectiveMotion == .swing && element.motionStrength>0
        motion.setEnabled(moving && reactsToTilt)
        if moving,link==nil {
            lastTime=0;let clock=CADisplayLink(target:target,selector:#selector(SeasonalPhotoTick.tick(_:)))
            clock.preferredFrameRateRange = .default;clock.add(to:.main,forMode:.common);link=clock
        } else if !moving { link?.invalidate();link=nil;lastTime=0 }
        setNeedsLayout()
    }
    override func layoutSubviews() { super.layoutSubviews();draw(delta:0,force:true) }
    fileprivate func tick(_ timestamp:Double) {
        guard window != nil,animated else { return }
        guard lastTime==0 || timestamp-lastTime>=updateInterval-0.001 else { return }
        let dt=lastTime==0 ? 0:min(0.1,max(0,timestamp-lastTime));lastTime=timestamp;elapsed += dt
        draw(delta:dt,force:false)
    }
    private func draw(delta:Double,force:Bool) {
        guard let element,bounds.width>0 else { return }
        let moving=animated && element.effectiveMotion == .swing && element.motionStrength>0
        let sample=moving && reactsToTilt ? motion.sample(orientation:window?.windowScene?.interfaceOrientation ?? .portrait):SeasonalMotionSample()
        if abs(sample.gravityX-lastGravity)>0.002 || abs(sample.acceleration)>0.025 { activeUntil=elapsed+0.8 }
        lastGravity=sample.gravityX
        let arriving=moving && elapsed<9
        let unsettled=parts.contains{abs($0.pendulum.velocity)>0.002}
        let active=arriving || elapsed<activeUntil || unsettled
        updateInterval=active ? 1.0/60:1.0/15
        guard force || active else { return }
        renderedFrameCount += 1
        let safeTop=preview ? 38:(window?.safeAreaInsets.top ?? 59)
        CATransaction.begin();CATransaction.setDisableActions(true);defer{CATransaction.commit()}
        let source=SeasonalSceneImages.image(element),ratio=(source?.size.width ?? 1)/max(1,source?.size.height ?? 1)
        for i in parts.indices {
            if moving { parts[i].pendulum.step(delta:delta,tilt:sample.gravityX*element.motionStrength*2,acceleration:sample.acceleration*(i==0 ? 1:0.72),intensity:intensity*element.motionStrength) }
            let progress=moving ? SeasonalChoreography.spiderProgress(at:elapsed,preview:preview,index:i):1
            let angle=moving ? parts[i].pendulum.angle*0.55:0
            let anchor=CGPoint(x:bounds.midX+(parts.count==1 ? 18:(i==0 ? 6:30)),y:max(18,safeTop-12))
            let length=8+max(24,safeTop+(i==0 ? 30:15)-anchor.y)*progress
            let end=CGPoint(x:anchor.x+sin(angle)*length,y:anchor.y+cos(angle)*length)
            let height=CGFloat(element.size)*(i==0 ? 1.65:1.4)*CGFloat(SeasonalDecorationGeometry.layoutScale(width:bounds.width,height:bounds.height))
            parts[i].image.bounds=CGRect(x:0,y:0,width:height*ratio,height:height)
            parts[i].image.position=end;parts[i].image.setAffineTransform(CGAffineTransform(rotationAngle:-angle))
            let thread=CGMutablePath();thread.move(to:anchor);thread.addLine(to:end);parts[i].thread.path=thread
        }
    }
    func stop() { link?.invalidate();link=nil;motion.setEnabled(false);lastTime=0 }
    override func didMoveToWindow() { super.didMoveToWindow();if window==nil { stop();element=nil } }
}
