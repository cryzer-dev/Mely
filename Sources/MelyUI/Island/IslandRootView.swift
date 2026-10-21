import SwiftUI
import MelyCore

/// Root of the island window: the black shape at the top centre and its content.
public struct IslandRootView<Compact: View, Expanded: View, Header: View>: View {
    let presentation: IslandPresentation
    let compactLeading: Compact
    let expanded: Expanded
    let header: Header
    let compactTrailing: AnyView

    public init(presentation: IslandPresentation,
                @ViewBuilder compactLeading: () -> Compact,
                compactTrailing: AnyView,
                @ViewBuilder expanded: () -> Expanded,
                @ViewBuilder header: () -> Header = { EmptyView() }) {
        self.presentation = presentation
        self.compactLeading = compactLeading()
        self.compactTrailing = compactTrailing
        self.expanded = expanded()
        self.header = header()
    }

    private var isExpanded: Bool { presentation.mode == .expanded }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        let size = presentation.islandSize
        let ear = IslandPresentation.earRadius
        let layout = IslandRestingLayout(width: size.width, height: presentation.geometry.height)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                IslandShape(width: size.width, height: size.height,
                            cornerRadius: isExpanded ? MelyRadius.island : presentation.mode == .peek || presentation.mode == .greeting ? 18 : 10,
                            topRadius: isExpanded ? 0 : -ear)
                    .fill(Color.black)
                    .overlay {
                        if presentation.isDropTargeted {
                            IslandShape(width: size.width, height: size.height,
                                        cornerRadius: isExpanded ? MelyRadius.island : presentation.mode == .peek ? 18 : 10,
                                        topRadius: isExpanded ? 0 : -ear)
                                .stroke(Color(red: 0.36, green: 0.56, blue: 1.0), lineWidth: 2)
                        }
                    }
                    .frame(width: size.width, height: size.height)

                switch presentation.mode {
                case .hidden:
                    EmptyView()
                case .compact:
                    HStack(spacing: 0) {
                        // The character's size goes down as an environment value: the left side
                        // may hold more than the character (a cover next to it while music plays).
                        compactLeading
                            .environment(\.islandCharacterSize, layout.characterDiameter)
                            .frame(height: layout.characterDiameter)
                            .frame(width: IslandPresentation.compactSideWidth, alignment: .center)
                        Spacer(minLength: presentation.geometry.width)
                        compactTrailing
                            .frame(width: IslandPresentation.compactSideWidth, alignment: .center)
                    }
                    .padding(.horizontal, ear)
                    .frame(width: size.width, height: size.height)
                    .transition(.islandContent)
                case .peek:
                    if let peek = presentation.peek {
                        PeekView(content: peek, dismiss: presentation.dismissPeek)
                            .padding(.top, presentation.geometry.height)
                            .padding(.horizontal, 16)
                            .frame(width: size.width, height: size.height, alignment: .top)
                            .transition(.islandContent)
                    }
                case .greeting:
                    GreetingView(start: presentation.greetingStart)
                        .padding(.top, presentation.geometry.height)
                        .frame(width: size.width, height: size.height, alignment: .top)
                        .transition(.islandContent)
                case .expanded:
                    VStack(spacing: 0) {
                        // Level with the notch: sections left, actions right (task 7.9).
                        header
                            .environment(\.islandNotchWidth, presentation.geometry.width + 16)
                            .frame(height: max(28, presentation.geometry.height))
                            // The limits card opens over the content below.
                            .zIndex(1)
                        expanded
                            .padding(.top, 8)
                            .padding([.horizontal, .bottom], 20)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .onPreferenceChange(IslandContentHeightKey.self) { height in
                                MainActor.assumeIsolated { presentation.contentHeight = height }
                            }
                    }
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .transition(.islandContent)
                }
            }
            // Reduce Motion: the shape changes with a short fade, no spring.
            .animation(reduceMotion ? .easeOut(duration: 0.15) : MelyMotion.island, value: presentation.mode)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : MelyMotion.island, value: presentation.contentHeight)
            .onDrop(of: [.fileURL], isTargeted: Binding(get: { presentation.isDropTargeted },
                                                        set: { presentation.isDropTargeted = $0 })) { providers in
                guard let take = presentation.dropFiles else { return false }
                Self.loadURLs(providers) { take($0) }
                return true
            }
            Spacer(minLength: 0)
        }
        .frame(width: IslandPresentation.panelSize.width, height: IslandPresentation.panelSize.height, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    /// File URLs from a drop, delivered on the main actor once all have loaded.
    static func loadURLs(_ providers: [NSItemProvider], _ done: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated { if !urls.isEmpty { done(urls) } }
        }
    }
}

extension AnyTransition {
    /// Content follows the shape (task 7.3): it comes in after the shape has moved, a touch
    /// small and blurred, and leaves quickly before the shape folds.
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                .combined(with: .modifier(active: BlurModifier(radius: 6), identity: BlurModifier(radius: 0)))
                .animation(MelyMotion.contentIn),
            removal: .opacity.animation(MelyMotion.contentOut))
    }
}

private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

private struct IslandCharacterSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = 26
}

public extension EnvironmentValues {
    /// The character's diameter in the compact island.
    var islandCharacterSize: CGFloat {
        get { self[IslandCharacterSizeKey.self] }
        set { self[IslandCharacterSizeKey.self] = newValue }
    }
}
