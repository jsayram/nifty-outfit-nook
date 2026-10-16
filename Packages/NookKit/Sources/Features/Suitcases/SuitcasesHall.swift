import DesignSystem
import Models
import SwiftUI

/// The entry hall at the top of Suitcases (`suitcases.html`): a door, hooks, a mirror and a
/// console on the wall, a runner on the floor, and her three favourites standing on it, the most
/// recently used in the middle (RD-09). Each has a luggage tag with its name and piece count in
/// live text; the chosen source's tag is the solid accent, with "Styling from this one" under it.
///
/// The hall is drawn in the mockup's units (a 390 x 450 box at 0.74) and the tags at full size,
/// so they never shrink. Tapping a tag or a suitcase chooses it, as the rows below do. The rows
/// are the controls VoiceOver and Voice Control use, so the hall is hidden from them.
struct SuitcasesHall: View {
    /// Up to three, most recently used first.
    let favorites: [Suitcase]
    let pieceCount: (Suitcase) -> Int
    let chosen: WardrobeSource
    let choose: (Suitcase) -> Void

    /// The hall's scale, as in the mockup.
    static let scale: CGFloat = 0.74
    /// The scene's height on the page, and where the floor starts in it.
    static let height: CGFloat = 362
    static let floorY: CGFloat = 240
    /// The hall box in hall units.
    static let box = CGSize(width: 390, height: 450)

    /// Where each favourite stands, left to right, in hall units: the most recently used in the
    /// middle, the next on the left, the third on the right.
    static let slots: [CGFloat] = [143, 14, 272]
    /// The suitcase drawings' size, and where their feet rest.
    static let caseSize = CGSize(width: 104, height: 182)
    static let floorLine: CGFloat = 415.4

    var body: some View {
        GeometryReader { proxy in
            let originX = (proxy.size.width - Self.box.width * Self.scale) / 2
            ZStack(alignment: .topLeading) {
                background
                    .frame(height: Self.height)
                hallArt
                    .frame(width: Self.box.width, height: Self.box.height, alignment: .topLeading)
                    .scaleEffect(Self.scale, anchor: .topLeading)
                    .offset(x: originX)
                ForEach(Array(favorites.prefix(3).enumerated()), id: \.element.id) { index, suitcase in
                    tag(for: suitcase, slot: Self.slots[index], originX: originX)
                }
                if let index = favorites.prefix(3).firstIndex(where: { chosen == .suitcase($0.id) }) {
                    usingPill
                        .position(
                            x: originX + (Self.slots[index] + 48) * Self.scale,
                            y: 347)
                }
            }
            .frame(width: proxy.size.width, height: Self.height, alignment: .topLeading)
        }
        .frame(height: Self.height)
        .clipped()
        .accessibilityHidden(true)
    }

    private var background: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.floorY)
            Rectangle().fill(Color.nook.floorLine).frame(height: 2)
            Color.nook.floor
        }
    }

    /// The hall, back to front, in hall units.
    private var hallArt: some View {
        ZStack(alignment: .topLeading) {
            art(.hallDoor, CGRect(x: 117, y: 11, width: 156, height: 322))
            art(.hallHooks, CGRect(x: 12, y: 57.5, width: 104, height: 90))
            art(.hallPeg, CGRect(x: 42, y: 64, width: 12, height: 12))
            art(.hallMirror, CGRect(x: 300, y: 50, width: 64, height: 78))
            art(.hallConsole, CGRect(x: 276, y: 158, width: 112, height: 174))
            art(.hallRunner, CGRect(x: 9, y: 342, width: 372, height: 108))
            ForEach(Array(favorites.prefix(3).enumerated()), id: \.element.id) { index, suitcase in
                Button {
                    choose(suitcase)
                } label: {
                    RoomArtImage(suitcase.icon.art)
                }
                .buttonStyle(ClosetPressStyle())
                .frame(width: Self.caseSize.width, height: Self.caseSize.height)
                .offset(x: Self.slots[index], y: Self.floorLine - Self.caseSize.height)
            }
        }
    }

    private func art(_ art: RoomArt, _ rect: CGRect) -> some View {
        RoomArtImage(art)
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }

    /// A luggage tag hanging on the suitcase's face, where its strap ends.
    private func tag(for suitcase: Suitcase, slot: CGFloat, originX: CGFloat) -> some View {
        let top = (Self.floorLine - Self.caseSize.height + 30) * Self.scale
        let centerX = originX + (slot + 48) * Self.scale
        return Button {
            choose(suitcase)
        } label: {
            LuggageTag(
                name: suitcase.name, detail: SuitcasesText.pieces(pieceCount(suitcase)),
                isChosen: chosen == .suitcase(suitcase.id))
        }
        .buttonStyle(ClosetPressStyle())
        .position(x: centerX, y: top + LuggageTag.size.height / 2)
        .accessibilityIdentifier("suitcases.hall.\(suitcase.id.rawValue)")
    }

    private var usingPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
            Text("Styling from this one", bundle: .module, comment: "Under the chosen suitcase in the hall")
                .nookTextStyle(.caption)
                .fontWeight(.bold)
        }
        .foregroundStyle(.nook.accent)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background {
            Capsule().fill(Color.nook.tintStrong)
                .softShadow(.drop, in: Capsule())
        }
        .fixedSize()
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// A luggage tag (`.ltag`): a white tag with clipped top corners, a bit of strap into its
/// eyelet, the name and a line under it. The chosen one is the solid accent. Fixed size, so the
/// words shrink a little rather than grow past it.
struct LuggageTag: View {
    let name: String
    let detail: String
    let isChosen: Bool

    static let size = CGSize(width: 88, height: 46)

    var body: some View {
        VStack(spacing: 0) {
            Text(name)
                .nookTextStyle(.chip)
                .fontWeight(.bold)
                .foregroundStyle(isChosen ? Color.nook.onAccent : Color.nook.textPrimary)
            Text(detail)
                .nookTextStyle(.finePrint)
                .foregroundStyle(isChosen ? Color.nook.onAccent.opacity(0.85) : Color.nook.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background {
            TagShape()
                .fill(isChosen ? Color.nook.accent : Color.nook.surface)
                .softShadow(.drop, in: TagShape())
        }
        .overlay(alignment: .top) {
            // The strap's last bit and the eyelet it's threaded through.
            ZStack {
                Capsule().fill(Color(red: 0.73, green: 0.53, blue: 0.20)).frame(width: 3.8, height: 8)
                Circle().fill(Color.nook.artButter).frame(width: 8, height: 8).offset(y: 7)
                Circle().fill(Color(red: 0.91, green: 0.74, blue: 0.43)).frame(width: 4, height: 4).offset(y: 7)
            }
            .offset(y: -2)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// The tag's outline: square at the bottom, the top corners clipped (`M8 0H80L88 8V42…`).
private struct TagShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cut = rect.width * 8 / 88
        let round = rect.height * 4 / 46
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - round))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - round, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + round, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - round), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        path.closeSubpath()
        return path
    }
}
