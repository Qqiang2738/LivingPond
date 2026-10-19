import AppKit
import SpriteKit

// Water surface responds only to falling rain and deliberate feeding.
// There are no ambient wind ripples or automatic swimming wakes.
// Paths are in point coordinates (not scaled unit-circles); stroke width
// therefore never balloons with a growing ring.
private enum RippleKind { case rain, food }
private final class CircleRipple {
    let node: SKShapeNode
    var age: TimeInterval = 0
    let lifespan: TimeInterval
    let kind: RippleKind
    private let size: CGFloat
    private let variation: CGFloat
    private let squash: CGFloat

    init(point: CGPoint, kind: RippleKind) {
        self.kind = kind
        self.size = kind == .food ? 47 : CGFloat.random(in:18...29)
        variation = CGFloat.random(in:0...(2*CGFloat.pi))
        squash = CGFloat.random(in:0.89...0.97)
        lifespan = kind == .food ? 1.42 : 1.02
        let shape = SKShapeNode()
        shape.position = point
        shape.fillColor = .clear
        shape.strokeColor = NSColor(calibratedRed:0.79,green:0.91,blue:0.87,alpha:1)
        shape.lineWidth = kind == .food ? 0.95 : 0.83
        shape.zPosition = 24
        shape.alpha = 0
        self.node = shape
        redraw(radius: 1.5)
    }

    private func redraw(radius: CGFloat) {
        let path=CGMutablePath()
        let passes = kind == .food ? 2 : 1
        for ring in 0..<passes {
            let r=radius*(ring == 0 ? 1 : 0.63)
            for i in 0...32 {
                let a=CGFloat(i)*2*CGFloat.pi/32
                let irregularity=1 + 0.023*sin(a*3+variation) + 0.012*cos(a*5-variation)
                let point=CGPoint(x:cos(a)*r*irregularity,y:sin(a)*r*squash*irregularity)
                if i == 0 { path.move(to:point) } else { path.addLine(to:point) }
            }
            path.closeSubpath()
        }
        node.path=path
    }

    // Advance the clock at 120 Hz. Rebuilding CGPaths at simulation
    // frequency would waste CPU on the 2017 Intel iMac.
    func advance(_ dt:TimeInterval) -> Bool {
        age += dt
        return age < lifespan
    }

    func refreshVisiblePath() {
        let t=min(1,age/lifespan)
        let growth=pow(t,0.73)
        redraw(radius:size*CGFloat(0.07 + 0.93*growth))
        let appear=min(1.0,t*13)
        let fade=pow(max(0,1-t),1.35)
        node.alpha=CGFloat(appear*fade)*(kind == .food ? 0.63 : 0.67)
    }
}

/// A tiny visible streak arriving at its own landing point. The water ring is
/// created *after* impact, not at the same instant the streak first appears.
/// This is a lightweight scene object: no SpriteKit particle emitter or texture
/// allocations each frame, preserving the Intel iMac performance baseline.
private final class FallingRainDrop {
    let node: SKShapeNode
    let impact: CGPoint
    let start: CGPoint
    let flightTime: TimeInterval
    private(set) var age: TimeInterval = 0
    private let visibility: CGFloat

    init(impact: CGPoint) {
        self.impact = impact
        // Slightly angled filaments: readable on an iMac display without
        // turning this quiet drizzle into obvious heavy rain.
        start = CGPoint(x: impact.x - CGFloat.random(in:10...22),
                        y: impact.y + CGFloat.random(in:65...115))
        flightTime = Double.random(in:0.31...0.48)
        visibility = CGFloat.random(in:0.40...0.70)
        let shape = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x:2.0,y:-12.5))
        path.addQuadCurve(to:CGPoint(x:-1.8,y:13.5),control:CGPoint(x:0.2,y:0))
        shape.path = path
        shape.lineWidth = CGFloat.random(in:0.65...1.05)
        shape.lineCap = .round
        shape.strokeColor = NSColor(calibratedRed:0.76,green:0.91,blue:0.91,alpha:1)
        shape.glowWidth = 0
        shape.zPosition = 23.5
        shape.position = start
        shape.alpha = 0
        node = shape
    }
    /// Returns true when the droplet touches the surface.
    func advance(_ dt:TimeInterval) -> Bool {
        age += dt
        let t = min(1, age / flightTime)
        node.position = CGPoint(x: start.x + (impact.x-start.x)*CGFloat(t),
                                y: start.y + (impact.y-start.y)*CGFloat(t))
        // Soft appearance, sharpest near the surface, no bright vertical bars.
        node.alpha = visibility * CGFloat(min(1, t*5)) * CGFloat(1 - 0.18*t)
        return t >= 1
    }
}

