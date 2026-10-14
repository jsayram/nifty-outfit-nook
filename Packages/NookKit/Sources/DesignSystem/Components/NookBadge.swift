import SwiftUI

/// The colour of a badge. Colour is never the only signal: the badge always has words.
nonisolated public enum NookBadgeTone: String, CaseIterable, Sendable {
    /// Quiet labels, like "Simulated" (`.sim`, `.pill.mauve`).
    case neutral
    /// The soft accent, like "Not in your closet".
    case accent
    /// Good news, like "On" or "Fits well" (`.pill`).
    case success
    /// A gentle heads-up, like "In the wash" (`.pill.butter`, `.dirty`).
    case warning
}

/// A small capsule label with optional icon. Not a button; VoiceOver reads it as text.
public struct NookBadge: View {
    private let title: String
    private let systemImage: String?
    private let tone: NookBadgeTone

    /// - Parameter title: The label, already localized.
    public init(_ title: String, systemImage: String? = nil, tone: NookBadgeTone = .neutral) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: NookSpacing.xSmall) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
        .nookTextStyle(.caption)
        .fontWeight(.bold)
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(background, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var foreground: Color {
        switch tone {
        case .neutral: .nook.textSecondary
        case .accent: .nook.accent
        case .success: .nook.success
        case .warning: .nook.warning
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: .nook.tintStrong
        case .accent: .nook.accentSoft
        case .success: .nook.successSurface
        case .warning: .nook.warningSurface
        }
    }
}
