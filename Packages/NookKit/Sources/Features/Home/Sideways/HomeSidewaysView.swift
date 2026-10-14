import DesignSystem
import Models
import SwiftUI

/// Home on a phone held sideways (`screens/home-landscape.html`).
///
/// The upright room would have to shrink to about 40% to fit the short screen, with drawers too
/// small to tap. Instead the mockup's sideways scene is drawn on the left, scaled to the height
/// above the tab bar so it keeps its proportions, and the room's controls sit beside it as soft
/// tiles in the room's order: Source and Occasion, Style Me, then Laundry and the three
/// drawers. The navigation bar would take a third of the height, so the title and the Profile
/// button sit at the top of the controls instead.
///
/// The drawings still open what they open upright, for a quick tap, but the tiles are the real
/// controls: each is at least 44 points and is what VoiceOver reads, so nothing is read twice.
/// The controls scroll if the text is too big for them to fit.
struct HomeSidewaysView<Notice: View>: View {
    let content: HomeRoomContent
    let open: (RoomControl) -> Void
    let openProfile: () -> Void
    /// The safe area to lay out for. `nil` reads it from the screen; the snapshot tests pass the
    /// measured one, since a still image has none.
    var screenInsets: EdgeInsets?
    @ViewBuilder let notice: Notice

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.roomIsStillImage) private var isStillImage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The controls' column never gets narrower than this; the scene gives way first.
    static var minimumControlsWidth: CGFloat { 340 }
    static var maximumControlsWidth: CGFloat { 420 }

    var body: some View {
        GeometryReader { proxy in
            let measured = proxy.safeAreaInsets
            let size = CGSize(
                width: proxy.size.width + measured.leading + measured.trailing,
                height: proxy.size.height + measured.top + measured.bottom)
            // On iPhone 17 sideways (iOS 26.5): 62 pt at each side and 64 pt for the tab bar.
            let insets = screenInsets ?? measured
            let layout = SidewaysLayout(
                height: size.height, top: insets.top, bottom: insets.bottom, leading: insets.leading,
                maximumWidth: size.width - insets.leading - insets.trailing - Self.minimumControlsWidth)
            ZStack(alignment: .topLeading) {
                backdrop(size: size, layout: layout)
                SidewaysScene(layout: layout, content: content, open: open, animates: !reduceMotion && !isStillImage)
                controls(top: insets.top, bottom: insets.bottom)
                    .padding(.trailing, insets.trailing)
                    .frame(width: max(0, size.width - layout.sceneMaxX), height: size.height, alignment: .top)
                    .background { sideTint }
                    .offset(x: layout.sceneMaxX)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .ignoresSafeArea()
        }
    }

    private func backdrop(size: CGSize, layout: SidewaysLayout) -> some View {
        ZStack(alignment: .topLeading) {
            Color.nook.wallGradient
            Color.nook.floorGradient
                .frame(height: max(0, size.height - layout.floorY))
                .offset(y: layout.floorY)
            Color.nook.floorLine
                .frame(height: 2)
                .offset(y: layout.floorY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// A wash behind the controls that fades in from the scene's edge (`.side`).
    private var sideTint: some View {
        LinearGradient(
            stops: [.init(color: .clear, location: 0), .init(color: .nook.tint, location: 0.06)],
            startPoint: .leading, endPoint: .trailing
        )
        .accessibilityHidden(true)
    }

    /// The controls scroll under the tab bar when the words are too big to fit above it.
    private func controls(top: CGFloat, bottom: CGFloat) -> some View {
        let column =
            controlStack
            .frame(maxWidth: Self.maximumControlsWidth)
            .frame(maxWidth: .infinity)
        return Group {
            if isStillImage {
                column.padding(.top, top)
            } else {
                ScrollView(.vertical) { column }
                    .contentMargins(.top, top, for: .scrollContent)
                    .contentMargins(.bottom, bottom, for: .scrollContent)
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
            }
        }
    }

    private var controlStack: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            header
            notice
            // Side by side at the usual sizes, as in the mockup; stacked once the words grow.
            if dynamicTypeSize <= .large {
                HStack(alignment: .top, spacing: NookSpacing.small) {
                    sourceTile
                    occasionTile.fixedSize(horizontal: true, vertical: false)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: NookSpacing.small) {
                    sourceTile
                    occasionTile
                }
            }
            NookButton(
                RoomControl.laptop.rowLabel(for: content), systemImage: "sparkles", fillsWidth: true
            ) { open(.laptop) }
            .accessibilityHint(RoomControl.laptop.accessibilityHint(for: content))
            .accessibilityIdentifier(RoomControl.laptop.identifier)
            more
        }
        .padding(.leading, 18)
        .padding(.trailing, NookSpacing.xLarge)
        .padding(.vertical, NookSpacing.xSmall)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: NookSpacing.small) {
            Text("Nifty Outfit Nook", bundle: .module, comment: "The app's name, as the Home title")
                .nookTextStyle(.title)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: openProfile) {
                Image(systemName: "person.crop.circle")
                    .font(.title2)
                    .foregroundStyle(.nook.accent)
                    .frame(width: NookSpacing.minimumTapTarget, height: NookSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Profile", bundle: .module, comment: "Button: opens Profile"))
            .accessibilityIdentifier("home.profile")
            .padding(.trailing, -NookSpacing.small)
        }
    }

    private var sourceTile: some View {
        SidewaysTile(control: .suitcase, content: content, systemImage: "suitcase.rolling", open: open) {
            LargeRowText(
                caption: String(localized: "Source", bundle: .module, comment: "Caption on Home's Source row"),
                title: content.source.name, style: .compact)
            SourcePill(source: content.source)
        }
    }

    private var occasionTile: some View {
        SidewaysTile(control: .occasion, content: content, systemImage: "calendar", fill: .warning, open: open) {
            LargeRowText(caption: nil, title: RoomControl.occasion.rowLabel(for: content), style: .compact)
        }
    }

    /// Laundry and the three drawers in one row, or two rows when they don't fit (`.more`).
    private var more: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                laundry
                drawerButtons
            }
            VStack(alignment: .leading, spacing: 6) {
                laundry
                HStack(spacing: 6) { drawerButtons }
            }
            VStack(alignment: .leading, spacing: 6) {
                laundry
                drawerButtons
            }
        }
    }

    private var laundry: some View {
        SidewaysTile(control: .hamper, content: content, systemImage: "basket", open: open) {
            LaundryTileText(hamper: content.hamper)
        }
    }

    @ViewBuilder private var drawerButtons: some View {
        drawer(.helpDrawer, title: String(localized: "Help", bundle: .module, comment: "Plate on the top desk drawer"))
        drawer(
            .feedbackDrawer,
            title: String(
                localized: "Feedback", bundle: .module, comment: "Plate on the middle desk drawer; opens Send feedback")
        )
        drawer(
            .privacyDrawer,
            title: String(
                localized: "Privacy", bundle: .module,
                comment: "Plate on the bottom desk drawer; opens Privacy and terms"))
    }

    /// A drawer as a small soft button with the drawer's own word on it. VoiceOver says the full
    /// name, and Voice Control answers to both.
    private func drawer(_ control: RoomControl, title: String) -> some View {
        Button(title) { open(control) }
            .buttonStyle(.nook(.soft, size: .small))
            .accessibilityLabel(control.rowLabel(for: content))
            .accessibilityInputLabels([Text(title), Text(control.rowLabel(for: content))])
            .accessibilityHint(control.accessibilityHint(for: content))
            .accessibilityIdentifier(control.identifier)
    }
}

