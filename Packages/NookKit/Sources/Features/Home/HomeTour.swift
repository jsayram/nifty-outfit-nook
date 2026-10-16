import Models
import SwiftUI

/// Home's quick tour (Phase 16a, PRD §7.8, `home-tour.html`): the laptop (Style Me), the
/// wardrobe (Closet), the suitcase (what Style Me picks from) and the name sign (Profile), in
/// that order, ending with Start styling.
///
/// Every layout of Home has the same four steps under one tour ID, so turning the phone or
/// changing the text size keeps the step and never counts as a new visit. The words follow the
/// approved copy for each layout: `home-tour.html` for the phone's room, and `js/screen-tours.js`
/// for the iPad rooms (`ipad-home`), large text (`home-ax`) and a phone held sideways
/// (`home-landscape`), where there's no laptop to point at.
enum HomeTour {
    /// Goes up only when Home's controls or the tour's steps really change (PRD §7.8).
    static let version = 1

    /// The four controls the tour points at.
    enum Anchor {
        static let styleMe = TourAnchorID("home.styleMe")
        static let closet = TourAnchorID("home.closet")
        static let source = TourAnchorID("home.source")
        static let profile = TourAnchorID("home.profile")
    }

    /// Which words the tour uses.
    enum Variant: Hashable {
        /// The room on a phone held upright.
        case phoneRoom
        /// The tall or wide room in a regular-width window.
        case iPadRoom
        /// The banner and large rows at the accessibility text sizes.
        case largeText
        /// A phone held sideways: the closer scene and the tiles.
        case sideways

        init(layout: HomeLayout, horizontalSizeClass: UserInterfaceSizeClass?) {
            switch layout {
            case .room: self = horizontalSizeClass == .regular ? .iPadRoom : .phoneRoom
            case .largeText: self = .largeText
            case .sideways: self = .sideways
            }
        }
    }

    /// The room control each anchor stands for.
    static func anchor(for control: RoomControl) -> TourAnchorID? {
        switch control {
        case .laptop: Anchor.styleMe
        case .wardrobe: Anchor.closet
        case .suitcase: Anchor.source
        case .nameSign: Anchor.profile
        default: nil
        }
    }

    static func definition(for variant: Variant) -> TourDefinition {
        TourDefinition(
            id: .home,
            version: version,
            steps: steps(for: variant),
            finishTitle: String(
                localized: "Start styling", bundle: .module, comment: "Last button of Home's quick tour; closes it"),
            // Start styling closes the tour; VoiceOver lands on Style Me, ready to start.
            finishFocus: Anchor.styleMe)
    }

