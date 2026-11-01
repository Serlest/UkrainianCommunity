import UIKit

/// Two occasional banner-towing aircraft. All motion runs in the compositor:
/// no display link, timers, live text layout, physics simulation or per-frame images.
@MainActor enum SeasonalViceFlights {
    static let period:Double = 76
    static let departures:[Double] = [5, 17]
    static let travel:Double = 18
    static let stripCount = 16
    // Asset-catalog lookup is cached by UIKit; the original is shared by both aircraft.
    static let plane=UIImage(named:"SeasonalVicePlane")
    static let banners:[UIImage] = [banner(club:false),banner(club:true)]

    static func isAvailable(in theme:SeasonalTheme) -> Bool {
        theme.visibleElements.contains { $0.artwork == .viceHeader }
    }

    struct Route {
        let start:CGPoint, end:CGPoint
        let width:CGFloat
        func point(_ progress:CGFloat) -> CGPoint {
            CGPoint(x:start.x+(end.x-start.x)*progress,
                    y:start.y+(end.y-start.y)*progress+sin(progress * .pi * 2)*5)
        }
    }
    static func route(size:CGSize,index:Int,preview:Bool) -> Route {
        let width=min(preview ? 245:310,size.width*0.76)
        let top=max(preview ? 38:112,size.height*0.20)
        let y=min(max(top,size.height*(index==0 ? 0.30:0.42)),size.height-100)
        return Route(start:CGPoint(x:size.width+width,y:y),end:CGPoint(x:-width,y:y-32),width:width)
    }

    static func install(in layer:CALayer,size:CGSize,preview:Bool,intensity:Double) -> [CALayer] {
        guard size.width>0,size.height>0,let image=plane?.cgImage else { return [] }
        let epoch=layer.convertTime(CACurrentMediaTime(),from:nil)
        return (0..<2).map { index in
            let route=route(size:size,index:index,preview:preview)
            let convoy=CALayer();convoy.name="seasonal.vice.aircraft.\(index)"
            let w=route.width,h=w*0.22
            convoy.bounds=CGRect(x:0,y:0,width:w,height:h)
            convoy.position=route.start
            let aircraft=CALayer();aircraft.name="seasonal.vice.plane"
            aircraft.contents=image;aircraft.contentsGravity = .resizeAspect
            aircraft.frame=CGRect(x:0,y:0,width:w*0.32,height:h)
            convoy.addSublayer(aircraft)
            let propeller=CALayer();propeller.name="seasonal.vice.propeller"
            propeller.frame=CGRect(x:w*0.026,y:h*0.30,width:2,height:h*0.40)
            propeller.backgroundColor=UIColor(white:0.65,alpha:0.16).cgColor;propeller.cornerRadius=1
            aircraft.addSublayer(propeller)
            let spin=CABasicAnimation(keyPath:"transform.rotation.x");spin.fromValue=0;spin.toValue=Double.pi*2;spin.duration=0.12;spin.repeatCount = .infinity
            propeller.add(spin,forKey:"seasonal.vice.propeller")
            // A Y bridle joins the banner's leading spar, with a sagged main towline.
            let rope=CAShapeLayer();rope.name="seasonal.vice.towline"
            let path=UIBezierPath();path.move(to:CGPoint(x:w*0.30,y:h*0.53))
            path.addQuadCurve(to:CGPoint(x:w*0.52,y:h*0.58),controlPoint:CGPoint(x:w*0.42,y:h*0.65))
            path.addLine(to:CGPoint(x:w*0.57,y:h*0.18));path.move(to:CGPoint(x:w*0.52,y:h*0.58));path.addLine(to:CGPoint(x:w*0.57,y:h*0.93))
            rope.path=path.cgPath;rope.fillColor=nil;rope.strokeColor=UIColor(white:0.35,alpha:0.82).cgColor;rope.lineWidth=0.65
            convoy.addSublayer(rope)
            let flag=CALayer();flag.name=index==0 ? "seasonal.vice.banner.city":"seasonal.vice.banner.club"
            flag.frame=CGRect(x:w*0.57,y:h*0.18,width:w*0.43,height:h*0.75)
            convoy.addSublayer(flag)
            for strip in 0..<stripCount {
                let piece=CALayer();piece.name="seasonal.vice.cloth"
                piece.contents=banners[index].cgImage;piece.contentsGravity = .resize
                let fraction=1/CGFloat(stripCount)
                piece.contentsRect=CGRect(x:CGFloat(strip)*fraction,y:0,width:fraction,height:1)
                // Subpixel overlap avoids seams without a live mask or offscreen shadow.
                piece.frame=CGRect(x:CGFloat(strip)*flag.bounds.width*fraction,y:0,width:flag.bounds.width*fraction+0.3,height:flag.bounds.height)
                flag.addSublayer(piece)
                let amplitude=min(2.1,h*0.045)*CGFloat(0.55+intensity*0.45)
                let wave=CAKeyframeAnimation(keyPath:"transform")
                wave.values=(0...24).map { sample -> NSValue in
                    let phase=CGFloat(sample)/24 * .pi * 2
                    let left=CGFloat(strip)/CGFloat(stripCount),right=CGFloat(strip+1)/CGFloat(stripCount)
                    let leftY=sin(phase-left * .pi * 2)*amplitude*left
                    let rightY=sin(phase-right * .pi * 2)*amplitude*right
                    // Each strip shears between shared edge samples. The cloth silhouette
                    // remains connected instead of creating staircase-shaped rectangle edges.
                    var transform=CATransform3DIdentity
                    transform.m12=(rightY-leftY)/piece.bounds.width
                    transform.m42=(leftY+rightY)/2
                    return NSValue(caTransform3D:transform)
                }
                wave.duration=1.8;wave.repeatCount = .infinity;wave.beginTime=epoch;wave.calculationMode = .linear
                piece.add(wave,forKey:"seasonal.vice.fabric")
            }
            let routeAnimation=CAKeyframeAnimation(keyPath:"position")
            let departure=departures[index]
            routeAnimation.values=[NSValue(cgPoint:route.start)]+(0...60).map { NSValue(cgPoint:route.point(CGFloat($0)/60)) }+[NSValue(cgPoint:route.end)]
            var keyTimes:[NSNumber]=[0]
            for sample in 0...60 {
                let time=(departure+travel*Double(sample)/60)/period
                keyTimes.append(NSNumber(value:time))
            }
            keyTimes.append(1);routeAnimation.keyTimes=keyTimes
            routeAnimation.duration=period;routeAnimation.repeatCount = .infinity;routeAnimation.calculationMode = .linear;routeAnimation.beginTime=epoch
            layer.addSublayer(convoy);convoy.add(routeAnimation,forKey:"seasonal.vice.flight")
            let bank=CAKeyframeAnimation(keyPath:"transform.rotation.z")
            bank.values=[0,-0.018,0.012,0];bank.duration=6.4;bank.repeatCount = .infinity
            convoy.add(bank,forKey:"seasonal.vice.bank")
            // Quiet between flights, even during an orientation change.
            let visibility=CAKeyframeAnimation(keyPath:"opacity")
            visibility.values=[0,1,0,0];visibility.keyTimes=[0,NSNumber(value:departure/period),NSNumber(value:(departure+travel)/period),1]
            visibility.calculationMode = .discrete;visibility.duration=period;visibility.repeatCount = .infinity;visibility.beginTime=epoch
            convoy.opacity=0;convoy.add(visibility,forKey:"seasonal.vice.visibility")
            return convoy
        }
    }

