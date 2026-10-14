import DesignSystem
import Models
import SwiftUI

/// The bedroom: wall, floor, furniture and the plates, drawn at one size (`screens/home.html`).
///
/// Everything is placed from `RoomStage` through `layout`, so the art and the tap areas stay
/// together at every phone size. The drawings are decorative; each control is one button with
/// its own label and hint (RD-01.2).
struct RoomCanvas: View {
    static let largestTextSize = DynamicTypeSize.xxxLarge

    let layout: RoomLayout
    let content: HomeRoomContent
    let open: (RoomControl) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop
            wall
            floor
            bed
            title
        }
        .frame(width: layout.size.width, height: layout.contentHeight, alignment: .topLeading)
        .clipped()
        // The plates are drawn at a fixed size on the art, so their words stop growing at the
        // largest standard size. At the accessibility sizes Phase 5b swaps the room for the
        // banner and large rows (`home-ax.html`, RD-01.5).
        .dynamicTypeSize(...Self.largestTextSize)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Wall and floor

    private var backdrop: some View {
        ZStack(alignment: .topLeading) {
            Color.nook.wallGradient
            Color.nook.floorGradient
                .frame(height: max(0, layout.contentHeight - layout.floorY))
                .offset(y: layout.floorY)
            Color.nook.floorLine
                .frame(height: 2)
                .offset(y: layout.floorY)
        }
        .frame(width: layout.size.width, height: layout.contentHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private var wall: some View {
        ZStack(alignment: .topLeading) {
            art(.windowRain, at: RoomStage.window)
            art(.shelfTop, at: RoomStage.shelfTop)
            shelfFrames
            art(.calendar, at: RoomStage.calendar)
            wardrobe
            nameSign
        }
    }

    private var floor: some View {
        ZStack(alignment: .topLeading) {
            art(.rug, at: RoomStage.rug)
            art(.desk, at: RoomStage.desk)
            art(.laptop, at: RoomStage.laptop)
            art(.lamp, at: RoomStage.lamp)
            art(.chair, at: RoomStage.chair)
            // Maya sleeps on the rug at RoomStage.maya, with her z's at RoomStage.mayaZs (Phase 5a).
            suitcase
            hamper
            savedLooksPlate
            occasion
            laptopScreen
            drawers
        }
    }

    // MARK: - Pieces

    private var wardrobe: some View {
        control(.wardrobe) {
            ZStack(alignment: .topLeading) {
                art(.wardrobe, at: RoomStage.wardrobe)
                art(.wardrobeRail, at: RoomStage.wardrobeRail)
                art(.flats, at: RoomStage.wardrobeFlats)
                ClosetPlate().roomFrame(layout.rect(RoomStage.closetPlate))
            }
        }
    }

    private var nameSign: some View {
        control(.nameSign) {
            ZStack(alignment: .topLeading) {
                art(.nameSign, at: RoomStage.sign)
                NameSignText(stored: content.signName)
                    .roomFrame(layout.rect(RoomStage.signName))
            }
        }
    }

    /// The three frames under the shelf. Phase 12a puts her saved looks in them; until then
    /// they're empty and decorative, and a tap does what the shelf plate does.
    private var shelfFrames: some View {
        art(.shelfFrames, at: RoomStage.shelfFrames)
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { open(.savedLooks) }
                    .roomFrame(layout.rect(RoomStage.framedLooks))
            }
    }

    private var savedLooksPlate: some View {
        control(.savedLooks) {
            SavedLooksPlate().roomFrame(layout.rect(RoomStage.savedPlate))
        }
    }

    private var occasion: some View {
        control(.occasion) {
            OccasionLabel(occasion: content.occasion).roomFrame(layout.rect(RoomStage.occasion))
        }
    }

    private var laptopScreen: some View {
        control(.laptop) {
            LaptopLabel().roomFrame(layout.rect(RoomStage.laptopScreen))
        }
    }

    private var drawers: some View {
        let titles = [
            String(localized: "Help", bundle: .module, comment: "Plate on the top desk drawer"),
            String(
                localized: "Feedback", bundle: .module, comment: "Plate on the middle desk drawer; opens Send feedback"),
            String(
                localized: "Privacy", bundle: .module,
                comment: "Plate on the bottom desk drawer; opens Privacy and terms"),
        ]
        let controls: [RoomControl] = [.helpDrawer, .feedbackDrawer, .privacyDrawer]
        return ZStack(alignment: .topLeading) {
            ForEach(Array(zip(controls, titles)), id: \.0) { control, title in
                let drawer = control.stageRect
                let plate = CGRect(
                    x: drawer.minX + RoomStage.drawerPlateInset.minX,
                    y: drawer.minY + RoomStage.drawerPlateInset.minY,
                    width: RoomStage.drawerPlateInset.width,
                    height: RoomStage.drawerPlateInset.height
                )
                self.control(control) {
                    DrawerPlate(title: title).roomFrame(layout.rect(plate))
                }
            }
        }
    }

    private var suitcase: some View {
        control(.suitcase) {
            ZStack(alignment: .topLeading) {
                art(.suitcase, at: RoomStage.suitcaseArt)
                SourceNamePlate(source: content.source).roomFrame(layout.rect(RoomStage.sourcePlate))
                ScopePlate(source: content.source).roomFrame(layout.rect(RoomStage.scopePlate))
            }
        }
    }

    /// One hamper drawing for now. Phase 5a adds the faded, empty and full states (RD-11).
    private var hamper: some View {
        control(.hamper) {
            ZStack(alignment: .topLeading) {
                art(.hamper, at: RoomStage.hamperArt)
                LaundryPlate(hamper: content.hamper).roomFrame(layout.rect(RoomStage.laundryPlate))
            }
        }
    }

    private var bed: some View {
        RoomArtImage(.bed)
            .roomFrame(layout.bed)
            .accessibilityHidden(true)
    }

    private var title: some View {
        Text("Nifty Outfit Nook", bundle: .module, comment: "The app's name, as the Home title")
            .nookTextStyle(.display)
            .foregroundStyle(.nook.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .roomFrame(layout.rect(RoomStage.title))
            .accessibilityAddTraits(.isHeader)
            .accessibilitySortPriority(Double(RoomControl.allCases.count + 1))
    }

    // MARK: - Helpers

    private func art(_ art: RoomArt, at stage: CGRect) -> some View {
        RoomArtImage(art).roomFrame(layout.rect(stage))
    }

    /// A control: what's drawn for it, with a button over its tap area.
    private func control<Drawing: View>(_ control: RoomControl, @ViewBuilder drawing: () -> Drawing) -> some View {
        ZStack(alignment: .topLeading) {
            drawing()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Button {
                open(control)
            } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(RoomControlButtonStyle())
            .roomFrame(layout.target(control.stageRect))
            .accessibilityLabel(control.accessibilityLabel(for: content))
            .accessibilityHint(control.accessibilityHint(for: content))
            .accessibilityIdentifier(control.identifier)
            .accessibilitySortPriority(control.sortPriority)
        }
    }
}

/// No visible change on the invisible tap area itself; the press shows as a soft dim over the
/// object instead, so she sees which piece she touched.
private struct RoomControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed {
                    NookRadius.shape(NookRadius.plateSlim)
                        .fill(Color.nook.textPrimary.opacity(0.08))
                }
            }
    }
}
