import DesignSystem
import Models
import SwiftUI

/// A simple drawing of a kind of piece, for garments that have no photo yet.
///
/// Stage A has no real photos, so every piece shows its kind's outline filled with its own colour
/// (Phase 6). When photos arrive (Phases 7b, 8b, 22) the photo replaces it and this stays for
/// pieces added by words only. The shapes are drawn in a 100 x 128 box, as a hanging piece or a
/// piece standing on the floor would sit, and scale to the frame.
nonisolated struct GarmentSilhouette: Shape {
    let category: GarmentCategory

    static let designSize = CGSize(width: 100, height: 128)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch category {
        case .top: Self.top(&path)
        case .bottom: Self.bottom(&path)
        case .dress: Self.dress(&path)
        case .layer: Self.layer(&path)
        case .shoes: Self.shoes(&path)
        case .bag: Self.bag(&path)
        case .accessory: Self.accessory(&path)
        }
        return path.applying(Self.transform(into: rect))
    }

    /// Scales the design box into `rect`, keeping its proportions and centring it.
    static func transform(into rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width / designSize.width, rect.height / designSize.height)
        let x = rect.minX + (rect.width - designSize.width * scale) / 2
        let y = rect.minY + (rect.height - designSize.height * scale) / 2
        return CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale)
    }

    // MARK: Outlines

    /// A short-sleeved top.
    private static func top(_ p: inout Path) {
        p.move(to: CGPoint(x: 38, y: 14))
        p.addQuadCurve(to: CGPoint(x: 62, y: 14), control: CGPoint(x: 50, y: 24))
        p.addLine(to: CGPoint(x: 80, y: 20))
        p.addLine(to: CGPoint(x: 97, y: 48))
        p.addLine(to: CGPoint(x: 83, y: 56))
        p.addLine(to: CGPoint(x: 78, y: 48))
        p.addLine(to: CGPoint(x: 79, y: 112))
        p.addQuadCurve(to: CGPoint(x: 21, y: 112), control: CGPoint(x: 50, y: 116))
        p.addLine(to: CGPoint(x: 22, y: 48))
        p.addLine(to: CGPoint(x: 17, y: 56))
        p.addLine(to: CGPoint(x: 3, y: 48))
        p.addLine(to: CGPoint(x: 20, y: 20))
        p.closeSubpath()
    }

    /// Trousers, hanging full length.
    private static func bottom(_ p: inout Path) {
        p.move(to: CGPoint(x: 24, y: 6))
        p.addLine(to: CGPoint(x: 76, y: 6))
        p.addLine(to: CGPoint(x: 86, y: 122))
        p.addLine(to: CGPoint(x: 56, y: 122))
        p.addLine(to: CGPoint(x: 50, y: 44))
        p.addLine(to: CGPoint(x: 44, y: 122))
        p.addLine(to: CGPoint(x: 14, y: 122))
        p.closeSubpath()
    }

    /// A dress with a fitted waist and a flared skirt.
    private static func dress(_ p: inout Path) {
        p.move(to: CGPoint(x: 38, y: 6))
        p.addQuadCurve(to: CGPoint(x: 62, y: 6), control: CGPoint(x: 50, y: 18))
        p.addLine(to: CGPoint(x: 72, y: 10))
        p.addLine(to: CGPoint(x: 68, y: 30))
        p.addLine(to: CGPoint(x: 65, y: 50))
        p.addLine(to: CGPoint(x: 90, y: 118))
        p.addQuadCurve(to: CGPoint(x: 10, y: 118), control: CGPoint(x: 50, y: 126))
        p.addLine(to: CGPoint(x: 35, y: 50))
        p.addLine(to: CGPoint(x: 32, y: 30))
        p.addLine(to: CGPoint(x: 28, y: 10))
        p.closeSubpath()
    }

    /// A long-sleeved jacket or cardigan.
    private static func layer(_ p: inout Path) {
        p.move(to: CGPoint(x: 39, y: 8))
        p.addLine(to: CGPoint(x: 50, y: 40))
        p.addLine(to: CGPoint(x: 61, y: 8))
        p.addLine(to: CGPoint(x: 80, y: 14))
        p.addQuadCurve(to: CGPoint(x: 92, y: 30), control: CGPoint(x: 90, y: 18))
        p.addLine(to: CGPoint(x: 97, y: 108))
        p.addLine(to: CGPoint(x: 85, y: 110))
        p.addLine(to: CGPoint(x: 79, y: 48))
        p.addLine(to: CGPoint(x: 80, y: 118))
        p.addLine(to: CGPoint(x: 20, y: 118))
        p.addLine(to: CGPoint(x: 21, y: 48))
        p.addLine(to: CGPoint(x: 15, y: 110))
        p.addLine(to: CGPoint(x: 3, y: 108))
        p.addLine(to: CGPoint(x: 8, y: 30))
        p.addQuadCurve(to: CGPoint(x: 20, y: 14), control: CGPoint(x: 10, y: 18))
        p.closeSubpath()
    }

    /// A loafer seen from the side: a low heel at the back, the opening, and a rounded toe.
    private static func shoes(_ p: inout Path) {
        p.move(to: CGPoint(x: 8, y: 110))
        p.addLine(to: CGPoint(x: 7, y: 88))
        p.addQuadCurve(to: CGPoint(x: 18, y: 80), control: CGPoint(x: 7, y: 80))
        p.addQuadCurve(to: CGPoint(x: 48, y: 88), control: CGPoint(x: 32, y: 90))
        p.addQuadCurve(to: CGPoint(x: 80, y: 88), control: CGPoint(x: 64, y: 78))
        p.addQuadCurve(to: CGPoint(x: 95, y: 104), control: CGPoint(x: 95, y: 92))
        p.addQuadCurve(to: CGPoint(x: 88, y: 110), control: CGPoint(x: 96, y: 110))
        p.closeSubpath()
    }

    /// A handbag with a top handle.
    private static func bag(_ p: inout Path) {
        p.addRoundedRect(
            in: CGRect(x: 12, y: 58, width: 76, height: 56), cornerSize: CGSize(width: 12, height: 12),
            style: .continuous)
        // The handle, as a thick band so it fills like the bag.
        p.move(to: CGPoint(x: 28, y: 60))
        p.addCurve(to: CGPoint(x: 72, y: 60), control1: CGPoint(x: 28, y: 22), control2: CGPoint(x: 72, y: 22))
        p.addLine(to: CGPoint(x: 64, y: 60))
        p.addCurve(to: CGPoint(x: 36, y: 60), control1: CGPoint(x: 64, y: 33), control2: CGPoint(x: 36, y: 33))
        p.closeSubpath()
    }

    /// A wide-brimmed hat, the stand-in for scarves, belts and hats.
    private static func accessory(_ p: inout Path) {
        p.addEllipse(in: CGRect(x: 4, y: 86, width: 92, height: 22))
        p.move(to: CGPoint(x: 28, y: 94))
        p.addCurve(to: CGPoint(x: 72, y: 94), control1: CGPoint(x: 26, y: 56), control2: CGPoint(x: 74, y: 56))
        p.closeSubpath()
    }
}

