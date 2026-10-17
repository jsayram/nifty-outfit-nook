import SwiftUI

extension View {
    /// Adds a hardware keyboard shortcut that runs `action`, for a command with no button of its
    /// own on screen, like Command-F for search (iPad, Stage A). The shortcut lives on an
    /// invisible button behind the view and shows in the keyboard's shortcut list under `title`.
    /// VoiceOver and taps never reach the button.
    ///
    /// The shortcut only exists while the view is on screen. A tab she isn't on, or a screen
    /// under a pushed one, stays alive in SwiftUI, and its shortcut would win over the one she
    /// can see: Command-F on Saved Looks went to Closet's search, a tab away.
    public func nookKeyboardShortcut(
        _ title: String, key: KeyEquivalent, modifiers: EventModifiers = .command, action: @escaping () -> Void
    ) -> some View {
        modifier(NookKeyboardShortcut(title: title, key: key, modifiers: modifiers, action: action))
    }
}

private struct NookKeyboardShortcut: ViewModifier {
    let title: String
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let action: () -> Void

    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        content
            .background {
                if isOnScreen {
                    Button(title, action: action)
                        .keyboardShortcut(key, modifiers: modifiers)
                        .opacity(0)
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onAppear { isOnScreen = true }
            .onDisappear { isOnScreen = false }
    }
}
