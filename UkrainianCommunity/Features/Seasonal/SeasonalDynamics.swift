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
    static func spiderProgress(at time: Double, preview: Bool) -> Double? {
        let phase = time.truncatingRemainder(dividingBy: preview ? 22 : 68)
        guard phase >= 2, phase < 16 else { return nil }
        let t = phase - 2
        func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        if t < 4 { return smooth(t / 4) }
        if t > 10 { return 1 - smooth((t - 10) / 4) }
        return 1
    }
    static func batProgress(at time: Double, preview: Bool) -> Double? {
        let phase = time.truncatingRemainder(dividingBy: preview ? 22 : 68)
        let start = preview ? 17.0 : 32.0
        guard phase >= start, phase < start + 4.5 else { return nil }
        return (phase - start) / 4.5
    }
}