/// Floating food is a physical scene object, rather than an invisible
/// target plus one generic ripple. A small scatter of grains drops to the
/// feeding point, floats briefly, and vanishes as nearby koi approach.
private final class FoodPellet {
    let node: SKShapeNode
    let anchor: CGPoint
    private let phase: CGFloat
    private let entry: TimeInterval
    private let lifetime: TimeInterval
    private(set) var age: TimeInterval = 0
    private(set) var consumed = false

    init(at target: CGPoint) {
        anchor = CGPoint(x: target.x + CGFloat.random(in:-31...31),
                         y: target.y + CGFloat.random(in:-21...21))
        phase = CGFloat.random(in:0...(2 * CGFloat.pi))
        entry = Double.random(in:0.16...0.32)
        lifetime = Double.random(in:3.2...4.8)
        let radius = CGFloat.random(in:2.5...3.9)
        let grain = SKShapeNode(ellipseOf: CGSize(width: radius*2.15,height: radius*1.65))
        grain.fillColor = NSColor(calibratedRed:0.91,green:0.74,blue:0.43,alpha:1)
        grain.strokeColor = NSColor(calibratedRed:0.48,green:0.36,blue:0.22,alpha:0.8)
        grain.lineWidth = 0.45
        grain.zPosition = 27
        grain.position = CGPoint(x:anchor.x-5,y:anchor.y+18)
        grain.alpha = 0
        node = grain
    }

    func advance(_ dt:TimeInterval, fish:[NativeFish]) -> Bool {
        age += dt
        let fall = min(1.0,age/entry)
        let bob = sin(CGFloat(age)*2.7+phase)*0.95
        node.position=CGPoint(x:anchor.x-5*CGFloat(1-fall)+sin(CGFloat(age)*0.8+phase)*1.3,
                              y:anchor.y+18*CGFloat(1-fall)+bob)
        node.alpha = CGFloat(min(1,fall*5))*CGFloat(min(1,max(0,(lifetime-age)/0.55)))
        if !consumed && age > entry+0.15 {
            for koi in fish {
                if hypot(koi.position.x-anchor.x,koi.position.y-anchor.y) < (koi.isLarge ? 23 : 16) {
                    consumed=true
                    break
                }
            }
        }
        return !consumed && age < lifetime
    }
}

/// Fully native pond scene. The bank art is generated by tools/generate_art.py,
/// not photographed; fish, rain and plant response remain live; the pond bed stays still.
final class PondScene: SKScene {
    let frameMeter = NativeFrameMeter()
    var onFeeding: (() -> Void)?
    // The native feeding HUD decides whether the hand has food.
    // A click on water must not automatically create pellets.
    var onSurfaceClick: ((CGPoint) -> Void)?

    private var fish: [NativeFish] = []
    private var feedingAssignments: [Int:FoodPellet] = [:]
    private var ripples: [CircleRipple] = []
    private var fallingDrops: [FallingRainDrop] = []
    private var foodPellets: [FoodPellet] = []
    private var artCache: [String: SKTexture] = [:]
    private var floatingLeaves: [SKSpriteNode] = []
    private var flowers: [SKSpriteNode] = []
    private var water: SKSpriteNode?
    private var backdrop = SKNode()
    private var activity = SKNode()
    private var initialized = false
    private var lastSize: CGSize = .zero
    private var updatePhaseStart: TimeInterval?
    private var previousTime: TimeInterval?
    private var accumulator: TimeInterval = 0
    private var rainCountdown: TimeInterval = 0.2
    private var foodLocation: CGPoint?
    private var foodRemaining: TimeInterval = 0
    private var pausedByUser = false
    private var diagnosticWindowMode = "Finder 桌面"
    private var rainEnabled = true
    private var lowPowerEnabled = false
    private var rippleCount = 0
    private(set) var plantHitCount = 0

