import DesignSystem
import Models
import SwiftUI

/// Home at the accessibility text sizes (`screens/home-ax.html`, RD-01.5).
///
/// The room shrinks to a banner (the edge of the wardrobe, her name sign and the window) and
/// every other control in the room becomes a large row, in the room's order: Source (the
/// suitcase), Occasion (the calendar), Style Me (the laptop), Laundry (the hamper), then the
/// three desk drawers. Text grows to the largest size and wraps; nothing is capped. The page
/// scrolls under the navigation bar and the tab bar. Saved Looks, the shelf in the room, is the
/// tab right below.
struct HomeLargeTextView<Notice: View>: View {
    let content: HomeRoomContent
    let open: (RoomControl) -> Void
    /// The error banner, shown under the room's banner when part of the room didn't load.
    @ViewBuilder let notice: Notice

    @Environment(\.roomIsStillImage) private var isStillImage

    /// Rows wider than this read badly; on a phone held sideways or an iPad the page centres.
    static var maximumWidth: CGFloat { 640 }

    var body: some View {
        if isStillImage {
            page.background(Color.nook.wallGradient)
        } else {
            ScrollView(.vertical) { page }
                .background(Color.nook.wallGradient.ignoresSafeArea())
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nifty Outfit Nook", bundle: .module, comment: "The app's name, as the Home title")
                .nookTextStyle(.display)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, NookSpacing.small)

            HomeBanner(content: content, open: open)
                .padding(.top, NookSpacing.medium)
                .padding(.horizontal, -NookSpacing.xSmall)

            notice

            rows
                .padding(.top, 14)
        }
        .padding(.horizontal, NookSpacing.screenMargin)
        .padding(.bottom, NookSpacing.xxLarge)
        .frame(maxWidth: Self.maximumWidth)
        .frame(maxWidth: .infinity)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 14) {
            LargeRow(control: .suitcase, content: content, systemImage: "suitcase.rolling", open: open) {
                LargeRowText(
                    caption: String(localized: "Source", bundle: .module, comment: "Caption on Home's Source row"),
                    title: content.source.name)
                SourcePill(source: content.source)
            }

            LargeRow(control: .occasion, content: content, systemImage: "calendar", fill: .warning, open: open) {
                // The chosen occasion goes under the caption once Style Me remembers one (Phase 10a).
                LargeRowText(caption: nil, title: control(.occasion))
            }

            NookButton(control(.laptop), systemImage: "sparkles", fillsWidth: true) { open(.laptop) }
                .accessibilityHint(RoomControl.laptop.accessibilityHint(for: content))
                .accessibilityIdentifier(RoomControl.laptop.identifier)

            LargeRow(control: .hamper, content: content, systemImage: "basket", open: open) {
                LaundryRowText(hamper: content.hamper)
            }

            Text("In the desk drawers", bundle: .module, comment: "Caption above Help, Send feedback and Privacy")
                .nookTextStyle(.note)
                .fontWeight(.semibold)
                .foregroundStyle(.nook.textSecondary)
                .padding(.top, NookSpacing.small)
                .padding(.horizontal, NookSpacing.xSmall)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                drawer(.helpDrawer, systemImage: "info.circle")
                NookDivider(inset: NookSpacing.medium)
                drawer(.feedbackDrawer, systemImage: "bubble.left")
                NookDivider(inset: NookSpacing.medium)
                drawer(.privacyDrawer, systemImage: "lock")
            }
        }
    }

    private func drawer(_ drawer: RoomControl, systemImage: String) -> some View {
        LargeRow(control: drawer, content: content, systemImage: systemImage, fill: nil, open: open) {
            LargeRowText(caption: nil, title: control(drawer))
        }
    }

    private func control(_ control: RoomControl) -> String {
        control.rowLabel(for: content)
    }
}

/// The fill behind a large row.
enum LargeRowFill {
    case tint
    case warning

    var color: Color {
        switch self {
        case .tint: .nook.tint
        case .warning: .nook.warningSurface
        }
    }
}

/// One of the room's controls as a large row (`.r` in `home-ax.html`): an icon, its words and a
/// chevron on a soft tinted pill, with a shadow only below. Drawer rows have no fill and sit in
/// a group split by soft dividers.
struct LargeRow<Label: View>: View {
    let control: RoomControl
    let content: HomeRoomContent
    let systemImage: String
    var fill: LargeRowFill? = .tint
    let open: (RoomControl) -> Void
    @ViewBuilder let label: Label

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 28
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At the two largest sizes the icon moves above the words, so a word like "Occasion" has
    /// the row's whole width and never breaks mid-word.
    private var iconAbove: Bool { dynamicTypeSize >= .accessibility4 }