    private static func banner(club:Bool) -> UIImage {
        let format=UIGraphicsImageRendererFormat();format.scale=1
        return UIGraphicsImageRenderer(size:CGSize(width:640,height:250),format:format).image { renderer in
            let context=renderer.cgContext
            let colors=(club ? [UIColor(red:0.30,green:0.09,blue:0.45,alpha:1),UIColor(red:0.51,green:0.24,blue:0.66,alpha:1)]:[UIColor(red:0.04,green:0.16,blue:0.35,alpha:1),UIColor(red:0.07,green:0.29,blue:0.58,alpha:1)]).map(\.cgColor) as CFArray
            if let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1]) {
                context.drawLinearGradient(gradient,start:.zero,end:CGPoint(x:640,y:250),options:[])
            }
            UIColor.white.withAlphaComponent(0.65).setStroke();context.setLineWidth(3);context.stroke(CGRect(x:2,y:2,width:636,height:246))
            let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center
            func text(_ value:String,_ rect:CGRect,_ font:UIFont,_ color:UIColor,tracking:Double=0) {
                (value as NSString).draw(in:rect,withAttributes:[.font:font,.foregroundColor:color,.paragraphStyle:paragraph,.kern:tracking])
            }
            if club {
                text("WHY SIXTY-NINE WHEN YOU CAN",CGRect(x:12,y:23,width:616,height:36),.systemFont(ofSize:25,weight:.medium),.white,tracking:1.4)
                text("NINE1NINE",CGRect(x:8,y:56,width:624,height:126),UIFont(name:"AvenirNextCondensed-Regular",size:106) ?? .systemFont(ofSize:86,weight:.light),.white,tracking:7)
                text("VICE CITY’S SEXIEST NIGHTCLUB",CGRect(x:12,y:193,width:616,height:32),.systemFont(ofSize:23,weight:.semibold),.white,tracking:1.5)
            } else {
                text("WELCOME TO",CGRect(x:12,y:19,width:616,height:32),.systemFont(ofSize:23,weight:.bold),.white,tracking:7)
                text("Vice City",CGRect(x:5,y:44,width:630,height:171),UIFont(name:"SnellRoundhand-Bold",size:133) ?? .italicSystemFont(ofSize:125),UIColor(red:1,green:0.68,blue:0.82,alpha:1))
                let underline=UIBezierPath();underline.move(to:CGPoint(x:137,y:218));underline.addQuadCurve(to:CGPoint(x:513,y:199),controlPoint:CGPoint(x:323,y:185));underline.lineWidth=5;UIColor(red:1,green:0.68,blue:0.82,alpha:1).setStroke();underline.stroke()
            }
        }
    }
}
