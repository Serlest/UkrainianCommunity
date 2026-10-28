import SceneKit
import UIKit

/// Original procedural meshes and materials: no network assets, emoji or SF-symbol stand-ins.
@MainActor enum SeasonalSceneArtwork {
    static func material(_ color: UIColor, roughness: CGFloat = 0.5, metalness: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .physicallyBased
        m.diffuse.contents = color; m.roughness.contents = roughness; m.metalness.contents = metalness
        return m
    }

    static func sphere(_ radius: CGFloat, material: SCNMaterial) -> SCNNode {
        let g = SCNSphere(radius: radius); g.segmentCount = 24; g.firstMaterial = material
        return SCNNode(geometry: g)
    }

    static func strand(from a: SCNVector3, to b: SCNVector3, radius: CGFloat, material: SCNMaterial) -> SCNNode {
        let dx = b.x-a.x, dy = b.y-a.y, dz = b.z-a.z
        let length = sqrt(dx*dx+dy*dy+dz*dz)
        let cylinder = SCNCylinder(radius: radius, height: CGFloat(length)); cylinder.radialSegmentCount = 5
        cylinder.firstMaterial = material
        let node = SCNNode(geometry: cylinder)
        node.position = SCNVector3((a.x+b.x)/2,(a.y+b.y)/2,(a.z+b.z)/2)
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0,1,0), to: SIMD3<Float>(dx,dy,dz) / max(length,0.001))
        return node
    }

    private static let face: [[CGPoint]] = [
        [CGPoint(x:-0.58,y:0.26),CGPoint(x:-0.12,y:0.15),CGPoint(x:-0.45,y:-0.04)],
        [CGPoint(x:0.58,y:0.26),CGPoint(x:0.12,y:0.15),CGPoint(x:0.45,y:-0.04)],
        [CGPoint(x:-0.55,y:-0.24),CGPoint(x:-0.30,y:-0.35),CGPoint(x:-0.18,y:-0.27),CGPoint(x:-0.06,y:-0.39),
         CGPoint(x:0.08,y:-0.30),CGPoint(x:0.22,y:-0.37),CGPoint(x:0.55,y:-0.24),CGPoint(x:0.34,y:-0.56),
         CGPoint(x:0.13,y:-0.61),CGPoint(x:0,y:-0.52),CGPoint(x:-0.15,y:-0.60),CGPoint(x:-0.36,y:-0.52)]
    ]
    private static let cutoutPaths: [UIBezierPath] = face.map { points in
        let path=UIBezierPath();path.move(to:points[0]);points.dropFirst().forEach{path.addLine(to:$0)};path.close();return path
    }
    private static func isCutout(_ p: SCNVector3) -> Bool {
        guard p.z > 0.45 else { return false }
        for path in cutoutPaths {
            if path.contains(CGPoint(x:CGFloat(p.x),y:CGFloat(p.y))) { return true }
        }
        return false
    }

    static func pumpkin() -> (root: SCNNode, ember: SCNMaterial, light: SCNLight) {
        let root = SCNNode()
        let skin = material(UIColor(red:0.86,green:0.29,blue:0.025,alpha:1),roughness:0.42)
        // Fine skin variation keeps highlights from looking like smooth plastic.
        let texture = UIGraphicsImageRenderer(size:CGSize(width:256,height:128)).image { context in
            for y in 0..<128 { for x in 0..<256 {
                let grain = sin(Double(x)*37.1+Double(y)*71.7)*0.026
                let rib = cos(Double(x)/256 * .pi * 20)*0.08
                UIColor(red:0.80+grain+rib,green:0.26+grain+rib*0.45,blue:0.018+max(0,grain),alpha:1).setFill()
                context.cgContext.fill(CGRect(x:x,y:y,width:1,height:1))
            } }
        }
        skin.diffuse.contents = texture; skin.isDoubleSided = true
        var vertices:[SCNVector3]=[], normals:[SCNVector3]=[], uv:[CGPoint]=[], indices:[Int32]=[]
        let rows=72, columns=128
        for row in 0...rows {
            let phi=Double(row)/Double(rows)*Double.pi
            for column in 0...columns {
                let theta=Double(column)/Double(columns)*Double.pi*2
                let rib=1+0.075*cos(theta*10)*pow(sin(phi),2)
                let x=sin(phi)*cos(theta)*rib,y=cos(phi)*0.82,z=sin(phi)*sin(theta)*rib
                vertices.append(SCNVector3(x,y,z));normals.append(SCNVector3(x,y/0.82/0.82,z))
                uv.append(CGPoint(x:Double(column)/Double(columns),y:Double(row)/Double(rows)))
            }
        }
        for row in 0..<rows { for column in 0..<columns {
            let a=row*(columns+1)+column,b=a+columns+1,c=b+1,d=a+1
            for tri in [[a,c,b],[a,d,c]] {
                let p=tri.map{vertices[$0]}
                let center=SCNVector3((p[0].x+p[1].x+p[2].x)/3,(p[0].y+p[1].y+p[2].y)/3,(p[0].z+p[1].z+p[2].z)/3)
                if !isCutout(center) { indices += tri.map(Int32.init) }
            }
        } }
        let geometry=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals),SCNGeometrySource(textureCoordinates:uv)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
        geometry.firstMaterial=skin;root.addChildNode(SCNNode(geometry:geometry))
        let inner=SCNNode(geometry:geometry.copy() as? SCNGeometry)
        inner.geometry?.firstMaterial=material(UIColor(red:0.30,green:0.075,blue:0.008,alpha:1));inner.geometry?.firstMaterial?.isDoubleSided=true
        inner.scale=SCNVector3(0.92,0.92,0.92);root.addChildNode(inner)
        let ember=material(UIColor(red:1,green:0.52,blue:0.04,alpha:1))
        ember.lightingModel = .constant;ember.emission.contents=UIColor(red:1,green:0.43,blue:0.025,alpha:1)
        let core=sphere(0.77,material:ember);core.scale=SCNVector3(1,0.8,1);root.addChildNode(core)
        let stemMat=material(UIColor(red:0.23,green:0.26,blue:0.075,alpha:1),roughness:0.86)
        let stem=SCNNode();root.addChildNode(stem)
        for i in 0..<4 {
            stem.addChildNode(strand(from:SCNVector3(Double(i)*0.018,0.72+Double(i)*0.075,0),to:SCNVector3(Double(i+1)*0.018,0.80+Double(i)*0.075,-0.015),radius:CGFloat(0.09-Double(i)*0.012),material:stemMat))
        }
        let light=SCNLight();light.type = .omni;light.color=UIColor.orange;light.intensity=28;light.attenuationStartDistance=0;light.attenuationEndDistance=4
        let lamp=SCNNode();lamp.light=light;lamp.position=SCNVector3(0,0,0.8);root.addChildNode(lamp)
        return (root,ember,light)
    }

    static func web() -> SCNNode {
        let root=SCNNode();root.name="web"
        let silk=material(UIColor(white:0.26,alpha:0.72),roughness:0.38,metalness:0.18)
        let count=10
        for ray in 0...count {
            let angle=Double.pi*(0.07+Double(ray)/Double(count)*0.86)
            root.addChildNode(strand(from:SCNVector3Zero,to:SCNVector3(cos(angle)*92,-sin(angle)*90,0),radius:0.40,material:silk))
        }
        for ring in 1...6 { for ray in 0..<count {
            let a=Double.pi*(0.07+Double(ray)/Double(count)*0.86), b=Double.pi*(0.07+Double(ray+1)/Double(count)*0.86)
            let r=Double(ring)/6*90
            var previous=SCNVector3(cos(a)*r,-sin(a)*r,0)
            for step in 1...5 {
                let t=Double(step)/5,angle=a+(b-a)*t,radius=r*(1-0.055*sin(t * .pi))
                let next=SCNVector3(cos(angle)*radius,-sin(angle)*radius,0)
                root.addChildNode(strand(from:previous,to:next,radius:0.32,material:silk));previous=next
            }
        } }
        return root.flattenedClone()
    }

    static func spider() -> (root:SCNNode,legs:[SCNNode]) {
        let root=SCNNode(),shell=material(UIColor(red:0.085,green:0.055,blue:0.035,alpha:1),roughness:0.36,metalness:0.08)
        let body=sphere(3.6,material:shell);body.scale=SCNVector3(0.83,1.15,0.8);root.addChildNode(body)
        let head=sphere(2,material:shell);head.position=SCNVector3(0,-3.4,1);root.addChildNode(head)
        let eyeMat=material(UIColor(red:0.57,green:0.26,blue:0.09,alpha:1),roughness:0.16)
        for x in [-0.8,0.8] { let eye=sphere(0.35,material:eyeMat);eye.position=SCNVector3(x,-3.8,2.9);root.addChildNode(eye) }
        var legs:[SCNNode]=[]
        for side in [-1.0,1.0] { for i in 0..<4 {
            let leg=SCNNode(),knee=SCNVector3(side*(5.4+Double(i)*0.3),3.5-Double(i)*2.5,1.2)
            let tip=SCNVector3(side*(7.2+Double(i)*0.3),1.0-Double(i)*2.7,0)
            leg.addChildNode(strand(from:SCNVector3(side,1-Double(i),0),to:knee,radius:0.35,material:shell))
            leg.addChildNode(strand(from:knee,to:tip,radius:0.21,material:shell));root.addChildNode(leg);legs.append(leg)
        } }
        return (root,legs)
    }

    static func bat() -> (root:SCNNode,wings:[SCNNode]) {
        let root=SCNNode(),fur=material(UIColor(red:0.12,green:0.085,blue:0.13,alpha:1),roughness:0.72)
        let body=sphere(2.5,material:fur);body.scale=SCNVector3(0.85,1.5,0.8);root.addChildNode(body)
        let head=sphere(1.8,material:fur);head.position=SCNVector3(0,3.5,0);root.addChildNode(head)
        for side in [-1.0,1.0] {
            let cone=SCNCone(topRadius:0.12,bottomRadius:0.75,height:2.8);cone.firstMaterial=fur
            let ear=SCNNode(geometry:cone);ear.position=SCNVector3(side,5.3,0);ear.eulerAngles.z=Float(-side*0.2);root.addChildNode(ear)
        }
        let membrane=material(UIColor(red:0.20,green:0.105,blue:0.12,alpha:1),roughness:0.38,metalness:0.04);membrane.isDoubleSided=true
        var wings:[SCNNode]=[]
        for side in [-1.0,1.0] {
            let p=UIBezierPath();p.move(to:CGPoint(x:0,y:2));p.addCurve(to:CGPoint(x:side*17,y:8),controlPoint1:CGPoint(x:side*7,y:6),controlPoint2:CGPoint(x:side*11,y:12))
            p.addQuadCurve(to:CGPoint(x:side*12,y:-4),controlPoint:CGPoint(x:side*14,y:0))
            p.addQuadCurve(to:CGPoint(x:side*7,y:-3),controlPoint:CGPoint(x:side*10,y:0))
            p.addQuadCurve(to:CGPoint(x:0,y:-3),controlPoint:CGPoint(x:side*4,y:0));p.close()
            let g=SCNShape(path:p,extrusionDepth:0.28);g.chamferRadius=0.12;g.firstMaterial=membrane
            let wing=SCNNode();wing.addChildNode(SCNNode(geometry:g))
            for end in [SCNVector3(side*17,8,0.4),SCNVector3(side*12,-4,0.4),SCNVector3(side*7,-3,0.4)] {
                wing.addChildNode(strand(from:SCNVector3(0,1,0.4),to:end,radius:0.16,material:fur))
            }
            root.addChildNode(wing);wings.append(wing)
        }
        return (root,wings)
    }
}
