import UIKit

/// Two small cached rasters follow the capsule's rounded shoulders. No live blur or physics.
@MainActor final class SeasonalSnowRim:UIImageView {
    private var renderedSize=CGSize.zero
    private var dark=false,accumulating=false
    private var cornerRadius:CGFloat=31
    private var startedAt=CACurrentMediaTime()
    private let extra=CALayer()
    private static let material=UIImage(named:"SeasonalSnowMaterial")
    override init(frame:CGRect) {
        super.init(frame:frame);contentMode = .scaleToFill;isUserInteractionEnabled=false
        layer.addSublayer(extra)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(animated:Bool,accumulate:Bool,dark:Bool,cornerRadius:CGFloat?=nil) {
        let grows=animated && accumulate
        let radius=min(31,max(1,cornerRadius ?? self.cornerRadius))
        guard renderedSize == .zero || self.dark != dark || accumulating != grows || self.cornerRadius != radius else { return }
        if self.dark != dark || accumulating != grows || self.cornerRadius != radius { renderedSize = .zero }
        if accumulating != grows { startedAt=CACurrentMediaTime() }
        self.dark=dark;self.cornerRadius=radius;accumulating=grows;setNeedsLayout()
    }
    /// y=18 is the capsule's horizontal upper lip; its sides turn down by a quarter circle.
    nonisolated static func contour(x:CGFloat,width:CGFloat,radius:CGFloat)->CGFloat {
        let distance=min(x,width-x)
        guard distance<radius else { return 18 }
        let dx=radius-max(0,distance)
        return 18+radius-sqrt(max(0,radius*radius-dx*dx))
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width>0,bounds.height>0,renderedSize != bounds.size else { return }
        renderedSize=bounds.size
        image=render(depth:0)
        CATransaction.begin();CATransaction.setDisableActions(true)
        extra.frame=bounds;extra.contents=render(depth:2.2).cgImage;extra.opacity=accumulating ? 1:0
        CATransaction.commit()
        extra.removeAllAnimations()
        if accumulating {
            let age=max(0,CACurrentMediaTime()-startedAt)
            if age<90 {
                let fade=CABasicAnimation(keyPath:"opacity");fade.fromValue=0;fade.toValue=1
                fade.duration=90;fade.timeOffset=age;fade.fillMode = .both;fade.isRemovedOnCompletion=false
                extra.add(fade,forKey:"seasonal.accumulation")
            }
        }
    }
    private func render(depth:CGFloat)->UIImage {
        let format=UIGraphicsImageRendererFormat();format.scale=2
        return UIGraphicsImageRenderer(size:bounds.size,format:format).image { context in
            let c=context.cgContext,w=bounds.width,r=min(cornerRadius,w/5)
            let path=CGMutablePath()
            // Irregular, reproducible banks with unequal spacing; no periodic scallop/tile.
            var seed:UInt64=0x5A17D93
            func random()->CGFloat { seed=seed &* 6364136223846793005 &+ 1442695040888963407;return CGFloat((seed>>33)&0xFFFF)/65535 }
            var knots:[CGPoint]=[CGPoint(x:0,y:5)],x:CGFloat=0
            while x<w { x=min(w,x+9+random()*29);knots.append(CGPoint(x:x,y:4.5+random()*7.5+depth)) }
            func bank(_ x:CGFloat)->CGFloat {
                var index=1
                while index<knots.count-1 && knots[index].x<x { index += 1 }
                let a=knots[index-1],b=knots[index],t=min(1,max(0,(x-a.x)/max(1,b.x-a.x)))
                let smooth=t*t*(3-2*t)
                return a.y+(b.y-a.y)*smooth
            }
            func top(_ x:CGFloat)->CGFloat { Self.contour(x:x,width:w,radius:r)-bank(x)*min(1,min(x,w-x)/16) }
            path.move(to:CGPoint(x:0,y:top(0)))
            for step in 1...Int(ceil(w)) { let x=min(w,CGFloat(step));path.addLine(to:CGPoint(x:x,y:top(x))) }
            var icicles:[CGPoint]=[],tip:CGFloat=19
            while tip<w-15 { tip += 24+random()*47;icicles.append(CGPoint(x:tip,y:1+random()*4)) }
            for step in stride(from:Int(ceil(w)),through:0,by:-1) {
                let x=min(w,CGFloat(step)),edge=min(1,min(x,w-x)/14)
                let droop=icicles.reduce(CGFloat(0)) { $0+max(0,1-abs(x-$1.x)/2.5)*$1.y }
                path.addLine(to:CGPoint(x:x,y:Self.contour(x:x,width:w,radius:r)+(2.3+droop)*edge))
            }
            path.closeSubpath()
            c.saveGState();c.addPath(path);c.clip()
            let colors=[UIColor.white.cgColor,UIColor(red:0.96,green:0.98,blue:1,alpha:1).cgColor,UIColor(red:0.69,green:0.79,blue:0.87,alpha:1).cgColor] as CFArray
            let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,0.52,1])!
            c.drawLinearGradient(gradient,start:CGPoint(x:0,y:7),end:CGPoint(x:0,y:28),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
            if let material=Self.material {
                c.saveGState();c.setBlendMode(.softLight);c.setAlpha(0.58)
                material.draw(in:CGRect(x:0,y:-w*0.42,width:w,height:w))
                c.restoreGState()
            }
            // Deterministic subpixel snow grains are baked once, not moving particles.
            for i in 0..<Int(w*7) {
                let x=CGFloat((i*137)%max(1,Int(w*10)))/10
                let y=top(x)+CGFloat((i*53)%110)/10
                let bright=i%3 != 0
                c.setFillColor((bright ? UIColor.white.withAlphaComponent(0.48):UIColor(red:0.45,green:0.6,blue:0.73,alpha:0.16)).cgColor)
                c.fillEllipse(in:CGRect(x:x,y:y,width:i%5==0 ? 0.8:0.4,height:0.45))
            }
            c.restoreGState()
            c.addPath(path);c.setStrokeColor(UIColor(red:0.43,green:0.56,blue:0.68,alpha:dark ? 0.48:0.33).cgColor)
            c.setLineWidth(0.35);c.strokePath()
        }
    }
    func stop() { extra.removeAllAnimations() }
}
