import DesignSystem
import Models
import SwiftUI

/// While the stylist works (`results.html?state=generating`): what's happening in three steps,
/// a progress bar and Cancel. Nothing moves under Reduce Motion except the dots fading.
struct StylingProgress: View {
    let model: YourLooksModel
    let text: YourLooksText
    let cancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var step: YourLooksModel.StylingStep {
        if case .styling(let step) = model.status { step } else { .checking }
    }

    var body: some View {
        let pieces = StyleMeText.pieces(model.usablePieces)
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            // At the accessibility sizes the badge and dots go under the title, so "Styling…"
            // keeps the full width.
            let header =
                dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: NookSpacing.small))
                : AnyLayout(HStackLayout(alignment: .center, spacing: NookSpacing.small))
            header {
                Text("Styling…", bundle: .module, comment: "Your looks while the stylist works")
                    .nookTextStyle(.title)
                    .foregroundStyle(.nook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("results.styling")
                HStack(spacing: NookSpacing.small) {
                    NookBadge(SharedText.simulated)
                    Spacer(minLength: 0)
                    // The dots only fade under Reduce Motion.
                    NookLoadingIndicator(size: .large)
                }
            }
            Text(
                "Choosing one outfit in three versions from \(text.sourceName) for \(text.occasionValue).",
                bundle: .module, comment: "Your looks while styling: the source and the occasion"
            )
            .nookTextStyle(.body)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
                StepRow(
                    number: 1, state: step == .checking ? .now : .done,
                    title: model.usablePieces > 0
                        ? String(
                            localized: "Check \(pieces) ready to wear", bundle: .module,
                            comment: "Styling step 1: how many pieces can be used")
                        : String(
                            localized: "Check the pieces ready to wear", bundle: .module,
                            comment: "Styling step 1, before the count is known"),
                    detail: String(localized: "On this iPhone", bundle: .module, comment: "Styling step detail"))
                StepRow(
                    number: 2, state: step == .checking ? .waiting : .done,
                    title: String(localized: "Send the request", bundle: .module, comment: "Styling step 2"),
                    detail: String(localized: "Simulated stylist", bundle: .module, comment: "Styling step detail"))
                StepRow(
                    number: 3, state: step == .choosing ? .now : .waiting,
                    title: String(
                        localized: "Choose one outfit in three versions", bundle: .module, comment: "Styling step 3"),
                    detail: nil)
            }
            .accessibilityElement(children: .contain)

            meter
            leavingNote
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("results.leavingNote")
            if model.isCloud && model.notificationOffer == .offer {
                NotificationOfferCard(model: model)
            }
            NookButton(
                String(localized: "Cancel", bundle: .module, comment: "Stops styling on Your looks"),
                kind: .soft, fillsWidth: true, action: cancel
            )
            .accessibilityIdentifier("results.cancel")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, NookSpacing.small)
    }

    /// What leaving does: Stage A's stylist on the phone stops; a cloud job keeps going (27c).
    @ViewBuilder private var leavingNote: some View {
        if !model.isCloud {
            Text(
                "Leaving this screen stops it, and nothing is used.", bundle: .module,
                comment: "Your looks while styling: leaving cancels the request")
        } else if model.isTakingLong {
            Text(
                "This is taking a little longer. It keeps going if you leave.", bundle: .module,
                comment: "Your looks while a cloud styling job is late and still being checked")
        } else {
            Text(
                "You can leave this screen. Your looks keep coming, and you’ll see a note when they’re ready.",
                bundle: .module, comment: "Your looks while a cloud styling job runs: leaving doesn't stop it")
        }
    }

    /// Two thirds once the request has gone, a third before. It moves only without Reduce Motion.
    private var meter: some View {
        let share = step == .checking ? 1.0 / 3 : 2.0 / 3
        let stepNumber = step == .checking ? 1 : 3
        return GeometryReader { proxy in
            Capsule()
                .fill(Color.nook.track)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.nook.accent)
                        .frame(width: proxy.size.width * share)
                }
        }
        .frame(height: 8)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: share)
        .accessibilityElement()
        .accessibilityLabel(Text("Progress", bundle: .module, comment: "VoiceOver name of the styling progress bar"))
        .accessibilityValue(
            Text(
                "Step \(stepNumber) of 3", bundle: .module,
                comment: "VoiceOver value of the styling progress bar"))
    }
}

