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
    var hangingVisible = true

    func makeUIView(context: Context) -> SeasonalSceneView { SeasonalSceneView() }
    func updateUIView(_ view: SeasonalSceneView, context: Context) {
        view.configure(theme:theme,placement:placement,animated:animated,dark:dark,preview:preview)
        view.setHangingVisible(hangingVisible)
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
    private var spiders:[(root:SCNNode,legs:[SCNNode],silk:SCNNode,pendulum:SeasonalPendulum)]=[]
    private var bats:[(root:SCNNode,wings:[SCNNode])]=[]
    private var elements:[SeasonalElement]=[]
    private var theme:SeasonalTheme?
    private var hangingElement:SeasonalElement? {
        elements.first { $0.zone == .hanging } ?? (theme?.isComposedScene == true ? nil:elements.first{$0.artwork == .web})
    }
    private var hangingFrames:[UIImage]=[]
    private var hangingVisible=true
    private var lastHangingFrame = -1
    private var hangingMoves:Bool {
        guard let hanger=hangingElement else { return false }
        return hangingVisible && hanger.motionStrength>0 && (hanger.zone == nil || hanger.effectiveMotion == .swing)
    }
    private var materialSignature:String?
    private var placement=SeasonalScenePlacement()
    private var animated=false, dark=false, preview=false
    private var link:CADisplayLink?
    private let target=SeasonalDisplayTarget()
    private let motion=SeasonalMotion()
    private var elapsed=0.0,lastTime=0.0
    private var fastMotionUntil=0.0
    private var lastMotion=SeasonalMotionSample()
    private var needsRedraw = true
    private var previouslyActive = false
    private(set) var renderedFrameCount = 0

    override init(frame:CGRect) {
        super.init(frame:frame)
        isUserInteractionEnabled=false;isAccessibilityElement=false;backgroundColor = .clear
        renderer.backgroundColor = .clear;renderer.isOpaque=false;renderer.isUserInteractionEnabled=false
        renderer.antialiasingMode = .multisampling4X;renderer.preferredFramesPerSecond=60
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
        super.layoutSubviews()
        guard renderer.frame != bounds else { return }
        needsRedraw = true
        renderer.frame=bounds
        cameraNode.camera?.orthographicScale=Double(max(1,bounds.height)/2)
        world.position=SCNVector3(-Float(bounds.width)/2,Float(bounds.height)/2,0)
        if !animated { draw(delta:0) }
    }

    func configure(theme:SeasonalTheme,placement:SeasonalScenePlacement,animated:Bool,dark:Bool,preview:Bool) {
        let themeChanged=self.theme != theme,animationChanged=self.animated != animated
        let restartClock=animated && link == nil
        guard themeChanged || self.placement != placement || animationChanged || self.dark != dark || self.preview != preview || restartClock else { return }
        let changedIdentity=self.theme?.id != theme.id
        let geometryChanged=themeChanged && (elements.map { $0.id+"|"+$0.artwork.rawValue+"|"+($0.zone?.rawValue ?? "") } != theme.elements.map { $0.id+"|"+$0.artwork.rawValue+"|"+($0.zone?.rawValue ?? "") } || zip(elements,theme.elements).contains{$0.pngFrames != $1.pngFrames})
        self.theme=theme;self.placement=placement;self.dark=dark;self.preview=preview
        if themeChanged { elements=theme.elements }
        if geometryChanged || changedIdentity {
            buildObjects();elapsed=0;fastMotionUntil=0;lastMotion=SeasonalMotionSample()
        } else if themeChanged {
            for index in pumpkinNodes.indices {
                if let current=elements.first(where:{$0.id==pumpkinNodes[index].3.id}) { pumpkinNodes[index].3=current }
            }
        }
        needsRedraw = true
        updateMaterialAppearance()
        self.animated=animated
        if animationChanged || themeChanged || restartClock {
            motion.setEnabled(animated && theme.reactsToTilt && hangingMoves)
        }
        if themeChanged {
            // Bloom/HDR stay in the tiny header pumpkin viewport, not the full-screen web.
            let litPumpkin=elements.contains{$0.artwork == .pumpkin}
            cameraNode.camera?.wantsHDR=litPumpkin
            cameraNode.camera?.bloomIntensity=litPumpkin ? 0.04:0
            cameraNode.camera?.exposureOffset=litPumpkin ? -0.25:0
            renderer.antialiasingMode=litPumpkin ? .multisampling4X:.multisampling2X
        }
        if animated && link == nil {
            lastTime=0
            let l=CADisplayLink(target:target,selector:#selector(SeasonalDisplayTarget.tick(_:)))
            l.preferredFramesPerSecond=60;l.add(to:.main,forMode:.common);link=l
        } else if !animated { link?.invalidate();link=nil;lastTime=0 }
        renderer.rendersContinuously=false;renderer.isPlaying=false
        // An active scene is drawn once by DisplayLink, including after placement changes.
        if !animated { draw(delta:0) }
    }

    func setHangingVisible(_ visible:Bool) {
        guard hangingVisible != visible else { return }
        hangingVisible=visible;needsRedraw=true
        for spider in spiders { spider.root.isHidden = !visible;spider.silk.isHidden = !visible }
        motion.setEnabled(animated && (theme?.reactsToTilt ?? false) && hangingMoves)
        if !animated { draw(delta:0) }
    }

    func stop() {
        link?.invalidate();link=nil;motion.setEnabled(false)
        renderer.rendersContinuously=false;renderer.isPlaying=false;lastTime=0
    }
    override func didMoveToWindow() { super.didMoveToWindow();if window == nil { stop() } }
    func tick(_ timestamp:Double) {
        guard let window,animated,convert(bounds,to:window).intersects(window.bounds) else { return }
        let dt=lastTime == 0 ? 0 : min(0.1,max(0,timestamp-lastTime));lastTime=timestamp;elapsed += dt
        draw(delta:dt)
    }

    private func buildObjects() {
        materialSignature=nil
        world.childNodes.forEach{$0.removeFromParentNode()};pumpkinNodes=[];bats=[];spiders=[];hangingFrames=[];lastHangingFrame = -1
        for element in elements where element.artwork == .pumpkin {
            let p=SeasonalSceneArtwork.pumpkin();world.addChildNode(p.root);pumpkinNodes.append((p.root,p.ember,p.light,element))
        }
        if let hanger=hangingElement {
            if hanger.artwork == .image { hangingFrames=SeasonalSceneImages.frames(hanger) }
            let nativeSpider=hanger.artwork == .web || hanger.artwork == .spider
            let count=nativeSpider || hanger.artwork == .glassBauble ? 2:1
            for index in 0..<count {
                let root:SCNNode,legs:[SCNNode]
                if nativeSpider {
                    let spider=SeasonalSceneArtwork.spider();root=spider.root;legs=spider.legs
                    root.name="seasonal.spider.\(index)"
                } else {
                    root=SCNNode();legs=[];root.name="seasonal.hanging.\(index)"
                    if let image=SeasonalSceneImages.image(hanger) {
                        let plane=SCNPlane(width:image.size.width/max(1,image.size.height),height:1)
                        let material=SCNMaterial();material.lightingModel = .constant;material.diffuse.contents=image
                        material.isDoubleSided=true;material.transparencyMode = .aOne;plane.firstMaterial=material
                        root.geometry=plane
                    }
                }
                world.addChildNode(root)
                let g=SCNCylinder(radius:0.25,height:1);g.radialSegmentCount=5
                let m=SCNMaterial();m.lightingModel = .constant;g.firstMaterial=m
                let silk=SCNNode(geometry:g);world.addChildNode(silk)
                root.isHidden = !hangingVisible;silk.isHidden = !hangingVisible
                spiders.append((root,legs,silk,SeasonalPendulum()))
            }
        }
        if elements.contains(where:{$0.artwork == .bat}) {
            for _ in 0..<SeasonalChoreography.batCount {
                let bat=SeasonalSceneArtwork.bat();world.addChildNode(bat.root);bats.append(bat)
            }
        }
    }

    /// Theme/material properties change on configuration, never during each animation tick.
    private func updateMaterialAppearance() {
        let glow=elements.first{$0.artwork == .bat}?.glow ?? false
        let signature="\(dark)|\(glow)|\(hangingElement?.accentHex ?? "")|"+pumpkinNodes.map{$0.3.accentHex ?? ""}.joined(separator:"|")
        guard signature != materialSignature else { return }
        materialSignature=signature
        for pumpkin in pumpkinNodes {
            pumpkin.1.diffuse.contents=pumpkin.3.accentColor; pumpkin.1.emission.contents=pumpkin.3.accentColor; pumpkin.2.color=pumpkin.3.accentColor
        }
        for spider in spiders {
            spider.silk.geometry?.firstMaterial?.diffuse.contents=(hangingElement?.artwork == .glassBauble || hangingElement?.artwork == .keychain) ? hangingElement?.accentColor:(dark ? UIColor(white:0.77,alpha:0.8):UIColor(white:0.24,alpha:0.68))
        }
        for bat in bats { bat.root.enumerateChildNodes { node,_ in node.geometry?.materials.forEach {
            $0.emission.contents=UIColor(red:0.12,green:0.07,blue:0.035,alpha:1);$0.emission.intensity=glow ? 0.025:0
        } } }
    }

    private func draw(delta:Double) {
        guard let theme else { return }
        let input=animated && hangingVisible && theme.reactsToTilt && !spiders.isEmpty ? motion.sample() : SeasonalMotionSample()
        let moved=abs(input.acceleration)>0.025 || abs(input.x-lastMotion.x)>0.003 || abs(input.y-lastMotion.y)>0.003 || abs(input.gravityX-lastMotion.gravityX)>0.003
        if moved { fastMotionUntil=elapsed+0.8 }
        lastMotion=input
        let swinging=hangingMoves && spiders.contains{abs($0.pendulum.velocity)>0.003}
        let hasWeb=hangingMoves
        let hasBat=elements.contains{$0.artwork == .bat && $0.sway>0}
        let arriving=hasWeb && elapsed<9
        let flying=hasBat && (0..<SeasonalChoreography.batCount).contains{
            SeasonalChoreography.batProgress(at:elapsed,preview:preview,index:$0) != nil
        }
        let spriteAnimating=animated && hangingVisible && hangingFrames.count>1 && hangingElement?.effectiveMotion != .still
        let spriteFrame=spriteAnimating ? Int(elapsed/(hangingElement?.frameDuration ?? 0.2)) % hangingFrames.count:nil
        let active=elapsed<fastMotionUntil || swinging || arriving || flying || (spriteFrame != nil && spriteFrame != lastHangingFrame)
        if animated {
            let rate=SeasonalFramePacing.rate(at:elapsed,hasWeb:hasWeb,hasBat:hasBat,preview:preview,moving:elapsed<fastMotionUntil || swinging)
            if link?.preferredFramesPerSecond != rate { link?.preferredFramesPerSecond=rate }
            if renderer.preferredFramesPerSecond != rate { renderer.preferredFramesPerSecond=rate }
        }
        // Poll gravity at the calm clock rate, but do not redraw an unmoving full-window
        // scene. The final active frame still hides departed bats and settles the legs.
        let wasActive=previouslyActive;previouslyActive=active
        guard needsRedraw || !animated || active || wasActive || pumpkinNodes.contains(where:{$0.3.glow && $0.3.motionStyle != .still}) else { return }
        needsRedraw=false;renderedFrameCount += 1
        SCNTransaction.begin();SCNTransaction.animationDuration=0;SCNTransaction.disableActions=true
        defer { SCNTransaction.commit() }
        let intensity=theme.intensity
        if let frame=spriteFrame {
            if frame != lastHangingFrame { for item in spiders { item.root.geometry?.firstMaterial?.diffuse.contents=hangingFrames[frame] };lastHangingFrame=frame }
        }
        for (index,p) in pumpkinNodes.enumerated() {
            let scale=p.3.size * 0.53 * Double(placement.objectScale)
            p.0.scale=SCNVector3(scale,scale,scale)
            p.0.position=SCNVector3(placement.pumpkin.x + CGFloat(index)*12,-placement.pumpkin.y,35)
            p.0.eulerAngles=SCNVector3(-0.08,-0.10,-0.05)
            let candle=p.3.glow ? ((animated || elapsed>0) ? SeasonalChoreography.candle(at:elapsed) : 0.65) : 0.035
            p.1.diffuse.intensity=CGFloat(candle);p.1.emission.intensity=CGFloat(candle*0.8);p.2.intensity=CGFloat(candle*20)
        }
        let top=Double(placement.webTop)
        let webElement=hangingElement
        let nativeSpider=webElement?.artwork == .web || webElement?.artwork == .spider
        let webScale=min((webElement?.size ?? 44)/44,Double(bounds.width)/300)
        for index in spiders.indices {
            let progress=(animated || elapsed>0) && hangingMoves
                ? SeasonalChoreography.spiderProgress(at:elapsed,preview:preview,index:index):1
            if animated && hangingMoves {
                spiders[index].pendulum.step(delta:delta,tilt:input.gravityX*(webElement?.motionStrength ?? 0)*2,
                    acceleration:input.acceleration*(index==0 ? 1:0.72),intensity:intensity*(webElement?.motionStrength ?? 0))
            }
            let safeTop=preview ? 38:Double(window?.safeAreaInsets.top ?? 0)
            let attachmentSize=elements.first{$0.artwork == .web}?.size ?? 34
            let point:CGPoint
            if nativeSpider {
                point=SeasonalDecorationGeometry.spiderAnchor(index:index,width:bounds.width,top:top,safeTop:safeTop,elementSize:attachmentSize)
            } else {
                point=CGPoint(x:bounds.width/2+(spiders.count == 1 ? 18:(index == 0 ? 6:30)),y:top+max(18,safeTop-12))
            }
            let anchor=SCNVector3(point.x,-point.y,33)
            let restingDepth=nativeSpider ? top+Double(placement.descent)*(index==0 ? 1:0.82):top+safeTop+(index==0 ? 30:15)
            let length=8+max(24,restingDepth-point.y)*progress
            let angle=(animated || elapsed>0) && hangingMoves ? spiders[index].pendulum.angle*(nativeSpider ? 1:0.55):0
            let x=Double(anchor.x)+sin(angle)*length,y=Double(-anchor.y)+cos(angle)*length
            let spider=spiders[index]
            spider.root.position=SCNVector3(x,-y,34);spider.root.eulerAngles.z=Float(angle)
            let scale=nativeSpider ? (index==0 ? 1.6:1.15)*webScale:(webElement?.size ?? 32)*(index==0 ? 1.65:1.4)
            spider.root.scale=SCNVector3(scale,scale,scale)
            let tip=nativeSpider ? 6:Float(scale*0.45)
            let end=SCNVector3(x-sin(angle)*Double(tip),-y+cos(angle)*Double(tip),33),start=SCNVector3(anchor.x,anchor.y,33)
            let dx=end.x-start.x,dy=end.y-start.y,len=sqrt(dx*dx+dy*dy)
            (spider.silk.geometry as? SCNCylinder)?.height=CGFloat(len)
            spider.silk.position=SCNVector3((start.x+end.x)/2,(start.y+end.y)/2,33)
            spider.silk.simdOrientation=simd_quatf(from:SIMD3<Float>(0,1,0),to:SIMD3<Float>(dx,dy,0)/max(len,0.001))
            for (i,leg) in spider.legs.enumerated() {
                leg.eulerAngles.z=(animated || elapsed>0) && progress<1 ? Float(sin(elapsed*(index==0 ? 2.6:2.1)+Double(i))*0.045*intensity):0
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
            }
        }
    }
}
