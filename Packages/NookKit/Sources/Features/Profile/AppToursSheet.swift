import DesignSystem
import Models
import SwiftUI

/// App tours (Phase 16b, `settings.html?sheet=tours`, PRD §7.8): every screen's quick tour with
/// its number of tips and what it covers, the common screens first and the rest under More
/// screen tours. Choosing one closes the sheet, opens that screen and starts its tour from
/// step 1, even with tips off. Then "Show tips on new screens" and Reset all tips.
struct AppToursSheet: View {
    /// Which Laundry tour to list: the one for the way tracking is set.
    let tracksLaundry: Bool
    /// "Show tips on new screens", or `nil` until it's read (or when it can't be).
    let showsTips: Bool?
    let replay: (TourID) -> Void
    /// Saves the switch. Returns false when it didn't save.
    let setShowsTips: (Bool) async -> Bool
    /// Forgets every tour seen. Returns false when it didn't save.
    let resetAll: () async -> Bool

    @State private var showsMore = false
    @State private var note: Note?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the sheet says under its controls after one is used.
    enum Note: Equatable {
        case tipsOn
        case tipsOff
        case reset
        case failed

        var text: String {
            switch self {
            case .tipsOn: AppToursText.tipsOnNote
            case .tipsOff: AppToursText.tipsOffNote
            case .reset: AppToursText.resetNote
            case .failed: ProfileText.failed
            }
        }
    }

    private var entries: [TourCatalogEntry] { TourCatalog.entries(tracksLaundry: tracksLaundry) }

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            VStack(spacing: NookSpacing.xxSmall) {
                ForEach(entries.filter(\.isCommon)) { row($0) }
                moreButton
                if showsMore {
                    ForEach(entries.filter { !$0.isCommon }) { row($0) }
                }
            }
            NookDivider()
            SettingsSwitchRow(
                title: AppToursText.switchTitle, detail: AppToursText.switchDetail, systemImage: "lightbulb",
                isOn: showsTips ?? true, identifier: "appTours.showTips"
            ) { isOn in
                Task {
                    let saved = await setShowsTips(isOn)
                    say(saved ? (isOn ? .tipsOn : .tipsOff) : .failed)
                }
            }
            .disabled(showsTips == nil)
            NookButton(
                AppToursText.reset, systemImage: "arrow.counterclockwise", kind: .soft, fillsWidth: true
            ) {
                Task { say(await resetAll() ? .reset : .failed) }
            }
            .accessibilityHint(Text(AppToursText.resetHint))
            .accessibilityIdentifier("appTours.reset")
            if let note {
                Text(note.text)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("appTours.note")
            }
        }
    }

    private func row(_ entry: TourCatalogEntry) -> some View {
        Button {
            replay(entry.id)
        } label: {
            NookRow(entry.title, subtitle: entry.detail, systemImage: entry.systemImage, accessory: .chevron)
        }
        .buttonStyle(.nookRow)
        .accessibilityHint(Text(entry.startsLater ?? AppToursText.replayHint))
        .accessibilityIdentifier("appTours.\(entry.id.rawValue)")
    }

    /// More screen tours: opens and closes the rest of the list.
    private var moreButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy) { showsMore.toggle() }
        } label: {
            HStack {
                Text(AppToursText.more)
                    .nookTextStyle(.label)
                    .foregroundStyle(.nook.accent)
                Spacer(minLength: NookSpacing.small)
                Image(systemName: showsMore ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.nook.accent)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, NookSpacing.medium)
            .frame(minHeight: NookSpacing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(showsMore ? AppToursText.open : AppToursText.closed))
        .accessibilityIdentifier("appTours.more")
    }

    private func say(_ note: Note) {
        self.note = note
        AccessibilityNotification.Announcement(note.text).post()
    }
}

/// The words in App tours.
nonisolated enum AppToursText {
    static var row: String {
        String(localized: "App tours", bundle: .module, comment: "Profile row: replays the quick tours")
    }

    static var rowDetail: String {
        String(
            localized: "Replay the tips for any screen", bundle: .module, comment: "Profile row: under App tours")
    }

    static var sheetLine: String {
        String(
            localized: "Pick a screen and I’ll show you around it again.", bundle: .module,
            comment: "Under the App tours sheet's title")
    }

    static var more: String {
        String(localized: "More screen tours", bundle: .module, comment: "App tours: shows the rest of the list")
    }

    static var open: String {
        String(localized: "Open", bundle: .module, comment: "VoiceOver value: a list that's showing")
    }

    static var closed: String {
        String(localized: "Closed", bundle: .module, comment: "VoiceOver value: a list that's hidden")
    }

    static var replayHint: String {
        String(
            localized: "Opens the screen and starts its tips from the beginning.", bundle: .module,
            comment: "VoiceOver hint on a screen in App tours")
    }

    static var switchTitle: String {
        String(localized: "Show tips on new screens", bundle: .module, comment: "App tours: switch")
    }

    static var switchDetail: String {
        String(
            localized: "Each tour shows once. Skip ends it.", bundle: .module, comment: "App tours: under the switch")
    }

    static var tipsOnNote: String {
        String(
            localized: "You’ll see tips the first time you open a screen.", bundle: .module,
            comment: "App tours: after turning tips on")
    }

    static var tipsOffNote: String {
        String(
            localized: "No more tips. You can replay any tour here.", bundle: .module,
            comment: "App tours: after turning tips off")
    }

    static var reset: String {
        String(localized: "Reset all tips", bundle: .module, comment: "App tours: button")
    }

    static var resetHint: String {
        String(
            localized: "Every screen shows its tips again the next time you open it.", bundle: .module,
            comment: "VoiceOver hint on Reset all tips")
    }

    static var resetNote: String {
        String(
            localized: "Done. Each screen shows its tips again the next time you open it, while tips are on.",
            bundle: .module, comment: "App tours: after Reset all tips")
    }
}
