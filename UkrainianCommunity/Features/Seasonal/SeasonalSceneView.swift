import SceneKit
import SwiftUI
import UIKit

struct SeasonalScenePlacement: Equatable {
    var pumpkin = CGPoint(x:80,y:80)
    var webTop: CGFloat = 0
    var descent: CGFloat = 180
    var objectScale: CGFloat = 1
}

struct SeasonalScene: UIViewRepresentable {
    let theme: SeasonalTheme
    let placement: SeasonalScenePlacement
    let animated: Bool
    let dark: Bool
    var preview = false

    func makeUIView(context: Context) -> SeasonalSceneView { SeasonalSceneView() }
    func updateUIView(_ view: SeasonalSceneView, context: Context) {
        view.configure(theme:theme,placement:placement,animated:animated,dark:dark,preview:preview)
    }
    static func dismantleUIView(_ view:SeasonalSceneView,coordinator:()) { view.stop() }
}

@MainActor private final class SeasonalDisplayTarget: NSObject {
    weak var view: SeasonalSceneView?
    @objc func tick(_ link:CADisplayLink) { view?.tick(link.timestamp) }
}

/// One transparent native Metal-backed scene. No touches, camera feed, physics engine or remote code.
@MainActor final class SeasonalSceneView: UIView {
    private let renderer = SCNView()
    private let world = SCNNode()
    private let cameraNode = SCNNode()
    private var pumpkinNodes:[(SCNNode,SCNMaterial,SCNLight,SeasonalElement)] = []
    private var webNode:SCNNode?
    private var spiders:[(root:SCNNode,legs:[SCNNode],silk:SCNNode,pendulum:SeasonalPendulum)]=[]
    private var bats:[(root:SCNNode,wings:[SCNNode])]=[]
    private var elements:[SeasonalElement]=[]
    private var theme:SeasonalTheme?
    private var placement=SeasonalScenePlacement()
    private var animated=false, dark=false, preview=false
    private var link:CADisplayLink?
    private let target=SeasonalDisplayTarget()
    private let motion=SeasonalMotion()
    private var elapsed=0.0,lastTime=0.0

    override init(frame:CGRect) {
        super.init(frame:frame)
        isUserInteractionEnabled=false;isAccessibilityElement=false;backgroundColor = .clear
        renderer.backgroundColor = .clear;renderer.isOpaque=false;renderer.isUserInteractionEnabled=false
        renderer.antialiasingMode = .multisampling4X;renderer.preferredFramesPerSecond=30
        let scene=SCNScene();scene.rootNode.addChildNode(world)
        let camera=SCNCamera();camera.usesOrthographicProjection=true;camera.zNear=0.1;camera.zFar=2000
        camera.wantsHDR=true;camera.wantsExposureAdaptation=false
        camera.exposureOffset = -0.25;camera.bloomIntensity=0.04;camera.bloomThreshold=1.2
        cameraNode.camera=camera;cameraNode.position=SCNVector3(0,0,700);scene.rootNode.addChildNode(cameraNode)
        let ambient=SCNLight();ambient.type = .ambient;ambient.color=UIColor(white:0.9,alpha:1);ambient.intensity=420
        let a=SCNNode();a.light=ambient;scene.rootNode.addChildNode(a)
        let key=SCNLight();key.type = .directional;key.color=UIColor(red:1,green:0.91,blue:0.78,alpha:1);key.intensity=1150
        let k=SCNNode();k.light=key;k.eulerAngles=SCNVector3(-0.45,-0.55,0);scene.rootNode.addChildNode(k)
        let rim=SCNLight();rim.type = .directional;rim.color=UIColor(red:0.62,green:0.73,blue:1,alpha:1);rim.intensity=400
        let r=SCNNode();r.light=rim;r.eulerAngles=SCNVector3(0.4,2.4,0);scene.rootNode.addChildNode(r)
        renderer.scene=scene;renderer.pointOfView=cameraNode;addSubview(renderer);target.view=self
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews();renderer.frame=bounds
        cameraNode.camera?.orthographicScale=Double(max(1,bounds.height)/2)
        world.position=SCNVector3(-Float(bounds.width)/2,Float(bounds.height)/2,0)
        draw(delta:0)
    }

