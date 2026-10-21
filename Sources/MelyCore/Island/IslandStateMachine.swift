// Portions © 2026 Louis Raillé, MIT License — see THIRD_PARTY_NOTICES.md.
import Foundation

/// Open/close logic of the island, without AppKit: the window controller feeds it
/// hover, clicks and app events, and follows `onTransition`.
@MainActor
public final class IslandStateMachine {

    public enum State: Equatable, Sendable {
        case hidden     // island invisible (notch size)
        case compact    // notch + side areas: character and status
        case expanded   // overview
        case greeting   // expanded, launch greeting
        case listening  // expanded, voice assistant listening
    }

    public private(set) var state: State = .hidden

    /// Fired on every transition: (from, to).
    public var onTransition: ((State, State) -> Void)?

    /// When it returns true, timers and mouse-leave never fold or hide the island
    /// (a pending approval or question holds it open).
    public var isHeldOpen: (() -> Bool)?
    /// The compact island stays (does not hide after `compactToHiddenDelay`) while this
    /// says so: something live, with the wings set to show while active.
    public var keepsCompact: (() -> Bool)?

    /// expanded → compact delay, kept in sync with the auto-close preference.
    public var expandedToCompactDelay: TimeInterval = 15 {
        didSet {
            guard expandedToCompactDelay != oldValue,
                  state == .expanded, expandedCollapseWork != nil else { return }
            scheduleExpandedCollapse()
        }
    }
    /// compact → hidden delay.
    public var compactToHiddenDelay: TimeInterval = 60
    /// Off («Не закрывать»): the pointer leaving never folds the expanded island; «×»,
    /// or Esc do.
    public var collapsesWhenLeft = true
    /// Folds the open island at once when the user works elsewhere (`focusLost()`).
    public var collapsesOnFocusLoss = true
    /// Off («Не убирать»): the compact island never hides by itself.
    public var hidesWhenIdle = true
    /// greeting → compact delay once the greeting animation ends (pointer away).
    public var greetAutoCollapseDelay: TimeInterval = 0.6
    /// greeting → compact delay while the pointer rests on the greeting.
    public var greetHoverCollapseDelay: TimeInterval = 10

    /// Hovering the island opens it, and an island opened that way folds shortly after
    /// the pointer leaves. Off: hover only peeks (compact).
    public var openOnHover = false
    /// Grace period after the pointer leaves a hover-opened island (no flicker at the edge).
    public var hoverCloseDelay: TimeInterval = 0.6
    /// True while the island is open because of a hover, until the user clicks inside it.
    public private(set) var openedByHover = false

    private var compactHideWork: DispatchWorkItem?
    private var expandedCollapseWork: DispatchWorkItem?
    private var greetCollapseWork: DispatchWorkItem?
    private var stateBeforeListening: State = .hidden

    public init() {}

    // MARK: – Inputs

    /// App launched: play the greeting.
    public func launch() {
        cancelTimers()
        transition(to: .greeting)
    }

    /// The pointer entered the island area.
    public func mouseEntered() {
        if openOnHover, state == .hidden || state == .compact, isHeldOpen?() != true {
            cancelTimers()
            openedByHover = true
            transition(to: .expanded)
            return
        }
        switch state {
        case .hidden:
            if isHeldOpen?() == true {
                // Already expanded by an external call: sync without a transition.
                state = .expanded
            } else {
                cancelTimers()
                transition(to: .compact)
            }
        case .compact:
            compactHideWork?.cancel()
            compactHideWork = nil
        case .expanded:
            expandedCollapseWork?.cancel()
            expandedCollapseWork = nil
        case .greeting:
            scheduleGreetCollapse(delay: greetHoverCollapseDelay)
        case .listening:
            if openOnHover {
                cancelTimers()
                openedByHover = true
                transition(to: .expanded)
            }
        }
    }

    /// The pointer left the island area.
    public func mouseLeft() {
        switch state {
        case .hidden:
            break
        case .compact:
            scheduleCompactHide()
        case .expanded:
            if isHeldOpen?() != true, collapsesWhenLeft { scheduleExpandedCollapse() }
        case .greeting:
            if isHeldOpen?() != true {
                greetCollapseWork?.cancel(); greetCollapseWork = nil
                transition(to: .compact)
            }
        case .listening:
            break   // never fold while listening
        }
    }

