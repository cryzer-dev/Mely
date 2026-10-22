import AppKit
import SwiftUI
import MelyUI

/// Lays a view out offscreen, as the snapshots do, and collects its layout probes.
@MainActor
public final class LayoutHarness {
    public let hosting: NSView
    private let window: NSWindow
    private let sink = ProbeSink()

    public init<V: View>(_ view: V) {
        _ = NSApplication.shared
        let sink = sink
        let root = view
            .environment(\.layoutProbesEnabled, true)
            .coordinateSpace(.named(LayoutProbe.space))
            .onPreferenceChange(LayoutProbeKey.self) { probes in
                MainActor.assumeIsolated { sink.probes = probes }
            }
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        self.hosting = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
    }

    /// Lets SwiftUI finish its passes (and the island settle at its page's height): until
    /// the probes stop moving, at least `minimum` and at most a second.
    /// Awaits rather than spinning the run loop: inside a main actor job (a test) a nested
    /// run loop does not run the main actor's other work, such as a chat answer arriving.
    public func settle(minimum: TimeInterval = 0.12) async {
        let start = Date()
        var last = ""
        while Date().timeIntervalSince(start) < 1 {
            try? await Task.sleep(for: .milliseconds(40))
            hosting.layoutSubtreeIfNeeded()
            let now = sink.probes.map { "\($0.id)\($0.frame)" }.joined()
            if now == last, Date().timeIntervalSince(start) >= minimum { return }
            last = now
        }
    }

    public var probes: [LayoutProbe] { sink.probes }

    /// Lays out the variant, runs its step, and returns its probes once settled.
    public static func lay(_ variant: LayoutVariant) async -> LayoutHarness {
        let harness = LayoutHarness(await variant.build())
        await harness.settle()
        if let then = variant.then {
            then()
            await harness.settle()
        }
        return harness
    }

    public func png() -> Data? {
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}

@MainActor
private final class ProbeSink {
    var probes: [LayoutProbe] = []
}