/// The detail on a piece (a waistband, a belt, a button placket, a sole, a flap), drawn in its
/// second colour if it has one.
nonisolated struct GarmentDetail: Shape {
    let category: GarmentCategory

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch category {
        case .top:
            p.move(to: CGPoint(x: 21.5, y: 100))
            p.addLine(to: CGPoint(x: 78.5, y: 100))
            p.addLine(to: CGPoint(x: 79, y: 112))
            p.addQuadCurve(to: CGPoint(x: 21, y: 112), control: CGPoint(x: 50, y: 116))
            p.closeSubpath()
        case .bottom:
            p.addRect(CGRect(x: 24, y: 6, width: 52, height: 10))
        case .dress:
            p.addRect(CGRect(x: 34, y: 46, width: 32, height: 7))
        case .layer:
            p.move(to: CGPoint(x: 47, y: 36))
            p.addLine(to: CGPoint(x: 53, y: 36))
            p.addLine(to: CGPoint(x: 53, y: 118))
            p.addLine(to: CGPoint(x: 47, y: 118))
            p.closeSubpath()
        case .shoes:
            // The sole, and the opening where the foot goes.
            p.addRect(CGRect(x: 8, y: 105, width: 82, height: 5))
            p.move(to: CGPoint(x: 15, y: 83))
            p.addQuadCurve(to: CGPoint(x: 46, y: 89), control: CGPoint(x: 30, y: 92))
            p.addQuadCurve(to: CGPoint(x: 15, y: 83), control: CGPoint(x: 30, y: 84))
            p.closeSubpath()
        case .bag:
            p.move(to: CGPoint(x: 12, y: 70))
            p.addQuadCurve(to: CGPoint(x: 24, y: 58), control: CGPoint(x: 12, y: 58))
            p.addLine(to: CGPoint(x: 76, y: 58))
            p.addQuadCurve(to: CGPoint(x: 88, y: 70), control: CGPoint(x: 88, y: 58))
            p.addLine(to: CGPoint(x: 88, y: 80))
            p.addQuadCurve(to: CGPoint(x: 12, y: 80), control: CGPoint(x: 50, y: 94))
            p.closeSubpath()
        case .accessory:
            p.move(to: CGPoint(x: 28.5, y: 86))
            p.addLine(to: CGPoint(x: 71.5, y: 86))
            p.addLine(to: CGPoint(x: 72, y: 94))
            p.addLine(to: CGPoint(x: 28, y: 94))
            p.closeSubpath()
        }
        return p.applying(GarmentSilhouette.transform(into: rect))
    }
}

