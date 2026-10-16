import Foundation
import Models
import Observation
import SwiftUI

/// Runs the quick tours (Phase 16a, PRD §7.8): which tour is showing and on which step, where
/// each anchored control is on screen, and what's recorded when a tour ends.
///
/// The root view keeps one for the whole app and draws the tour over every tab (`TourOverlay`),
/// so the dim covers the bars too and the tab bar can't be tapped through it. Screens ask for
/// their tour with `startIfNeeded(_:when:)` once their controls are ready, and mark the controls
/// with `.tourAnchor(_:label:action:)`.
///
/// A tour starts on its own at most once a session and only while "Show tips on new screens" is
/// on and she hasn't seen its version (`TourRules`). Skip, the last button, Escape and tapping
/// the highlighted control all end it and record it as seen. Replay from Profile (Phase 16b)
/// calls `start(_:)`, which doesn't ask.
@MainActor
@Observable
final class TourCenter {
    /// The tour on screen.
    struct Active: Hashable {
        var definition: TourDefinition
        var run: TourRun

        var step: TourStep { definition.steps[run.index] }
    }

    /// An anchored control, as the tour sees it.
    struct Anchor {
        /// Where it is, in the window's coordinates.
        var frame: CGRect?
        /// What VoiceOver calls it.
        var label: String
        /// What activating it from the tour does, read after the label.
        var hint: String?
        /// What it does when tapped. The tour ends first, then this runs once.
        var action: (@MainActor () -> Void)?
        /// The view that registered it, so a view leaving doesn't remove another one's anchor.
        var owner: UUID
    }

    /// Asks a control to take VoiceOver focus after a tour closes. The serial makes each request
    /// a change, even to the same control.
    struct FocusRequest: Hashable {
        var anchor: TourAnchorID
        var serial: Int
    }

    private(set) var active: Active?
    private(set) var anchors: [TourAnchorID: Anchor] = [:]
    private(set) var focusRequest: FocusRequest?

    @ObservationIgnored private let store: (any TourProgressStore)?
    @ObservationIgnored private let launch: TourLaunchOptions
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var isPrepared = false
    /// Tours that already started this session, so a failed write never brings one back.
    @ObservationIgnored private var startedThisSession: Set<TourID> = []
    /// Tours the `-tour` debug flag starts once, whatever is recorded.
    @ObservationIgnored private var forced: Set<TourID>
    /// The last write to the store, so tests can wait for it.
    @ObservationIgnored private(set) var lastWrite: Task<Void, Never>?

    init(
        store: (any TourProgressStore)?, launch: TourLaunchOptions = .standard,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.store = store
        self.launch = launch
        self.now = now
        forced = launch.startsTours
    }

    /// The control the current step points at.
    var currentAnchor: TourAnchorID? { active?.step.anchor }

    var isShowing: Bool { active != nil }

    // MARK: Starting

    /// Starts `definition` if it should start by itself: no tour is showing, it hasn't started
    /// this session, and tips are on with this version unseen (or the `-tour` flag asks for it).
    /// `isReady` is asked again after reading the store, so a screen that has since opened a
    /// sheet or pushed a screen doesn't get a tour over it.
    ///
    /// - Returns: whether the tour started.
    @discardableResult
    func startIfNeeded(_ definition: TourDefinition, when isReady: () -> Bool = { true }) async -> Bool {
        guard canStart(definition.id) else { return false }
        await prepare()
        if forced.remove(definition.id) != nil {
            guard canStart(definition.id), isReady() else { return false }
            start(definition)
            return true
        }
        // A store that can't be read means no tour: they're optional, and never worth an error.
        guard let store, let progress = try? await store.progress() else { return false }
        guard TourRules.startsAutomatically(definition.id, version: definition.version, progress: progress) else {
            return false
        }
        guard canStart(definition.id), isReady() else { return false }
        start(definition)
        return true
    }

    /// Starts `definition` from step 1 whatever is recorded: replay from Profile (Phase 16b).
    func start(_ definition: TourDefinition) {
        guard let run = TourRun(tour: definition.id, version: definition.version, stepCount: definition.steps.count)
        else { return }
        startedThisSession.insert(definition.id)
        active = Active(definition: definition, run: run)
    }

    /// Swaps in the words for another layout of the same screen (the phone turned, the text
    /// size changed), keeping the step.
    func update(_ definition: TourDefinition) {
        guard var current = active, current.definition.id == definition.id,
            current.definition.steps.count == definition.steps.count, current.definition != definition
        else { return }
        current.definition = definition
        active = current
    }

    /// After Delete my data: tours can start again this session, as on a fresh install.
    func forgetSession() {
        active = nil
        startedThisSession = []
    }

    // MARK: The buttons

    func next() {
        guard var current = active else { return }
        switch current.run.next() {
        case .moved: active = current
        case .finished: end(.finished, focus: current.definition.finishFocus ?? current.step.anchor)
        }
    }

    func back() {
        guard var current = active, current.run.back() else { return }
        active = current
    }

    /// Skip, Escape and the VoiceOver escape gesture.
    func skip() {
        guard let current = active else { return }
        end(.skipped, focus: current.step.anchor)
    }

    /// A tap on the highlighted control: the tour ends, then the control does what it always
    /// does, once.
    func activateTarget() {
        guard let current = active else { return }
        let action = anchors[current.step.anchor]?.action
        end(.controlActivated, focus: nil)
        action?()
    }

    private func end(_ outcome: TourOutcome, focus: TourAnchorID?) {
        guard let current = active else { return }
        let record = current.run.record(outcome, at: now())
        active = nil
        if let focus {
            focusRequest = FocusRequest(anchor: focus, serial: (focusRequest?.serial ?? 0) + 1)
        }
        guard let store else { return }
        lastWrite = Task {
            // A failed write only means the tour may show again next launch.
            try? await store.record(record)
        }
    }

    // MARK: Anchors

    /// Registers or refreshes what an anchored control is called and does.
    func register(
        _ id: TourAnchorID, owner: UUID, frame: CGRect? = nil, label: String, hint: String?,
        action: (@MainActor () -> Void)?
    ) {
        let known = anchors[id]?.owner == owner ? anchors[id]?.frame : nil
        anchors[id] = Anchor(frame: frame ?? known, label: label, hint: hint, action: action, owner: owner)
    }

    /// Where an anchored control is now. Only a change is written, so a still screen causes no
    /// updates.
    func move(_ id: TourAnchorID, owner: UUID, to frame: CGRect) {
        guard var anchor = anchors[id], anchor.owner == owner, anchor.frame != frame else { return }
        anchor.frame = frame
        anchors[id] = anchor
    }

    /// The control left the screen. Another layout's view with the same anchor keeps its own.
    func remove(_ id: TourAnchorID, owner: UUID) {
        guard anchors[id]?.owner == owner else { return }
        anchors[id] = nil
    }

    // MARK: Launch options

    /// Applies `-tour reset` and `-tour off` once, before the first tour is considered.
    private func prepare() async {
        guard !isPrepared else { return }
        isPrepared = true
        guard let store else { return }
        if launch.resetsProgress { try? await store.eraseAll() }
        if launch.turnsTipsOff { try? await store.setShowsTipsOnNewScreens(false) }
    }

    private func canStart(_ id: TourID) -> Bool {
        active == nil && !startedThisSession.contains(id)
    }
}

extension EnvironmentValues {
    /// The app's tours. `nil` in previews and snapshot tests, where nothing starts.
    @Entry var tourCenter: TourCenter?
}