    /// The compact island was clicked. Also accepts `.hidden` (an alert put the island on
    /// screen under a pointer the machine never saw enter) and `.listening` (open the
    /// overview while the voice assistant keeps running).
    public func click() {
        openedByHover = false
        guard state == .compact || state == .hidden || state == .listening else { return }
        cancelTimers()
        transition(to: .expanded)
    }

    /// The app hid the island on its own (nothing left to show). Mirror it without side
    /// effects, so the next hover peeks again.
    public func hiddenExternally() {
        guard state == .compact else { return }
        cancelTimers()
        state = .hidden
    }

    /// The app expanded the island itself (an approval or an alert). Sync to `.expanded`
    /// without firing `onTransition`, so the next hover or leave behaves correctly.
    public func openedExternally() {
        cancelTimers()
        openedByHover = false
        guard state != .expanded && state != .greeting else { return }
        state = .expanded
    }

    /// The app folded the island itself (Escape, a button, auto-close).
    public func collapse() {
        openedByHover = false
        guard state == .expanded || state == .greeting || state == .listening else { return }
        cancelTimers()
        transition(to: .compact)
    }

    /// A click outside Mely or another app came forward. The listening island and one held
    /// open by a request stay.
    public func focusLost() {
        guard collapsesOnFocusLoss, state == .expanded || state == .greeting, isHeldOpen?() != true else { return }
        openedByHover = false
        cancelTimers()
        transition(to: .compact)
    }

    // MARK: – Voice

    /// Wake phrase heard: open in listening mode from any state.
    public func voiceWoke() {
        stateBeforeListening = state
        cancelTimers()
        openedByHover = false
        transition(to: .listening)
    }

    /// The voice turn ended (silence, cancel phrase, dismissal).
    public func voiceFinished() {
        guard state == .listening else { return }
        let target: State = stateBeforeListening == .expanded ? .expanded : .compact
        transition(to: target)
        if target == .expanded, isHeldOpen?() != true, collapsesWhenLeft { scheduleExpandedCollapse() }
    }

    /// The greeting animation finished. Does not override a longer hover timer already running.
    public func greetComplete() {
        guard state == .greeting else { return }
        if greetCollapseWork == nil {
            scheduleGreetCollapse(delay: greetAutoCollapseDelay)
        }
    }

    /// Non-alert activity: show the compact island from hidden.
    public func reveal() {
        guard state == .hidden else { return }
        cancelTimers()
        transition(to: .compact)
        scheduleCompactHide()
    }

    /// The user clicked inside: a hover-opened island now keeps the normal auto-close
    /// instead of folding as soon as the pointer leaves.
    public func userInteracted() {
        openedByHover = false
    }

    public func cancelTimers() {
        compactHideWork?.cancel();      compactHideWork = nil
        expandedCollapseWork?.cancel(); expandedCollapseWork = nil
        greetCollapseWork?.cancel();    greetCollapseWork = nil
    }

    // MARK: – Timers

    private func scheduleGreetCollapse(delay: TimeInterval) {
        greetCollapseWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.state == .greeting else { return }
                self.transition(to: .compact)
            }
        }
        greetCollapseWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func scheduleCompactHide() {
        compactHideWork?.cancel()
        guard hidesWhenIdle else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.state == .compact, !(self.isHeldOpen?() ?? false) else { return }
                // Still live: look again later instead of hiding.
                if self.keepsCompact?() == true { self.scheduleCompactHide(); return }
                self.transition(to: .hidden)
            }
        }
        compactHideWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + compactToHiddenDelay, execute: item)
    }

    private func scheduleExpandedCollapse() {
        expandedCollapseWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.state == .expanded, !(self.isHeldOpen?() ?? false) else { return }
                self.openedByHover = false
                self.transition(to: .compact)
            }
        }
        expandedCollapseWork = item
        let delay = openedByHover ? hoverCloseDelay : expandedToCompactDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func transition(to new: State) {
        guard new != state else { return }
        let old = state
        state = new
        onTransition?(old, new)
    }
}
