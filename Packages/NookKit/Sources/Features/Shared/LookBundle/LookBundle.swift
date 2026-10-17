import DesignSystem
import Models
import SwiftUI

/// How big a look bundle is drawn. The bundle keeps the mockups' 300 x 356 shape at every size.
struct LookBundleSize: Hashable {
    /// The width in points.
    let width: CGFloat

    init(width: CGFloat) {
        self.width = width
    }

    var height: CGFloat { width / StickerBundleLayout.aspectRatio }

    /// Thumbnails show a small tag icon instead of words on an idea piece, and never animate in.
    var isThumbnail: Bool { width < 120 }

    /// The open look on results and look detail (`results.html`, 300 x 356).
    static let large = Self(width: 300)
    /// A saved look in a list or grid.
    static let medium = Self(width: 168)
    /// The other versions on results, and pictures' links back to their look (`.thumb`).
    static let small = Self(width: 64)
}

/// A look as a sticker bundle (RD-07): her pieces cut out with a white sticker edge, laid out
/// where they're worn, slightly tilted and overlapping. No tiles, no hangers. The one view used
/// wherever a look appears: results, Saved Looks, look detail and swap.
///
/// - Pieces come through `GarmentPicture`, so a clean cutout is a sticker, a photo without one
///   is a rounded tile in the same space (RD-07.2), and a piece with no photo is its drawing.
/// - An idea piece she doesn't own (LR-05b) is drawn from its kind and colours and carries a
///   soft "Not in your closet" tag; thumbnails show just the tag icon.
/// - A piece of hers that has since left her closet is faded (LR-16.4).
/// - The layout (`StickerBundleLayout`) is seeded by the look's ID, so a look lies the same way
///   on every screen and launch.
/// - VoiceOver reads the bundle as one element that names the pieces in body order, with each
///   piece's kind and name as custom content (the More Content rotor). Each piece is also in
///   `LookPieceList` under the bundle (RD-07.3).
/// - With `animatesEntrance`, the pieces settle into place one after another. Under Reduce
///   Motion they only fade in, with no tilt or movement (RD-07.4). Thumbnails and still images
///   never animate.
struct LookBundle: View {
    let content: LookBundleContent
    let size: LookBundleSize
    /// What VoiceOver calls the look before naming its pieces, such as "Simple" or "Look 2".
    /// The look's name, or "Look", when not given.
    let title: String?
    let animatesEntrance: Bool
    /// The piece being changed in Swap a piece (Phase 11): the others step back, as in
    /// `swap.html`. `nil` shows every piece the same.
    let focusedPieceID: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.closetIsStillImage) private var isStillImage
    @Environment(\.locale) private var locale
    @State private var hasSettled = false

    init(
        _ content: LookBundleContent, size: LookBundleSize, title: String? = nil, animatesEntrance: Bool = false,
        focusedPieceID: String? = nil
    ) {
        self.content = content
        self.size = size
        self.title = title
        self.animatesEntrance = animatesEntrance
        self.focusedPieceID = focusedPieceID
    }

    private var isSettled: Bool {
        hasSettled || !animatesEntrance || isStillImage || size.isThumbnail
    }

    var body: some View {
        let placements = StickerBundleLayout.place(content.pieces.map(\.role), seed: content.layoutSeed)
        ZStack(alignment: .topLeading) {
            ForEach(placements, id: \.index) { placement in
                piece(content.pieces[placement.index], placement: placement)
            }
            ForEach(placements.filter { content.pieces[$0.index].isIdea }, id: \.index) { placement in
                ideaTag(at: placement.frame(forWidth: size.width))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onAppear {
            if !isSettled { hasSettled = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LookBundleText.summary(of: content, title: title, locale: locale)))
        .modifier(PieceCustomContent(pieces: content.pieces))
        .accessibilityIdentifier("lookBundle.\(content.id)")
    }

    private func piece(_ piece: LookBundlePiece, placement: BundlePlacement) -> some View {
        let frame = placement.frame(forWidth: size.width)
        let settled = isSettled
        // Under Reduce Motion the pieces only fade: no tilt, rise or scale is animated.
        let moves = !settled && !reduceMotion
        return GarmentPicture(
            photo: piece.photo, cutout: piece.cutout, category: piece.category, colors: piece.colors,
            size: frame.size, presentation: .sticker(.centred)
        )
        .rotationEffect(.degrees(moves ? placement.angle * 2.4 : placement.angle))
        .scaleEffect(moves ? 0.94 : 1)
        .offset(y: moves ? -10 : 0)
        .opacity(settled ? restingOpacity(of: piece) : 0)
        .animation(entrance(order: placement.zIndex), value: settled)
        .position(x: frame.midX, y: frame.midY)
        .zIndex(placement.zIndex)
    }

    /// Pieces step back while another is being swapped, and a piece that has left her closet
    /// stays faded (LR-16.4). The words say so too: the list under the bundle and VoiceOver.
    private func restingOpacity(of piece: LookBundlePiece) -> Double {
        if let focusedPieceID, focusedPieceID != piece.id { return Self.steppedBack }
        return piece.isRemoved ? Self.steppedBack : 1
    }

    static let steppedBack = 0.42

    /// Back to front, a little apart, so the bundle is laid down piece by piece.
    private func entrance(order: Double) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.25)
            : .spring(response: 0.45, dampingFraction: 0.78).delay(order * 0.05)
    }

    @ViewBuilder
    private func ideaTag(at frame: CGRect) -> some View {
        if size.isThumbnail {
            // A small round tag by the piece's top corner.
            BundleTagLayout(centre: CGPoint(x: frame.maxX - 6, y: frame.minY + 6)) {
                IdeaTagIcon(diameter: 16)
            }
            .frame(width: size.width, height: size.height)
            .zIndex(100)
            .opacity(isSettled ? 1 : 0)
        } else {
            // Across the piece's lower half, as in `results-versions.html`.
            BundleTagLayout(centre: CGPoint(x: frame.midX, y: frame.maxY - frame.height * 0.22)) {
                IdeaTag()
            }
            .frame(width: size.width, height: size.height)
            .zIndex(100)
            .opacity(isSettled ? 1 : 0)
            .animation(entrance(order: 6), value: isSettled)
        }
    }
}