/// The placeholder picture for a piece with no photo: its kind's outline in its own colours,
/// with a soft contact shadow under it, like the pieces standing on the floor in `closet.html`.
/// Cheap to draw: two filled paths and a stroke, no blur.
struct GarmentPlaceholderArt: View {
    let category: GarmentCategory
    let colors: [ColorName]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let main = colors.first.map(GarmentColor.fill(for:)) ?? .unknown
        let second = colors.dropFirst().first.map(GarmentColor.fill(for:)) ?? main.scaled(0.86)
        ZStack {
            if colors.first == .multicolor {
                GarmentSilhouette(category: category).fill(Self.stripes(colorScheme))
            } else {
                GarmentSilhouette(category: category).fill(main.color(in: colorScheme))
            }
            GarmentDetail(category: category).fill(second.color(in: colorScheme))
            GarmentSilhouette(category: category)
                .stroke(main.line.color(in: colorScheme), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        }
        .aspectRatio(GarmentSilhouette.designSize, contentMode: .fit)
    }

    private static func stripes(_ scheme: ColorScheme) -> LinearGradient {
        let colours = GarmentColor.multicolorStripes.map { $0.color(in: scheme) }
        var stops: [Gradient.Stop] = []
        for (index, colour) in colours.enumerated() {
            let start = Double(index) / Double(colours.count)
            let end = Double(index + 1) / Double(colours.count)
            stops.append(Gradient.Stop(color: colour, location: start))
            stops.append(Gradient.Stop(color: colour, location: end))
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }
}

/// An idea for a piece she doesn't own (LR-05b), in a look bundle: its kind's outline filled
/// softly in its colour, with a dashed edge. Among her photo stickers a full drawing looked like a
/// cartoon pretending to be a photo (real-photo audit, 17 October 2026); this reads as a
/// suggestion. VoiceOver and the list under the bundle name it.
struct IdeaSilhouette: View {
    let category: GarmentCategory
    let colors: [ColorName]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let main = colors.first.map(GarmentColor.fill(for:)) ?? .unknown
        ZStack {
            GarmentSilhouette(category: category)
                .fill(main.color(in: colorScheme).opacity(0.5))
            GarmentSilhouette(category: category)
                .stroke(
                    Color.nook.accent,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [4, 3]))
        }
        .aspectRatio(GarmentSilhouette.designSize, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The soft oval shadow a piece stands on (`.gcard::before` in `closet.html`). A gradient, not a
/// blur, so a long grid stays cheap to scroll.
struct GarmentContactShadow: View {
    var body: some View {
        Ellipse()
            .fill(
                EllipticalGradient(
                    colors: [Color.nook.shadow, Color.nook.shadow.opacity(0)], center: .center,
                    startRadiusFraction: 0, endRadiusFraction: 0.5)
            )
            .accessibilityHidden(true)
    }
}
