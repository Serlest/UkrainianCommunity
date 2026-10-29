import XCTest
import SceneKit
@testable import UkrainianCommunity

@MainActor final class SeasonalRenderingTests: XCTestCase {
    func testViceEmblemUsesCachedArtworkAndStopsCompositorMotion() throws {
        let element=try XCTUnwrap(SeasonalTheme.gtaVI().headerElements.first)
        let image=try XCTUnwrap(SeasonalSceneImages.image(element))
        XCTAssertTrue(image === SeasonalSceneImages.image(element))
        XCTAssertEqual(image.size,CGSize(width:192,height:192))
        let view=SeasonalHeaderImageView(frame:CGRect(x:0,y:0,width:52,height:52))
        view.configure(element,animated:true,intensity:0.6);view.layoutIfNeeded()
        let picture=try XCTUnwrap(view.subviews.first as? UIImageView)
        XCTAssertNotNil(picture.layer.animation(forKey:"seasonal.object"))
        for dark in [false,true] {
            let rendered=UIGraphicsImageRenderer(size:CGSize(width:240,height:120)).image { context in
                (dark ? UIColor(white:0.12,alpha:1):.white).setFill();context.fill(CGRect(x:0,y:0,width:240,height:120))
                image.draw(in:CGRect(x:24,y:18,width:84,height:84))
                image.draw(in:CGRect(x:156,y:38,width:44,height:44))
            }
            let attachment=XCTAttachment(image:rendered);attachment.name="Vice-VI-"+(dark ? "dark":"light");attachment.lifetime = .keepAlways;add(attachment)
        }
        view.configure(element,animated:false,intensity:0.6)
        XCTAssertNil(picture.layer.animationKeys())
        XCTAssertTrue(view.layer.sublayers?.allSatisfy{($0.animationKeys() ?? []).isEmpty} == true)
    }
    func testStaticArtworkIsCachedTransparentAndBounded() throws {
        let light=SeasonalStaticArtwork.web(dark:false),dark=SeasonalStaticArtwork.web(dark:true)
        XCTAssertTrue(light === SeasonalStaticArtwork.web(dark:false))
        XCTAssertTrue(dark === SeasonalStaticArtwork.web(dark:true))
        XCTAssertFalse(light === dark)
        XCTAssertEqual(light.size,CGSize(width:180,height:180))
        let leaves=try XCTUnwrap(SeasonalStaticArtwork.leaves)
        let cg=try XCTUnwrap(leaves.cgImage)
        XCTAssertLessThanOrEqual(cg.width,512);XCTAssertLessThanOrEqual(cg.height,512)
        var pixels=[UInt8](repeating:0,count:cg.width*cg.height*4)
        pixels.withUnsafeMutableBytes { data in
            let c=CGContext(data:data.baseAddress,width:cg.width,height:cg.height,bitsPerComponent:8,bytesPerRow:cg.width*4,
                            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(cg,in:CGRect(x:0,y:0,width:cg.width,height:cg.height))
        }
        let transparent=stride(from:3,to:pixels.count,by:4).filter{pixels[$0]<8}.count
        let covered=stride(from:3,to:pixels.count,by:4).filter{pixels[$0]>128}.count
        XCTAssertGreaterThan(transparent,cg.width*cg.height/6,"A rectangular leaf background must never cover the UI")
        XCTAssertGreaterThan(covered,cg.width*cg.height/10,"The actual botanical artwork must be present")
    }

    func testCalmFullWindowStopsSceneSubmissionsAndFlightResumes() throws {
        let window=UIWindow(frame:CGRect(x:0,y:0,width:393,height:852))
        let view=SeasonalSceneView(frame:window.bounds);window.addSubview(view)
        defer { view.stop();view.removeFromSuperview() }
        var theme=SeasonalTheme.halloween();theme.elements.removeAll{$0.artwork == .pumpkin}
        view.configure(theme:theme,placement:SeasonalScenePlacement(),animated:true,dark:false,preview:false)
        view.layoutIfNeeded()
        for i in 0...210 { view.tick(1000+Double(i)/10) }
        let resting=view.renderedFrameCount
        XCTAssertGreaterThan(resting,0)
        for i in 211...300 { view.tick(1000+Double(i)/10) }
        XCTAssertEqual(view.renderedFrameCount,resting,"Still spiders must not resubmit a full-window scene ten times a second")
        for i in 301...350 { view.tick(1000+Double(i)/10) }
        XCTAssertGreaterThan(view.renderedFrameCount,resting,"The rare flight must wake rendering again")
        let renderer=try XCTUnwrap(view.subviews.compactMap{$0 as? SCNView}.first)
        var morphers=0
        renderer.scene?.rootNode.enumerateChildNodes { node,_ in if node.morpher != nil { morphers += 1 } }
        XCTAssertEqual(morphers,0,"The static web must have no animated mesh or morph target")
    }

    func testPausingDuringDescentFreezesPoseAndResumesWithoutJump() throws {
        let window=UIWindow(frame:CGRect(x:0,y:0,width:393,height:852))
        let view=SeasonalSceneView(frame:window.bounds);window.addSubview(view)
        defer { view.stop();view.removeFromSuperview() }
        var theme=SeasonalTheme.halloween();theme.elements.removeAll{$0.artwork != .web}
        theme.elements[0].sway = 0 // Actual legacy published package: web motion was disabled.
        view.configure(theme:theme,placement:SeasonalScenePlacement(),animated:true,dark:false,preview:false)
        view.layoutIfNeeded()
        for i in 0...30 { view.tick(1000+Double(i)/10) }
        let renderer=try XCTUnwrap(view.subviews.compactMap{$0 as? SCNView}.first)
        let spider=try XCTUnwrap(renderer.scene?.rootNode.childNode(withName:"seasonal.spider.0",recursively:true))
        let y=spider.position.y
        view.configure(theme:theme,placement:SeasonalScenePlacement(),animated:false,dark:false,preview:false)
        XCTAssertEqual(spider.position.y,y,accuracy:0.001)
        view.configure(theme:theme,placement:SeasonalScenePlacement(),animated:true,dark:false,preview:false)
        view.tick(1010)
        XCTAssertEqual(spider.position.y,y,accuracy:0.001)
        view.tick(1010.1)
        XCTAssertLessThan(spider.position.y,y)
    }

    func testPhotographicHangingScenesSettleAndKeepOneBoundedScene() throws {
        for preset in [SeasonalTheme.gtaVI(),.christmas(),.newYear()] {
            let window=UIWindow(frame:CGRect(x:0,y:0,width:393,height:852))
            let view=SeasonalSceneView(frame:window.bounds);window.addSubview(view)
            var theme=preset;theme.elements.removeAll{$0.zone != .hanging}
            view.configure(theme:theme,placement:SeasonalScenePlacement(),animated:true,dark:true,preview:false);view.layoutIfNeeded()
            for i in 0...210 { view.tick(1000+Double(i)/10) }
            let renderer=try XCTUnwrap(view.subviews.compactMap{$0 as? SCNView}.first)
            let node=try XCTUnwrap(renderer.scene?.rootNode.childNode(withName:"seasonal.hanging.0",recursively:true))
            XCTAssertTrue(node.geometry is SCNPlane)
            XCTAssertTrue(node.geometry?.firstMaterial?.diffuse.contents is UIImage)
            let settled=view.renderedFrameCount
            for i in 211...300 { view.tick(1000+Double(i)/10) }
            XCTAssertEqual(view.renderedFrameCount,settled)
            view.stop();view.removeFromSuperview()
        }
    }

    func testHangingVisibilityDoesNotRecreateOrRestartObjects() throws {
        let window=UIWindow(frame:CGRect(x:0,y:0,width:430,height:932))
        let view=SeasonalSceneView(frame:window.bounds);window.addSubview(view)
        defer { view.stop();view.removeFromSuperview() }
        var theme=SeasonalTheme.halloweenScene();theme.elements.removeAll{$0.zone == .brand}
        view.configure(theme:theme,placement:SeasonalScenePlacement(),animated:true,dark:false,preview:false);view.layoutIfNeeded()
        for i in 0...210 { view.tick(1000+Double(i)/10) }
        let scene=try XCTUnwrap(view.subviews.compactMap{$0 as? SCNView}.first?.scene)
        let spider=try XCTUnwrap(scene.rootNode.childNode(withName:"seasonal.spider.0",recursively:true))
        let y=spider.position.y
        view.setHangingVisible(false);XCTAssertTrue(spider.isHidden)
        view.setHangingVisible(true);XCTAssertFalse(spider.isHidden)
        XCTAssertTrue(scene.rootNode.childNode(withName:"seasonal.spider.0",recursively:true) === spider)
        XCTAssertEqual(spider.position.y,y,accuracy:0.001)
    }

    func testPreparedAmbientScenesUseOnlyBoundedCompositorEffects() throws {
        for theme in [SeasonalTheme.gtaVI(),.christmas(),.newYear()] {
            let view=SeasonalAmbientView(frame:CGRect(x:0,y:0,width:393,height:852))
            view.configure(elements:theme.elements,animated:true,intensity:1,preview:false);view.layoutIfNeeded()
            let images=view.subviews.compactMap{$0 as? UIImageView}
            XCTAssertEqual(images.count,4)
            for image in images {
                let cg=try XCTUnwrap(image.image?.cgImage)
                XCTAssertLessThanOrEqual(cg.width,image.accessibilityIdentifier?.contains("navigation") == true ? 768:512);XCTAssertLessThanOrEqual(cg.height,512)
            }
            let animatedLayers=(view.layer.sublayers ?? []).filter{!($0.animationKeys() ?? []).isEmpty}
            XCTAssertLessThanOrEqual(animatedLayers.count,54)
            let snowLayers=(view.layer.sublayers ?? []).filter{$0.name=="seasonal.snow"}
            XCTAssertLessThanOrEqual(snowLayers.count,48)
            if theme.elements.contains(where:{$0.artwork == .snowflake}) { XCTAssertGreaterThanOrEqual(snowLayers.count,18) }
            var particleBudget=0.0
            for emitter in (view.layer.sublayers ?? []).compactMap({$0 as? CAEmitterLayer}) {
                for cell in emitter.emitterCells ?? [] { particleBudget += Double(cell.birthRate)*Double(cell.lifetime) }
            }
            XCTAssertLessThanOrEqual(particleBudget,24)

            view.configure(elements:theme.elements,animated:false,intensity:1,preview:false)
            XCTAssertTrue((view.layer.sublayers ?? []).allSatisfy{($0.animationKeys() ?? []).isEmpty && !($0 is CAEmitterLayer)})
            view.stop()
        }
    }
}
