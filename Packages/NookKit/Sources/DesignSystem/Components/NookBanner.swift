import SwiftUI

/// The colour of a banner.
nonisolated public enum NookBannerTone: Sendable {
    /// Butter: offline, a partial result, something to know (`.banner`).
    case warning
    /// The strong white tint: a neutral note.
    case neutral
}

/// An honest note at the top of a screen, like "You're offline" (`.banner` in Your looks).
///
/// A soft tint with a shadow below, never an edge. The icon is decorative; the text says it
/// all. At large text sizes the action moves under the text. VoiceOver reads the note as one
/// element and the action as a separate button.
public struct NookBanner: View {
    private let message: String
    private let systemImage: String
    private let tone: NookBannerTone
    private let actionTitle: String?
    private let action: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameters:
    ///   - message: The note, already localized. So is `actionTitle`.
    ///   - actionTitle: A short action, like "Retry". Shown only with an `action`.
    public init(
        _ message: String,
        systemImage: String,
        tone: NookBannerTone = .warning,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.message = message
        self.systemImage = systemImage
        self.tone = tone
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NookSpacing.small))
            : AnyLayout(HStackLayout(spacing: NookSpacing.small))
        layout {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
                Text(message)
                    .foregroundStyle(.nook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .nookTextStyle(.note)
            .accessibilityElement(children: .combine)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .nookTextStyle(.label)
                        .foregroundStyle(.nook.accent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, NookSpacing.medium)
                        .frame(minHeight: NookSpacing.minimumTapTarget)
                        .background(actionFill, in: NookRadius.shape(NookRadius.plateSlim))
                        .contentShape(NookRadius.shape(NookRadius.plateSlim))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, NookSpacing.medium)
        .padding(.trailing, action == nil ? NookSpacing.medium : NookSpacing.xSmall)
        .padding(.vertical, action == nil ? 10 : NookSpacing.xSmall)
        .frame(minHeight: NookSpacing.minimumTapTarget)
        .background {
            NookRadius.shape(NookRadius.button)
                .fill(background)
                .softShadow(.drop, in: NookRadius.shape(NookRadius.button))
        }
    }

    private var background: Color {
        switch tone {
        case .warning: .nook.warningSurface
        case .neutral: .nook.tintStrong
        }
    }

    /// The action button's fill, which has to stand apart from the banner's own.
    private var actionFill: Color {
        switch tone {
        case .warning: .nook.tintStrong
        case .neutral: .nook.accentSoft
        }
    }

    private var iconColor: Color {
        switch tone {
        case .warning: .nook.warning
        case .neutral: .nook.accent
        }
    }
}

/// The offline banner: "You're offline.", then what still works, in butter with the no-wifi icon.
public struct NookOfflineBanner: View {
    private let detail: String?
    private let retry: (() -> Void)?

    /// - Parameters:
    ///   - detail: What still works, already localized, like "These looks are kept on this iPhone."
    ///   - retry: Shows a "Retry" button when given.
    public init(detail: String? = nil, retry: (() -> Void)? = nil) {
        self.detail = detail
        self.retry = retry
    }

    public var body: some View {
        let offline = String(
            localized: "You’re offline.", bundle: .module, comment: "Banner shown without a connection")
        NookBanner(
            [offline, detail].compactMap(\.self).joined(separator: " "),
            systemImage: "wifi.slash",
            tone: .warning,
            actionTitle: retry == nil
                ? nil : String(localized: "Retry", bundle: .module, comment: "Button that tries to reconnect"),
            action: retry
        )
    }
}
