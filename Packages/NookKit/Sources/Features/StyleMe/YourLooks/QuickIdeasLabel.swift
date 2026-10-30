import DesignSystem
import Models
import SwiftUI

extension QuickIdeasStylist {
    /// Quick ideas with Your looks' "why" lines (Phase 28).
    nonisolated public static var standard: QuickIdeasStylist {
        QuickIdeasStylist(why: QuickIdeasText.why)
    }
}

/// Quick ideas' words: the "why" line templates and the label that says the phone made the looks.
nonisolated public enum QuickIdeasText {
    /// One version's reason, from templates. Short, about the occasion, the colours and the
    /// weather; never about her body.
    public static func why(_ why: QuickIdeasWhy) -> String {
        switch why.change {
        case .none:
            return String(
                localized: "\(lead(why.occasion)), in \(palette(why.palette))\(weather(why)).", bundle: .module,
                comment:
                    "Quick ideas why line for Simple: occasion, colours, then weather (for example ', with a layer for the rain')"
            )
        case .dressier(let category):
            return String(
                localized: "The same outfit with a dressier \(category.singularTitle.lowercased()) for a lift.",
                bundle: .module, comment: "Quick ideas why line for Dressed up; the piece kind, such as top")
        case .another(let category):
            return String(
                localized: "A fresh take with another of your \(category.chipTitle.lowercased()).", bundle: .module,
                comment: "Quick ideas why line for Something new when ideas aren't allowed; the piece kind, plural")
        case .idea(let idea):
            return String(
                localized: "Simple plus one idea to try: \(idea.name.lowercased()).", bundle: .module,
                comment: "Quick ideas why line for Something new with an idea piece")
        }
    }

    private static func lead(_ occasion: Occasion) -> String {
        switch occasion {
        case .office:
            String(localized: "Smart enough for the office", bundle: .module, comment: "Quick ideas why line start")
        case .casual: String(localized: "Easy for a casual day", bundle: .module, comment: "Quick ideas why line start")
        case .brunch: String(localized: "Relaxed for brunch", bundle: .module, comment: "Quick ideas why line start")
        case .dateNight:
            String(localized: "Dressed up for date night", bundle: .module, comment: "Quick ideas why line start")
        case .event: String(localized: "Polished for the event", bundle: .module, comment: "Quick ideas why line start")
        case .concert:
            String(localized: "Comfortable for the concert", bundle: .module, comment: "Quick ideas why line start")
        case .other:
            String(localized: "Picked from your pieces", bundle: .module, comment: "Quick ideas why line start")
        }
    }

    private static func palette(_ palette: QuickIdeasWhy.Palette) -> String {
        switch palette {
        case .neutrals:
            String(localized: "calm neutrals", bundle: .module, comment: "Quick ideas why line: an all-neutral outfit")
        case .neutralsAnd(let color):
            String(
                localized: "neutrals with a touch of \(color.title.lowercased())", bundle: .module,
                comment: "Quick ideas why line: neutrals and one colour")
        case .mixed:
            String(
                localized: "a mix of your colours", bundle: .module, comment: "Quick ideas why line: several colours")
        }
    }

    private static func weather(_ why: QuickIdeasWhy) -> String {
        guard case .outdoors(let band, let wet) = why.weather else { return "" }
        if why.addsLayer {
            if wet {
                return String(
                    localized: ", with a layer for the wet weather", bundle: .module,
                    comment: "Quick ideas why line end")
            }
            if band == .cold {
                return String(
                    localized: ", with a warm layer for the cold", bundle: .module, comment: "Quick ideas why line end")
            }
            return String(
                localized: ", with a layer for the cool day", bundle: .module, comment: "Quick ideas why line end")
        }
        if band == .hot {
            return String(localized: ", light for the heat", bundle: .module, comment: "Quick ideas why line end")
        }
        return ""
    }

    /// The label's title, by the stylist that made the looks.
    public static func title(_ lane: StylistLane) -> String {
        switch lane {
        case .onDevice:
            String(
                localized: "Ideas from Apple Intelligence (on your phone)", bundle: .module,
                comment: "Your looks label when Apple's on-device model made the looks")
        case .rules, .cloud:
            String(
                localized: "Quick ideas (on your phone)", bundle: .module,
                comment: "Your looks label when the rule-based stylist on the phone made the looks")
        }
    }

    /// Why the phone made them, and what she can do about it.
    public static func detail(_ reason: QuickIdeasReason?) -> String {
        let made = String(
            localized: "Made on this iPhone from your own pieces.", bundle: .module,
            comment: "Quick ideas label: what made the looks")
        switch reason {
        case nil, .cloudNotSetUp:
            return made
        case .needsConsent:
            return made + " "
                + String(
                    localized: "For the stylist’s ideas, Style Me needs your OK.", bundle: .module,
                    comment: "Quick ideas label without stylist consent")
        case .offline:
            return String(
                localized: "You’re offline, so these were made on this iPhone from your own pieces.", bundle: .module,
                comment: "Quick ideas label when offline")
        case .limited(let problem):
            return made + " " + CloudLimitText.message(for: problem)
        case .cloudDidNotFinish:
            return String(
                localized: "The stylist didn’t finish, so these were made on this iPhone. Nothing was charged.",
                bundle: .module, comment: "Quick ideas label after the cloud stylist failed")
        }
    }
}

/// Says the looks on screen were made on the phone, and why (Phase 28). Over the result, under
/// any problem banner. Review opens the stylist's consent; Ask the stylist tries the cloud again.
struct QuickIdeasLabel: View {
    let lane: StylistLane
    let reason: QuickIdeasReason?
    let retry: () -> Void
    let reviewConsent: () -> Void
    /// Release: signed out, after Not now: Sign in, then the stylist tries again.
    var signIn: () -> Void = {}
    /// F1c: the server shows no styling access: opens Styling access.
    var seeStylingAccess: () -> Void = {}

    @Environment(\.connection) private var connection

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
            Label(QuickIdeasText.title(lane), systemImage: "iphone")
                .nookTextStyle(.label)
                .foregroundStyle(.nook.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("results.quickIdeas")
            NookBanner(
                QuickIdeasText.detail(reason), systemImage: "info.circle", tone: .neutral, actionTitle: actionTitle,
                action: action)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionTitle: String? {
        switch reason {
        case .needsConsent: StylistConsentText.review
        case .limited(.account(.signedOut)): SignInText.signIn
        case .limited(.needsStylingAccess): CloudLimitText.seeStylingAccess
        case .offline where !connection.isOffline, .cloudDidNotFinish:
            String(
                localized: "Ask the stylist", bundle: .module,
                comment: "Quick ideas label: tries the cloud stylist again")
        default: nil
        }
    }

    private var action: (() -> Void)? {
        switch reason {
        case .needsConsent: reviewConsent
        case .limited(.account(.signedOut)): signIn
        case .limited(.needsStylingAccess): seeStylingAccess
        case .offline where !connection.isOffline, .cloudDidNotFinish: retry
        default: nil
        }
    }
}
