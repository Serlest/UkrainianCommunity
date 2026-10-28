import SwiftUI
import UIKit

/// One cached bitmap per appearance. Neither the web nor the leaves enter the animated scene.
@MainActor enum SeasonalStaticArtwork {
    static let leaves = SeasonalAssetImages.cropped("SeasonalAutumnLeaves", fraction:0.74)
    private static let lightWeb = drawWeb(dark: false)
    private static let darkWeb = drawWeb(dark: true)
    static func web(dark: Bool) -> UIImage { dark ? darkWeb : lightWeb }

    private static func drawWeb(dark: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 3; format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 180, height: 180), format: format).image { renderer in
            let c = renderer.cgContext
            let angles = [0.0, 0.19, 0.39, 0.62, 0.85, 1.10, 1.34, Double.pi / 2]
            let lengths = [176.0, 163, 174, 170, 178, 166, 174, 178]
            func point(_ ray: Int, _ fraction: Double) -> CGPoint {
                let radius = lengths[ray] * fraction
                return CGPoint(x: cos(angles[ray]) * radius, y: sin(angles[ray]) * radius)
            }
            func silk(_ a: CGPoint, _ b: CGPoint, slack: Double, width: CGFloat) {
                let middle = CGPoint(x: (a.x + b.x) / 2 + slack, y: (a.y + b.y) / 2 + slack)
                let path = CGMutablePath(); path.move(to: a); path.addQuadCurve(to: b, control: middle)
                c.setLineCap(.round); c.setLineJoin(.round)
                // A faint offset strand gives silk depth without a runtime blur or lighting pass.
                c.saveGState(); c.translateBy(x: 0.35, y: 0.45)
                c.setStrokeColor(UIColor(white: 0.05, alpha: dark ? 0.17 : 0.10).cgColor)
                c.setLineWidth(width + 0.35); c.addPath(path); c.strokePath(); c.restoreGState()
                c.setStrokeColor(UIColor(white: dark ? 0.67 : 0.16, alpha: dark ? 0.68 : 0.73).cgColor)
                c.setLineWidth(width); c.addPath(path); c.strokePath()
            }
            for ray in angles.indices { silk(.zero, point(ray, 1), slack: sin(Double(ray)) * 0.8, width: 0.95) }
            for (ring, fraction) in [0.13, 0.23, 0.35, 0.49, 0.64, 0.80, 0.98].enumerated() {
                for ray in 0..<(angles.count - 1) {
                    if ring == 6 && ray == 2 { continue } // A natural, incomplete outer cell.
                    let jitter = sin(Double(ray) * 2.1 + Double(ring)) * 0.014
                    silk(point(ray, fraction + jitter), point(ray + 1, fraction - jitter),
                         slack: 0.8 + fraction * 3.4, width: ring.isMultiple(of: 3) ? 0.88 : 0.65)
                }
            }
            // Keep the actual status time readable. Bake this fade once rather than
            // placing a live blur/mask over the status region on every animation frame.
            c.setBlendMode(.destinationIn)
            let shades=[0.18,0.20,0.75,0.85].map{UIColor(white:1,alpha:$0).cgColor} as CFArray
            let fade=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:shades,locations:[0,0.52,0.78,1])!
            c.drawLinearGradient(fade,start:.zero,end:CGPoint(x:0,y:180),options:[])
        }
    }
}

/// Shared screen-space geometry keeps the static web and its first silk thread aligned.
enum SeasonalDecorationGeometry {
    static func webSide(width: Double, elementSize: Double) -> Double {
        min(width * 0.30, max(78, min(122, 78+(elementSize-16)*44/28)))
    }
    static func spiderAnchor(index: Int, width: Double, top: Double, safeTop: Double, elementSize: Double) -> CGPoint {
        if index == 0 {
            let side = webSide(width: width, elementSize: elementSize)
            let radius = side * (178.0 / 180) * 0.9
            return CGPoint(x: cos(0.85) * radius, y: top + sin(0.85) * radius)
        }
        // Public window safe area, not a private Dynamic Island API. The thread emerges
        // from beneath the cutout; it also degrades to the top edge on other devices.
        return CGPoint(x: width / 2 + 18, y: top + max(18, safeTop - 12))
    }
}

struct SeasonalStaticDecorations: View {
    let element: SeasonalElement
    let top: CGFloat
    let dark: Bool
    var preview = false
    var includeLeaves = true

    var body: some View {
        GeometryReader { geometry in
            let side = SeasonalDecorationGeometry.webSide(width: geometry.size.width, elementSize: element.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: SeasonalStaticArtwork.web(dark: dark))
                    .resizable().frame(width: side, height: side)
                    .offset(y: top)
                if includeLeaves, let leaves = SeasonalStaticArtwork.leaves {
                    // Stay in the outer gutter, beyond the text and controls. Clip at the
                    // window edge, not at an article/card boundary, and never participate in layout.
                    Image(uiImage: leaves).resizable().scaledToFit()
                        .frame(width: preview ? 32 : 48, height: preview ? 88 : 144)
                        .rotationEffect(.degrees(12))
                        .position(x: preview ? 0 : 2, y: geometry.size.height * 0.50)
                    Image(uiImage: leaves).resizable().scaledToFit()
                        .frame(width: preview ? 30 : 44, height: preview ? 82 : 132)
                        .scaleEffect(x: -1, y: 1).rotationEffect(.degrees(-17))
                        .position(x: geometry.size.width - 1, y: geometry.size.height * 0.74)
                }
            }
        }
        .clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}
