import DesignSystem
import Models
import SwiftUI

/// The top of the desk-drawer screens, Help, Send feedback and Privacy and terms (RD-10,
/// `help.html`, `feedback.html`, `privacy.html`): the title in display type with a line under it
/// on the wall, and the desk's three drawers as a small chest standing on the floor at the right,
/// with this screen's drawer pulled open. Accessibility and Delete my data use it without a
/// drawing.
///
/// At the accessibility sizes the chest is left out and the title steps down one style, so the
/// words get the whole width and never break mid-word (playbook, Phase 14a).
struct SettingsHeader: View {
    let title: String
    let lede: String
    /// The chest with this screen's drawer open, or `nil` for a plain wall.
    var art: RoomArt?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// `acct-drawers-*.svg` (`.chest` in the mockups).
    static let artSize = CGSize(width: 136, height: 156)
    /// The chest's feet end at y 148 in its 156-unit drawing; the rest is its contact shadow.
    static let feet: CGFloat = 148
    static let floorBand: CGFloat = 16

    private var showsArt: Bool { art != nil && !dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        HStack(alignment: .top, spacing: NookSpacing.small) {
            VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
                Text(title)
                    .nookTextStyle(dynamicTypeSize.isAccessibilitySize ? .title : .display)
                    .foregroundStyle(.nook.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(lede)
                    .nookTextStyle(.label)
                    .fontWeight(.regular)
                    .foregroundStyle(.nook.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, NookSpacing.small)
            .padding(.bottom, NookSpacing.xLarge)
            if showsArt, let art {
                // The chest stands on the floor: its column reaches the floor line, and the
                // drawing hangs a little below it so the feet land just past the line, as in the
                // mockups.
                VStack(spacing: 0) {
                    Spacer(minLength: NookSpacing.medium)
                    RoomArtImage(art)
                        .frame(width: Self.artSize.width, height: Self.artSize.height)
                        .offset(y: Self.artSize.height - Self.feet + 2)
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.leading, NookSpacing.xLarge)
        .padding(.trailing, showsArt ? NookSpacing.medium : NookSpacing.xLarge)
        // The title and the chest line up with the rows below on a wide window.
        .readablePane()
        .background(Color.nook.wallGradient)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.nook.floorLine)
                .frame(height: 2)
                .offset(y: 2)
                .accessibilityHidden(true)
        }
        .padding(.bottom, Self.floorBand)
    }
}

/// A desk-drawer or settings screen: the header on the wall, then its content on the floor, at
/// a comfortable reading width. It scrolls, except in snapshot tests, which draw the whole page.
struct SettingsPage<Content: View>: View {
    let header: SettingsHeader
    @ViewBuilder let content: Content

    @Environment(\.closetIsStillImage) private var isStillImage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if isStillImage {
            page
                .background(Color.nook.floor)
        } else {
            ScrollView(.vertical) {
                page
            }
            .background(FloorBackground())
        }
    }

    private var page: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: NookSpacing.groupGap) {
                content
            }
            // As on Profile, rows take a little more of the width at the accessibility sizes.
            .padding(
                .horizontal, dynamicTypeSize.isAccessibilitySize ? NookSpacing.small : NookSpacing.screenMargin
            )
            .padding(.top, NookSpacing.small)
            .padding(.bottom, NookSpacing.xxxLarge)
            .readablePane()
            .background(Color.nook.floor)
        }
    }
}

/// A group of rows or words on the floor, with an optional header, on the soft tint (as Profile's
/// groups are).
struct SettingsGroup<Rows: View>: View {
    var header: String?
    var identifier: String?
    @ViewBuilder let rows: Rows

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
            if let header {
                NookSectionHeader(header)
                    .padding(.horizontal, NookSpacing.small)
                    .padding(.top, NookSpacing.xSmall)
                    .padding(.bottom, NookSpacing.xxSmall)
            }
            rows
        }
        .padding(.vertical, NookSpacing.xSmall)
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 0 : NookSpacing.xSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floorCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier ?? "")
    }
}

/// A short note under or inside a group, in secondary text. On the floor it needs the tint
/// behind it (DesignSystem README, "Contrast"), which `SettingsGroup` gives.
struct SettingsNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NookSpacing.medium)
            .padding(.vertical, NookSpacing.xSmall)
    }
}

/// A row that only tells something (no tap): an icon, a title and a line or two under it, with
/// an optional value. One VoiceOver element.
struct SettingsInfoRow: View {
    let title: String
    var detail: String?
    var value: String?
    let systemImage: String

    var body: some View {
        NookRow(title, subtitle: detail, value: value, systemImage: systemImage)
    }
}

/// A switch in a row (Track laundry on Profile, Include app details on Send feedback): the row's
/// icon and words, with the system switch at the end, which VoiceOver reads as one switch with
/// its state.
///
/// Snapshot tests can't draw the system switch (`ImageRenderer` shows a placeholder), so there
/// it's a drawing of one in the same place.
struct SettingsSwitchRow: View {
    let title: String
    var detail: String?
    let systemImage: String
    let isOn: Bool
    let identifier: String
    let set: @MainActor @Sendable (Bool) -> Void

    @Environment(\.closetIsStillImage) private var isStillImage

    var body: some View {
        if isStillImage {
            HStack(spacing: 0) {
                label
                DrawnSwitch(isOn: isOn)
                    .padding(.trailing, NookSpacing.medium)
            }
        } else {
            Toggle(isOn: Binding(get: { isOn }, set: { set($0) })) {
                label
            }
            .tint(.nook.accent)
            .padding(.trailing, NookSpacing.medium)
            .accessibilityIdentifier(identifier)
        }
    }

    private var label: some View {
        NookRow(title, subtitle: detail, systemImage: systemImage)
    }
}

/// The system switch as a still drawing, for snapshot tests.
private struct DrawnSwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color.nook.accent : Color.nook.track)
            .frame(width: 51, height: 31)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 27, height: 27)
                    .padding(2)
            }
            .fixedSize()
            .accessibilityHidden(true)
    }
}
