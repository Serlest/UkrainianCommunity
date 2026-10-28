import XCTest
import SceneKit
import Metal
@testable import UkrainianCommunity

@MainActor final class SeasonalRenderingTests: XCTestCase {
    func testWebRenderingCost() throws {
        guard let device=MTLCreateSystemDefaultDevice() else { throw XCTSkip("A Metal-capable simulator host is required for this rendering benchmark") }
        let queue=try XCTUnwrap(device.makeCommandQueue())
        let renderer=SCNRenderer(device:device,options:nil)
        let scene=SCNScene(),web=SeasonalSceneArtwork.web();scene.rootNode.addChildNode(web)
        let camera=SCNNode();camera.camera=SCNCamera();camera.camera?.usesOrthographicProjection=true
        camera.camera?.orthographicScale=110;camera.position=SCNVector3(0,-30,700)
        scene.rootNode.addChildNode(camera);renderer.scene=scene;renderer.pointOfView=camera
        let light=SCNNode();light.light=SCNLight();light.light?.type = .ambient;light.light?.intensity=800
        scene.rootNode.addChildNode(light)
        let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:1179,height:660,mipmapped:false)
        descriptor.usage=[.renderTarget,.shaderRead];descriptor.storageMode = .private
        let texture=try XCTUnwrap(device.makeTexture(descriptor:descriptor))
        let depth=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:1179,height:660,mipmapped:false)
        depth.usage = .renderTarget;depth.storageMode = .private
        let depthTexture=try XCTUnwrap(device.makeTexture(descriptor:depth))
        let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=texture
        pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture=depthTexture;pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
        var vertices=0,triangles=0,morphVertices=0,nodes:[SCNNode]=[]
        web.enumerateChildNodes { node,_ in
            guard let g=node.geometry else { return };nodes.append(node)
            vertices += g.sources(for:.vertex).first?.vectorCount ?? 0
            triangles += g.elements.reduce(0) { $0+$1.primitiveCount }
            morphVertices += node.morpher?.targets.reduce(0) { $0+($1.sources(for:.vertex).first?.vectorCount ?? 0) } ?? 0
        }
        var samples:[Double]=[],gpu:[Double]=[]
        for frame in 0..<80 {
            SCNTransaction.begin();SCNTransaction.disableActions=true
            let q=sin(Double(frame)*0.2)
            for node in nodes { node.morpher?.setWeight(CGFloat(max(0,q)),forTargetAt:0);node.morpher?.setWeight(CGFloat(max(0,-q)),forTargetAt:1) }
            SCNTransaction.commit()
            let buffer=try XCTUnwrap(queue.makeCommandBuffer()),start=CFAbsoluteTimeGetCurrent()
            renderer.render(atTime:Double(frame)/30,viewport:CGRect(x:0,y:0,width:1179,height:660),commandBuffer:buffer,passDescriptor:pass)
            buffer.commit();buffer.waitUntilCompleted()
            XCTAssertNil(buffer.error)
            if frame>=20 {
                samples.append((CFAbsoluteTimeGetCurrent()-start)*1000)
                if buffer.gpuEndTime>buffer.gpuStartTime { gpu.append((buffer.gpuEndTime-buffer.gpuStartTime)*1000) }
            }
        }
        let sorted=samples.sorted()
        let report:[String:Any]=["vertices":vertices,"triangles":triangles,"morphVertices":morphVertices,
            "frames":samples.count,"medianWallMs":sorted[sorted.count/2],"p95WallMs":sorted[Int(Double(sorted.count-1)*0.95)],
            "meanGpuMs":gpu.isEmpty ? 0:gpu.reduce(0,+)/Double(gpu.count),"scope":"isolated web, simulator Metal, 1179x660; not iPhone FPS"]
        let data=try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys])
        let attachment=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");attachment.name="SeasonalWebRenderCost";attachment.lifetime = .keepAlways;add(attachment)
        print("SEASONAL_WEB_BENCHMARK "+String(decoding:data,as:UTF8.self))
        XCTAssertGreaterThan(vertices,0)
        // A silk overlay has a strict budget; do not regress to lit thread cylinders.
        XCTAssertLessThanOrEqual(vertices,100)
        XCTAssertLessThanOrEqual(triangles,150)
        XCTAssertLessThanOrEqual(morphVertices,200)
    }
}
