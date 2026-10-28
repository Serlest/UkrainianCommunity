import SwiftUI
import UIKit

@MainActor enum SeasonalSceneImages {
    private static let cache=NSCache<NSString,UIImage>()
    static func image(_ element:SeasonalElement) -> UIImage? {
        if element.artwork == .image { return frames(element).first }
        let name:String = switch element.artwork {
        case .christmasTree:"SeasonalChristmasTree"
        case .viceHeader:"SeasonalViceHeader"
        case .christmasGlobe:"SeasonalChristmasGlobe"
        case .newYearHeader:"SeasonalNewYearHeader"
        case .keychain:"SeasonalViceKeychain"
        case .glassBauble:"SeasonalGlassBauble"
        case .snowLedge:"SeasonalSnowLedge"
        case .leaves:"SeasonalAutumnLeaves"
        case .palm:"SeasonalPalm"
        case .pine:"SeasonalChristmas"
        case .star:"SeasonalNewYear"
        default:""
        }
        guard !name.isEmpty else { return nil }
        if let cached=cache.object(forKey:name as NSString) { return cached }
        guard let source=UIImage(named:name) else { return nil }
        let result=trimmed(source);cache.setObject(result,forKey:name as NSString,cost:Int(result.size.width*result.size.height*4))
        cache.totalCostLimit=8*1024*1024;return result
    }
    static func frames(_ element:SeasonalElement) -> [UIImage] {
        element.pngFrames.compactMap { encoded in
            let key=encoded as NSString
            if let cached=cache.object(forKey:key) { return cached }
            guard let data=Data(base64Encoded:encoded),let image=UIImage(data:data) else { return nil }
            cache.totalCostLimit=8*1024*1024;cache.countLimit=48
            cache.setObject(image,forKey:key,cost:Int(image.size.width*image.size.height*4));return image
        }
    }
    /// Trim transparent generator padding once, never photo pixels; no live mask/blur.
    private static func trimmed(_ image:UIImage) -> UIImage {
        guard let cg=image.cgImage else { return image }
        let w=cg.width,h=cg.height;var bytes=[UInt8](repeating:0,count:w*h*4)
        bytes.withUnsafeMutableBytes { buffer in
            let context=CGContext(data:buffer.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
                                  space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cg,in:CGRect(x:0,y:0,width:w,height:h))
        }
        var left=w,right=0,top=h,bottom=0
        for y in 0..<h { for x in 0..<w where bytes[(y*w+x)*4+3]>12 {
            left=min(left,x);right=max(right,x);top=min(top,y);bottom=max(bottom,y)
        } }
        guard right>=left,bottom>=top else { return image }
        let x=max(0,left-2),y=max(0,top-2)
        // CGContext pixel rows above match CGImage's source pixel order.
        guard let crop=cg.cropping(to:CGRect(x:x,y:y,width:min(w-x,right-left+5),height:min(h-y,bottom-top+5))) else { return image }
        return UIImage(cgImage:crop,scale:image.scale,orientation:.up)
    }
}

struct SeasonalHeaderImage:UIViewRepresentable {
    let element:SeasonalElement
    let animated:Bool
    let intensity:Double
    func makeUIView(context:Context) -> SeasonalHeaderImageView { SeasonalHeaderImageView() }
    func updateUIView(_ view:SeasonalHeaderImageView,context:Context) { view.configure(element,animated:animated,intensity:intensity) }
    static func dismantleUIView(_ view:SeasonalHeaderImageView,coordinator:()) { view.stop() }
}

