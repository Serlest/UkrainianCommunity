import UIKit

@MainActor enum SeasonalSnowCrystals {
    static let light=(0..<6).map { photograph(variant:$0,dark:false) }
    static let dark=(0..<6).map { photograph(variant:$0,dark:true) }
    static func photograph(variant:Int,dark:Bool)->CGImage? {
        guard let image=UIImage(named:"SeasonalSnowCrystal"+String(variant)) else { return nil }
        let format=UIGraphicsImageRendererFormat();format.scale=1
        return UIGraphicsImageRenderer(size:CGSize(width:96,height:96),format:format).image { ctx in
            let c=ctx.cgContext
            c.setShadow(offset:CGSize(width:0,height:0.6),blur:dark ? 0:1.2,color:UIColor(red:0.36,green:0.48,blue:0.59,alpha:dark ? 0:0.9).cgColor)
            image.draw(in:CGRect(x:2,y:2,width:92,height:92))
        }.cgImage
    }
    static let fireworkColors:[UIColor]=[
        UIColor(red:1,green:0.19,blue:0.31,alpha:1),UIColor(red:0.25,green:0.76,blue:1,alpha:1),
        UIColor(red:1,green:0.75,blue:0.19,alpha:1),UIColor(red:0.73,green:0.3,blue:1,alpha:1),
        UIColor(red:0.23,green:0.95,blue:0.61,alpha:1),UIColor(red:1,green:0.35,blue:0.77,alpha:1)]
    static let fireworkTextures=fireworkColors.map { color in
        let format=UIGraphicsImageRendererFormat();format.scale=2
        return UIGraphicsImageRenderer(size:CGSize(width:12,height:32),format:format).image { ctx in
            let c=ctx.cgContext
            // A saturated comet head with a tapered luminous tail, not a faint circular dot.
            let tail=CGMutablePath();tail.move(to:CGPoint(x:3,y:5));tail.addQuadCurve(to:CGPoint(x:6,y:31),control:CGPoint(x:4,y:22));tail.addQuadCurve(to:CGPoint(x:9,y:5),control:CGPoint(x:8,y:22));tail.closeSubpath()
            c.saveGState();c.addPath(tail);c.clip()
            let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[color.cgColor,color.withAlphaComponent(0.85).cgColor,color.withAlphaComponent(0.04).cgColor] as CFArray,locations:[0,0.35,1])!
            c.drawLinearGradient(gradient,start:CGPoint(x:6,y:4),end:CGPoint(x:6,y:31),options:[]);c.restoreGState()
            c.setShadow(offset:.zero,blur:2,color:color.withAlphaComponent(0.7).cgColor)
            c.setFillColor(color.cgColor);c.fillEllipse(in:CGRect(x:3,y:1,width:6,height:6))
            c.setShadow(offset:.zero,blur:0,color:nil)
            c.setFillColor(UIColor.white.withAlphaComponent(0.65).cgColor);c.fillEllipse(in:CGRect(x:5,y:2,width:1.5,height:1.5))
        }.cgImage
    }
    static let sparkle:CGImage? = {
        let format=UIGraphicsImageRendererFormat();format.scale=2
        return UIGraphicsImageRenderer(size:CGSize(width:12,height:12),format:format).image { ctx in
            let c=ctx.cgContext
            let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[UIColor.white.cgColor,UIColor.clear.cgColor] as CFArray,locations:[0,1])!
            c.drawRadialGradient(gradient,startCenter:CGPoint(x:6,y:6),startRadius:0,endCenter:CGPoint(x:6,y:6),endRadius:6,options:[])
        }.cgImage
    }()
}
