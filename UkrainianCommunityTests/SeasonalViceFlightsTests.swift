import XCTest
@testable import UkrainianCommunity

@MainActor final class SeasonalViceFlightsTests:XCTestCase {
    func testFlightsAreOnlyDerivedForVisibleViceArtworkWithoutChangingWireFormat() throws {
        var vice=SeasonalTheme.gtaVI()
        XCTAssertTrue(SeasonalViceFlights.isAvailable(in:vice))
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let before=try encoder.encode(vice)
        _ = SeasonalViceFlights.isAvailable(in:vice)
        XCTAssertEqual(before,try encoder.encode(vice))
        XCTAssertNil(vice.celebration,"No unsupported celebration value may reach already released clients")
        for theme in [SeasonalTheme.halloween(),.christmas(),.newYear()] { XCTAssertFalse(SeasonalViceFlights.isAvailable(in:theme)) }
        for i in vice.elements.indices { vice.elements[i].isEnabled=false }
        XCTAssertFalse(SeasonalViceFlights.isAvailable(in:vice))
    }

    func testStaggeredRoutesStartAndFinishOutsidePortraitAndLandscape() {
        XCTAssertGreaterThan(SeasonalViceFlights.departures[1],SeasonalViceFlights.departures[0]+8)
        XCTAssertLessThan(SeasonalViceFlights.departures[1]+SeasonalViceFlights.travel,SeasonalViceFlights.period)
        for size in [CGSize(width:393,height:852),CGSize(width:852,height:393),CGSize(width:1024,height:1366)] {
            for index in 0..<2 {
                let route=SeasonalViceFlights.route(size:size,index:index,preview:false)
                XCTAssertGreaterThan(route.start.x-route.width/2,size.width)
                XCTAssertLessThan(route.end.x+route.width/2,0)
                for sample in 0...60 {
                    let point=route.point(CGFloat(sample)/60)
                    XCTAssertGreaterThan(point.y,70)
                    XCTAssertLessThan(point.y,size.height-65)
                }
            }
        }
    }

    func testRendererReusesTexturesStaysBoundedAndStopsForReducedMotion() throws {
        let view=SeasonalFestivitiesView(frame:CGRect(x:0,y:0,width:393,height:852))
        view.configure(nil,animated:true,intensity:0.8,preview:false,viceFlights:true);view.layoutIfNeeded()
        XCTAssertEqual(view.effectLayers.count,2)
        let original=view.effectLayers
        for flight in original {
            let route=try XCTUnwrap(flight.animation(forKey:"seasonal.vice.flight") as? CAKeyframeAnimation)
            XCTAssertEqual(route.duration,76);XCTAssertEqual(route.values?.count,63)
            let flag=try XCTUnwrap(flight.sublayers?.first{$0.name?.contains("banner.")==true})
            XCTAssertEqual(flag.sublayers?.count,16)
            XCTAssertTrue(flag.sublayers?.allSatisfy{$0.contents != nil && $0.animation(forKey:"seasonal.vice.fabric") != nil} == true)
            let strips=try XCTUnwrap(flag.sublayers)
            for sample in [0,7,13,24] {
                for index in 0..<(strips.count-1) {
                    func edge(_ strip:CALayer,right:Bool) throws -> CGFloat {
                        let animation=try XCTUnwrap(strip.animation(forKey:"seasonal.vice.fabric") as? CAKeyframeAnimation)
                        let value=try XCTUnwrap(animation.values?[sample] as? NSValue).caTransform3DValue
                        return value.m42+(right ? 1:-1)*value.m12*strip.bounds.width/2
                    }
                    XCTAssertEqual(try edge(strips[index],right:true),try edge(strips[index+1],right:false),accuracy:0.00001,"Waving cloth strips must meet, without staircase gaps")
                }
            }
            XCTAssertEqual(flight.opacity,0,"No parked plane may remain on screen between passes")
        }
        for _ in 0..<30 { view.configure(nil,animated:true,intensity:0.8,preview:false,viceFlights:true);view.layoutIfNeeded() }
        XCTAssertTrue(view.effectLayers[0] === original[0],"Returning to a screen must not rebuild identical compositor layers")
        view.frame=CGRect(x:0,y:0,width:852,height:393);view.setNeedsLayout();view.layoutIfNeeded()
        XCTAssertEqual(view.effectLayers.count,2);XCTAssertNil(original[0].superlayer)
        view.configure(nil,animated:false,intensity:0.8,preview:false,viceFlights:true);view.layoutIfNeeded()
        XCTAssertTrue(view.effectLayers.isEmpty)
        view.configure(.fireworks,animated:true,intensity:0.8,preview:false,viceFlights:true);view.layoutIfNeeded()
        XCTAssertFalse(view.effectLayers.contains{$0.name?.contains("vice")==true},"Explicit scenes must not mix their celebrations")
        view.stop();XCTAssertTrue(view.effectLayers.isEmpty)
    }

    func testArtworkContactSheets() throws {
        XCTAssertNotNil(SeasonalViceFlights.plane)
        for dark in [false,true] {
            let view=SeasonalFestivitiesView(frame:CGRect(x:0,y:0,width:430,height:500))
            view.configure(nil,animated:true,intensity:0.8,preview:false,viceFlights:true);view.layoutIfNeeded()
            for (index,flight) in view.effectLayers.enumerated() {
                flight.removeAllAnimations();flight.opacity=1;flight.position=CGPoint(x:215,y:CGFloat(140+index*150))
            }
            let image=UIGraphicsImageRenderer(size:view.bounds.size).image { context in
                (dark ? UIColor(white:0.10,alpha:1):UIColor(red:0.92,green:0.96,blue:1,alpha:1)).setFill();context.fill(view.bounds)
                view.layer.render(in:context.cgContext)
            }
            let attachment=XCTAttachment(image:image);attachment.name="Vice-Aircraft-"+(dark ? "dark":"light");attachment.lifetime = .keepAlways;add(attachment)
        }
    }
}
