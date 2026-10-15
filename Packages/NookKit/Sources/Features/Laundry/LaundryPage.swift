import DesignSystem
import Models
import SwiftUI

/// What Laundry's buttons do. The screen fills these in; snapshot tests leave them empty.
struct LaundryActions {
    var retry: () -> Void = {}
    var markClean: (Garment.ID) -> Void = { _ in }
    var cleanSelected: () -> Void = {}
    var cleanAll: () -> Void = {}
    var turnOn: () -> Void = {}
    var openProfile: () -> Void = {}
    var chooseScope: (WardrobeSource) -> Void = { _ in }
    var toggleSelected: (Garment.ID) -> Void = { _ in }
}

/// Laundry, top to bottom (`laundry.html`): the title on the wall with how many pieces are in
/// the wash, and a washer, a shelf, the hamper and a plant on the right; then the whole closet or
/// the source suitcase, the pieces in the wash with a tick and Mark clean each, and Clean
/// selected and Mark all clean. While tracking is off it says so, with Turn on (RD-11).
///
/// Separate from `LaundryScreen` so snapshot tests can draw it from a model.
struct LaundryPage: View {
    let model: LaundryModel
    var actions = LaundryActions()
    var isSaving = false

    @Environment(\.closetIsStillImage) private var isStillImage
    @Environment(\.locale) private var locale

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
            WallHeader(title: LaundryText.title, detail: headerLine, detailIdentifier: "laundry.count") {
                LaundryCorner(hamper: model.phase == .loaded ? hamper : nil)
            }
            content
                .padding(.horizontal, NookSpacing.screenMargin)
                .padding(.top, NookSpacing.large)
                .padding(.bottom, NookSpacing.xxxLarge)
                .frame(maxWidth: SuitcasesPage.maximumWidth)
                .frame(maxWidth: .infinity)
                .background(Color.nook.floor)
        }
    }

    private var hamper: HamperState {
        guard model.tracksLaundry else { return .off }
        return model.dirtyCount == 0 ? .allClean : .toWash(model.dirtyCount)
    }

    private var headerLine: String? {
        guard model.phase == .loaded else { return nil }
        guard model.tracksLaundry else { return LaundryText.trackingOff }
        return LaundryText.inTheWash(model.dirtyCount)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            NookLoadingState(String(localized: "Opening your laundry", bundle: .module, comment: "Laundry loading"))
                .floorCard()
        case .failed:
            NookErrorState(
                String(localized: "Your laundry didn’t load", bundle: .module, comment: "Laundry error title"),
                message: String(
                    localized: "Nothing was lost. Try again in a moment.", bundle: .module,
                    comment: "Closet error message"),
                retry: actions.retry
            )
            .floorCard()
        case .loaded:
            if model.tracksLaundry {
                tracking
            } else {
                off
            }
        }
    }

    private var tracking: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            if let suitcase = model.sourceSuitcase {
                scopeChips(suitcase)
            }
            let shown = model.shown
            if shown.isEmpty {
                NookEmptyState(
                    model.scope == .mainCloset
                        ? String(localized: "Nothing in the wash", bundle: .module, comment: "Laundry: all clean")
                        : String(
                            localized: "Nothing in the wash in \(model.scopeName)", bundle: .module,
                            comment: "Laundry: all clean in a suitcase"),
                    message: String(
                        localized: "Every piece here counts as available to Style Me.", bundle: .module,
                        comment: "Laundry: all clean"),
                    systemImage: "checkmark.circle"
                )
                .floorCard()
                .accessibilityIdentifier("laundry.empty")
            } else {
                if shown.count > 1 {
                    Text(
                        "Tick the circles to clean a few together.", bundle: .module,
                        comment: "Laundry: how to clean several at once"
                    )
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NookSpacing.small)
                    .padding(.vertical, 2)
                    .floorCard()
                }
                VStack(spacing: NookSpacing.xSmall) {
                    ForEach(shown) { garment in
                        LaundryRow(
                            garment: garment, place: model.whereItIs(garment, locale: locale),
                            isSelected: model.isSelected(garment.id),
                            markClean: { actions.markClean(garment.id) },
                            select: { actions.toggleSelected(garment.id) })
                    }
                }
                .padding(.vertical, NookSpacing.xSmall)
                .floorCard()
                .accessibilityElement(children: .contain)
                .accessibilityLabel(
                    Text("Pieces in the wash", bundle: .module, comment: "Laundry: name of the list"))
                buttons(count: shown.count)
            }
            Label {
                Text(
                    "Style Me skips pieces in the wash. A piece in two suitcases is one piece, so cleaning it cleans it everywhere.",
                    bundle: .module, comment: "Laundry: what being in the wash means"
                )
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.nook.accent)
                    .accessibilityHidden(true)
            }
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textSecondary)
            .padding(NookSpacing.small)
            .floorCard()
        }
    }

    /// Main closet · 2 and Jose's house · 1, when Style Me's source is a suitcase (PRD §7.3).
    private func scopeChips(_ suitcase: Suitcase) -> some View {
        VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
            NookChipBar(
                String(localized: "Which clothes", bundle: .module, comment: "Laundry: name of the scope chips")
            ) {
                NookChip(
                    "\(SuitcasesText.mainCloset) · \(model.count(in: .mainCloset))", systemImage: "hanger",
                    isSelected: model.scope == .mainCloset
                ) {
                    actions.chooseScope(.mainCloset)
                }
                .accessibilityIdentifier("laundry.scope.mainCloset")
                NookChip(
                    "\(suitcase.name) · \(model.count(in: .suitcase(suitcase.id)))", systemImage: "suitcase",
                    isSelected: model.scope == .suitcase(suitcase.id)
                ) {
                    actions.chooseScope(.suitcase(suitcase.id))
                }
                .accessibilityIdentifier("laundry.scope.suitcase")
            }
            .flushChipBar()
            Text(
                model.scope == .mainCloset
                    ? String(
                        localized: "Every piece you own, packed or not.", bundle: .module,
                        comment: "Laundry: what the Main closet chip shows")
                    : String(
                        localized: "\(suitcase.name) is your Style Me source. Only what’s packed in it.",
                        bundle: .module, comment: "Laundry: what the suitcase chip shows"),
            )
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, NookSpacing.small)
            .padding(.vertical, 2)
            .floorCard()
        }
    }

    private func buttons(count: Int) -> some View {
        let selected = model.selected.count
        return NookAdaptiveStack(spacing: NookSpacing.small) {
            NookButton(
                selected == 0
                    ? String(
                        localized: "Clean selected", bundle: .module, comment: "Button: marks the ticked pieces clean")
                    : String(
                        localized: "Clean \(selected) selected", bundle: .module,
                        comment: "Button: marks the ticked pieces clean, with how many"),
                systemImage: "checkmark", kind: .soft, isLoading: isSaving, fillsWidth: true,
                action: actions.cleanSelected
            )
            .disabled(selected == 0)
            .accessibilityIdentifier("laundry.cleanSelected")
            NookButton(
                String(
                    localized: "Mark all clean", bundle: .module, comment: "Button: marks every piece in the wash clean"
                ),
                isLoading: isSaving, fillsWidth: true, action: actions.cleanAll
            )
            .accessibilityValue(Text("\(model.scopeName) · \(SuitcasesText.pieces(count))"))
            .accessibilityIdentifier("laundry.cleanAll")
        }
    }

    /// Tracking off (`laundry.html?laundry=off`): every piece counts, her marks are kept, Turn on.
    private var off: some View {
        NookEmptyState(
            LaundryText.trackingIsOff,
            message: model.dirtyCount > 0
                ? String(
                    localized:
                        "Every piece counts as available to Style Me. The \(model.dirtyCount) pieces you marked as in the wash are kept. Turn tracking on and they come back.",
                    bundle: .module, comment: "Laundry, tracking off, with marks kept")
                : String(
                    localized: "Every piece counts as available to Style Me.", bundle: .module,
                    comment: "Laundry, tracking off"),
            systemImage: "basket"
        ) {
            NookButton(
                String(localized: "Turn on", bundle: .module, comment: "Button: turns laundry tracking on"),
                isLoading: isSaving, fillsWidth: true, action: actions.turnOn
            )
            .accessibilityIdentifier("laundry.turnOn")
            NookButton(
                String(
                    localized: "You can change this in Profile", bundle: .module,
                    comment: "Link from the laundry tracking sheet to the Profile switch"),
                kind: .text, action: actions.openProfile)
        }
        .floorCard()
    }
}

