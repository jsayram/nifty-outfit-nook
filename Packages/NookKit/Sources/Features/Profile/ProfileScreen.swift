import DesignSystem
import Models
import SwiftUI

/// A screen Profile pushes.
nonisolated enum ProfileDestination: Hashable, Identifiable, Sendable {
    /// Fit and measurements (Phase 14a).
    case fit
    // Phase 14b. App tours joins them in Phase 16b, when there are tours to replay.
    case accessibility
    case help
    case feedback
    case privacy
    case deleteData

    /// The Help and privacy group, in order.
    static let helpAndPrivacy: [ProfileDestination] = [.accessibility, .help, .feedback, .privacy, .deleteData]

    var id: Self { self }

    var title: String {
        switch self {
        case .fit: ProfileText.fitRow
        case .accessibility: ProfileText.accessibilityRow
        case .help: ProfileText.helpRow
        case .feedback: ProfileText.feedbackRow
        case .privacy: ProfileText.privacyRow
        case .deleteData: ProfileText.deleteDataRow
        }
    }

    var systemImage: String {
        switch self {
        case .fit: "ruler"
        case .accessibility: "accessibility"
        case .help: "questionmark.circle"
        case .feedback: "bubble.left"
        case .privacy: "hand.raised"
        case .deleteData: "trash"
        }
    }

    /// A stable name for UI tests.
    var identifier: String {
        switch self {
        case .fit: "fit"
        case .accessibility: "accessibility"
        case .help: "help"
        case .feedback: "feedback"
        case .privacy: "privacy"
        case .deleteData: "deleteData"
        }
    }
}

/// A sheet Profile opens over itself.
nonisolated enum ProfileSheet: String, Identifiable, Hashable, Sendable {
    case name
    case preferences
    case repeatWindow
    case tryOnPhoto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: ProfileText.nameRow
        case .preferences: ProfileText.preferencesRow
        case .repeatWindow: ProfileText.repeatRow
        case .tryOnPhoto: ProfileText.photoRow
        }
    }

    var subtitle: String? {
        switch self {
        case .name: ProfileText.nameSheetLine
        case .preferences, .repeatWindow, .tryOnPhoto: nil
        }
    }
}

/// Profile (Phase 14a, `settings.html`), pushed from Home's name sign and Profile button, and
/// from the Profile link on Laundry and the laundry sheet.
///
/// Name on your sign, Preferences and Avoid repeating outfits for open small sheets and save
/// when she picks. Fit and measurements is pushed. Your try-on photo is a sheet that explains
/// the photo and, in Stage A, offers an example instead of the camera or her photos. Track
/// laundry is a switch (Phase 14b). Accessibility, Help, Send feedback, Privacy and terms and
/// Delete my data are pushed (14b). Home reloads when Profile closes, so a new name is on the
/// sign and the hamper follows Track laundry straight away (RD-03.1, RD-11).
struct ProfileScreen: View {
    @Environment(\.services) private var services
    @Environment(\.locale) private var locale
    @State private var model = ProfileModel()
    @State private var pushed: ProfileDestination?
    @State private var sheet: ProfileSheet?
    @State private var toast: NookToastMessage?

    var body: some View {
        ProfilePage(
            model: model,
            actions: ProfileActions(
                retry: { Task { await model.load(from: services, locale: locale) } },
                editName: { sheet = .name },
                open: { pushed = $0 },
                openSheet: { sheet = $0 },
                setTracksLaundry: { isOn in Task { await setTracksLaundry(isOn) } }
            )
        )
        .navigationTitle(ProfileText.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The title is on the wall, as on Laundry.
            ToolbarItem(placement: .principal) {
                Text(verbatim: "").accessibilityHidden(true)
            }
        }
        .navigationDestination(item: $pushed) { destination in
            switch destination {
            case .fit: FitScreen(model: model)
            case .accessibility: AccessibilityScreen()
            case .help: HelpScreen()
            case .feedback: FeedbackScreen()
            case .privacy: PrivacyScreen()
            case .deleteData: DeleteDataScreen()
            }
        }
        .nookSheet(
            item: $sheet, title: { $0.title }, subtitle: { $0.subtitle },
            detents: sheetDetents
        ) { sheet in
            sheetContent(sheet)
        }
        .overlay {
            Color.clear
                .nookToast($toast)
        }
        .task { await model.load(from: services, locale: locale) }
    }

    /// The try-on photo sheet opens full height, so its photo and buttons are never cut off
    /// (playbook, Phase 12b).
    private var sheetDetents: Set<PresentationDetent> {
        sheet == .tryOnPhoto ? [.large] : [.medium, .large]
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ProfileSheet) -> some View {
        switch sheet {
        case .name:
            NameSignSheet(name: model.profile.signName, problem: model.nameProblem) { text in
                guard let saved = await model.saveName(text, in: services) else { return false }
                self.sheet = nil
                toast = NookToastMessage(ProfileText.signSays(SignName.shown(saved)), systemImage: "checkmark")
                return true
            }
        case .preferences:
            ProfileChoices(
                options: PieceMode.allCases.map { mode in
                    ProfileChoice(
                        value: mode, title: mode.title, detail: mode.detail,
                        systemImage: mode == .mineAndOneIdea ? "sparkles" : "hanger",
                        identifier: "profile.preferences.\(mode.rawValue)")
                },
                selected: model.profile.preferences.pieceMode, note: ProfileText.preferencesNote
            ) { mode in
                await closing { await model.setPieceMode(mode, in: services) }
            }
        case .repeatWindow:
            ProfileChoices(
                options: RepeatWindow.allCases.map { window in
                    ProfileChoice(
                        value: window, title: window.title, detail: window.detail,
                        systemImage: window == .noLimit ? "infinity" : "calendar",
                        identifier: "profile.repeat.\(window.rawValue)")
                },
                selected: model.profile.preferences.repeatWindow, note: ProfileText.repeatNote
            ) { window in
                await closing { await model.setRepeatWindow(window, in: services) }
            }
        case .tryOnPhoto:
            TryOnPhotoSheet(hasPhoto: model.hasTryOnPhoto) {
                await model.useExamplePhoto(in: services)
            } remove: {
                await model.removePhoto(in: services)
            }
        }
    }

    /// Track laundry: saves the switch and says what happened to her dirty marks (RD-11). When it
    /// doesn't save, the switch stays as it was and a toast says so.
    private func setTracksLaundry(_ isOn: Bool) async {
        let saved = await model.setTracksLaundry(isOn, in: services)
        toast =
            saved
            ? NookToastMessage(
                ProfileText.laundryToast(isOn: isOn, kept: model.keptDirtyCount),
                systemImage: isOn ? "basket" : "checkmark")
            : NookToastMessage(ProfileText.failed, systemImage: "exclamationmark.triangle")
    }

    /// Closes the sheet once its change is saved. When it isn't, the sheet stays and says so.
    private func closing(_ change: () async -> Bool) async -> Bool {
        let saved = await change()
        if saved { sheet = nil }
        return saved
    }
}