    private static func steps(for variant: Variant) -> [TourStep] {
        switch variant {
        case .phoneRoom:
            [
                TourStep(
                    anchor: Anchor.styleMe,
                    title: String(localized: "Style Me", bundle: .module, comment: "Home tour, step 1 title"),
                    message: String(
                        localized:
                            "Tap the laptop and I’ll pull together a look from your closet for today’s weather and plans.",
                        bundle: .module, comment: "Home tour, step 1, on the phone's room")),
                TourStep(
                    anchor: Anchor.closet,
                    title: String(localized: "Your closet", bundle: .module, comment: "Home tour, step 2 title"),
                    message: String(
                        localized: "Open the wardrobe to add clothes and see everything you own.", bundle: .module,
                        comment: "Home tour, step 2, on the phone's room")),
                TourStep(
                    anchor: Anchor.source,
                    title: String(
                        localized: "Packing from", bundle: .module,
                        comment: "Home tour, step 3 title on the phone's room: the suitcase Style Me picks from"),
                    message: String(
                        localized:
                            "Style Me only picks from what’s in this suitcase. Tap it to switch suitcases or use your whole closet.",
                        bundle: .module, comment: "Home tour, step 3, on the phone's room")),
                TourStep(
                    anchor: Anchor.profile,
                    title: String(
                        localized: "That’s you", bundle: .module, comment: "Home tour, step 4 title on the phone's room"
                    ),
                    message: String(
                        localized: "Your profile lives here. You can replay this tour from it any time.",
                        bundle: .module, comment: "Home tour, step 4, on the phone's room")),
            ]
        case .iPadRoom, .largeText, .sideways:
            [
                TourStep(
                    anchor: Anchor.styleMe,
                    title: String(localized: "Style Me", bundle: .module, comment: "Home tour, step 1 title"),
                    message: variant == .iPadRoom
                        ? String(
                            localized: "Tap the laptop for an outfit idea made from your clothes.", bundle: .module,
                            comment: "Home tour, step 1, on the iPad's room")
                        : String(
                            localized: "Tap here for an outfit idea made from your clothes.", bundle: .module,
                            comment: "Home tour, step 1, at large text sizes and on a phone held sideways")),
                TourStep(
                    anchor: Anchor.closet,
                    title: String(localized: "Your closet", bundle: .module, comment: "Home tour, step 2 title"),
                    message: String(
                        localized: "Open the wardrobe to see or add your clothes.", bundle: .module,
                        comment: "Home tour, step 2, on the iPad, at large text sizes and sideways")),
                TourStep(
                    anchor: Anchor.source,
                    title: String(
                        localized: "Your suitcase", bundle: .module,
                        comment: "Home tour, step 3 title on the iPad, at large text sizes and sideways"),
                    message: variant == .iPadRoom
                        ? String(
                            localized: "Choose which packed clothes to use, or switch to your whole closet.",
                            bundle: .module, comment: "Home tour, step 3, on the iPad's room")
                        : String(
                            localized: "Choose a suitcase or your whole closet for outfit ideas.", bundle: .module,
                            comment: "Home tour, step 3, at large text sizes and on a phone held sideways")),
                TourStep(
                    anchor: Anchor.profile,
                    title: String(
                        localized: "That is you", bundle: .module,
                        comment: "Home tour, step 4 title on the iPad, at large text sizes and sideways"),
                    message: String(
                        localized: "Your name sign opens Profile, where you can replay these tours.", bundle: .module,
                        comment: "Home tour, step 4, on the iPad, at large text sizes and sideways")),
            ]
        }
    }

    /// What VoiceOver hears for a control in the spotlight: the tour ends first, then the
    /// control does what it always does.
    static func targetHint(for control: RoomControl, content: HomeRoomContent) -> String {
        let ends = String(
            localized: "Ends the tour.", bundle: .module,
            comment: "VoiceOver hint on a control in a quick tour's spotlight, before what the control does")
        return "\(ends) \(control.accessibilityHint(for: content))"
    }
}

extension View {
    /// Marks one of Home's controls for the tour, when the tour points at it: the spot to light
    /// up, and the control VoiceOver returns to when the tour closes. Other controls are
    /// unchanged.
    ///
    /// - Parameters:
    ///   - label: what VoiceOver calls the control in this layout, when it isn't the room's
    ///     label (the large rows and tiles read their words).
    ///   - focus: whether this view is the one VoiceOver can land on. A drawing hidden from
    ///     VoiceOver says false.
    func homeTourAnchor(
        _ control: RoomControl, content: HomeRoomContent, label: String? = nil,
        open: @escaping (RoomControl) -> Void, focus: Bool = true
    ) -> some View {
        modifier(
            HomeTourAnchorModifier(
                control: control, content: content, label: label ?? control.accessibilityLabel(for: content),
                open: open, focus: focus))
    }

    /// Lets a Home control take VoiceOver focus when the tour that pointed at it closes.
    func homeTourFocus(_ control: RoomControl) -> some View {
        modifier(HomeTourFocusModifier(control: control))
    }
}

private struct HomeTourAnchorModifier: ViewModifier {
    let control: RoomControl
    let content: HomeRoomContent
    let label: String
    let open: (RoomControl) -> Void
    let focus: Bool

    func body(content view: Content) -> some View {
        if let anchor = HomeTour.anchor(for: control) {
            let tourAnchored = view.tourAnchor(
                anchor, label: label,
                hint: HomeTour.targetHint(for: control, content: content),
                action: { [open, control] in open(control) })
            if focus {
                tourAnchored.tourFocusTarget(anchor)
            } else {
                tourAnchored
            }
        } else {
            view
        }
    }
}

private struct HomeTourFocusModifier: ViewModifier {
    let control: RoomControl

    func body(content: Content) -> some View {
        if let anchor = HomeTour.anchor(for: control) {
            content.tourFocusTarget(anchor)
        } else {
            content
        }
    }
}
