import DesignSystem
import Models
import SwiftUI

/// The welcome (`onboarding.html`): the front door of the home, seen from the porch on a calm day,
/// with "Welcome home" in the sky and Get started on the porch.
///
/// From top to bottom: the sky with the title, the line under it and the clouds; the house front
/// (roof edge, siding, the door with its lantern, mat and pots, a plant, the peg rail with a coat
/// and the bench with sneakers); then the porch with the two buttons. The sky, siding, roof and
/// porch run the full width of the window, and the door and its props sit in the mockup's
/// 390-point stage in the middle, so a wide window lets the scene breathe instead of stretching it
/// (the mockup's own note). The stage grows to fill the height between the words and the buttons,
/// between 0.6 and 1.6 times. With large text the words take the room they need and the stage
/// gets smaller. At the accessibility sizes the buttons come right after the words and the porch
/// follows, small, so Get started is on the first screen; the page scrolls for the rest.
///
/// VoiceOver reads the title, the line, Get started and I already use Nifty Outfit Nook. The
/// drawing is decoration. Nothing moves, so Reduce Motion has nothing to change.
struct WelcomeView: View {
    let getStarted: () -> Void
    let alreadyUsing: () -> Void
    var isWorking = false
    /// Under the buttons when finishing didn't work.
    var problem: String?
    /// False in Release, which ships no sample closet (Phase 20a).
    var offersSampleCloset = true

    @Environment(\.closetIsStillImage) private var isStillImage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if isStillImage {
            // Snapshot tests: the page at the size they propose, without the scroll view.
            GeometryReader { proxy in
                page(height: proxy.size.height)
            }
            .background(Color.nook.floor)
        } else {
            GeometryReader { proxy in
                ScrollView(.vertical) {
                    page(height: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .background {
                    // The sky behind the status bar, and the porch everywhere else.
                    VStack(spacing: 0) {
                        Color.nook.skyTop.frame(height: proxy.safeAreaInsets.top)
                        Color.nook.floor
                    }
                    .ignoresSafeArea()
                }
            }
        }
    }

    @ViewBuilder
    private func page(height: CGFloat) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            // At the accessibility sizes the words alone fill most of the screen, so the buttons
            // come straight after them, where she can reach them without scrolling, and the
            // porch follows as decoration.
            VStack(spacing: 0) {
                sky
                buttons
                    .background(Color.nook.floor)
                PorchScene()
                    .frame(height: PorchScene.minimumHeight)
            }
            .frame(minHeight: height, alignment: .top)
            // Its own height, even where the space offered is smaller (a still image).
            .fixedSize(horizontal: false, vertical: true)
        } else {
            WelcomeStack(height: height) {
                sky
                PorchScene()
                buttons
            }
        }
    }

    private var sky: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            Text(OnboardingText.welcomeTitle)
                .nookTextStyle(.display)
                .foregroundStyle(.nook.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("welcome.title")
            Text(OnboardingText.welcomeLede)
                .nookTextStyle(.body)
                .foregroundStyle(.nook.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, NookSpacing.xLarge)
        .padding(.top, NookSpacing.small)
        .padding(.bottom, NookSpacing.large)
        .frame(maxWidth: WelcomeStack.columnWidth)
        .background(alignment: .topTrailing) {
            // Beside the title, as in the mockup (its stage x 290, y 44, two points above the title).
            RoomArtImage(.welcomeClouds)
                .frame(width: 96, height: 96)
                .offset(x: -4, y: -2)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .background(Color.nook.skyGradient)
    }

    private var buttons: some View {
        VStack(spacing: NookSpacing.xxSmall) {
            NookButton(OnboardingText.getStarted, isLoading: isWorking, fillsWidth: true, action: getStarted)
                .accessibilityIdentifier("welcome.getStarted")
            NookButton(OnboardingText.alreadyUsing, kind: .text, fillsWidth: true, action: alreadyUsing)
                .accessibilityHint(
                    Text(offersSampleCloset ? OnboardingText.alreadyUsingHint : OnboardingText.alreadyUsingEmptyHint)
                )
                .accessibilityIdentifier("welcome.alreadyUsing")
                .disabled(isWorking)
            if let problem {
                FieldProblemNote(message: problem)
            }
        }
        .padding(.horizontal, NookSpacing.large)
        .padding(.top, NookSpacing.xLarge)
        .padding(.bottom, NookSpacing.small)
        .frame(maxWidth: WelcomeStack.columnWidth)
        .frame(maxWidth: .infinity)
    }
}

/// Stacks the welcome's three parts: the sky at the height its words need, the buttons at the
/// height they need, and the porch scene in the rest of `height`, never less than
/// `PorchScene.minimumHeight`. Taller than `height` only when the words are very large, and then
/// the page scrolls.
///
/// A layout rather than measured state, so a still image (`ImageRenderer`, one pass) comes out
/// the same as the screen.
struct WelcomeStack: Layout {
    /// The height to fill: the window between its safe areas.
    let height: CGFloat

