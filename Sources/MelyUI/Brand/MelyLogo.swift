import SwiftUI
import AppKit

/// Mely's mark: a soft bun with a leaf on top, dot eyes and a small smile.
/// One geometry for the menu bar template and the app icon.
public enum MelyLogo {
    /// The body, in a unit square scaled to `rect`.
    static func body(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        path.move(to: p(0.5, 0.2))
        path.addCurve(to: p(0.95, 0.66), control1: p(0.8, 0.2), control2: p(0.95, 0.4))
        path.addCurve(to: p(0.5, 0.95), control1: p(0.95, 0.88), control2: p(0.76, 0.95))
        path.addCurve(to: p(0.05, 0.66), control1: p(0.24, 0.95), control2: p(0.05, 0.88))
        path.addCurve(to: p(0.5, 0.2), control1: p(0.05, 0.4), control2: p(0.2, 0.2))
        path.closeSubpath()
        return path
    }

    /// The leaf sprouting from the top, leaning right.
    static func leaf(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        path.move(to: p(0.5, 0.23))
        path.addCurve(to: p(0.78, 0.04), control1: p(0.5, 0.1), control2: p(0.62, 0.03))
        path.addCurve(to: p(0.5, 0.23), control1: p(0.76, 0.17), control2: p(0.62, 0.23))
        path.closeSubpath()
        return path
    }

    static func eyes(in r: CGRect) -> Path {
        var path = Path()
        for x in [0.35, 0.65] {
            path.addEllipse(in: CGRect(x: r.minX + (x - 0.055) * r.width, y: r.minY + 0.5 * r.height,
                                       width: 0.11 * r.width, height: 0.15 * r.height))
        }
        return path
    }

    static func smile(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        path.move(to: p(0.44, 0.72))
        path.addQuadCurve(to: p(0.56, 0.72), control: p(0.5, 0.79))
        return path
    }

    /// Menu bar icon: a template silhouette (eyes and smile cut out) that macOS tints
    /// for light and dark menu bars.
    public static func menuBarImage(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            let r = rect.insetBy(dx: size * 0.02, dy: 0)
            cg.addPath(body(in: r).cgPath)
            cg.addPath(leaf(in: r).cgPath)
            cg.setFillColor(NSColor.black.cgColor)
            cg.fillPath()
            cg.setBlendMode(.clear)
            cg.addPath(eyes(in: r).cgPath)
            cg.fillPath()
            cg.addPath(smile(in: r).cgPath)
            cg.setLineWidth(max(1.2, size * 0.075))
            cg.setLineCap(.round)
            cg.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Mely"
        return image
    }
}

/// The colour mark: the bun with blush, drawn at any size.
public struct MelyMark: View {
    public init() {}

    public var body: some View {
        Canvas { context, size in
            let r = CGRect(origin: .zero, size: size)
            context.fill(MelyLogo.leaf(in: r), with: .linearGradient(
                Gradient(colors: [Color(red: 0.55, green: 0.85, blue: 0.5), Color(red: 0.3, green: 0.68, blue: 0.4)]),
                startPoint: CGPoint(x: r.midX, y: 0), endPoint: CGPoint(x: r.maxX * 0.8, y: r.height * 0.2)))
            let body = MelyLogo.body(in: r)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.18), radius: size.width * 0.03, y: size.width * 0.02))
                layer.fill(body, with: .linearGradient(
                    Gradient(colors: [Color(red: 1.0, green: 0.98, blue: 0.95), Color(red: 1.0, green: 0.9, blue: 0.84)]),
                    startPoint: CGPoint(x: r.midX, y: r.height * 0.2), endPoint: CGPoint(x: r.midX, y: r.maxY)))
            }
            let ink = Color(red: 0.24, green: 0.16, blue: 0.15)
            context.fill(MelyLogo.eyes(in: r), with: .color(ink))
            // Eye highlights.
            for x in [0.35, 0.65] {
                context.fill(Path(ellipseIn: CGRect(x: (x - 0.012) * r.width, y: 0.525 * r.height,
                                                    width: 0.035 * r.width, height: 0.035 * r.width)),
                             with: .color(.white.opacity(MelyInk.primary)))
            }
            context.stroke(MelyLogo.smile(in: r), with: .color(ink),
                           style: StrokeStyle(lineWidth: r.width * 0.03, lineCap: .round))
            for x in [0.24, 0.76] {
                context.fill(Path(ellipseIn: CGRect(x: (x - 0.07) * r.width, y: 0.66 * r.height,
                                                    width: 0.14 * r.width, height: 0.07 * r.height)),
                             with: .color(Color(red: 1.0, green: 0.55, blue: 0.55).opacity(0.55)))
            }
        }
    }
}

/// The app icon: the mark on a warm squircle, on the macOS icon grid (824 of 1024).
public struct MelyAppIcon: View {
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let tile = side * 824 / 1024
            ZStack {
                RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.74, blue: 0.47),
                                                  Color(red: 1.0, green: 0.46, blue: 0.34)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                        .strokeBorder(.white.opacity(MelyInk.faint), lineWidth: max(1, tile * 0.006)))
                    .frame(width: tile, height: tile)
                    .shadow(color: .black.opacity(0.25), radius: side * 0.012, y: side * 0.01)
                MelyMark()
                    .frame(width: tile * 0.68, height: tile * 0.68)
                    .offset(y: -tile * 0.02)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