/// 27c: the first time a job that can take a while starts, a short explanation before iOS asks
/// about notifications. Not now keeps it from coming back; the banner in the app works either way.
private struct NotificationOfferCard: View {
    let model: YourLooksModel

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            Text("Want a note when they’re ready?", bundle: .module, comment: "Your looks: offer of notifications")
                .nookTextStyle(.headline)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(
                "If you leave the app, a notification can tell you when your outfit ideas are ready. It never says what’s in them.",
                bundle: .module, comment: "Your looks: why the app asks about notifications"
            )
            .nookTextStyle(.body)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: NookSpacing.small) { buttons }
                VStack(spacing: NookSpacing.small) { buttons }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nookCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("results.notifyOffer")
    }

    @ViewBuilder private var buttons: some View {
        NookButton(
            String(localized: "Notify me", bundle: .module, comment: "Your looks: turn on notifications for jobs"),
            kind: .primary, size: .small, fillsWidth: true
        ) {
            Task { await model.allowNotifications() }
        }
        .accessibilityIdentifier("results.notifyMe")
        NookButton(
            String(localized: "Not now", bundle: .module, comment: "Your looks: don't turn on notifications"),
            kind: .soft, size: .small, fillsWidth: true
        ) {
            Task { await model.declineNotifications() }
        }
        .accessibilityIdentifier("results.notifyNotNow")
    }
}

/// One step of the styling progress: a numbered dot (a check once done, solid while it's
/// happening), its title and a small detail.
private struct StepRow: View {
    enum State {
        case done
        case now
        case waiting
    }

    let number: Int
    let state: State
    let title: String
    let detail: String?

    @ScaledMetric(relativeTo: .body) private var dot: CGFloat = 26

    var body: some View {
        HStack(alignment: .center, spacing: NookSpacing.medium) {
            ZStack {
                Circle().fill(fill)
                switch state {
                case .done:
                    Image(systemName: "checkmark").fontWeight(.bold).foregroundStyle(.nook.success)
                case .now:
                    Text(number, format: .number).fontWeight(.bold).foregroundStyle(.nook.onAccent)
                case .waiting:
                    Text(number, format: .number).foregroundStyle(.nook.textSecondary)
                }
            }
            .nookTextStyle(.caption)
            .frame(width: dot, height: dot)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .nookTextStyle(.body)
                    .fontWeight(state == .now ? .bold : .regular)
                    .foregroundStyle(state == .waiting ? Color.nook.textSecondary : Color.nook.textPrimary)
                if let detail {
                    Text(detail)
                        .nookTextStyle(.caption)
                        .foregroundStyle(.nook.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: NookSpacing.minimumTapTarget)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(stateWord))
    }

    private var fill: Color {
        switch state {
        case .done: .nook.successSurface
        case .now: .nook.accent
        case .waiting: .nook.tintStrong
        }
    }

    private var stateWord: String {
        switch state {
        case .done: String(localized: "Done", bundle: .module, comment: "VoiceOver: a styling step is done")
        case .now: String(localized: "In progress", bundle: .module, comment: "VoiceOver: the styling step now")
        case .waiting: String(localized: "Next", bundle: .module, comment: "VoiceOver: a styling step still to come")
        }
    }
}

/// No valid outfit in this source (InsufficientWardrobe, `results.html?state=insufficient`):
/// what a look needs, and ways forward. Nothing was made up to fill the gap.
struct InsufficientState: View {
    let wardrobe: InsufficientWardrobe
    let usablePieces: Int
    let text: YourLooksText
    let actions: YourLooksActions