    override func didMove(to view: SKView) {
        backgroundColor = NSColor(calibratedRed: 0.035, green: 0.20, blue: 0.19, alpha: 1)
        scaleMode = .resizeFill
        guard !initialized else { return }
        initialized = true
        setupWater()
        setupPlants()
        setupFish()
        lastSize = size
    }

    private func artTexture(_ name: String, ext: String = "png") -> SKTexture? {
        let key = "\(name).\(ext)"
        if let cached = artCache[key] { return cached }
        guard let path = Bundle.main.path(forResource: name, ofType: ext, inDirectory: "Art"),
              let image = NSImage(contentsOfFile: path) else { return nil }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        artCache[key] = texture // reuse textures on plant relayout / screen changes
        return texture
    }

    private func setupWater() {
        let texture = artTexture("pond-bed", ext: "jpg")
        let layer = texture.map { SKSpriteNode(texture: $0) } ?? SKSpriteNode(color: NSColor(red: 0.055, green: 0.27, blue: 0.26, alpha: 1), size: size)
        layer.position = CGPoint(x: size.width / 2, y: size.height / 2)
        layer.size = size
        layer.zPosition = -80
        layer.name = "pondWater"
        addChild(layer)
        water = layer

        // Preserve the authored pond-bed color, depth and soft static light.
        // No per-frame shader, wind patches, ambient lake waves or surface motion.
    }

    private func placeLeaf(_ kind: Int, x: CGFloat, y: CGFloat, diameter: CGFloat, angle: CGFloat) {
        guard let texture = artTexture("leaf-\(kind % 6)") else { return }
        let leaf = SKSpriteNode(texture: texture, size: CGSize(width: diameter, height: diameter))
        leaf.name = "leaf"
        leaf.position = CGPoint(x: size.width*x, y: size.height*y)
        leaf.zRotation = angle
        leaf.zPosition = 12
        leaf.userData = NSMutableDictionary(dictionary: ["baseAngle": Double(angle)])
        backdrop.addChild(leaf)
        floatingLeaves.append(leaf)
    }

    private func placeFlower(_ kind: Int, x: CGFloat, y: CGFloat, diameter: CGFloat) {
        guard let texture = artTexture("lotus-\(kind % 3)") else { return }
        let lotus = SKSpriteNode(texture: texture, size: CGSize(width: diameter, height: diameter))
        lotus.position = CGPoint(x: size.width*x, y: size.height*y)
        lotus.zPosition = 15
        lotus.name = "lotus"
        backdrop.addChild(lotus)
        flowers.append(lotus)
    }

    private func setupPlants() {
        backdrop.removeFromParent()
        backdrop.removeAllChildren()
        floatingLeaves.removeAll()
        flowers.removeAll()
        backdrop = SKNode()
        backdrop.name = "pondBank"
        addChild(backdrop)
        // Four corners contain the plants; central water intentionally breathes.
        // Percent coordinates are independent of 2017 iMac display scale.
        let leafPositions: [(CGFloat,CGFloat,CGFloat,CGFloat)] = [
            (0.012,0.970,170,0.41), (0.108,0.994,122,0.09), (0.067,0.873,104,-0.35),
            (0.021,0.697,84,0.75), (0.026,0.095,151,0.58), (0.094,0.029,127,-0.41),
            (0.157,0.017,96,0.34), (0.048,0.305,67,0.26),
            (0.978,0.958,164,-0.22), (0.884,0.998,108,0.58), (0.954,0.786,96,0.62),
            (0.996,0.148,163,-0.16), (0.893,0.063,136,0.41), (0.988,0.020,116,0.12),
            (0.946,0.316,82,-0.35), (0.176,0.997,65,0.62), (0.818,0.008,70,-0.46),
            (0.040,0.892,63,0.22), (0.936,0.912,62,0.44),
            (0.134,0.925,47,-0.76), (0.871,0.096,51,0.92)
        ]
        for (idx,entry) in leafPositions.enumerated() {
            placeLeaf(idx, x:entry.0, y:entry.1, diameter: entry.2, angle:entry.3)
        }
        placeFlower(0, x: 0.065, y: 0.90, diameter: 91)
        placeFlower(1, x: 0.926, y: 0.125, diameter: 98)
        // A quiet ivory blossom in the upper bank, smaller than the two focal flowers.
        placeFlower(2, x: 0.938, y: 0.954, diameter: 43)
    }

