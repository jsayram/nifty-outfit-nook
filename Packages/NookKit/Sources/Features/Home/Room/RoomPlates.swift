import DesignSystem
import Models
import SwiftUI

/// A label plate that sits on a piece of furniture (`.tag` in the mockups): a near-white tint so
/// the words read over the drawing, soft corners and a shadow that falls only below. No edge.
struct RoomPlate<Content: View>: View {
    var radius: CGFloat = NookRadius.button
    var fill: Color = .nook.tintStrong
    var hasShadow = true
    @ViewBuilder var content: Content

    var body: some View {
        let shape = NookRadius.shape(radius)
        content
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(fill, in: shape)
            .softShadow(.drop, in: shape, isVisible: hasShadow)
    }
}

/// "Closet" on the wardrobe (`.closetp`).
struct ClosetPlate: View {
    var body: some View {
        RoomPlate {
            // At larger text sizes the chevron goes first, then the icon, so the word stays whole.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    icon
                    title
                    Spacer(minLength: 0)
                    chevron
                }
                HStack(spacing: 5) {
                    icon
                    title
                }
                title
            }
            .padding(.leading, 10)
            .padding(.trailing, 9)
        }
    }

    private var icon: some View {
        Image(systemName: "hanger")
            .font(.body)
            .foregroundStyle(.nook.accent)
    }

    private var title: some View {
        Text("Closet", bundle: .module, comment: "Plate on the wardrobe")
            .nookTextStyle(.label)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize()
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.nook.accent)
    }
}

/// "Source · Main closet" on the suitcase (`.srcp`).
struct SourceNamePlate: View {
    let source: SourcePlate

    var body: some View {
        RoomPlate {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text("Source", bundle: .module, comment: "Plate on the suitcase, above the source's name")
                        .nookTextStyle(.finePrint)
                        .foregroundStyle(.nook.textSecondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.nook.accent)
                }
                Text(source.name)
                    .nookTextStyle(.label)
                    .foregroundStyle(.nook.textPrimary)
            }
            .padding(.leading, 9)
            .padding(.trailing, 7)
        }
    }
}

/// "17 pieces · Whole closet" under the source plate (`.scopep`). A suitcase source is green,
/// an empty suitcase butter, so the strict suitcase scope stands out (PRD §7.7).
struct ScopePlate: View {
    let source: SourcePlate

    private var tone: (fill: Color, text: Color) {
        guard source.isSuitcase else { return (.nook.tintStrong, .nook.textPrimary) }
        return source.pieceCount == 0 ? (.nook.warningSurface, .nook.warning) : (.nook.successSurface, .nook.success)
    }

    var body: some View {
        RoomPlate(radius: 13, fill: tone.fill) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    if source.isSuitcase {
                        Image(systemName: "lock")
                            .font(.caption2.weight(.semibold))
                    }
                    Text(source.countText ?? "00 pieces")
                        .nookTextStyle(.chip)
                        .fontWeight(.bold)
                        .redacted(reason: source.countText == nil ? .placeholder : [])
                }
                Text(source.scopeText)
                    .nookTextStyle(.chip)
            }
            .foregroundStyle(tone.text)
            .padding(.leading, 9)
            .padding(.trailing, 8)
        }
    }
}

/// "Laundry · Off" on the hamper (`.laup`). Quiet when tracking is off (RD-11).
struct LaundryPlate: View {
    let hamper: HamperState?
    @Environment(\.colorScheme) private var colorScheme

    private var isOff: Bool { hamper == .off }

    /// Off is a fainter plate with no shadow. The faint tint vanishes on a dark wall, so dark
    /// keeps the strong tint and stays quiet through its text alone.
    private var fill: Color {
        isOff && colorScheme == .light ? .nook.tint : .nook.tintStrong
    }

    var body: some View {
        RoomPlate(radius: 13, fill: fill, hasShadow: !isOff) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Laundry", bundle: .module, comment: "Plate on the hamper")
                    .nookTextStyle(.finePrint)
                    .foregroundStyle(.nook.textSecondary)
                Text(hamper?.plateText ?? "All clean")
                    .nookTextStyle(.chip)
                    .fontWeight(isOff ? .semibold : .bold)
                    .foregroundStyle(isOff ? .nook.textSecondary : .nook.textPrimary)
                    .redacted(reason: hamper == nil ? .placeholder : [])
            }
            .padding(.leading, 9)
            .padding(.trailing, 6)
        }
    }
}

/// "Saved Looks" under the plant shelf (`.saved`, a soft accent plate).
struct SavedLooksPlate: View {
    var body: some View {
        RoomPlate(radius: 12, fill: .nook.accentSoft) {
            HStack(spacing: 5) {
                Image(systemName: "bookmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.nook.accent)
                Text("Saved Looks", bundle: .module, comment: "Plate on the shelf")
                    .nookTextStyle(.chip)
                    .fontWeight(.bold)
                    .foregroundStyle(.nook.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.nook.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
        }
    }
}

/// A desk drawer's plate (`.dplate`).
struct DrawerPlate: View {
    let title: String

    var body: some View {
        RoomPlate(radius: 9) {
            Text(title)
                .nookTextStyle(.chip)
                .fontWeight(.bold)
                .foregroundStyle(.nook.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
        }
    }
}

/// "Occasion" on the calendar's flat face (`.cal`). Words on drawn surfaces keep dark ink in
/// dark mode, because the art is dimmed, not inverted.
struct OccasionLabel: View {
    let occasion: Occasion?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.footnote.weight(.semibold))
                Text("Occasion", bundle: .module, comment: "Label on the calendar")
                    .nookTextStyle(.chip)
                    .fontWeight(.bold)
            }
            // The chosen occasion appears here once Style Me remembers one (Phase 10a).
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(.nook.signText)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "Style Me" on the laptop screen (`.styleme`). The screen is the dark espresso of the art in
/// both appearances, so the words stay white.
struct LaptopLabel: View {
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "sparkles")
                .font(.body.weight(.semibold))
            Text("Style Me", bundle: .module, comment: "Words on the laptop screen; opens Style Me")
                .nookTextStyle(.label)
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
