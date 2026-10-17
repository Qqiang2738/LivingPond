import AppKit
import SpriteKit

struct FishPalette {
    let name: String
    let base: NSColor
    let spots: [NSColor]
}

/// Each named koi has a deliberately different morphometric and pigmentation
/// profile; body, pectorals and caudal fin are independently drawn geometry.
/// No screenshots or whole-fish sprites are used.
final class NativeFish: SKNode {
    let identity: Int
    let length: CGFloat
    let bodyWidth: CGFloat
    let isLarge: Bool
    let palette: FishPalette

    private struct Pigment {
        var t: CGFloat
        var width: CGFloat
        var coverage: CGFloat
        var offset: CGFloat
        var color: NSColor
    }
    private let leftPectoral = SKShapeNode()
    private let rightPectoral = SKShapeNode()
    private let tail = SKShapeNode()
    private let tailRays = SKShapeNode()
    private let dorsal = SKShapeNode()
    private let body = SKShapeNode()
    private let softShadow = SKShapeNode()
    private let gillMark = SKShapeNode()
    private let scaleDetails = SKShapeNode()
    private let sheen = SKShapeNode()
    private let backHighlight = SKShapeNode()
    private let breedDetails = SKShapeNode()
    private let leftEye = SKShapeNode(circleOfRadius: 1.3)
    private let rightEye = SKShapeNode(circleOfRadius: 1.3)
    private var pigments: [(node: SKShapeNode, spec: Pigment)] = []
    private var phase = CGFloat.random(in: 0...(2 * CGFloat.pi))
    private var heading: CGFloat
    private var goal: CGPoint = .zero
    private var goalAge: TimeInterval = 0
    private let swimSpeed: CGFloat
    private let maxTurn: CGFloat
    private let tailRate: CGFloat
    private let finScale: CGFloat
    private let caudalScale: CGFloat
    private let crownShape: CGFloat
    private let rearFullness: CGFloat

