import SwiftUI
import UIKit

/// Vector artwork stays sharp; custom PNG frames are bounded and decoded once per element identity.
struct SeasonalArtworkView: View {
    let element: SeasonalElement
    let phase: Double
    let animated: Bool
    @Environment(\.colorScheme) private var scheme
    @State private var frames: [UIImage] = []

    var body: some View {
        Group {
            switch element.artwork {
            case .pumpkin: pumpkin
            case .web: web
            case .bat: SeasonalBatShape().fill(color.gradient)
            case .image:
                if !frames.isEmpty {
                    let index = animated ? Int(phase / element.frameDuration) % frames.count : 0
                    Image(uiImage: frames[max(0, index)]).resizable().scaledToFit()
                } else {
                    // Keep a real render node so .task can load an initially empty bitmap.
                    // EmptyView inside Group never receives the loading lifecycle.
                    Color.clear
                }
            default:
                Image(systemName: symbol).resizable().scaledToFit()
                    .foregroundStyle(color.gradient)
            }
        }
        .frame(width: element.size, height: element.size)
        .shadow(color: element.glow && element.artwork != .pumpkin ? glowColor.opacity(candle) : .clear, radius: 4)
        .task(id: element.pngFrames) {
            frames = element.pngFrames.compactMap { Data(base64Encoded: $0).flatMap(UIImage.init(data:)) }
        }
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch element.artwork {
        case .bat: "bat.fill"
        case .snowflake: "snowflake"
        case .pine: "tree.fill"
        default: "star.fill"
        }
    }
    private var color: Color {
        switch element.artwork {
        case .bat: scheme == .dark ? Color(red: 0.62, green: 0.52, blue: 0.76) : Color(red: 0.22, green: 0.16, blue: 0.32)
        case .snowflake: scheme == .dark ? .white : .cyan
        case .pine: .green
        default: .orange
        }
    }
    private var glowColor: Color {
        element.artwork == .web ? (scheme == .dark ? .white : .gray) : color
    }
    private var candle: Double {
        guard element.glow else { return 0 }
        guard animated else { return 0.7 }
        return min(1, max(0, 0.45 + 0.5 * sin(phase * 1.6) + 0.05 * sin(phase * 3.1)))
    }
    private var pumpkin: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            ZStack {
                Capsule().fill(Color(red: 0.26, green: 0.34, blue: 0.12))
                    .frame(width: w * 0.12, height: w * 0.24).rotationEffect(.degrees(18)).offset(y: -w * 0.35)
                Ellipse().fill(LinearGradient(colors: [.orange, Color(red: 0.72, green: 0.22, blue: 0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: w * 0.94, height: w * 0.75).offset(y: w * 0.08)
                ForEach([-0.22, 0.0, 0.22], id: \.self) { offset in
                    Ellipse().stroke(Color(red: 0.48, green: 0.13, blue: 0.01).opacity(0.3), lineWidth: 0.7)
                        .frame(width: w * 0.36, height: w * 0.71).offset(x: w * offset, y: w * 0.08)
                }
                PumpkinFace().fill(Color(red: 0.24, green: 0.08, blue: 0.01))
                PumpkinFace().fill(Color.yellow.opacity(candle))
                    .shadow(color: .orange.opacity(candle), radius: w * 0.1)
            }.shadow(color: .black.opacity(0.16), radius: 2, y: 2)
        }
    }
    private var web: some View {
        Canvas { context, size in
            let origin = CGPoint(x: size.width, y: 0)
            var path = Path()
            for ray in 0...5 {
                let angle = Double.pi / 2 + Double(ray) * Double.pi / 10
                path.move(to: origin)
                path.addLine(to: CGPoint(x: origin.x + cos(angle) * size.width, y: sin(angle) * size.height))
            }
            for radius in [0.32, 0.62, 0.92] {
                for ray in 0..<5 {
                    let a = Double.pi / 2 + Double(ray) * Double.pi / 10
                    let b = a + Double.pi / 10
                    path.move(to: CGPoint(x: origin.x + cos(a) * size.width * radius, y: sin(a) * size.height * radius))
                    path.addQuadCurve(to: CGPoint(x: origin.x + cos(b) * size.width * radius, y: sin(b) * size.height * radius),
                                      control: CGPoint(x: origin.x + cos((a+b)/2) * size.width * radius * 0.9, y: sin((a+b)/2) * size.height * radius * 0.9))
                }
            }
            context.stroke(path, with: .color(scheme == .dark ? .white.opacity(0.48) : .black.opacity(0.35)), lineWidth: 0.65)
        }
    }
}

private struct PumpkinFace: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in [0.23, 0.57] {
            path.move(to: CGPoint(x: rect.width*x, y: rect.height*0.39))
            path.addLine(to: CGPoint(x: rect.width*(x+0.19), y: rect.height*0.47))
            path.addLine(to: CGPoint(x: rect.width*(x+0.02), y: rect.height*0.51)); path.closeSubpath()
        }
        path.move(to: CGPoint(x: rect.width*0.25, y: rect.height*0.63))
        path.addQuadCurve(to: CGPoint(x: rect.width*0.75, y: rect.height*0.63), control: CGPoint(x: rect.width*0.5, y: rect.height*0.94))
        path.addLine(to: CGPoint(x: rect.width*0.61, y: rect.height*0.67))
        path.addLine(to: CGPoint(x: rect.width*0.55, y: rect.height*0.73))
        path.addLine(to: CGPoint(x: rect.width*0.45, y: rect.height*0.73))
        path.addLine(to: CGPoint(x: rect.width*0.39, y: rect.height*0.67)); path.closeSubpath()
        return path
    }
}

private struct SeasonalBatShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.width*x, y: rect.height*y) }
        p.move(to: point(0.49,0.35))
        p.addLine(to: point(0.42,0.18)); p.addLine(to: point(0.39,0.4))
        p.addCurve(to: point(0,0.13), control1: point(0.26,0.42), control2: point(0.13,0.14))
        p.addQuadCurve(to: point(0.12,0.69), control: point(0.01,0.5))
        p.addQuadCurve(to: point(0.29,0.65), control: point(0.15,0.49))
        p.addQuadCurve(to: point(0.43,0.84), control: point(0.4,0.59))
        p.addQuadCurve(to: point(0.57,0.84), control: point(0.5,0.74))
        p.addQuadCurve(to: point(0.71,0.65), control: point(0.6,0.59))
        p.addQuadCurve(to: point(0.88,0.69), control: point(0.85,0.49))
        p.addQuadCurve(to: point(1,0.13), control: point(0.99,0.5))
        p.addCurve(to: point(0.61,0.4), control1: point(0.87,0.14), control2: point(0.74,0.42))
        p.addLine(to: point(0.58,0.18));p.addLine(to: point(0.51,0.35));p.closeSubpath()
        return p
    }
}