    var body: some View {
        let pieces = StyleMeText.pieces(usablePieces)
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            VStack(alignment: .leading, spacing: NookSpacing.small) {
                Text("Not enough pieces for a look", bundle: .module, comment: "Your looks: insufficient wardrobe")
                    .nookTextStyle(.title)
                    .foregroundStyle(.nook.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("results.insufficient")
                Text(
                    "Nothing was charged, and nothing was made up to fill the gap.", bundle: .module,
                    comment: "Your looks: insufficient wardrobe"
                )
                .nookTextStyle(.body)
                .foregroundStyle(.nook.textPrimary)
                Text(
                    "\(text.sourceName) has \(pieces) you can use today.", bundle: .module,
                    comment: "Your looks: insufficient wardrobe, the source's name and a count"
                )
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            if !wardrobe.missing.isEmpty {
                VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
                    NookSectionHeader(
                        String(localized: "A look needs", bundle: .module, comment: "Your looks: insufficient wardrobe")
                    )
                    ForEach(wardrobe.missing, id: \.self) { kind in
                        HStack(spacing: NookSpacing.medium) {
                            Image(systemName: Self.symbol(for: kind))
                                .foregroundStyle(.nook.accent)
                                .frame(width: 34, height: 34)
                                .background(Color.nook.tintStrong, in: Circle())
                                .accessibilityHidden(true)
                            Text(Self.needed(kind))
                                .nookTextStyle(.body)
                                .foregroundStyle(.nook.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(minHeight: NookSpacing.minimumTapTarget)
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            VStack(spacing: NookSpacing.medium) {
                NookButton(
                    wardrobe.source.isSuitcase
                        ? String(
                            localized: "Add pieces to \(text.sourceName)", bundle: .module,
                            comment: "Your looks: insufficient wardrobe in a suitcase, its name")
                        : String(localized: "Add a piece", bundle: .module, comment: "Button that opens Add a piece"),
                    systemImage: "plus", fillsWidth: true, action: actions.addPieces
                )
                .accessibilityIdentifier("results.addPieces")
                NookButton(
                    String(localized: "Change your request", bundle: .module, comment: "Your looks: back to Style Me"),
                    systemImage: "slider.horizontal.3", kind: .soft, fillsWidth: true, action: actions.backToStyleMe
                )
                .accessibilityIdentifier("results.changeRequest")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, NookSpacing.small)
    }

    static func needed(_ kind: GarmentCategory) -> String {
        switch kind {
        case .top: String(localized: "A top", bundle: .module, comment: "What a look needs")
        case .bottom:
            String(localized: "A bottom, like trousers or a skirt", bundle: .module, comment: "What a look needs")
        case .dress: String(localized: "A dress", bundle: .module, comment: "What a look needs")
        case .layer: String(localized: "A layer", bundle: .module, comment: "What a look needs")
        case .shoes: String(localized: "Shoes", bundle: .module, comment: "What a look needs")
        case .bag: String(localized: "A bag", bundle: .module, comment: "What a look needs")
        case .accessory: String(localized: "An accessory", bundle: .module, comment: "What a look needs")
        }
    }

    static func symbol(for kind: GarmentCategory) -> String {
        switch kind {
        case .top, .layer: "tshirt"
        case .bottom, .dress: "hanger"
        case .shoes: "shoe"
        case .bag: "bag"
        case .accessory: "sparkle"
        }
    }
}

/// Styling gave no result: offline, didn't finish, stopped, or couldn't start. Each says whether
/// anything was used and offers a way on. The Saved tab still works (LR-06).
struct FailureState: View {
    let failure: YourLooksModel.Failure
    let actions: YourLooksActions
    let openSaved: () -> Void

    var body: some View {
        switch failure {
        case .offline:
            VStack(spacing: NookSpacing.medium) {
                NookOfflineBanner(
                    detail: String(
                        localized: "Your request is kept.", bundle: .module,
                        comment: "Offline banner on Your looks with no result"),
                    retry: actions.retry
                )
                NookEmptyState(
                    String(
                        localized: "Styling needs a connection", bundle: .module,
                        comment: "Your looks offline state title"),
                    message: String(
                        localized:
                            "Tap Retry when you’re back online. Nothing was charged, and your saved looks still work.",
                        bundle: .module, comment: "Your looks offline state"),
                    systemImage: "wifi.slash"
                ) {
                    savedButton
                    backButton(kind: .text)
                }
            }
        case .notCompleted:
            NookErrorState(
                String(localized: "Styling didn’t finish", bundle: .module, comment: "Your looks failed state title"),
                message: String(
                    localized:
                        "The stylist didn’t answer. Nothing was charged, and your request is kept as you left it.",
                    bundle: .module, comment: "Your looks failed state"),
                retry: actions.retry
            ) {
                backButton(kind: .soft)
                savedButton
            }
        case .stopped:
            NookErrorState(
                String(localized: "Styling stopped", bundle: .module, comment: "Your looks after leaving mid-way"),
                message: String(
                    localized: "You left before your looks came, so nothing was used. Your request is kept.",
                    bundle: .module, comment: "Your looks after leaving mid-way"),
                retryTitle: String(localized: "Style again", bundle: .module, comment: "Sends the request again"),
                retry: actions.retry
            ) {
                backButton(kind: .soft)
            }
        case .closetUnavailable:
            NookErrorState(
                String(
                    localized: "Your closet couldn’t be read", bundle: .module,
                    comment: "Your looks when the stores fail"),
                message: String(
                    localized: "Nothing was sent. Try again in a moment.", bundle: .module,
                    comment: "Your looks when the stores fail"),
                retry: actions.retry
            ) {
                backButton(kind: .soft)
            }
        case .requestChanged:
            NookErrorState(
                String(
                    localized: "Your request needs another look", bundle: .module,
                    comment: "Your looks when the suitcase or starting piece changed"),
                message: String(
                    localized: "A piece or suitcase in it changed since you asked. Nothing was sent.",
                    bundle: .module, comment: "Your looks when the suitcase or starting piece changed"),
                retryTitle: Self.backTitle,
                retry: actions.backToStyleMe)
        case .needsConsent:
            // 27a: nothing was sent. Review shows the consent text; Back keeps her request.
            NookErrorState(
                StylistConsentText.needsConsentTitle,
                message: StylistConsentText.needsConsent,
                retryTitle: StylistConsentText.review,
                retry: actions.reviewConsent
            ) {
                backButton(kind: .soft)
                savedButton
            }
        case .hidden:
            // Release: she reported the result and hid it. A new request avoids its pieces.
            NookEmptyState(
                AIReportText.hiddenTitle, message: AIReportText.hiddenMessage, systemImage: "eye.slash"
            ) {
                NookButton(
                    String(localized: "Try a different outfit", bundle: .module, comment: "Your looks button (LR-05a)"),
                    systemImage: "arrow.triangle.2.circlepath", kind: .primary, fillsWidth: true, action: actions.retry
                )
                .accessibilityIdentifier("results.hidden.tryDifferent")
                backButton(kind: .soft)
            }
        case .limited(let problem):
            // 27a: a server limit. Its own words say when it can work again; nothing was counted.
            NookErrorState(
                String(
                    localized: "Styling is resting for now", bundle: .module,
                    comment: "Your looks when a cloud limit stops styling"),
                message: CloudLimitText.message(for: problem),
                retry: actions.retry
            ) {
                backButton(kind: .soft)
                savedButton
            }
        }
    }

    static var backTitle: String {
        String(localized: "Back to Style Me", bundle: .module, comment: "Your looks button")
    }

    private func backButton(kind: NookButtonKind) -> some View {
        NookButton(Self.backTitle, kind: kind, fillsWidth: true, action: actions.backToStyleMe)
            .accessibilityIdentifier("results.backToStyleMe")
    }

    private var savedButton: some View {
        NookButton(
            String(localized: "See saved looks", bundle: .module, comment: "Your looks: opens the Saved tab"),
            systemImage: "heart", kind: .soft, fillsWidth: true, action: openSaved
        )
        .accessibilityIdentifier("results.seeSaved")
    }
}
