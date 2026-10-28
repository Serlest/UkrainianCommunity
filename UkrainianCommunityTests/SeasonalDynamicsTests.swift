import Foundation
import Testing
@testable import UkrainianCommunity

struct SeasonalDynamicsTests {
    @Test func batMakesOneCentralLoopAndExitsUpperRight() {
        for preview in [true,false] {
            let size=CGSize(width:393,height:preview ? 190:820)
            let start=SeasonalFlightPath.point(at:0,size:size,top:0,preview:preview)
            let end=SeasonalFlightPath.point(at:1,size:size,top:0,preview:preview)
            #expect(start.x<0 && start.y>size.height)
            #expect(end.x>size.width && end.y<0)
            let cx=size.width*0.5,cy=size.height*(preview ? 0.69:0.52)
            let radius=min(size.width*0.17,size.height*0.105)
            for step in 0...100 {
                let q=0.28+0.42*Double(step)/100
                let p=SeasonalFlightPath.point(at:q,size:size,top:0,preview:preview)
                #expect(abs(hypot(p.x-cx,p.y-cy)-radius)<0.001)
            }
            let right=SeasonalFlightPath.point(at:0.385,size:size,top:0,preview:preview)
            let upper=SeasonalFlightPath.point(at:0.49,size:size,top:0,preview:preview)
            let left=SeasonalFlightPath.point(at:0.595,size:size,top:0,preview:preview)
            #expect(right.x>cx && upper.y<cy && left.x<cx)
        }
    }
    @Test func flightJoinsHaveContinuousPositionAndVelocity() {
        let size=CGSize(width:393,height:820),epsilon=0.00001
        for join in [0.28,0.70] {
            let a=SeasonalFlightPath.point(at:join-epsilon,size:size,top:0,preview:false)
            let b=SeasonalFlightPath.point(at:join,size:size,top:0,preview:false)
            let c=SeasonalFlightPath.point(at:join+epsilon,size:size,top:0,preview:false)
            let left=CGPoint(x:(b.x-a.x)/epsilon,y:(b.y-a.y)/epsilon)
            let right=CGPoint(x:(c.x-b.x)/epsilon,y:(c.y-b.y)/epsilon)
            #expect(hypot(left.x-right.x,left.y-right.y)<1)
            #expect(hypot(b.x-a.x,b.y-a.y)<0.02)
        }
    }
    @Test func fourBatsHaveSeparateRoutesAndStaggeredArrival() {
        for preview in [true,false] {
            let size=CGSize(width:393,height:preview ? 190:820)
            let start=preview ? 18.0:32.0
            #expect(SeasonalChoreography.batCount==4)
            #expect(SeasonalChoreography.batProgress(at:start+0.1,preview:preview,index:0) != nil)
            #expect(SeasonalChoreography.batProgress(at:start+0.1,preview:preview,index:1)==nil)
            var points:[CGPoint]=[]
            for index in 0..<4 {
                let q=SeasonalChoreography.batProgress(at:start+4,preview:preview,index:index)
                #expect(q != nil)
                let p=SeasonalFlightPath.point(at:q ?? 0,size:size,top:0,preview:preview,index:index)
                #expect(p.x.isFinite && p.y.isFinite)
                for other in points { #expect(hypot(p.x-other.x,p.y-other.y)>10) }
                points.append(p)
                let end=SeasonalFlightPath.point(at:1,size:size,top:0,preview:preview,index:index)
                #expect(end.x>size.width && end.y<0)
            }
        }
    }
    @Test func calmScenesUseTenAndActiveMotionIsCappedAtThirty() {
        #expect(SeasonalFramePacing.rate(at:20,hasWeb:true,hasBat:true,preview:false,moving:false)==10)
        #expect(SeasonalFramePacing.rate(at:20,hasWeb:false,hasBat:false,preview:false,moving:false)==10)
        #expect(SeasonalFramePacing.rate(at:5,hasWeb:true,hasBat:false,preview:false,moving:false)==30)
        #expect(SeasonalFramePacing.rate(at:20,hasWeb:false,hasBat:false,preview:false,moving:true)==30)
        for preview in [true,false] {
            let start=preview ? 18.0:32.0
            #expect(SeasonalFramePacing.rate(at:start+10,hasWeb:true,hasBat:true,preview:preview,moving:false)==30)
            #expect(SeasonalFramePacing.rate(at:start+11,hasWeb:true,hasBat:true,preview:preview,moving:false)==10)
        }
    }
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
    @Test func spidersDescendOnceAndRemainAcrossAllFormerCycleBoundaries() {
        #expect(SeasonalChoreography.spiderCount==2)
        for preview in [true,false] { for index in 0..<2 {
            var previous=0.0
            for tick in 0...1400 {
                let t=Double(tick)/10
                let progress=SeasonalChoreography.spiderProgress(at:t,preview:preview,index:index)
                #expect((0...1).contains(progress))
                #expect(progress>=previous)
                previous=progress
                if t>=9 { #expect(progress==1) }
            }
            #expect(SeasonalChoreography.spiderProgress(at:3600,preview:preview,index:index)==1)
        } }
        #expect(SeasonalChoreography.spiderProgress(at:3,preview:false,index:0) >
                SeasonalChoreography.spiderProgress(at:3,preview:false,index:1))
        #expect(SeasonalChoreography.batProgress(at:20,preview:false)==nil)
        #expect(SeasonalChoreography.batProgress(at:33,preview:false) != nil)
    }
    @Test func cornerAndCutoutHaveSeparateStableAnchors() {
        for width in [320.0,393,440,768] {
            for size in [16.0,30,44] {
                let corner=SeasonalDecorationGeometry.spiderAnchor(index:0,width:width,top:0,safeTop:62,elementSize:size)
                let island=SeasonalDecorationGeometry.spiderAnchor(index:1,width:width,top:0,safeTop:62,elementSize:size)
                #expect(corner.x>0 && corner.x<width*0.36)
                #expect(corner.y>50 && corner.y<154)
                #expect(island.x>width/2 && island.x<width/2+40)
                #expect(island.y>=40 && island.y<62)
                #expect(hypot(corner.x-island.x,corner.y-island.y)>45)
                let shifted=SeasonalDecorationGeometry.spiderAnchor(index:0,width:width,top:12,safeTop:62,elementSize:size)
                #expect(shifted.x==corner.x && shifted.y==corner.y+12)
            }
        }
    }
    @Test func candleHasSmoothBrightAndNearlyExtinguishedIntervals() {
        let values=(0...720).map{SeasonalChoreography.candle(at:Double($0)/60)}
        #expect(values.min()!<0.04);#expect(values.max()!>0.95)
        for pair in zip(values,values.dropFirst()) { #expect(abs(pair.0-pair.1)<0.03) }
        #expect(SeasonalChoreography.candle(at:.nan).isFinite)
    }
}