@MainActor final class SeasonalHeaderImageView:UIView {
    private let imageView=UIImageView()
    private let shine=CAGradientLayer()
    private let silhouette=CALayer()
    private var bulbs:[CALayer]=[]
    private let bulbPoints:[CGPoint]=[.init(x:0.43,y:0.28),.init(x:0.58,y:0.3),.init(x:0.48,y:0.42),.init(x:0.36,y:0.47),.init(x:0.62,y:0.59),.init(x:0.39,y:0.65),.init(x:0.55,y:0.75),.init(x:0.27,y:0.8),.init(x:0.68,y:0.86)]
    private var element:SeasonalElement?,animated=false,intensity=0.0
    override init(frame:CGRect) {
        super.init(frame:frame);backgroundColor = .clear;isUserInteractionEnabled=false;isAccessibilityElement=false
        imageView.contentMode = .scaleAspectFit;addSubview(imageView)
        shine.colors=[UIColor.clear.cgColor,UIColor.white.withAlphaComponent(0.42).cgColor,UIColor.clear.cgColor]
        shine.startPoint=CGPoint(x:0,y:0.25);shine.endPoint=CGPoint(x:1,y:0.75);shine.locations=[0,0.12,0.24]
        shine.mask=silhouette;layer.addSublayer(shine)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ element:SeasonalElement,animated:Bool,intensity:Double) {
        guard self.element != element || self.animated != animated || self.intensity != intensity else { return }
        self.element=element;self.animated=animated;self.intensity=intensity;stop()
        shine.colors=[UIColor.clear.cgColor,element.accentColor.withAlphaComponent(0.42).cgColor,UIColor.clear.cgColor]
        let frames=element.artwork == .image ? SeasonalSceneImages.frames(element):[]
        imageView.image=frames.first ?? SeasonalSceneImages.image(element)
        silhouette.contents=imageView.image?.cgImage;silhouette.contentsGravity = .resizeAspect
        shine.opacity=0
        if animated {
            if frames.count>1 { imageView.animationImages=frames;imageView.animationDuration=element.frameDuration*Double(frames.count);imageView.startAnimating() }
            if element.glow {
                if element.artwork == .christmasTree { addGarland(element) } else { addGlow(intensity:intensity) }
            }
            switch element.effectiveMotion {
            case .glow:break
            case .float,.rotate:
                let move=CABasicAnimation(keyPath:element.effectiveMotion == .float ? "transform.translation.y":"transform.rotation.z")
                let amplitude=(element.effectiveMotion == .float ? 3.0:0.045)*element.sway
                move.fromValue = -amplitude;move.toValue=amplitude;move.duration=3.2;move.autoreverses=true;move.repeatCount = .infinity
                move.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut);imageView.layer.add(move,forKey:"seasonal.object")
            default:break
            }
        }
        setNeedsLayout()
    }
    private func addGarland(_ element:SeasonalElement) {
        for i in bulbPoints.indices {
            let bulb=CALayer();bulb.name="seasonal.garland";bulb.backgroundColor=element.accentColor.cgColor;bulb.cornerRadius=0.8
            bulb.bounds=CGRect(x:0,y:0,width:1.6,height:1.6);bulb.opacity=0.85
            layer.addSublayer(bulb);bulbs.append(bulb)
            let pulse=CAKeyframeAnimation(keyPath:"opacity");pulse.values=[0.12,0.95,0.55,0.12];pulse.keyTimes=[0,0.3,0.62,1]
            pulse.duration=element.effectiveMotion == .twinkle ? 2.6:4.8;pulse.repeatCount = .infinity
            pulse.timeOffset=(CACurrentMediaTime()+Double(i)*(element.effectiveMotion == .twinkle ? 0.24:0.03)).truncatingRemainder(dividingBy:pulse.duration)
            pulse.calculationMode = .cubic;bulb.add(pulse,forKey:"seasonal.garland")
        }
    }
    private func addGlow(intensity:Double) {
        let breath=CABasicAnimation(keyPath:"opacity");breath.fromValue=0.70;breath.toValue=1
        breath.duration=2.8;breath.autoreverses=true;breath.repeatCount = .infinity
        breath.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut);imageView.layer.add(breath,forKey:"seasonal.breathe")
        shine.opacity=Float(intensity*0.45)
        let glint=CABasicAnimation(keyPath:"locations");glint.fromValue=[-0.5,-0.35,-0.2];glint.toValue=[1.1,1.25,1.4]
        glint.duration=6;glint.repeatCount = .infinity;shine.add(glint,forKey:"seasonal.glint")
    }
    override func layoutSubviews() {
        super.layoutSubviews();CATransaction.begin();CATransaction.setDisableActions(true);defer{CATransaction.commit()}
        let side=min(bounds.height,CGFloat(element?.size ?? 40)*(element?.artwork == .christmasTree ? 1.27:1))
        let rect=CGRect(x:(bounds.width-side)/2,y:(bounds.height-side)/2,width:side,height:side)
        imageView.frame=rect;shine.frame=rect;silhouette.frame=shine.bounds
        let ratio=(imageView.image?.size.width ?? 1)/max(1,imageView.image?.size.height ?? 1)
        let actualSize=CGSize(width:side*min(1,ratio),height:side*min(1,1/max(0.01,ratio)))
        let actual=CGRect(x:rect.midX-actualSize.width/2,y:rect.midY-actualSize.height/2,width:actualSize.width,height:actualSize.height)
        for i in bulbs.indices { bulbs[i].position=CGPoint(x:actual.minX+actual.width*bulbPoints[i].x,y:actual.minY+actual.height*bulbPoints[i].y) }
    }
    func stop() { bulbs.forEach{$0.removeAllAnimations();$0.removeFromSuperlayer()};bulbs=[];imageView.stopAnimating();imageView.animationImages=nil;imageView.layer.removeAllAnimations();shine.removeAllAnimations();shine.opacity=0 }
    override func didMoveToWindow() { super.didMoveToWindow();if window == nil { stop();element=nil } }
}
