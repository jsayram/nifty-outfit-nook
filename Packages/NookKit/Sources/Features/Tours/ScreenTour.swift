import Models
import SwiftUI

extension View {
    /// Starts this screen's quick tour by itself, once its controls are ready (Phase 16b, PRD
    /// §7.8). Put it on the screen's outermost view.
    ///
    /// The tour is asked for each time the screen appears and each time `isReady` turns true, so
    /// a sheet, a toast or a pushed screen holds it back until it's gone. It's asked again when
    /// another tour ends, and when App tours asks to replay it. `TourCenter` decides whether it
    /// starts: never over another tour, and on its own only while tips are on and this version
    /// is unseen.
    ///
    /// - Parameters:
    ///   - definition: the tour in the words for the layout that's showing. A change of layout
    ///     keeps the step and swaps in the new words.
    ///   - isReady: true when the controls the tour points at are on screen and nothing is on
    ///     top of them: no sheet, toast, alert, keyboard or work in progress, and no empty,
    ///     loading or error state standing in for them.
    func screenTour(_ definition: TourDefinition, isReady: Bool) -> some View {
        modifier(ScreenTourModifier(definition: definition, isReady: isReady))
    }
}

private struct ScreenTourModifier: ViewModifier {
    let definition: TourDefinition
    let isReady: Bool

    @Environment(\.tourCenter) private var tours
    @State private var isVisible = false
    /// `isReady` as it is now, read after the store has been read.
    @State private var isReadyNow = false

    /// Everything that can let the tour start. A change asks again.
    private struct Trigger: Hashable {
        var isVisible: Bool
        var isReady: Bool
        var isAnotherTourShowing: Bool
        var isWaiting: Bool
    }

    func body(content: Content) -> some View {
        if let tours {
            content
                .onAppear { isVisible = true }
                .onDisappear { isVisible = false }
                .onChange(of: isReady, initial: true) { isReadyNow = isReady }
                .task(
                    id: Trigger(
                        isVisible: isVisible, isReady: isReady, isAnotherTourShowing: tours.isShowing,
                        isWaiting: tours.isWaiting(definition.id))
                ) {
                    guard isVisible, isReady, !tours.isShowing else { return }
                    await tours.startIfNeeded(definition) { isVisible && isReadyNow }
                }
                // Turning the phone or changing the text size keeps the step, in the new words.
                .onChange(of: definition) { tours.update(definition) }
        } else {
            content
        }
    }
}