/// Each piece's kind and name as VoiceOver custom content, so the More Content rotor steps
/// through the pieces one at a time.
private struct PieceCustomContent: ViewModifier {
    let pieces: [LookBundlePiece]

    func body(content: Content) -> some View {
        pieces.reduce(AnyView(content)) { view, piece in
            AnyView(
                view.accessibilityCustomContent(
                    AccessibilityCustomContentKey(Text(piece.category.singularTitle), id: piece.id),
                    Text(LookBundleText.spokenName(of: piece))
                ))
        }
    }
}

/// Places one view centred on a point, moved just enough to stay inside the bounds.
struct BundleTagLayout: Layout {
    let centre: CGPoint

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let origin = Self.origin(for: size, centredOn: centre, in: bounds.size)
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: ProposedViewSize(size))
        }
    }

    /// The top-left corner for a view of `size` centred on `centre`, kept inside `bounds`.
    nonisolated static func origin(for size: CGSize, centredOn centre: CGPoint, in bounds: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(0, centre.x - size.width / 2), max(0, bounds.width - size.width)),
            y: min(max(0, centre.y - size.height / 2), max(0, bounds.height - size.height)))
    }
}

/// The soft tag on an idea piece: words on a plate with a shadow below, no outline
/// (`.newtag` in `results-versions.html`). On one line, or the thumbnails' round icon when one
/// line doesn't fit across the bundle: wrapped onto two lines it covered the picture of a narrow
/// card on iPad (QA, October 2026).
struct IdeaTag: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            words
            IdeaTagIcon(diameter: 24)
        }
    }

    private var words: some View {
        HStack(spacing: NookSpacing.xSmall) {
            Image(systemName: "tag")
                .accessibilityHidden(true)
            Text(LookBundleText.notInYourCloset)
                .lineLimit(1)
        }
        .fixedSize()
        .nookTextStyle(.caption)
        .fontWeight(.bold)
        .foregroundStyle(.nook.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.nook.surface, in: Capsule())
        .softShadow(.drop, in: Capsule())
        // It sits on the picture, so it stops growing where it would cover the bundle. The words
        // are in the list under the bundle and in what VoiceOver reads, at any size.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .allowsHitTesting(false)
    }
}

/// The idea tag on a thumbnail: the tag icon on a small round plate.
struct IdeaTagIcon: View {
    let diameter: CGFloat

    var body: some View {
        Image(systemName: "tag.fill")
            .font(.system(size: diameter * 0.5, weight: .bold))
            .foregroundStyle(.nook.accent)
            .frame(width: diameter, height: diameter)
            .background(Color.nook.surface, in: Circle())
            .softShadow(.drop, in: Circle())
            .allowsHitTesting(false)
    }
}