    private func setupFish() {
        let palettes: [FishPalette] = [
            .init(name:"红白·云锦", base: NSColor(red:0.96,green:0.96,blue:0.88,alpha:1), spots:[.systemRed,.systemRed,NSColor(red:0.78,green:0.28,blue:0.17,alpha:1)]),
            .init(name:"昭和·玄影", base:NSColor(red:0.16,green:0.21,blue:0.20,alpha:1),spots:[.white,.systemRed,.white]),
            .init(name:"山吹黄金·金鳞", base:NSColor(red:0.96,green:0.70,blue:0.21,alpha:1),spots:[NSColor(red:0.96,green:0.80,blue:0.37,alpha:1),NSColor(red:0.90,green:0.55,blue:0.12,alpha:1)]),
            .init(name:"丹顶·朱心", base:.white,spots:[.systemRed,.white,.white]),
            .init(name:"秋翠·浅川", base:NSColor(red:0.69,green:0.85,blue:0.86,alpha:1),spots:[.systemOrange,.systemBlue,.white]),
            .init(name:"白写·墨玉", base:NSColor(red:0.9,green:0.92,blue:0.86,alpha:1),spots:[.black,.black,.white]),
            .init(name:"茶鲤·秋土", base:NSColor(red:0.58,green:0.47,blue:0.30,alpha:1),spots:[.brown,.white,.brown]),
            .init(name:"浅黄·碧纹", base:NSColor(red:0.47,green:0.70,blue:0.78,alpha:1),spots:[.white,.systemBlue,.systemRed]),
            .init(name:"孔雀·青金", base:NSColor(red:0.52,green:0.69,blue:0.60,alpha:1),spots:[.systemRed,.white,.systemRed]),
            .init(name:"大正三色·云墨", base:.white,spots:[.systemRed,.black,.systemRed]),
            .init(name:"白金·银练", base:NSColor(red:0.94,green:0.95,blue:0.89,alpha:1),spots:[.white,.white,.white])
        ]
        // Three adults, eight juveniles: same population as user-approved baseline.
        for i in 0..<palettes.count {
            let koi = NativeFish(identity:i,big:i<3,palette:palettes[i],sceneSize:size)
            koi.name = "koi-\(i)-\(palettes[i].name)"
            activity.addChild(koi)
            fish.append(koi)
        }
        addChild(activity)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard initialized, size.width > 10, size.height > 10 else { return }
        let old = lastSize
        water?.position = CGPoint(x:size.width*0.5,y:size.height*0.5)
        water?.size = size
        // Only rebuild plant sprites after an actual screen geometry change.
        setupPlants()
        if old.width > 10 && old.height > 10 {
            let rx=size.width/old.width,ry=size.height/old.height
            fish.forEach { $0.position=CGPoint(x:$0.position.x*rx,y:$0.position.y*ry) }
        }
        lastSize=size
    }

    func setUserPaused(_ value: Bool) { pausedByUser=value; resetFrameClock() }
    func resetFrameClock() {
        previousTime = nil
        accumulator = 0
        frameMeter.markInterruption()
    }
    func setDiagnosticWindowMode(_ value: String) { diagnosticWindowMode = value }
    func setRainEnabled(_ value: Bool) {
        rainEnabled=value
        if !value {
            fallingDrops.forEach { $0.node.removeFromParent() }
            fallingDrops.removeAll()
        }
    }
    func setLowPower(_ value: Bool) { lowPowerEnabled=value }
    func feedAtCenter() { feed(at:CGPoint(x:size.width*0.5,y:size.height*0.52)) }
    func feed(at point:CGPoint) {
        // A handful is scattered across the actual clicked location.
        // Keep a hard particle bound even after very rapid repeated feeding.
        while foodPellets.count > 30 {
            let old=foodPellets.removeFirst()
            old.node.removeFromParent()
        }
        for _ in 0..<13 {
            let pellet=FoodPellet(at:point)
            activity.addChild(pellet.node)
            foodPellets.append(pellet)
        }
        foodLocation=point
        foodRemaining=5.0
        // Each koi pursues a specific grain, not the same shared coordinate.
        feedingAssignments.removeAll()
        refreshFeedingAssignments()
        addRipple(at:point,large:true)
        onFeeding?()
    }

