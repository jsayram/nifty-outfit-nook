import DesignSystem
import Models
import SwiftUI

/// What a suitcase page's buttons do. The screen fills these in; snapshot tests leave them empty.
struct SuitcaseDetailActions {
    var retry: () -> Void = {}
    var back: () -> Void = {}
    var edit: () -> Void = {}
    var pack: () -> Void = {}
    var useForStyleMe: () -> Void = {}
    var useMainCloset: () -> Void = {}
    var styleMe: () -> Void = {}
    var bringBack: () -> Void = {}
    var openPiece: (ClosetItem) -> Void = { _ in }
    var removePiece: (ClosetItem) -> Void = { _ in }
}

/// A suitcase, top to bottom (`suitcase.html`): its name on the wall with how many pieces and
/// when it was used, its drawing on the right and Edit; whether Style Me uses it, with "Style me
/// from this suitcase"; then the packed pieces in Closet's grid, each with a minus to take it out,
/// and "Add or remove". Empty, it says how to pack it.
///
/// Separate from `SuitcaseDetailScreen` so snapshot tests can draw it from a model.
struct SuitcaseDetailPage: View {
    let model: SuitcaseDetailModel
    var actions = SuitcaseDetailActions()

    @Environment(\.closetIsStillImage) private var isStillImage
    @Environment(\.calendar) private var calendar
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
            if let suitcase = model.suitcase, model.phase == .loaded {
                WallHeader(title: suitcase.name, detail: headerLine(suitcase), detailIdentifier: "suitcase.count") {
                    SuitcaseArtView(icon: suitcase.icon, height: 120)
                        .padding(.top, NookSpacing.small)
                }
            } else {
                WallHeader(title: "", hasFloorLine: true) { Color.clear.frame(height: 60) }
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

    /// "5 pieces · Used today", or "5 pieces · Style Me source".
    private func headerLine(_ suitcase: Suitcase) -> String {
        let used =
            model.isSource
            ? SuitcasesText.styleMeSource
            : SuitcasesText.lastUsed(suitcase.lastUsedAt, now: model.loadedAt, calendar: calendar, locale: locale)
        return "\(SuitcasesText.pieces(model.pieceCount)) · \(used)"
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            NookLoadingState(String(localized: "Opening this suitcase", bundle: .module, comment: "Suitcase loading"))
                .floorCard()
        case .failed:
            NookErrorState(
                String(localized: "This suitcase didn’t load", bundle: .module, comment: "Suitcase error title"),
                message: String(
                    localized: "Nothing was lost. Try again in a moment.", bundle: .module,
                    comment: "Closet error message"),
                retry: actions.retry
            )
            .floorCard()
        case .gone:
            NookEmptyState(
                String(
                    localized: "This suitcase isn’t there any more", bundle: .module,
                    comment: "Suitcase: it was deleted elsewhere"),
                message: String(
                    localized: "Its pieces are still in your closet.", bundle: .module,
                    comment: "Suitcase gone: the pieces stay"),
                systemImage: "suitcase"
            ) {
                NookButton(
                    String(localized: "Back", bundle: .module, comment: "Button: goes back"),
                    systemImage: "chevron.left", kind: .soft, fillsWidth: true, action: actions.back)
            }
            .floorCard()
        case .loaded:
            loaded
        }
    }