    /// The column the words and buttons keep to, centred on a wide window (iPad).
    nonisolated static let columnWidth: CGFloat = 520

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? WelcomeStack.columnWidth
        let parts = heights(width: width, subviews: subviews)
        return CGSize(width: width, height: parts.sky + parts.scene + parts.buttons)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let parts = heights(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (subview, height) in zip(subviews, [parts.sky, parts.scene, parts.buttons]) {
            subview.place(
                at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height
        }
    }

    private func heights(width: CGFloat, subviews: Subviews) -> (sky: CGFloat, scene: CGFloat, buttons: CGFloat) {
        guard subviews.count == 3 else { return (0, 0, 0) }
        let free = ProposedViewSize(width: width, height: nil)
        let sky = subviews[0].sizeThatFits(free).height
        let buttons = subviews[2].sizeThatFits(free).height
        let scene = max(PorchScene.minimumHeight, height - sky - buttons)
        return (sky, scene, buttons)
    }
}

/// The house front and the porch from `onboarding.html`, in its 390-point stage from the roof's
/// edge (y 156 there) to just past the mat (y 630). The stage scales to fit the space it's given
/// and sits at the top of it, and the porch runs on below.
struct PorchScene: View {
    /// The stage, in mockup points: 390 wide, from the roof's top to just past the mat.
    nonisolated static let stage = CGSize(width: 390, height: 474)
    /// The mockup's y for the stage's top.
    nonisolated static let stageTop: CGFloat = 156
    nonisolated static let minimumScale: CGFloat = 0.6
    nonisolated static let maximumScale: CGFloat = 1.6
    nonisolated static var minimumHeight: CGFloat { stage.height * minimumScale }

    /// Every drawing on the stage with its rect, in mockup points, in drawing order.
    static let props: [(RoomArt?, CGRect)] = [
        (.welcomeDoor, CGRect(x: 158, y: 226, width: 188, height: 390)),
        (.welcomeLantern, CGRect(x: 342, y: 300, width: 34, height: 64)),
        (.welcomeMat, CGRect(x: 188, y: 607, width: 124, height: 22)),
        (.welcomePots, CGRect(x: 6, y: 556, width: 48, height: 66)),
        (.floorPlant, CGRect(x: 318, y: 494, width: 72, height: 124)),
        (.hallHooks, CGRect(x: 58, y: 330, width: 104, height: 90)),
        // The camel coat hanging from the rail, drawn as a garment (`nil` here).
        (nil, CGRect(x: 42, y: 332.97, width: 104, height: 147.33)),
        (.hallPeg, CGRect(x: 88, y: 336.5, width: 12, height: 12)),
        (.porchBench, CGRect(x: 58, y: 564, width: 100, height: 46)),
        (.porchSneakers, CGRect(x: 85, y: 595.6, width: 46, height: 13)),
    ]

    /// The scale that fits the stage in `size`.
    static func scale(for size: CGSize) -> CGFloat {
        let fit = min(size.width / stage.width, size.height / stage.height)
        return min(max(fit, minimumScale), maximumScale)
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = Self.scale(for: proxy.size)
            // The roof sits right under the words, and a taller space gives more porch, as a
            // taller phone does in the mockup.
            let origin = CGPoint(x: (proxy.size.width - Self.stage.width * scale) / 2, y: 0)
            // Mockup y to this view's y.
            let y = { (mockupY: CGFloat) in origin.y + (mockupY - Self.stageTop) * scale }
            ZStack(alignment: .topLeading) {
                // The sky behind the roof's edge.
                Color.nook.skyBottom
                    .frame(height: max(0, y(176)))
                RoomArtImage(.welcomeSiding)
                    .frame(width: proxy.size.width, height: 432 * scale)
                    .offset(y: y(174))
                porch(width: proxy.size.width, top: y(606), bottom: proxy.size.height, scale: scale)
                roof(width: proxy.size.width, originX: origin.x, top: y(156), scale: scale)
                ForEach(Self.props.indices, id: \.self) { index in
                    let (art, rect) = Self.props[index]
                    let frame = CGRect(
                        x: origin.x + rect.minX * scale, y: y(rect.minY), width: rect.width * scale,
                        height: rect.height * scale)
                    Group {
                        if let art {
                            RoomArtImage(art)
                        } else {
                            GarmentPicture(photo: .noPhoto, category: .layer, colors: [.tan], size: frame.size)
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    /// The roof's edge, one 390-point tile centred on the stage and repeated to both edges.
    private func roof(width: CGFloat, originX: CGFloat, top: CGFloat, scale: CGFloat) -> some View {
        let tile = Self.stage.width * scale
        let before = Int((originX / tile).rounded(.up))
        let after = Int(((width - originX - tile) / tile).rounded(.up))
        return ForEach(-before...max(0, after), id: \.self) { index in
            RoomArtImage(.welcomeRoof)
                .frame(width: tile, height: 54 * scale)
                .offset(x: originX + CGFloat(index) * tile, y: top)
        }
    }

    /// The porch floor with its line along the house and the first seam of its boards (the
    /// mockup's y 624). Its other seams, at 646 and 674, fall where the buttons are.
    private func porch(width: CGFloat, top: CGFloat, bottom: CGFloat, scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.nook.floor
                .frame(width: width, height: max(0, bottom - top))
                .offset(y: top)
            Color.nook.floorLine
                .frame(width: width, height: 2)
                .offset(y: top)
            Color.nook.floorLine
                .opacity(0.45)
                .frame(width: width, height: 1.2)
                .offset(y: top + (624 - 606) * scale)
        }
    }
}
