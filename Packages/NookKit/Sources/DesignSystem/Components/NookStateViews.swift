import SwiftUI

/// What a screen shows when there's nothing to show yet (`.empty` in Closet).
///
/// A soft round icon, a serif title, a short explanation and up to a couple of actions. All
/// text wraps; nothing is cut off at any text size.
///
/// ```swift
/// NookEmptyState("Your closet is empty", message: "Add a piece to get started.", systemImage: "hanger") {
///     NookButton("Add a piece", systemImage: "plus", fillsWidth: true) { add() }
/// }
/// ```
public struct NookEmptyState<Actions: View>: View {
    private let title: String
    private let message: String?
    private let systemImage: String
    private let actions: Actions

    /// - Parameters:
    ///   - title: The heading, already localized. So is `message`.
    ///   - actions: Buttons stacked under the text. Usually one `NookButton` with `fillsWidth`.
    public init(
        _ title: String,
        message: String? = nil,
        systemImage: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actions = actions()
    }

    public var body: some View {
        NookStateLayout(
            title: title,
            message: message,
            symbol: { NookStateSymbol(systemImage: systemImage, fill: .nook.tintStrong, tint: .nook.accent) },
            actions: { actions }
        )
    }
}

extension NookEmptyState where Actions == EmptyView {
    public init(_ title: String, message: String? = nil, systemImage: String) {
        self.init(title, message: message, systemImage: systemImage) { EmptyView() }
    }
}

/// What a screen shows while it waits for its content: the soft dots, a title and a short line.
/// VoiceOver reads it as one element, so she hears what's loading in one go.
public struct NookLoadingState: View {
    private let title: String
    private let message: String?

    /// - Parameter title: What's happening, already localized, like "Getting your looks". So is `message`.
    public init(_ title: String, message: String? = nil) {
        self.title = title
        self.message = message
    }

    public var body: some View {
        NookStateLayout(
            title: title,
            message: message,
            symbol: { NookLoadingIndicator(size: .large).frame(minHeight: NookSpacing.minimumTapTarget) },
            actions: { EmptyView() }
        )
        .accessibilityElement(children: .combine)
    }
}

/// What a screen shows when something failed: what happened, in plain words, and a way to try
/// again. Say whether anything was lost or charged in `message` (the mockups always do).
public struct NookErrorState<Actions: View>: View {
    private let title: String
    private let message: String?
    private let retryTitle: String
    private let retry: () -> Void
    private let actions: Actions

    /// - Parameters:
    ///   - title: What went wrong, already localized. So are `message` and `retryTitle`.
    ///   - retryTitle: The retry button's label. Defaults to "Try again".
    ///   - retry: Runs when she taps the retry button.
    ///   - actions: More buttons under the retry button, like "Back to Style Me".
    public init(
        _ title: String,
        message: String? = nil,
        retryTitle: String? = nil,
        retry: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.retryTitle =
            retryTitle
            ?? String(localized: "Try again", bundle: .module, comment: "Button that repeats a failed action")
        self.retry = retry
        self.actions = actions()
    }

    public var body: some View {
        NookStateLayout(
            title: title,
            message: message,
            symbol: {
                NookStateSymbol(systemImage: "exclamationmark.circle", fill: .nook.errorSurface, tint: .nook.error)
            },
            actions: {
                NookButton(retryTitle, systemImage: "arrow.clockwise", fillsWidth: true, action: retry)
                actions
            }
        )
    }
}

extension NookErrorState where Actions == EmptyView {
    public init(_ title: String, message: String? = nil, retryTitle: String? = nil, retry: @escaping () -> Void) {
        self.init(title, message: message, retryTitle: retryTitle, retry: retry) { EmptyView() }
    }
}

/// The shared layout of the empty, loading and error states: centred, at most 360 points wide.
struct NookStateLayout<Symbol: View, Actions: View>: View {
    let title: String
    let message: String?
    @ViewBuilder let symbol: Symbol
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: NookSpacing.medium) {
            symbol
            VStack(spacing: NookSpacing.small) {
                Text(title)
                    .nookTextStyle(.title)
                    .foregroundStyle(.nook.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message)
                        .nookTextStyle(.body)
                        .foregroundStyle(.nook.textSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: NookSpacing.medium) { actions }
                .padding(.top, NookSpacing.small)
        }
        .frame(maxWidth: 360)
        .padding(.horizontal, NookSpacing.xLarge)
        .padding(.vertical, NookSpacing.xxLarge)
        .frame(maxWidth: .infinity)
    }
}

/// A big SF Symbol in a soft circle, above a state's title. Decorative, so VoiceOver skips it.
struct NookStateSymbol: View {
    let systemImage: String
    let fill: Color
    let tint: Color

    @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 72

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .accessibilityHidden(true)
    }
}