    private var loaded: some View {
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            NookButton(
                String(
                    localized: "Name and picture", bundle: .module,
                    comment: "Button: renames a suitcase or changes its picture"),
                systemImage: "pencil", kind: .pill, size: .small, action: actions.edit
            )
            .accessibilityIdentifier("suitcase.edit")
            if model.isArchived {
                archivedNote
            } else {
                sourceCard
            }
            if model.items.isEmpty {
                empty
            } else {
                packed
            }
        }
    }

    /// Archived (PRD §7.7): kept with its pieces, but not offered as a source.
    private var archivedNote: some View {
        NookBanner(
            String(
                localized: "Archived. Its pieces are kept, but it isn’t offered as a source.", bundle: .module,
                comment: "Suitcase: it's archived"),
            systemImage: "archivebox", tone: .neutral,
            actionTitle: String(localized: "Bring it back", bundle: .module, comment: "Button: unarchives a suitcase"),
            action: actions.bringBack
        )
        .accessibilityIdentifier("suitcase.archived")
    }

    /// Whether Style Me uses this suitcase, and the way to use it (`.source`).
    private var sourceCard: some View {
        let count = model.pieceCount
        let title: String
        let line: String
        let systemImage: String
        if model.isSource {
            systemImage = "checkmark"
            title = String(
                localized: "Style Me is using this suitcase", bundle: .module, comment: "Suitcase: it's the source")
            line = String(
                localized: "Suitcase only: Style Me picks from these \(SuitcasesText.pieces(count)) and nothing else.",
                bundle: .module, comment: "Suitcase: what being the source means, with its piece count")
        } else if count > 0 {
            systemImage = "suitcase"
            title = String(
                localized: "Style from \(model.suitcase?.name ?? "")", bundle: .module,
                comment: "Suitcase: card title when it isn't the source, with its name")
            line = String(
                localized:
                    "Suitcase only: Style Me would pick from these \(SuitcasesText.pieces(count)) and nothing else. Now it uses \(model.sourceName).",
                bundle: .module, comment: "Suitcase: what using it would mean, and the source now")
        } else {
            systemImage = "suitcase"
            title = String(localized: "Not ready for Style Me", bundle: .module, comment: "Suitcase: it's empty")
            line = String(
                localized: "Pack at least one piece first. Style Me keeps using \(model.sourceName) until then.",
                bundle: .module, comment: "Suitcase: empty, with the source now")
        }
        return VStack(alignment: .leading, spacing: NookSpacing.medium) {
            HStack(alignment: .top, spacing: NookSpacing.medium) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(model.isSource ? Color.nook.onAccent : Color.nook.accent)
                    .frame(width: 36, height: 36)
                    .background(model.isSource ? Color.nook.accent : Color.nook.accentSoft, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .nookTextStyle(.headline)
                        .foregroundStyle(.nook.textPrimary)
                    Text(line)
                        .nookTextStyle(.note)
                        .foregroundStyle(.nook.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("suitcase.sourceCard")
            }
            if count > 0 {
                VStack(alignment: .leading, spacing: NookSpacing.small) {
                    NookButton(
                        String(
                            localized: "Style me from this suitcase", bundle: .module,
                            comment: "Button: opens Style Me with this suitcase as the source"),
                        systemImage: "sparkles", fillsWidth: true, action: actions.styleMe
                    )
                    .accessibilityIdentifier("suitcase.styleMe")
                    if model.isSource {
                        NookButton(
                            String(
                                localized: "Use Main closet", bundle: .module,
                                comment: "Button: makes the main closet the source"),
                            kind: .text, isLoading: model.isSaving, action: actions.useMainCloset
                        )
                        .accessibilityIdentifier("suitcase.useMainCloset")
                    } else {
                        NookButton(
                            String(
                                localized: "Use for Style Me", bundle: .module,
                                comment: "Button: makes this suitcase the source"),
                            systemImage: "checkmark", kind: .soft, isLoading: model.isSaving, fillsWidth: true,
                            action: actions.useForStyleMe
                        )
                        .accessibilityIdentifier("suitcase.useForStyleMe")
                    }
                }
            }
        }
        .padding(NookSpacing.medium)
        .background {
            NookRadius.shape(NookRadius.tile)
                .fill(Color.nook.tintStrong)
                .softShadow(.drop, in: NookRadius.shape(NookRadius.tile))
        }
    }

    private var packed: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            HStack(alignment: .center, spacing: NookSpacing.small) {
                Text("Packed", bundle: .module, comment: "Suitcase: heading over its pieces")
                    .nookTextStyle(.title)
                    .foregroundStyle(.nook.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(model.pieceCount.formatted())
                    .nookTextStyle(.label)
                    .foregroundStyle(.nook.textSecondary)
                    .accessibilityHidden(true)
                Spacer(minLength: NookSpacing.small)
                packButton(
                    title: String(
                        localized: "Add or remove", bundle: .module, comment: "Button: opens the packing sheet"))
            }
            Text("Tap a piece for details.", bundle: .module, comment: "Suitcase: under Packed")
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .padding(.horizontal, NookSpacing.small)
                .padding(.vertical, 2)
                .floorCard()
            GarmentGrid(
                items: model.items, now: model.loadedAt, identifierPrefix: "suitcase.garment",
                remove: GarmentRemoveAction(
                    label: { item in
                        String(
                            localized: "Remove \(item.name) from \(model.suitcase?.name ?? "")", bundle: .module,
                            comment: "Button on a packed piece: takes it out of this suitcase")
                    },
                    action: actions.removePiece)
            ) { item in
                actions.openPiece(item)
            }
            .padding(.top, NookSpacing.small)
            Label {
                Text(
                    "Removing a piece only takes it out of this suitcase. It stays in your closet and in any other suitcase.",
                    bundle: .module, comment: "Suitcase: what removing a piece does"
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
            .padding(.top, NookSpacing.medium)
        }
    }

    private func packButton(title: String) -> some View {
        NookButton(title, systemImage: "plus", kind: .pill, size: .small, action: actions.pack)
            .accessibilityIdentifier("suitcase.pack")
    }

    /// Nothing packed yet: Add pieces opens the packing sheet (PRD §7.7: "including when the
    /// suitcase is empty").
    private var empty: some View {
        NookEmptyState(
            String(
                localized: "\(model.suitcase?.name ?? "") is empty", bundle: .module,
                comment: "Suitcase: nothing packed, with its name"),
            message: String(
                localized: "Add pieces from your closet. They stay in your closet too, and nothing is copied.",
                bundle: .module, comment: "Suitcase: empty message"),
            systemImage: "suitcase"
        ) {
            NookButton(
                String(localized: "Add pieces", bundle: .module, comment: "Button: opens the packing sheet"),
                systemImage: "plus", fillsWidth: true, action: actions.pack
            )
            .accessibilityIdentifier("suitcase.pack")
        }
        .floorCard()
    }
}