    var body: some View {
        Button {
            open(control)
        } label: {
            HStack(spacing: NookSpacing.medium) {
                if !iconAbove {
                    // A fixed column, so the words line up from row to row.
                    icon.frame(width: min(iconSize, 44) * 1.3)
                }
                VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
                    if iconAbove {
                        icon.padding(.bottom, NookSpacing.xxSmall)
                    }
                    label
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.nook.accent)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .padding(.leading, fill == nil ? NookSpacing.medium : NookSpacing.large)
            .padding(.trailing, NookSpacing.large)
            .frame(minHeight: 64)
            .contentShape(NookRadius.shape(NookRadius.sheet))
        }
        .buttonStyle(LargeRowButtonStyle(fill: fill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(control.rowLabel(for: content))
        .accessibilityHint(control.accessibilityHint(for: content))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(control.identifier)
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: min(iconSize, 44)))
            .foregroundStyle(.nook.accent)
            .accessibilityHidden(true)
    }
}

/// The row's fill, and a soft dim while it's pressed.
private struct LargeRowButtonStyle: ButtonStyle {
    let fill: LargeRowFill?

    func makeBody(configuration: Configuration) -> some View {
        let shape = NookRadius.shape(fill == nil ? NookRadius.group : NookRadius.sheet)
        configuration.label
            .background {
                if let fill {
                    shape.fill(fill.color)
                        .softShadow(.dropLarge, in: shape)
                }
            }
            .overlay {
                if configuration.isPressed {
                    shape.fill(Color.nook.textPrimary.opacity(0.08))
                }
            }
    }
}

/// A small caption over the row's main words. Both wrap; nothing is cut off.
struct LargeRowText: View {
    enum Style {
        /// The large-text rows (`.r small`, `.r b`).
        case large
        /// The smaller tiles beside the sideways room (`.tile small`, `.tile b`).
        case compact
    }

    let caption: String?
    let title: String
    var isQuiet = false
    var style: Style = .large

    var body: some View {
        if let caption {
            Text(caption)
                .nookTextStyle(style == .large ? .note : .finePrint)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text(title)
            .nookTextStyle(style == .large ? .headline : .label)
            .fontWeight(isQuiet ? .semibold : .bold)
            .foregroundStyle(isQuiet ? .nook.textSecondary : .nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Laundry" over "2 to wash", "All clean", or "Off · tap to learn more" in a quieter weight
/// (RD-11). A placeholder while the closet loads.
struct LaundryRowText: View {
    let hamper: HamperState?

    var body: some View {
        let caption = String(localized: "Laundry", bundle: .module, comment: "Caption on Home's Laundry row")
        switch hamper {
        case .off:
            LargeRowText(
                caption: caption,
                title: String(
                    localized: "Off · tap to learn more", bundle: .module,
                    comment: "Home's Laundry row while laundry tracking is off"),
                isQuiet: true)
        case .allClean, .toWash:
            LargeRowText(caption: caption, title: hamper?.plateText ?? "")
        case nil:
            LargeRowText(caption: caption, title: "All clean")
                .redacted(reason: .placeholder)
        }
    }
}

/// "17 pieces · Whole closet" under the source's name (`.pill`). A suitcase source is green with
/// a lock, an empty suitcase butter, so the strict suitcase scope stands out (PRD §7.7).
struct SourcePill: View {
    let source: SourcePlate

    private var tone: (fill: Color, text: Color) {
        guard source.isSuitcase else { return (.nook.tintStrong, .nook.textSecondary) }
        return source.pieceCount == 0 ? (.nook.warningSurface, .nook.warning) : (.nook.successSurface, .nook.success)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if source.isSuitcase {
                Image(systemName: "lock")
                    .accessibilityHidden(true)
            }
            Text(
                "\(source.countText ?? "00 pieces") · \(source.scopeText)", bundle: .module,
                comment: "Pill on Home's Source row: the piece count, then the scope"
            )
            .fixedSize(horizontal: false, vertical: true)
            .redacted(reason: source.countText == nil ? .placeholder : [])
        }
        .nookTextStyle(.chip)
        .foregroundStyle(tone.text)
        .padding(.vertical, 3)
        .padding(.leading, 9)
        .padding(.trailing, 11)
        .background(tone.fill, in: NookRadius.shape(NookRadius.plateSlim))
        .padding(.top, 3)
    }
}
