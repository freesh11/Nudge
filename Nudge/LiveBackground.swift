import SwiftUI

enum LiveBackground: String, CaseIterable, Identifiable {
    case none, constellations, starfield, aurora, fireflies
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Off"
        case .constellations: return "Constellations"
        case .starfield: return "Starfield"
        case .aurora: return "Aurora"
        case .fireflies: return "Fireflies"
        }
    }

    /// Frames per second each style needs to look smooth; slow ones don't need 60.
    var fps: Double {
        switch self {
        case .constellations: return 60
        case .starfield, .fireflies: return 30
        case .aurora: return 15
        case .none: return 1
        }
    }
}

/// The screen background: a base color plus the chosen live animation.
struct AppBackground: View {
    var base: Color = Theme.bg
    var ink: Color = Theme.ink      // dots and lines
    @AppStorage(Keys.background, store: SharedStore.defaults) private var style = LiveBackground.constellations.rawValue
    @AppStorage(Keys.accent, store: SharedStore.defaults) private var accentName = "orange"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        ZStack {
            base
            if let s = LiveBackground(rawValue: style), s != .none {
                // Low Power Mode drops to 10 fps; Reduce Motion freezes it.
                TimelineView(.animation(minimumInterval: 1.0 / (lowPower ? 10 : s.fps), paused: reduceMotion)) { ctx in
                    Canvas { g, size in
                        let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000)
                        LiveBackground.draw(s, in: &g, size: size, t: t, ink: ink, accent: Theme.accent(accentName))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension LiveBackground {
    /// Same particle layout every frame with no stored state: index → stable pseudo-random 0..<1.
    static func rnd(_ i: Int, _ k: Int) -> Double {
        let x = sin(Double(i &* 127 &+ k &* 311) * 12.9898) * 43758.5453
        return x - x.rounded(.down)
    }

    static func wrap(_ v: Double, _ m: Double) -> Double {
        let r = v.truncatingRemainder(dividingBy: m)
        return r < 0 ? r + m : r
    }

    static func draw(_ style: LiveBackground, in g: inout GraphicsContext, size: CGSize, t: Double, ink: Color, accent: Color) {
        let w = Double(size.width), h = Double(size.height)
        guard w > 0, h > 0 else { return }
        switch style {
        case .none: return
        case .constellations: constellations(&g, w, h, t, ink)
        case .starfield: starfield(&g, w, h, t, ink)
        case .aurora: aurora(&g, w, h, t, accent)
        case .fireflies: fireflies(&g, w, h, t, accent)
        }
    }

    private static func dot(_ g: inout GraphicsContext, _ x: Double, _ y: Double, _ r: Double, _ color: Color) {
        g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color))
    }

    /// Drifting stars that link up with thin lines when they pass near each other.
    private static func constellations(_ g: inout GraphicsContext, _ w: Double, _ h: Double, _ t: Double, _ ink: Color) {
        let n = 42, reach = 120.0
        var pts: [(Double, Double)] = []
        pts.reserveCapacity(n)
        for i in 0..<n {
            let angle = rnd(i, 1) * 2 * .pi, speed = 4 + rnd(i, 2) * 8
            pts.append((wrap(rnd(i, 3) * w + cos(angle) * speed * t, w), wrap(rnd(i, 4) * h + sin(angle) * speed * t, h)))
        }
        let bands = 4
        var lines = [Path](repeating: Path(), count: bands)   // nearer pairs → brighter band
        for i in 0..<n {
            for j in (i + 1)..<n {
                let dx = pts[i].0 - pts[j].0, dy = pts[i].1 - pts[j].1
                let d2 = dx * dx + dy * dy
                guard d2 < reach * reach else { continue }
                let band = min(bands - 1, Int((1 - d2.squareRoot() / reach) * Double(bands)))
                lines[band].move(to: CGPoint(x: pts[i].0, y: pts[i].1))
                lines[band].addLine(to: CGPoint(x: pts[j].0, y: pts[j].1))
            }
        }
        for (band, path) in lines.enumerated() {
            g.stroke(path, with: .color(ink.opacity((Double(band) + 0.5) / Double(bands) * 0.3)), lineWidth: 1)
        }
        for (i, p) in pts.enumerated() {
            let twinkle = 0.45 + 0.35 * sin(t * (0.8 + rnd(i, 5) * 1.5) + rnd(i, 6) * 6.28)
            dot(&g, p.0, p.1, 1.4 + rnd(i, 7) * 1.4, ink.opacity(twinkle))
        }
    }

    /// Three depths of stars rising slowly; nearer ones are bigger and faster.
    private static func starfield(_ g: inout GraphicsContext, _ w: Double, _ h: Double, _ t: Double, _ ink: Color) {
        for i in 0..<110 {
            let depth = 1 + Double(i % 3)
            let x = rnd(i, 1) * w
            let y = wrap(rnd(i, 2) * h - t * 3 * depth, h)
            let twinkle = 0.25 + 0.3 * depth / 3 * (0.6 + 0.4 * sin(t * 2 + rnd(i, 3) * 6.28))
            dot(&g, x, y, 0.6 * depth, ink.opacity(twinkle))
        }
    }

    /// Soft blurred color glows slowly orbiting the screen.
    private static func aurora(_ g: inout GraphicsContext, _ w: Double, _ h: Double, _ t: Double, _ accent: Color) {
        let colors = [accent, Color(hex: 0x8FA2FF), Color(hex: 0x4FD1A5)]
        for (i, c) in colors.enumerated() {
            let k = Double(i)
            let x = w * (0.5 + 0.35 * sin(t * (0.07 + k * 0.02) + k * 2))
            let y = h * (0.35 + 0.3 * cos(t * (0.05 + k * 0.015) + k))
            let r = w * (0.45 + 0.1 * sin(t * 0.1 + k))
            let glow = Gradient(colors: [c.opacity(0.3), c.opacity(0.12), c.opacity(0)])
            g.fill(Path(ellipseIn: CGRect(x: x - r * 1.4, y: y - r * 1.4, width: r * 2.8, height: r * 2.8)),
                   with: .radialGradient(glow, center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r * 1.4))
        }
    }

    /// Glowing dots wandering lazily and pulsing in your accent color.
    private static func fireflies(_ g: inout GraphicsContext, _ w: Double, _ h: Double, _ t: Double, _ accent: Color) {
        for i in 0..<26 {
            let sx = 0.05 + rnd(i, 1) * 0.1, sy = 0.05 + rnd(i, 2) * 0.1
            let x = wrap(rnd(i, 3) * w + sin(t * sx + rnd(i, 4) * 6.28) * 60 + t * (rnd(i, 5) - 0.5) * 6, w)
            let y = wrap(rnd(i, 6) * h + cos(t * sy + rnd(i, 7) * 6.28) * 60, h)
            let pulse = 0.5 + 0.5 * sin(t * (1 + rnd(i, 8)) + rnd(i, 9) * 6.28)
            dot(&g, x, y, 10, accent.opacity(0.12 * pulse))
            dot(&g, x, y, 2.4, accent.opacity(0.35 + 0.5 * pulse))
        }
    }
}