    override func mouseDown(with event:NSEvent) {
        onSurfaceClick?(event.location(in:self))
    }

    /// Called only while a feeding session has living grain particles.
    /// Assign nearest unclaimed grains to the closest fish first; each
    /// consumed grain releases its assignment and the next one can be chosen.
    private func refreshFeedingAssignments() {
        let active=foodPellets.filter { !$0.consumed && $0.age < 4.8 }
        if active.isEmpty {
            feedingAssignments.removeAll()
            return
        }
        feedingAssignments=feedingAssignments.filter { _,pellet in
            active.contains(where: { $0 === pellet })
        }
        var available=active.filter { candidate in
            !feedingAssignments.values.contains(where: { $0 === candidate })
        }
        let ordered=fish.sorted {
            let origin=foodLocation ?? CGPoint(x:size.width/2,y:size.height/2)
            let dx0=$0.position.x-origin.x,dy0=$0.position.y-origin.y
            let dx1=$1.position.x-origin.x,dy1=$1.position.y-origin.y
            return dx0*dx0+dy0*dy0 < dx1*dx1+dy1*dy1
        }
        for koi in ordered where feedingAssignments[koi.identity] == nil {
            guard !available.isEmpty else { break }
            let bestIndex=available.indices.min { a,b in
                let p0=available[a].anchor,p1=available[b].anchor
                let dx0=p0.x-koi.position.x,dy0=p0.y-koi.position.y
                let dx1=p1.x-koi.position.x,dy1=p1.y-koi.position.y
                return dx0*dx0+dy0*dy0 < dx1*dx1+dy1*dy1
            }!
            feedingAssignments[koi.identity]=available.remove(at:bestIndex)
        }
    }

    private func addRipple(at point:CGPoint,large:Bool) {
        if ripples.count >= 62 {
            ripples.first?.node.removeFromParent()
            ripples.removeFirst()
        }
        let ripple=CircleRipple(point:point,kind:large ? .food : .rain)
        activity.addChild(ripple.node)
        ripples.append(ripple)
        rippleCount += 1
    }

    private func spawnFallingDrop(at point: CGPoint) {
        // A few simultaneous drops are enough to *see* a drizzle from above.
        // The cap protects CPU/GPU resources if the display briefly stalls.
        if fallingDrops.count >= 14 { return }
        let drop = FallingRainDrop(impact:point)
        fallingDrops.append(drop)
        activity.addChild(drop.node)
    }

    private func rainTouch(_ point:CGPoint) {
        // Water surface reacts normally; nearby plants sway, not identical waves.
        var hit=false
        for leaf in floatingLeaves where hypot(leaf.position.x-point.x,leaf.position.y-point.y) < leaf.size.width*0.40 {
            if leaf.action(forKey:"raindrop") == nil {
                let delta=CGFloat.random(in:-0.026...0.026)
                let sequence=SKAction.sequence([.rotate(byAngle:delta,duration:0.15),.rotate(byAngle:-delta*1.5,duration:0.28),.rotate(byAngle:delta*0.5,duration:0.36)])
                leaf.run(sequence,withKey:"raindrop")
            }
            plantHitCount += 1
            hit=true
            break
        }
        if !hit {
            for flower in flowers where hypot(flower.position.x-point.x,flower.position.y-point.y) < flower.size.width*0.28 {
                if flower.action(forKey:"raindrop") == nil {
                    flower.run(.sequence([.scale(to:0.965,duration:0.15),.scale(to:1.0,duration:0.42)]),withKey:"raindrop")
                }
                plantHitCount += 1
                hit=true
                break
            }
        }
        if !hit {
            addRipple(at:point,large:false)
            let sparkle=SKShapeNode(ellipseOf:CGSize(width:3.1,height:2.0))
            sparkle.fillColor=NSColor(calibratedRed:0.80,green:0.94,blue:0.91,alpha:0.68)
            sparkle.strokeColor = .clear
            sparkle.zPosition=26
            sparkle.position=point
            activity.addChild(sparkle)
            sparkle.run(.sequence([.group([.scale(to:0.45,duration:0.16),
                                         .fadeOut(withDuration:0.16)]),.removeFromParent()]))
        }

    }

