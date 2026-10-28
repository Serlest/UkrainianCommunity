import Testing
@testable import UkrainianCommunity

struct SeasonalDynamicsTests {
    @Test func sustainedTiltReachesStableAngleAndDampingSettles() {
        var p=SeasonalPendulum()
        for _ in 0..<900 { p.step(delta:1.0/60,tilt:0.6,acceleration:0,intensity:1) }
        #expect(abs(p.angle-0.312)<0.01)
        for _ in 0..<900 { p.step(delta:1.0/60,tilt:0,acceleration:0,intensity:1) }
        #expect(abs(p.angle)<0.001);#expect(abs(p.velocity)<0.001)
    }
    @Test func SuddenAccelerationProducesSwingWithoutTilt() {
        var p=SeasonalPendulum()
        p.step(delta:1.0/30,tilt:0,acceleration:1.5,intensity:1)
        // Inertia initially opposes acceleration of the phone.
        #expect(p.velocity<0);#expect(p.angle<0)
    }
    @Test func extremeMovementAndLongFrameStayBounded() {
        var p=SeasonalPendulum()
        for _ in 0..<1000 { p.step(delta:20,tilt:100,acceleration:100,intensity:1) }
        #expect(p.angle.isFinite && abs(p.angle)<=0.58)
        #expect(abs(p.velocity)<=2.2)
        let angle=p.angle
        p.step(delta:.nan,tilt:0,acceleration:0,intensity:1)
        #expect(p.angle==angle)
    }
    @Test func spiderAndBatNeverOverlapAndFlightIsInfrequent() {
        for preview in [true,false] {
            for tick in 0..<1360 {
                let t=Double(tick)/10
                let spider=SeasonalChoreography.spiderProgress(at:t,preview:preview)
                let bat=SeasonalChoreography.batProgress(at:t,preview:preview)
                #expect(spider==nil || bat==nil)
                if let spider { #expect((0...1).contains(spider)) }
                if let bat { #expect((0...1).contains(bat)) }
            }
        }
        #expect(SeasonalChoreography.spiderProgress(at:8,preview:false)==1)
        #expect(SeasonalChoreography.batProgress(at:20,preview:false)==nil)
        #expect(SeasonalChoreography.batProgress(at:33,preview:false) != nil)
    }
}