/// A control as a soft tile beside the sideways room (`.tile`): an icon and words. No chevron,
/// as in the mockup, so the words get the room.
struct SidewaysTile<Label: View>: View {
    let control: RoomControl
    let content: HomeRoomContent
    let systemImage: String
    var fill: LargeRowFill = .tint
    let open: (RoomControl) -> Void
    @ViewBuilder let label: Label

    var body: some View {
        let shape = NookRadius.shape(NookRadius.group)
        Button {
            open(control)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.nook.accent)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    label
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 9)
            .padding(.leading, NookSpacing.medium)
            .padding(.trailing, 10)
            .frame(minHeight: NookSpacing.minimumTapTarget)
            .background(fill.color, in: shape)
            .softShadow(.drop, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(SidewaysTileButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(control.rowLabel(for: content))
        .accessibilityHint(control.accessibilityHint(for: content))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(control.identifier)
    }
}

private struct SidewaysTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if configuration.isPressed {
                    NookRadius.shape(NookRadius.group).fill(Color.nook.textPrimary.opacity(0.08))
                }
            }
    }
}

/// "Laundry" over its state, in the small tile.
struct LaundryTileText: View {
    let hamper: HamperState?

    var body: some View {
        let caption = String(localized: "Laundry", bundle: .module, comment: "Caption on Home's Laundry row")
        LargeRowText(
            caption: caption, title: hamper?.plateText ?? "All clean", isQuiet: hamper == .off, style: .compact
        )
        .redacted(reason: hamper == nil ? .placeholder : [])
    }
}