    override func update(_ currentTime: TimeInterval) {
        let updateStart = ProcessInfo.processInfo.systemUptime
        updatePhaseStart = updateStart
        defer { frameMeter.recordUpdateWork((ProcessInfo.processInfo.systemUptime - updateStart) * 1000) }
        frameMeter.sample(currentTime, context: "窗口=\(diagnosticWindowMode) | 池水=静态 | 细雨画面=\(rainEnabled ? "开" : "关") | 低功耗=\(lowPowerEnabled ? "开" : "关")")
        guard let before=previousTime else { previousTime=currentTime;return }
        previousTime=currentTime
        if pausedByUser { return }
        let dt=max(0,currentTime-before)
        // 120Hz fixed simulation. Catch up after stalls; never turn 200ms into 90ms.
        accumulator += min(dt,0.35)
        let fixed=1.0/120.0
        var steps=0
        while accumulator >= fixed && steps < 30 {
            advance(fixed)
            accumulator -= fixed
            steps += 1
        }
        if accumulator >= fixed {
            accumulator=accumulator.truncatingRemainder(dividingBy:fixed)
            frameMeter.droppedSimulationTime()
        }
        for koi in fish { koi.refreshVisuals() }
        for ripple in ripples { ripple.refreshVisiblePath() }
    }

    override func didFinishUpdate() {
        if let started = updatePhaseStart {
            frameMeter.recordScenePhase((ProcessInfo.processInfo.systemUptime - started) * 1000)
        }
        updatePhaseStart = nil
    }

    private func advance(_ dt:TimeInterval) {
        if foodRemaining > 0 {
            foodRemaining -= dt
            if foodRemaining <= 0 { foodLocation=nil }
        }
        if !feedingAssignments.isEmpty || !foodPellets.isEmpty {
            refreshFeedingAssignments()
        }
        for koi in fish {
            let pellet=feedingAssignments[koi.identity]
            koi.simulate(step:dt,pondSize:size,food:pellet?.anchor)
        }
        for pellet in foodPellets {
            if !pellet.advance(dt,fish:fish) { pellet.node.removeFromParent() }
        }
        foodPellets.removeAll { $0.consumed || $0.age >= 4.8 }
        if foodPellets.isEmpty {
            feedingAssignments.removeAll()
            foodLocation=nil
        }
        // Advance actual falling streaks; ripple and tiny impact flash start
        // only when the droplet reaches the surface or a nearby lotus leaf.
        for drop in fallingDrops {
            if drop.advance(dt) {
                drop.node.removeFromParent()
                rainTouch(drop.impact)
            }
        }
        fallingDrops.removeAll { $0.age >= $0.flightTime }
        rainCountdown -= dt
        if rainEnabled && rainCountdown <= 0 {
            rainCountdown = (lowPowerEnabled ? 0.25 : 0.030) + Double.random(in:0.025...0.065)
            let p=CGPoint(x:CGFloat.random(in:0...max(1,size.width)), y:CGFloat.random(in:0...max(1,size.height)))
            spawnFallingDrop(at:p)
        }
        for ripple in ripples {
            if !ripple.advance(dt) { ripple.node.removeFromParent() }
        }
        ripples.removeAll { $0.age >= $0.lifespan }
    }

    func diagnostic(mode:String, preferredFPS:Int) -> String {
        let base=frameMeter.report(mode:mode,nodeCount:allDescendants(),viewPreferredFPS:preferredFPS)
        return base + "\n池水：静态池底（无风纹 / 无动态湖浪）\n可见鱼食颗粒：\(foodPellets.count)\n当前下落雨滴：\(fallingDrops.count)\n当前扩散波纹：\(ripples.count)\n鱼群：\(fish.count)（大 3 / 小 8）\n雨纹数：\(rippleCount)\n植物响应：\(plantHitCount)\n渲染：SpriteKit / 无 WebKit"
    }
    private func allDescendants() -> Int {
        func count(_ node:SKNode)->Int { 1 + node.children.reduce(0) { $0+count($1) } }
        return count(self)-1
    }
}
