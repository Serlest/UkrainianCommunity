import UIKit

/// Sparse native-compositor events share the root overlay. No timers, display links or scene renderer.
@MainActor final class SeasonalFestivitiesView:UIView {
    private var effect:SeasonalCelebration?,animated=false,preview=false,intensity=0.6
    private var renderedSize=CGSize.zero
    private(set) var effectLayers:[CALayer]=[]
    private static let santaFrames=(0..<4).compactMap { UIImage(named:"SeasonalSantaCycle"+String($0))?.cgImage }
    override init(frame:CGRect) { super.init(frame:frame);isUserInteractionEnabled=false;backgroundColor = .clear;isAccessibilityElement=false }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ effect:SeasonalCelebration?,animated:Bool,intensity:Double,preview:Bool) {
        guard self.effect != effect || self.animated != animated || self.intensity != intensity || self.preview != preview else { return }
        self.effect=effect;self.animated=animated;self.intensity=intensity;self.preview=preview
        stop();renderedSize = .zero;setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width>0,bounds.height>0,renderedSize != bounds.size else { return }
        stop();renderedSize=bounds.size
        guard animated else { return }
        switch effect {
        case .santaFlight:flySanta()
        case .fireworks:fireworks()
        case nil:break
        }
    }
    private func flySanta() {
        guard let image=Self.santaFrames.first else { return }
        let sprite=CALayer();sprite.name="seasonal.santa";sprite.contents=image;sprite.contentsGravity = .resizeAspect
        let scale:CGFloat=preview ? 1:CGFloat(SeasonalDecorationGeometry.layoutScale(width:bounds.width,height:bounds.height))
        let width=min(preview ? 170:285,bounds.width*0.72)*scale,height=width*CGFloat(image.height)/CGFloat(image.width)
        sprite.bounds=CGRect(x:0,y:0,width:width,height:height);sprite.position=CGPoint(x:-width,y:bounds.height*0.84)
        layer.addSublayer(sprite);effectLayers.append(sprite)
        let total=preview ? 26.0:84.0,start=preview ? 1.5:7.0,duration=11.0
        let route=CAKeyframeAnimation(keyPath:"position")
        var points=[NSValue(cgPoint:sprite.position)],times=[NSNumber(value:0)]
        for i in 0...60 {
            let t=CGFloat(i)/60
            points.append(NSValue(cgPoint:CGPoint(x:-width+bounds.width*t+2*width*t,y:bounds.height*(0.84-0.75*t)+sin(t*CGFloat.pi*2)*bounds.height*0.035)))
            times.append(NSNumber(value:(start+duration*Double(t))/total))
        }
        points.append(points.last!);times.append(1)
        route.values=points;route.keyTimes=times;route.duration=total;route.repeatCount = .infinity;route.calculationMode = .linear
        sprite.add(route,forKey:"seasonal.santa.flight")
        let gait=CAKeyframeAnimation(keyPath:"contents")
        let count=80
        var frames:[CGImage]=[image],frameTimes:[NSNumber]=[0]
        for i in 0...count {
            frames.append(Self.santaFrames[i%Self.santaFrames.count]);frameTimes.append(NSNumber(value:(start+duration*Double(i)/Double(count))/total))
        }
        frames.append(image);frameTimes.append(1)
        gait.values=frames;gait.keyTimes=frameTimes;gait.calculationMode = .discrete;gait.duration=total;gait.repeatCount = .infinity
        sprite.add(gait,forKey:"seasonal.santa.gallop")
        let lean=CAKeyframeAnimation(keyPath:"transform.rotation.z");lean.values=[0,0,-0.07,0.03,0,0]
        lean.keyTimes=[0,NSNumber(value:start/total),NSNumber(value:(start+3)/total),NSNumber(value:(start+8)/total),NSNumber(value:(start+duration)/total),1]
        lean.duration=total;lean.repeatCount = .infinity;sprite.add(lean,forKey:"seasonal.santa.lean")
    }
    private func fireworks() {
        let total=preview ? 18.0:66.0
        // Three staggered multicolour bursts. Texture pixels are tinted; no white contents covering a coloured background.
        for burst in 0..<3 {
            let start=(preview ? 2.0:9.0)+Double(burst)*2.8,duration=2.1
            let center=CGPoint(x:bounds.width*[0.27,0.72,0.46][burst],y:max(108,bounds.height*[0.26,0.4,0.59][burst]))
            let radius=min(100,bounds.width*0.23,bounds.height*0.23)
            for i in 0..<18 {
                let spark=CALayer();spark.name="seasonal.firework";spark.contents=SeasonalSnowCrystals.fireworkTextures[(i/3+burst*2)%6]
                spark.cornerRadius=1.1;spark.bounds=CGRect(x:0,y:0,width:4.2,height:15);spark.opacity=0;spark.position=center
                layer.addSublayer(spark);effectLayers.append(spark)
                let angle=CGFloat(i)*CGFloat.pi*2/18,r=radius*CGFloat(i%3==0 ? 0.68:1)
                spark.setAffineTransform(CGAffineTransform(rotationAngle:angle+CGFloat.pi/2))
                let travel=CAKeyframeAnimation(keyPath:"position");travel.values=[NSValue(cgPoint:center),NSValue(cgPoint:center),NSValue(cgPoint:CGPoint(x:center.x+cos(angle)*r*0.75,y:center.y+sin(angle)*r*0.75)),NSValue(cgPoint:CGPoint(x:center.x+cos(angle)*r,y:center.y+sin(angle)*r+16)),NSValue(cgPoint:center)]
                travel.keyTimes=[0,NSNumber(value:start/total),NSNumber(value:(start+0.6)/total),NSNumber(value:(start+duration)/total),1];travel.duration=total;travel.repeatCount = .infinity
                spark.add(travel,forKey:"seasonal.firework.travel")
                let opacity=CAKeyframeAnimation(keyPath:"opacity");opacity.values=[0,0,1.0,0.9,0,0]
                opacity.keyTimes=[0,NSNumber(value:start/total),NSNumber(value:(start+0.08)/total),NSNumber(value:(start+0.65)/total),NSNumber(value:(start+duration)/total),1]
                opacity.duration=total;opacity.repeatCount = .infinity;spark.add(opacity,forKey:"seasonal.firework.opacity")
            }
        }
    }
    func stop() { renderedSize = .zero;effectLayers.forEach{$0.removeAllAnimations();$0.removeFromSuperlayer()};effectLayers=[] }
}
