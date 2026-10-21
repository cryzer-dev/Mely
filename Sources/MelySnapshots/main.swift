import AppKit
import SwiftUI
import MelyUI

/// Renders UI states to PNG files in ./snapshots (or the directory given as the first argument).
/// Uses a real NSHostingView in an offscreen window: ImageRenderer leaves AppKit-backed
/// controls (Form, Toggle, Button) blank.
@MainActor
func render(_ snapshot: Snapshot, into dir: URL) throws {
    let hosting = NSHostingView(rootView: snapshot.view)
    let size = hosting.fittingSize
    hosting.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    window.layoutIfNeeded()
    hosting.layoutSubtreeIfNeeded()
    // Let SwiftUI finish its first pass, and the open island settle at its page's height.
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        throw NSError(domain: "snapshots", code: 1, userInfo: [NSLocalizedDescriptionKey: "render failed: \(snapshot.name)"])
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "snapshots", code: 2, userInfo: [NSLocalizedDescriptionKey: "encode failed: \(snapshot.name)"])
    }
    try png.write(to: dir.appendingPathComponent("\(snapshot.name).png"))
    print("snapshot \(snapshot.name).png")
}

/// `mely-snapshots --app-icon <dir.iconset>`: the PNG sizes `iconutil` turns into AppIcon.icns.
if CommandLine.arguments.dropFirst().first == "--app-icon" {
    let dir = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "AppIcon.iconset")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try MainActor.assumeIsolated {
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let renderer = ImageRenderer(content: MelyAppIcon().frame(width: CGFloat(points), height: CGFloat(points)))
                renderer.scale = CGFloat(scale)
                guard let cg = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "snapshots", code: 3, userInfo: [NSLocalizedDescriptionKey: "icon \(points)@\(scale)x"])
                }
                let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
                try png.write(to: dir.appendingPathComponent(name))
            }
        }
    }
    print("iconset \(dir.path)")
    exit(0)
}

/// `mely-snapshots --dmg-background <dir>`: the installer window's background at 1x and 2x
/// (scripts/make-dmg.sh joins them into one HiDPI TIFF).
if CommandLine.arguments.dropFirst().first == "--dmg-background" {
    let dir = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ".")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try MainActor.assumeIsolated {
        for scale in [1, 2] {
            let renderer = ImageRenderer(content: DMGBackground())
            renderer.scale = CGFloat(scale)
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                throw NSError(domain: "snapshots", code: 4, userInfo: [NSLocalizedDescriptionKey: "dmg background"])
            }
            try png.write(to: dir.appendingPathComponent(scale == 2 ? "background@2x.png" : "background.png"))
        }
    }
    print("dmg background \(dir.path)")
    exit(0)
}

/// `mely-snapshots --readme <dir>`: the README's pictures.
if CommandLine.arguments.dropFirst().first == "--readme" {
    let dir = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "docs/images", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    _ = NSApplication.shared
    try MainActor.assumeIsolated {
        for snapshot in Snapshots.readme { try render(snapshot, into: dir) }
    }
    exit(0)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "snapshots", isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
_ = NSApplication.shared
try MainActor.assumeIsolated {
    for snapshot in Snapshots.all {
        try render(snapshot, into: outDir)
    }
}