/// One piece in the wash (`.item`): a tick to clean it with others, its sticker, its name with
/// its kind and where it is, and Mark clean.
private struct LaundryRow: View {
    let garment: Garment
    let place: String
    let isSelected: Bool
    /// Mark clean, this piece alone.
    let markClean: () -> Void
    let select: () -> Void

    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 72

    var body: some View {
        HStack(spacing: NookSpacing.small) {
            Button(action: select) {
                SelectionTick(isSelected: isSelected)
                    .frame(width: NookSpacing.minimumTapTarget, height: NookSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ClosetPressStyle())
            .accessibilityLabel(
                Text("Select \(garment.name)", bundle: .module, comment: "Laundry: ticks a piece to clean with others")
            )
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityIdentifier("laundry.select.\(garment.id.rawValue)")
            GarmentPicture(garment, size: CGSize(width: 48, height: 56), presentation: .sticker(.centred))
                .rotationEffect(.degrees(-3))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(garment.name)
                    .nookTextStyle(.label)
                    .foregroundStyle(.nook.textPrimary)
                Text("\(garment.category.singularTitle) · \(place)")
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            NookButton(
                String(localized: "Mark clean", bundle: .module, comment: "Button: marks one piece clean"),
                kind: .pill, size: .small, action: markClean
            )
            .fixedSize()
            .accessibilityLabel(
                Text("Mark \(garment.name) clean", bundle: .module, comment: "Laundry: marks one piece clean")
            )
            .accessibilityIdentifier("laundry.markClean.\(garment.id.rawValue)")
        }
        .padding(.horizontal, NookSpacing.xSmall)
        .frame(minHeight: minHeight)
    }
}

/// The laundry corner in the header (`.corner`): a shelf, the washer, the hamper as Home shows
/// it, and a plant. Decoration only.
struct LaundryCorner: View {
    /// `nil` while loading: the plain empty hamper.
    let hamper: HamperState?

    static let scale: CGFloat = 0.6
    static let size = CGSize(width: 324, height: 296)

    var body: some View {
        let look = HamperLook(hamper: hamper)
        ZStack(alignment: .topLeading) {
            art(.laundryShelf, CGRect(x: 4, y: 0, width: 224, height: 76))
            art(.washer, CGRect(x: 0, y: 115.7, width: 123.2, height: 173.8))
            // Home's hamper at the washer's 1.1, standing on the same floor. The full one is
            // drawn taller for the heap above its rim.
            art(
                look.art,
                look == .full
                    ? CGRect(x: 135, y: 168.5, width: 96.8, height: 121)
                    : CGRect(x: 135, y: 183.9, width: 96.8, height: 105.6))
            art(.floorPlant, CGRect(x: 252, y: 164, width: 72, height: 124))
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .scaleEffect(Self.scale, anchor: .topLeading)
        .frame(width: Self.size.width * Self.scale, height: Self.size.height * Self.scale, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func art(_ art: RoomArt, _ rect: CGRect) -> some View {
        RoomArtImage(art)
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}