/// The sideways room: the mockup's closer scene, each drawing in its place. The objects that do
/// something open the same thing as upright, but they're hidden from VoiceOver, because the
/// tiles beside them carry the same controls with words and full-size targets.
struct SidewaysScene: View {
    let layout: SidewaysLayout
    let content: HomeRoomContent
    let open: (RoomControl) -> Void
    let animates: Bool

    var body: some View {
        let look = HamperLook(hamper: content.hamper)
        ZStack(alignment: .topLeading) {
            art(.rug, at: SidewaysStage.rug)
            window
            tappable(.wardrobe) {
                art(.wardrobe, at: SidewaysStage.wardrobe)
                art(.wardrobeRail, at: SidewaysStage.onWardrobe(RoomStage.wardrobeRail))
                art(.flats, at: SidewaysStage.onWardrobe(RoomStage.wardrobeFlats))
            }
            tappable(.nameSign) {
                art(.nameSign, at: SidewaysStage.sign)
                NameSignText(stored: content.signName)
                    .roomFrame(layout.rect(SidewaysStage.signName))
            }
            tappable(.occasion) { art(.calendar, at: SidewaysStage.calendar) }
            LampGlow(isNight: content.window.lightsTheLamp)
                .roomFrame(layout.rect(SidewaysStage.lampGlow))
            art(.desk, at: SidewaysStage.desk)
            ForEach([RoomControl.helpDrawer, .feedbackDrawer, .privacyDrawer], id: \.self) { drawer in
                tappable(drawer) { Color.clear.roomFrame(layout.rect(SidewaysStage.rect(for: drawer) ?? .zero)) }
            }
            tappable(.laptop) {
                art(.laptop, at: SidewaysStage.laptop)
                Image(systemName: "sparkles")
                    .font(.system(size: 17 * layout.scale))
                    .foregroundStyle(.white)
                    .roomFrame(layout.rect(SidewaysStage.laptopScreen))
            }
            art(.lamp, at: SidewaysStage.lamp)
            art(.chair, at: SidewaysStage.chair)
            Group {
                art(.maya, at: SidewaysStage.maya)
                SleepyZs(scale: layout.scale * SidewaysStage.artScale, animates: animates)
                    .roomFrame(layout.rect(SidewaysStage.mayaZs))
            }
            .allowsHitTesting(false)
            tappable(.suitcase) { art(.suitcase, at: SidewaysStage.suitcase) }
            tappable(.hamper) { art(look.art, at: SidewaysStage.hamperArt(look)) }
        }
        .dynamicTypeSize(...RoomCanvas.largestTextSize)
        .accessibilityHidden(true)
    }

    private var window: some View {
        let window = content.window
        return ZStack {
            RoomArtImage(window.art)
                .id(window)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.4), value: window)
        .roomFrame(layout.rect(SidewaysStage.window))
        .allowsHitTesting(false)
    }

    private func art(_ art: RoomArt, at stage: CGRect) -> some View {
        RoomArtImage(art).roomFrame(layout.rect(stage))
    }

    /// A drawing that opens `control` when tapped.
    private func tappable<Drawing: View>(_ control: RoomControl, @ViewBuilder drawing: () -> Drawing) -> some View {
        ZStack(alignment: .topLeading) {
            drawing().allowsHitTesting(false)
            if let stage = SidewaysStage.rect(for: control) {
                Color.clear
                    .contentShape(Rectangle())
                    .roomFrame(layout.rect(stage))
                    .onTapGesture { open(control) }
            }
        }
    }
}