    init(identity: Int, big: Bool, palette: FishPalette, sceneSize: CGSize) {
        self.identity = identity
        self.isLarge = big
        self.palette = palette
        // Individuals are different in silhouette, not just scale / color.
        let widthProfile: [CGFloat] = [1.12, 1.04, 0.89, 1.00, 0.86, 1.08, 1.17, 0.98, 0.96, 1.10, 0.84]
        let headProfile: [CGFloat] = [1.04, 1.12, 0.92, 1.02, 0.82, 1.10, 1.18, 0.90, 0.96, 1.06, 0.86]
        let caudals: [CGFloat] = [0.94, 1.02, 0.76, 0.98, 1.07, 0.98, 0.79, 0.84, 1.20, 1.02, 1.12]
        let fins: [CGFloat] = [1.02, 1.06, 0.82, 0.93, 1.09, 1.07, 0.83, 0.88, 1.16, 1.02, 1.08]
        self.length = big ? CGFloat(115 + identity * 8) : CGFloat(50 + (identity % 5) * 6)
        self.bodyWidth = length * (big ? 0.212 : 0.206) * widthProfile[identity % 11]
        self.crownShape = headProfile[identity % 11]
        self.rearFullness = widthProfile[identity % 11]
        self.caudalScale = caudals[identity % 11]
        self.finScale = fins[identity % 11]
        // Proven V0.8.x flight model, intentionally unchanged.
        self.swimSpeed = (big ? 47 : 62) + CGFloat(identity % 4) * 3
        self.maxTurn = big ? 0.48 : 0.82
        self.tailRate = big ? 1.32 : 1.70
        self.heading = CGFloat.random(in: -CGFloat.pi...CGFloat.pi)
        super.init()
        position = CGPoint(x:sceneSize.width * CGFloat.random(in:0.22...0.76),
                           y:sceneSize.height * CGFloat.random(in:0.22...0.77))
        zRotation = heading
        goal = CGPoint(x:sceneSize.width * 0.52, y:sceneSize.height * 0.52)
        zPosition = big ? 18 : 17

        softShadow.zPosition = -2
        softShadow.fillColor = .black.withAlphaComponent(big ? 0.13 : 0.11)
        softShadow.strokeColor = .clear
        addChild(softShadow)
        for (node, order) in [(tail,0.0),(leftPectoral,1.0),(rightPectoral,1.0),
                              (dorsal,2.0),(body,3.0),(backHighlight,3.6),(sheen,4.0)] {
            node.zPosition = CGFloat(order)
            node.strokeColor = .clear
            addChild(node)
        }
        body.fillColor = palette.base
        body.strokeColor = NSColor.white.withAlphaComponent(0.10)
        body.lineWidth = 0.55
        for node in [leftPectoral,rightPectoral,tail,dorsal] {
            node.fillColor = palette.base.withAlphaComponent(0.70)
            node.strokeColor = NSColor.white.withAlphaComponent(0.16)
            node.lineWidth = 0.55
        }
        tailRays.fillColor = .clear
        tailRays.strokeColor = NSColor.white.withAlphaComponent(0.15)
        tailRays.lineWidth = 0.35
        tailRays.zPosition = 0.5
        tail.addChild(tailRays)
        gillMark.fillColor = .clear
        gillMark.strokeColor = NSColor(calibratedWhite:0.18,alpha:0.19)
        gillMark.lineWidth = max(0.48,length * 0.0048)
        gillMark.zPosition = 5.4
        addChild(gillMark)
        scaleDetails.fillColor = .clear
        scaleDetails.strokeColor = NSColor.white.withAlphaComponent(0.14)
        scaleDetails.lineWidth = 0.38
        scaleDetails.zPosition = 5.2
        addChild(scaleDetails)
        backHighlight.fillColor = NSColor.white.withAlphaComponent(identity == 2 || identity == 10 ? 0.12 : 0.065)
        backHighlight.strokeColor = .clear
        breedDetails.fillColor = .clear
        breedDetails.strokeColor = NSColor.white.withAlphaComponent(0.17)
        breedDetails.lineWidth = 0.33
        breedDetails.zPosition = 5.3
        addChild(breedDetails)
        sheen.fillColor = .clear
        sheen.strokeColor = NSColor.white.withAlphaComponent(0.19)
        sheen.lineWidth = 0.58
        for pigment in markings() {
            let shape = SKShapeNode(path:pigmentPath(pigment))
            shape.fillColor = pigment.color
            shape.strokeColor = .clear
            shape.zPosition = 4.8
            addChild(shape)
            pigments.append((shape,pigment))
        }
        for eye in [leftEye,rightEye] {
            eye.fillColor = NSColor(calibratedWhite:0.045,alpha:0.90)
            eye.strokeColor = .clear
            eye.zPosition = 6.1
            addChild(eye)
        }
        renderShape()
        renderBreedDetails()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func markings() -> [Pigment] {
        let black = NSColor(red:0.10,green:0.16,blue:0.15,alpha:0.98)
        let vermilion = NSColor(red:0.82,green:0.23,blue:0.12,alpha:0.98)
        let coral = NSColor(red:0.89,green:0.34,blue:0.18,alpha:0.96)
        let blue = NSColor(red:0.29,green:0.49,blue:0.62,alpha:0.94)
        let warm = NSColor(red:0.92,green:0.53,blue:0.23,alpha:0.88)
        func p(_ t:CGFloat,_ width:CGFloat,_ coverage:CGFloat,_ offset:CGFloat,_ color:NSColor)->Pigment {
            Pigment(t:t,width:width,coverage:coverage,offset:offset,color:color)
        }
        switch identity {
        case 0: // Kohaku: large, isolated vermilion islands, clean snow-white flanks.
            return [p(0.20,0.095,0.73,0,vermilion),p(0.43,0.12,0.79,0.08,coral),p(0.65,0.093,0.70,-0.08,vermilion)]
        case 1: // Showa: sumi foundation, bold asymmetric white and crimson islands.
            return [p(0.19,0.10,0.65,0.02,.white),p(0.40,0.12,0.85,-0.10,vermilion),p(0.59,0.075,0.65,0.19,.white),p(0.74,0.055,0.70,0.02,coral)]
        case 2: // Yamabuki ogon: metallic gold, NO fake red polka dots.
            return []
        case 3: // Tancho: unmistakable single forehead mark.
            return [p(0.14,0.067,0.74,0,vermilion)]
        case 4: // Shusui: blue dorsal chain and warm reddish lateral accents.
            return [p(0.27,0.095,0.43,0,blue),p(0.48,0.075,0.38,0,blue),p(0.64,0.060,0.36,0,blue),p(0.42,0.070,0.25,0.66,warm),p(0.55,0.072,0.26,-0.69,warm)]
        case 5: // Shiro utsuri: bold cross-back sumi on ivory.
            return [p(0.18,0.070,0.84,0.07,black),p(0.39,0.098,0.97,-0.02,black),p(0.65,0.067,0.90,0.13,black)]
        case 6: // Chagoi: quiet solid earthen koi, no counterfeit spots.
            return []
        case 7: // Asagi: blue back, warm orange near lateral line.
            return [p(0.28,0.12,0.47,0,blue),p(0.49,0.10,0.52,0,blue),p(0.67,0.078,0.43,0,blue),p(0.43,0.045,0.31,0.67,warm),p(0.57,0.045,0.27,-0.67,warm)]
        case 8: // Kujaku: metallic net scales with restrained red accents.
            return [p(0.19,0.070,0.63,0,coral),p(0.51,0.095,0.72,-0.03,vermilion),p(0.73,0.044,0.60,0.05,coral)]
        case 9: // Taisho sanke: red islands plus small sumi islands, white head.
            return [p(0.27,0.085,0.73,0.02,coral),p(0.43,0.048,0.42,-0.46,black),p(0.56,0.095,0.81,0.04,vermilion),p(0.72,0.050,0.40,0.31,black)]
        default: // Platinum ogon: silver-white, unspotted, luminous scales.
            return []
        }
    }

    private func pigmentPath(_ spec:Pigment) -> CGPath {
        // Hand-edged pigment islands, not a polygon stamped on every fish.
        // Piecewise quadratic contour preserves the natural curved edges of sumi/hi.
        let rx = length * spec.width
        let ry = widthAt(spec.t) * min(spec.coverage, 0.81)
        let count = 16
        var pts: [CGPoint] = []
        for i in 0..<count {
            let a=CGFloat(i)*2*CGFloat.pi/CGFloat(count)
            let irregularity = 1 + 0.086*sin(a*3 + spec.t*19 + CGFloat(identity)*0.57)
                              + 0.034*cos(a*5 - spec.t*11)
            pts.append(CGPoint(x: cos(a)*rx*irregularity,
                               y: sin(a)*ry*(0.91+0.06*cos(a*2+spec.t*8))))
        }
        let result=CGMutablePath()
        func mid(_ a:CGPoint,_ b:CGPoint)->CGPoint {
            CGPoint(x:(a.x+b.x)*0.5,y:(a.y+b.y)*0.5)
        }
        result.move(to:mid(pts[count-1],pts[0]))
        for i in 0..<count {
            result.addQuadCurve(to:mid(pts[i],pts[(i+1)%count]),control:pts[i])
        }
        result.closeSubpath()
        return result
    }

    private func renderBreedDetails() {
        // Species-specific markings are constructed once and move as a group.
        // No new particles, textures or per-frame nodes are created.
        let p=CGMutablePath()
        let ink: NSColor
        switch identity {
        case 4: // Shusui: a line of dark mirror scales along the spine.
            ink=NSColor(red:0.17,green:0.29,blue:0.37,alpha:0.48)
            for i in 0..<10 {
                let t=CGFloat(0.24)+CGFloat(i)*0.058
                let x=length*(0.47-0.89*t)
                let r=length*(0.011-0.004*t)
                p.move(to:CGPoint(x:x+r,y:0))
                p.addQuadCurve(to:CGPoint(x:x-r,y:0),control:CGPoint(x:x,y:r*0.78))
                p.addQuadCurve(to:CGPoint(x:x+r,y:0),control:CGPoint(x:x,y:-r*0.78))
            }
        case 7,8: // Asagi/Kujaku: fine reticulated scale mesh.
            ink=NSColor(red:0.13,green:0.30,blue:0.34,alpha:0.29)
            for row in 0..<3 {
                for i in 0..<13 {
                    let t=CGFloat(0.27)+CGFloat(i)*0.042
                    let x=length*(0.47-0.89*t)
                    let y=(CGFloat(row)-1)*widthAt(t)*0.38
                    let r=length*0.014
                    p.move(to:CGPoint(x:x+r*0.63,y:y))
                    p.addQuadCurve(to:CGPoint(x:x-r*0.63,y:y),control:CGPoint(x:x,y:y+r*0.72))
                }
            }
        case 2,10: // Metallic ogon: interrupted, restrained flank glints.
            ink=NSColor.white.withAlphaComponent(0.22)
            for i in 0..<9 {
                let t=CGFloat(0.27)+CGFloat(i)*0.065
                let x=length*(0.47-0.89*t)
                let y=widthAt(t)*(i%2==0 ? CGFloat(0.36) : CGFloat(-0.33))
                p.move(to:CGPoint(x:x-length*0.012,y:y))
                p.addQuadCurve(to:CGPoint(x:x+length*0.011,y:y+length*0.004),
                               control:CGPoint(x:x,y:y+length*0.009))
            }
        case 6: // Chagoi: subtle, quiet large scales, no false spots.
            ink=NSColor(red:0.31,green:0.26,blue:0.16,alpha:0.15)
            for i in 0..<9 {
                let t=CGFloat(0.28)+CGFloat(i)*0.060
                let x=length*(0.47-0.89*t)
                let r=widthAt(t)*0.57
                p.move(to:CGPoint(x:x,y:r))
                p.addQuadCurve(to:CGPoint(x:x-length*0.016,y:-r),control:CGPoint(x:x+length*0.009,y:0))
            }
        default:
            ink=NSColor.white.withAlphaComponent(0.10)
        }
        breedDetails.strokeColor=ink
        breedDetails.path=p
    }

    private func centerline(_ t:CGFloat) -> CGFloat {
        sin(phase - t*3.2) * pow(t,2.36) * length * (isLarge ? 0.043 : 0.055)
    }

    private func widthAt(_ t:CGFloat) -> CGFloat {
        // A full forehead and a continuously narrowing peduncle; no abrupt
        // 'pointy fish' silhouette or flat connection with the tail fin.
        let dome = max(CGFloat(0.03),sin(CGFloat.pi*(0.04+t*0.93)))
        let head = (1.0 + (crownShape-1.0)*max(0,1.0-t*2.0))
        let rear = (1.0 - (0.63 + (1.0-rearFullness)*0.15)*pow(t,2.15))
        return max(0.9,bodyWidth*0.5*pow(dome,0.70)*head*rear)
    }

    private func renderShape() {
        let l = length
        let outline = CGMutablePath()
        let segments = 22
        let tip = CGPoint(x:l*0.48,y:0)
        outline.move(to:tip)
        for i in 0...segments {
            let t=CGFloat(i)/CGFloat(segments)
            let p=CGPoint(x:l*(0.47-0.89*t),y:centerline(t)+widthAt(t))
            if i == 0 { outline.addQuadCurve(to:p,control:CGPoint(x:l*0.479,y:widthAt(0)*0.38)) }
            else { outline.addLine(to:p) }
        }
        for i in (0...segments).reversed() {
            let t=CGFloat(i)/CGFloat(segments)
            outline.addLine(to:CGPoint(x:l*(0.47-0.89*t),y:centerline(t)-widthAt(t)))
        }
        outline.addQuadCurve(to:tip,control:CGPoint(x:l*0.479,y:-widthAt(0)*0.38))
        outline.closeSubpath()
        body.path=outline
        // Narrow translucent back light suggests rounded shoulders under water.
        let back=CGMutablePath()
        back.move(to:CGPoint(x:l*0.38,y:0))
        back.addCurve(to:CGPoint(x:-l*0.30,y:centerline(0.85)),
                      control1:CGPoint(x:l*0.14,y:bodyWidth*0.20),
                      control2:CGPoint(x:-l*0.16,y:widthAt(0.78)*0.38))
        back.addCurve(to:CGPoint(x:l*0.38,y:0),
                      control1:CGPoint(x:-l*0.11,y:-widthAt(0.66)*0.14),
                      control2:CGPoint(x:l*0.23,y:-bodyWidth*0.075))
        back.closeSubpath()
        backHighlight.path=back
        softShadow.path=outline
        softShadow.position=CGPoint(x:l*0.028,y:-l*0.052)

        // A koi caudal peduncle is narrow but not severed from its fin.
        // Keep this fin in the peduncle's local coordinate system so its
        // membrane follows the fish rather than orbiting the body center.
        let root=CGPoint(x:-l*0.42,y:centerline(1))
        tail.position=root
        let rootHalf=max(CGFloat(0.95),widthAt(1)*0.86)
        let span=l*(isLarge ? 0.077 : 0.078)*caudalScale
        let finLength=l*(isLarge ? 0.149 : 0.160)*caudalScale
        let fin=CGMutablePath()
        // One connected membrane with rounded paired lobes and a shallow fork.
        // It meets the peduncle as a continuous collar, not two clipped triangles.
        fin.move(to:CGPoint(x:l*0.004,y:rootHalf))
        fin.addCurve(to:CGPoint(x:-finLength*0.82,y:span*0.95),
                     control1:CGPoint(x:-finLength*0.30,y:rootHalf+span*0.36),
                     control2:CGPoint(x:-finLength*0.65,y:span*0.97))
        fin.addCurve(to:CGPoint(x:-finLength*0.98,y:span*0.76),
                     control1:CGPoint(x:-finLength*0.97,y:span*1.00),
                     control2:CGPoint(x:-finLength*1.04,y:span*0.91))
        fin.addCurve(to:CGPoint(x:-finLength*0.80,y:0),
                     control1:CGPoint(x:-finLength*0.91,y:span*0.46),
                     control2:CGPoint(x:-finLength*0.72,y:span*0.18))
        fin.addCurve(to:CGPoint(x:-finLength*0.98,y:-span*0.76),
                     control1:CGPoint(x:-finLength*0.72,y:-span*0.18),
                     control2:CGPoint(x:-finLength*0.91,y:-span*0.46))
        fin.addCurve(to:CGPoint(x:-finLength*0.82,y:-span*0.95),
                     control1:CGPoint(x:-finLength*1.04,y:-span*0.91),
                     control2:CGPoint(x:-finLength*0.97,y:-span*1.00))
        fin.addCurve(to:CGPoint(x:l*0.004,y:-rootHalf),
                     control1:CGPoint(x:-finLength*0.65,y:-span*0.97),
                     control2:CGPoint(x:-finLength*0.30,y:-rootHalf-span*0.36))
        fin.addQuadCurve(to:CGPoint(x:l*0.004,y:rootHalf),
                         control:CGPoint(x:-finLength*0.038,y:0))
        fin.closeSubpath()
        tail.path=fin
        // Swim cadence unchanged; lateral deflection stays subtle for adults.
        tail.zRotation=sin(phase+0.40)*(isLarge ? 0.060 : 0.091)
        tail.fillColor=palette.base.withAlphaComponent(identity == 1 || identity == 9 ? 0.62 : 0.52)
        let rays=CGMutablePath()
        for factor:CGFloat in [-0.72,-0.40,0.40,0.72] {
            rays.move(to:CGPoint(x:-finLength*0.04,y:0))
            rays.addQuadCurve(to:CGPoint(x:-finLength*0.91,y:span*factor),
                              control:CGPoint(x:-finLength*0.55,y:span*factor*0.66))
        }
        tailRays.path=rays

        for (finNode,sign): (SKShapeNode,CGFloat) in [(leftPectoral,1),(rightPectoral,-1)] {
            let baseX=l*0.17
            let baseY=sign*bodyWidth*0.31
            let flap=sin(phase*0.52+sign)*l*0.008
            let fp=CGMutablePath()
            fp.move(to:CGPoint(x:baseX,y:baseY))
            fp.addCurve(to:CGPoint(x:baseX-l*0.115*finScale,y:baseY+sign*l*0.086*finScale+flap),
                        control1:CGPoint(x:baseX-l*0.016,y:baseY+sign*l*0.065),
                        control2:CGPoint(x:baseX-l*0.065,y:baseY+sign*l*0.110*finScale))
            fp.addQuadCurve(to:CGPoint(x:baseX-l*0.068,y:baseY),
                            control:CGPoint(x:baseX-l*0.135,y:baseY+sign*l*0.022))
            fp.closeSubpath()
            finNode.path=fp
        }
        let dp=CGMutablePath()
        dp.move(to:CGPoint(x:-l*0.035,y:centerline(0.54)))
        dp.addQuadCurve(to:CGPoint(x:-l*0.118,y:centerline(0.68)+l*0.021),
                        control:CGPoint(x:-l*0.065,y:centerline(0.61)+l*0.031))
        dp.addLine(to:CGPoint(x:-l*0.155,y:centerline(0.70)))
        dp.closeSubpath()
        dorsal.path=dp

        let gloss=CGMutablePath()
        gloss.move(to:CGPoint(x:l*0.31,y:bodyWidth*0.10))
        gloss.addQuadCurve(to:CGPoint(x:-l*0.30,y:centerline(0.85)+widthAt(0.85)*0.43),
                           control:CGPoint(x:l*0.01,y:centerline(0.46)+widthAt(0.46)*0.73))
        sheen.path=gloss

        let gill=CGMutablePath()
        let gx=l*0.22
        gill.move(to:CGPoint(x:gx,y:bodyWidth*0.31))
        gill.addQuadCurve(to:CGPoint(x:gx,y:-bodyWidth*0.31),control:CGPoint(x:gx-l*0.037,y:0))
        gillMark.path=gill
        let scales=CGMutablePath()
        // Chagoi and two metallic ogon have subtle scales; Asagi/Kujaku have
        // pronounced netting, Shusui is Doitsu-style with a dorsal chain.
        let rows = identity == 4 ? 8 : ((identity == 7 || identity == 8) ? 11 : 6)
        for n in 0..<rows {
            let u=CGFloat(0.32)+CGFloat(n)*CGFloat(0.48)/CGFloat(max(1,rows-1))
            let x=l*(0.47-0.89*u)
            let amt=identity == 7 || identity == 8 ? CGFloat(0.55) : CGFloat(0.32)
            let half=widthAt(u)*amt
            scales.move(to:CGPoint(x:x,y:centerline(u)+half))
            scales.addQuadCurve(to:CGPoint(x:x-l*0.020,y:centerline(u)-half),
                                control:CGPoint(x:x+l*0.011,y:centerline(u)))
        }
        for side:CGFloat in [-1,1] {
            let at=CGPoint(x:l*0.433,y:side*bodyWidth*0.045)
            scales.move(to:at)
            scales.addQuadCurve(to:CGPoint(x:l*0.456,y:side*bodyWidth*0.087),
                                control:CGPoint(x:l*0.463,y:side*bodyWidth*0.028))
        }
        scaleDetails.path=scales
        scaleDetails.strokeColor = (identity == 7 || identity == 8) ?
            NSColor(calibratedWhite:0.10,alpha:0.20) : NSColor.white.withAlphaComponent(0.105)
        leftEye.position=CGPoint(x:l*0.333,y:bodyWidth*0.15)
        rightEye.position=CGPoint(x:l*0.333,y:-bodyWidth*0.15)
        for (shape,spec) in pigments {
            shape.position=CGPoint(x:l*(0.47-0.89*spec.t),
                                   y:centerline(spec.t)+widthAt(spec.t)*spec.offset)
            shape.zRotation = sin(phase-spec.t*3.2)*pow(spec.t,2)*0.055
        }
    }

    func simulate(step dt:TimeInterval,pondSize:CGSize,food:CGPoint?) {
        phase += CGFloat(dt)*CGFloat.pi*2*tailRate
        goalAge += dt
        let margin=length*0.83
        if let food=food { goal=food;goalAge=0 }
        else if goalAge > 5.0+Double(identity%6) || hypot(goal.x-position.x,goal.y-position.y)<33 || goal == .zero {
            goal=CGPoint(x:CGFloat.random(in:max(margin,pondSize.width*0.10)...max(margin+1,pondSize.width-margin)),
                         y:CGFloat.random(in:max(margin,pondSize.height*0.12)...max(margin+1,pondSize.height-margin)))
            goalAge=0
        }
        let desired=atan2(goal.y-position.y,goal.x-position.x)
        let delta=atan2(sin(desired-heading),cos(desired-heading))
        heading += max(-maxTurn*CGFloat(dt),min(maxTurn*CGFloat(dt),delta))
        zRotation=heading
        let boost:CGFloat = food != nil ? 1.25 : 1.0
        position.x += cos(heading)*swimSpeed*CGFloat(dt)*boost
        position.y += sin(heading)*swimSpeed*CGFloat(dt)*boost
        position.x = min(max(length*0.35,position.x),pondSize.width-length*0.35)
        position.y = min(max(length*0.35,position.y),pondSize.height-length*0.35)
    }

    func refreshVisuals() { renderShape() }
}