    func configure(theme:SeasonalTheme,placement:SeasonalScenePlacement,animated:Bool,dark:Bool,preview:Bool) {
        let changedIdentity=self.theme?.id != theme.id
        self.theme=theme;self.placement=placement;self.dark=dark;self.preview=preview
        let geometryChanged=elements.map { $0.id+"|"+$0.artwork.rawValue } != theme.elements.map { $0.id+"|"+$0.artwork.rawValue }
        elements=theme.elements
        if geometryChanged || changedIdentity {
            buildObjects();elapsed=0
        } else {
            // Size, glow and motion sliders update transforms/materials, never regenerate meshes.
            for index in pumpkinNodes.indices {
                if let current=elements.first(where:{$0.id==pumpkinNodes[index].3.id}) { pumpkinNodes[index].3=current }
            }
        }
        self.animated=animated
        motion.setEnabled(animated && theme.reactsToTilt && theme.elements.contains{$0.sway > 0})
        if animated && link == nil {
            lastTime=0
            let l=CADisplayLink(target:target,selector:#selector(SeasonalDisplayTarget.tick(_:)))
            l.preferredFramesPerSecond=30;l.add(to:.main,forMode:.common);link=l
        } else if !animated { link?.invalidate();link=nil;lastTime=0 }
        renderer.rendersContinuously=animated;renderer.isPlaying=animated
        draw(delta:0)
    }

    func stop() {
        link?.invalidate();link=nil;motion.setEnabled(false)
        renderer.rendersContinuously=false;renderer.isPlaying=false;lastTime=0
    }
    override func didMoveToWindow() { super.didMoveToWindow();if window == nil { stop() } }
    fileprivate func tick(_ timestamp:Double) {
        guard window != nil,animated else { return }
        let dt=lastTime == 0 ? 0 : min(0.05,max(0,timestamp-lastTime));lastTime=timestamp;elapsed += dt
        draw(delta:dt)
    }

    private func buildObjects() {
        world.childNodes.forEach{$0.removeFromParentNode()};pumpkinNodes=[];webNode=nil;bats=[];spiders=[]
        for element in elements where element.artwork == .pumpkin {
            let p=SeasonalSceneArtwork.pumpkin();world.addChildNode(p.root);pumpkinNodes.append((p.root,p.ember,p.light,element))
        }
        if elements.contains(where:{$0.artwork == .web}) {
            let web=SeasonalSceneArtwork.web();world.addChildNode(web);webNode=web
            for _ in 0..<SeasonalChoreography.spiderCount {
                let spider=SeasonalSceneArtwork.spider();world.addChildNode(spider.root)
                let g=SCNCylinder(radius:0.25,height:1);g.radialSegmentCount=5
                let m=SCNMaterial();m.lightingModel = .constant;g.firstMaterial=m
                let silk=SCNNode(geometry:g);world.addChildNode(silk)
                spiders.append((spider.root,spider.legs,silk,SeasonalPendulum()))
            }
        }
        if elements.contains(where:{$0.artwork == .bat}) {
            for _ in 0..<SeasonalChoreography.batCount {
                let bat=SeasonalSceneArtwork.bat();world.addChildNode(bat.root);bats.append(bat)
            }
        }
    }

    private func draw(delta:Double) {
        guard let theme else { return }
        SCNTransaction.begin();SCNTransaction.animationDuration=0;SCNTransaction.disableActions=true
        defer { SCNTransaction.commit() }
        let input=animated && theme.reactsToTilt ? motion.sample() : SeasonalMotionSample()
        let intensity=theme.intensity
        for (index,p) in pumpkinNodes.enumerated() {
            let scale=p.3.size * 0.53 * Double(placement.objectScale)
            p.0.scale=SCNVector3(scale,scale,scale)
            p.0.position=SCNVector3(placement.pumpkin.x + CGFloat(index)*12,-placement.pumpkin.y + (animated ? sin(elapsed*1.1)*1.2*intensity*p.3.sway:0),35)
            p.0.eulerAngles=SCNVector3(-0.08 + input.y*0.20*p.3.sway,-0.10 + input.x*0.38*p.3.sway + (animated ? sin(elapsed*0.6)*0.045*p.3.sway*intensity:0),-0.05)
            let candle=p.3.glow ? (animated ? max(0.12,0.6+sin(elapsed*1.6)*0.29+sin(elapsed*3.2)*0.07) : 0.65) : 0.08
            p.1.emission.intensity=CGFloat(candle*0.9);p.2.intensity=CGFloat(candle*20)
        }
        let top=Double(placement.webTop),center=Double(bounds.width)/2
        let webElement=elements.first{$0.artwork == .web}
        let webScale=min((webElement?.size ?? 44)/44*1.22,Double(bounds.width)/300)
        // The upper anchors never rotate. The mesh bends below the cutout on the GPU.
        webNode?.position=SCNVector3(center,-top,22);webNode?.scale=SCNVector3(webScale,webScale,webScale)
        let webStrength=animated ? (webElement?.sway ?? 0)*intensity : 0
        let bend=max(-1,min(1,(sin(elapsed*0.65)*0.55+input.x*1.5)*webStrength))
        webNode?.enumerateChildNodes { node,_ in
            node.morpher?.setWeight(CGFloat(max(0,bend)),forTargetAt:0)
            node.morpher?.setWeight(CGFloat(max(0,-bend)),forTargetAt:1)
            node.geometry?.materials.forEach {
                $0.diffuse.contents=dark ? UIColor(white:0.69,alpha:0.84):UIColor(white:0.20,alpha:0.78)
                $0.emission.contents=UIColor(white:0.12,alpha:1);$0.emission.intensity=(webElement?.glow ?? false) ? 0.035:0
            }
        }
        for index in spiders.indices {
            let progress=animated && (webElement?.sway ?? 0)>0
                ? SeasonalChoreography.spiderProgress(at:elapsed,preview:preview,index:index):1
            if animated {
                spiders[index].pendulum.step(delta:delta,tilt:input.gravityX*(webElement?.sway ?? 0)*2,
                    acceleration:input.acceleration*(index==0 ? 1:0.72),intensity:intensity*(webElement?.sway ?? 0))
            }
            let tapered=SeasonalWebShape.tapered(SeasonalWebShape.attachments[index])
            let point=SeasonalWebShape.displaced(tapered,amount:bend)
            let anchor=webNode?.convertPosition(SCNVector3(point.x,point.y,0),to:world) ?? SCNVector3(center,-top,33)
            let restingDepth=Double(placement.descent)*(index==0 ? 1:0.82)
            let length=8+max(18,restingDepth+Double(point.y)*webScale)*progress
            let angle=animated ? spiders[index].pendulum.angle:0
            let x=Double(anchor.x)+sin(angle)*length,y=Double(-anchor.y)+cos(angle)*length
            let spider=spiders[index]
            spider.root.position=SCNVector3(x,-y,34);spider.root.eulerAngles.z=Float(angle)
            let scale=(index==0 ? 1.6:1.15)*webScale
            spider.root.scale=SCNVector3(scale,scale,scale)
            let end=SCNVector3(x-sin(angle)*6,-y+cos(angle)*6,33),start=SCNVector3(anchor.x,anchor.y,33)
            let dx=end.x-start.x,dy=end.y-start.y,len=sqrt(dx*dx+dy*dy)
            (spider.silk.geometry as? SCNCylinder)?.height=CGFloat(len)
            spider.silk.position=SCNVector3((start.x+end.x)/2,(start.y+end.y)/2,33)
            spider.silk.simdOrientation=simd_quatf(from:SIMD3<Float>(0,1,0),to:SIMD3<Float>(dx,dy,0)/max(len,0.001))
            spider.silk.geometry?.firstMaterial?.diffuse.contents=dark ? UIColor(white:0.77,alpha:0.8):UIColor(white:0.24,alpha:0.68)
            for (i,leg) in spider.legs.enumerated() {
                leg.eulerAngles.z=animated ? Float(sin(elapsed*(index==0 ? 2.6:2.1)+Double(i))*0.045*intensity):0
            }
        }
        let batElement=elements.first{$0.artwork == .bat}
        for (index,bat) in bats.enumerated() {
            let progress=animated && (batElement?.sway ?? 0)>0 ? SeasonalChoreography.batProgress(at:elapsed,preview:preview,index:index) : nil
            bat.root.isHidden=progress == nil
            if let q=progress {
                let point=SeasonalFlightPath.point(at:q,size:bounds.size,top:top,preview:preview,index:index)
                let before=SeasonalFlightPath.point(at:q-0.001,size:bounds.size,top:top,preview:preview,index:index)
                let after=SeasonalFlightPath.point(at:q+0.001,size:bounds.size,top:top,preview:preview,index:index)
                let heading=atan2(-(after.y-before.y),after.x-before.x)
                bat.root.position=SCNVector3(point.x,-point.y,65)
                bat.root.eulerAngles=SCNVector3(0.35,sin(q * .pi*4)*0.38,Double(heading)-Double.pi/2)
                let scale=(batElement?.size ?? 20)/28*(0.8+sin(q * .pi)*0.3)*[1.0,0.81,0.92,0.74][index]
                bat.root.scale=SCNVector3(scale,scale,scale)
                for (i,wing) in bat.wings.enumerated() { wing.eulerAngles.y=Float(sin(elapsed*(17+Double(index)*0.9)+Double(index)*1.7)*(i == 0 ? -1:1)*(0.65+0.25*(batElement?.sway ?? 0))) }
                bat.root.enumerateChildNodes { node,_ in node.geometry?.materials.forEach {
                    $0.emission.contents=UIColor(red:0.22,green:0.11,blue:0.12,alpha:1);$0.emission.intensity=(batElement?.glow ?? false) ? 0.3:0
                } }
            }
        }
    }
}
