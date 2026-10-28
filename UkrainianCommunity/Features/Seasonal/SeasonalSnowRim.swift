import UIKit

/// Small rasterized snow banks follow only the tab bar's upper lip. No particles accumulate
/// in a physics engine and no text/icon area can become covered.
@MainActor final class SeasonalSnowRim:UIImageView {
    private var renderedSize=CGSize.zero
    private var dark=false
    private var accumulating=false
    private let reveal=CALayer()
    private var startedAt=CACurrentMediaTime()
    override init(frame:CGRect) { super.init(frame:frame);contentMode = .scaleToFill;isUserInteractionEnabled=false;layer.mask=reveal }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(animated:Bool,accumulate:Bool,dark:Bool) {
        if self.dark != dark { self.dark=dark;renderedSize = .zero }
        let shouldGrow=animated && accumulate
        if accumulating != shouldGrow { accumulating=shouldGrow;reveal.removeAllAnimations();startedAt=CACurrentMediaTime();renderedSize = .zero }
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width>0,bounds.height>0,renderedSize != bounds.size else { return }
        renderedSize=bounds.size
        let format=UIGraphicsImageRendererFormat();format.scale=2
        image=UIGraphicsImageRenderer(size:bounds.size,format:format).image { ctx in
            let c=ctx.cgContext,w=bounds.width,h=bounds.height
            let path=CGMutablePath();path.move(to:CGPoint(x:0,y:h*0.82))
            let segments=max(8,Int(w/27))
            for i in 0..<segments {
                let x0=w*CGFloat(i)/CGFloat(segments),x1=w*CGFloat(i+1)/CGFloat(segments)
                let top=h*CGFloat(0.20+0.12*sin(Double(i)*1.7))
                path.addCurve(to:CGPoint(x:x1,y:h*0.47),control1:CGPoint(x:x0+(x1-x0)*0.32,y:top),control2:CGPoint(x:x0+(x1-x0)*0.72,y:top))
            }
            path.addQuadCurve(to:CGPoint(x:w-5,y:h*0.82),control:CGPoint(x:w,y:h*0.86))
            path.addLine(to:CGPoint(x:5,y:h*0.82));path.closeSubpath()
            c.saveGState();c.addPath(path);c.clip()
            let colors=[UIColor.white.cgColor,UIColor(red:0.83,green:0.9,blue:0.97,alpha:1).cgColor] as CFArray
            let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1])!
            c.drawLinearGradient(gradient,start:.zero,end:CGPoint(x:0,y:h),options:[]);c.restoreGState()
            c.addPath(path);c.setStrokeColor(UIColor(red:0.43,green:0.56,blue:0.69,alpha:dark ? 0.45:0.5).cgColor);c.setLineWidth(0.4);c.strokePath()
        }
        CATransaction.begin();CATransaction.setDisableActions(true)
        reveal.backgroundColor=UIColor.white.cgColor;reveal.anchorPoint=CGPoint(x:0.5,y:1)
        reveal.bounds=CGRect(x:0,y:0,width:bounds.width,height:bounds.height);reveal.position=CGPoint(x:bounds.midX,y:bounds.maxY)
        CATransaction.commit()
        reveal.removeAnimation(forKey:"seasonal.accumulation")
        if accumulating {
            let age=max(0,CACurrentMediaTime()-startedAt),duration=90.0
            if age<duration {
                let grow=CABasicAnimation(keyPath:"bounds.size.height");grow.fromValue=bounds.height*0.60;grow.toValue=bounds.height
                grow.duration=duration;grow.timeOffset=age;grow.fillMode = .both;grow.isRemovedOnCompletion=false
                reveal.add(grow,forKey:"seasonal.accumulation")
            }
        }
    }
    func stop() { reveal.removeAllAnimations() }
}
