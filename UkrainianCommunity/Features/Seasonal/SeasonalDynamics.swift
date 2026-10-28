import CoreMotion
import Foundation

/// Bounded, deterministic pendulum. Long pauses never accumulate a physics jump.
struct SeasonalPendulum {
    private(set) var angle: Double = 0
    private(set) var velocity: Double = 0

    mutating func step(delta: Double, tilt: Double, acceleration: Double, intensity: Double) {
        guard delta.isFinite, delta > 0 else { return }
        let dt = min(delta, 1.0 / 20)
        let target = min(0.42, max(-0.42, tilt * 0.52))
        let impulse = -min(2, max(-2, acceleration)) * 6 * intensity
        velocity += ((target - angle) * 13 - velocity * 2.8 + impulse) * dt
        velocity = min(2.2, max(-2.2, velocity))
        angle = min(0.58, max(-0.58, angle + velocity * dt))
    }
}

struct SeasonalMotionSample {
    var x = 0.0
    var y = 0.0
    var acceleration = 0.0
    var gravityX = 0.0
}

@MainActor final class SeasonalMotion {
    private let manager = CMMotionManager()
    private var origin: (Double, Double)?
    private var filtered = SeasonalMotionSample()

    func setEnabled(_ enabled: Bool) {
        if enabled && !manager.isDeviceMotionActive && manager.isDeviceMotionAvailable {
            origin = nil; filtered = SeasonalMotionSample()
            manager.deviceMotionUpdateInterval = 1.0 / 30
            if CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical) {
                manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
            }
        } else if !enabled {
            manager.stopDeviceMotionUpdates(); origin = nil; filtered = SeasonalMotionSample()
        }
    }

    func sample() -> SeasonalMotionSample {
        guard let data = manager.deviceMotion else { return SeasonalMotionSample() }
        if origin == nil { origin = (data.gravity.x, data.gravity.y) }
        filtered.x += (min(1, max(-1, (data.gravity.x - (origin?.0 ?? 0)) * 2)) - filtered.x) * 0.14
        filtered.y += (min(1, max(-1, (data.gravity.y - (origin?.1 ?? 0)) * 2)) - filtered.y) * 0.14
        filtered.acceleration = min(2, max(-2, data.userAcceleration.x))
        filtered.gravityX = min(1,max(-1,data.gravity.x))
        return filtered
    }
    deinit { manager.stopDeviceMotionUpdates() }
}

enum SeasonalChoreography {
    static let spiderCount = 2
    /// One arrival per scene activation, then a permanent hanging state (no cycle reset).
    static func spiderProgress(at time: Double, preview: Bool, index: Int = 0) -> Double {
        guard time.isFinite else { return 0 }
        let start=2.0+Double(min(1,max(0,index)))*1.4
        let q=min(1,max(0,(time-start)/(preview ? 3.2:4.2)))
        return q*q*(3-2*q)
    }
    static let batCount = 4
    static func batProgress(at time: Double, preview: Bool, index: Int = 0) -> Double? {
        let phase = time.truncatingRemainder(dividingBy: preview ? 32 : 68)
        guard (0..<batCount).contains(index) else { return nil }
        let start = (preview ? 18.0 : 32.0) + Double(index) * 0.72
        guard phase >= start, phase < start + 8 else { return nil }
        return (phase - start) / 8
    }
}

/// Screen-space route: lower-left approach, one complete central loop, upper-right exit.
/// Cubic control handles match the circle's tangent and speed at both joins.
enum SeasonalFlightPath {
    static func point(at progress:Double,size:CGSize,top:Double,preview:Bool,index:Int = 0) -> CGPoint {
        let q=progress.isFinite ? min(1,max(0,progress)):0
        let width=Double(size.width),height=Double(size.height)
        let lane = Double(min(3,max(0,index)))
        let cx=width*(0.5 + [0.0,-0.09,0.08,-0.025][Int(lane)])
        let cy=height*(preview ? 0.69:0.52) + lane*(preview ? -5:23)
        let radius=min(width*0.17,height*0.105)*(1-lane*0.095)
        let join=CGPoint(x:cx,y:cy+radius)
        func cubic(_ t:Double,_ a:CGPoint,_ b:CGPoint,_ c:CGPoint,_ d:CGPoint) -> CGPoint {
            let s=1-t
            return CGPoint(x:s*s*s*a.x+3*s*s*t*b.x+3*s*t*t*c.x+t*t*t*d.x,
                           y:s*s*s*a.y+3*s*s*t*b.y+3*s*t*t*c.y+t*t*t*d.y)
        }
        if q<0.28 {
            let handle=2 * Double.pi * radius * 0.28 / (3 * 0.42)
            return cubic(q/0.28,CGPoint(x:-45,y:height+35),CGPoint(x:width*0.07,y:height*0.78),CGPoint(x:cx-handle,y:join.y),join)
        }
        if q<0.70 {
            let angle=Double.pi/2-(q-0.28)/0.42 * Double.pi*2
            return CGPoint(x:cx+cos(angle)*radius,y:cy+sin(angle)*radius)
        }
        let handle=2 * Double.pi * radius * 0.30 / (3 * 0.42)
        return cubic((q-0.70)/0.30,join,CGPoint(x:cx+handle,y:join.y),CGPoint(x:width*0.9,y:top+55),CGPoint(x:width+45,y:top-25))
    }
}

/// Shared by GPU morph targets and the two silk attachment points.
/// Points are expressed in native SceneKit coordinates: negative Y goes down.
enum SeasonalWebShape {
    static let attachments=[CGPoint(x:-40,y:-94),CGPoint(x:36,y:-103)]
    static func tapered(_ point:CGPoint) -> CGPoint {
        let q=min(1,max(0,(-point.y-38)/62))
        return CGPoint(x:point.x*(0.52+0.48*q*q*(3-2*q)),y:point.y)
    }
    static func displaced(_ point:CGPoint,amount:Double) -> CGPoint {
        let q=min(1,max(0,(-point.y-42)/80)),weight=q*q*(3-2*q)
        let bend=min(1,max(-1,amount))
        return CGPoint(x:point.x+bend*(7+sin(point.x*0.028)*2)*weight,
                       y:point.y+bend*sin(point.x*0.022)*1.5*weight)
    }
}

/// Keep the calm scene inexpensive; short motion/flight bursts get full-rate updates.
enum SeasonalFramePacing {
    static func rate(at time:Double,hasWeb:Bool,hasBat:Bool,preview:Bool,moving:Bool) -> Int {
        if moving || (hasWeb && time<9) { return 60 }
        if hasBat && (0..<SeasonalChoreography.batCount).contains(where:{SeasonalChoreography.batProgress(at:time,preview:preview,index:$0) != nil}) { return 60 }
        return 15
    }
}
