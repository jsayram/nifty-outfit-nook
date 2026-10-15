import DesignSystem
import Models
import SwiftUI

/// The words on Laundry.
nonisolated enum LaundryText {
    static var title: String {
        String(localized: "Laundry", bundle: .module, comment: "Screen title")
    }

    static var trackingOff: String {
        String(localized: "Tracking off", bundle: .module, comment: "Laundry: under the title while tracking is off")
    }

    static var trackingIsOff: String {
        String(localized: "Laundry tracking is off", bundle: .module, comment: "Sheet title")
    }

    /// "2 pieces in the wash", "Nothing in the wash".
    static func inTheWash(_ count: Int) -> String {
        count == 0
            ? String(localized: "Nothing in the wash", bundle: .module, comment: "Laundry: all clean")
            : String(
                localized: "\(count) pieces in the wash", bundle: .module,
                comment: "Laundry: under the title, how many pieces are dirty")
    }

    /// "White lace top marked clean", "2 pieces marked clean".
    static func markedClean(_ names: [String]) -> String {
        if names.count == 1, let name = names.first {
            return String(
                localized: "\(name) marked clean", bundle: .module, comment: "Toast after marking one piece clean")
        }
        return String(
            localized: "\(names.count) pieces marked clean", bundle: .module,
            comment: "Toast after marking several pieces clean")
    }
}

/// The question before cleaning several (PRD §7.3, FR-65): what's being cleaned, from where,
/// how many, and the pieces themselves, then Mark N clean or Cancel.
nonisolated struct CleanRequest: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Everything in the wash in the scope.
        case all
        /// The ones she ticked.
        case selected
    }

    let kind: Kind
    let ids: [Garment.ID]
    let scopeName: String
    /// True when it's the source suitcase, not the whole closet.
    var isSuitcase = false

    var id: [Garment.ID] { ids }

    var title: String {
        String(
            localized: "Mark \(ids.count) pieces clean?", bundle: .module,
            comment: "Laundry: asks before cleaning several, with how many")
    }
}

/// Laundry (Phase 13, `laundry.html`, RD-11, PRD §7.3), pushed on Closet's stack: from Closet's
/// Laundry tile, and from Home's hamper while tracking is on, which opens it on the Closet tab.
///
/// Mark clean on one piece needs no question and offers Undo. Clean selected (two or more) and
/// Mark all clean ask first, with the pieces listed, and offer Undo too. Leaving the screen
/// shows the change on Home's hamper and Closet straight away, since both reload when they
/// appear.
struct LaundryScreen: View {
    let open: (ClosetDestination) -> Void

    @Environment(\.services) private var services
    @State private var model = LaundryModel()
    @State private var request: CleanRequest?
    @State private var isSaving = false
    @State private var toast: NookToastMessage?

    var body: some View {
        LaundryPage(
            model: model,
            actions: LaundryActions(
                retry: { Task { await model.load(from: services) } },
                markClean: { clean([$0]) },
                cleanSelected: cleanSelected,
                cleanAll: {
                    request = CleanRequest(
                        kind: .all, ids: model.shown.map(\.id), scopeName: model.scopeName,
                        isSuitcase: model.scope.isSuitcase)
                },
                turnOn: turnOn,
                openProfile: { open(.profile) },
                chooseScope: { model.choose(scope: $0) },
                toggleSelected: { model.toggleSelected($0) }
            ),
            isSaving: isSaving
        )
        .navigationTitle(LaundryText.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(verbatim: "").accessibilityHidden(true)
            }
        }
        .nookSheet(item: $request, title: { $0.title }) { request in
            CleanConfirmation(request: request, model: model) {
                self.request = nil
                clean(request.ids)
            } cancel: {
                self.request = nil
            }
        }
        .overlay {
            Color.clear
                .nookToast($toast)
        }
        .task { await model.load(from: services) }
    }

    /// One ticked piece is cleaned straight away; two or more ask first.
    private func cleanSelected() {
        let ids = model.shown.map(\.id).filter(model.isSelected)
        if ids.count == 1 {
            clean(ids)
        } else if ids.count > 1 {
            request = CleanRequest(
                kind: .selected, ids: ids, scopeName: model.scopeName, isSuitcase: model.scope.isSuitcase)
        }
    }

    private func clean(_ ids: [Garment.ID]) {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                let cleaned = try await model.markClean(ids, in: services)
                guard !cleaned.isEmpty else { return }
                let names = cleaned.compactMap { model.garment($0)?.name }
                toast = NookToastMessage(
                    LaundryText.markedClean(names), systemImage: "checkmark", actionTitle: SuitcasesText.undo
                ) {
                    Task { try? await model.undoClean(cleaned, in: services) }
                }
            } catch {
                toast = NookToastMessage(SuitcasesText.failed, systemImage: "exclamationmark.circle")
            }
        }
    }

    private func turnOn() {
        Task {
            isSaving = true
            let saved = await model.turnOnTracking(in: services)
            isSaving = false
            toast =
                saved
                ? NookToastMessage(
                    String(localized: "Laundry tracking is on.", bundle: .module, comment: "Toast after turning it on"),
                    systemImage: "basket")
                : NookToastMessage(
                    String(
                        localized: "Couldn’t turn it on. Try again.", bundle: .module,
                        comment: "Laundry tracking sheet: saving the setting failed"),
                    systemImage: "exclamationmark.circle")
        }
    }
}

/// The confirmation sheet's content (`.sheet` in `laundry.html`).
struct CleanConfirmation: View {
    let request: CleanRequest
    let model: LaundryModel
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            Label {
                Text(scopeLine)
            } icon: {
                Image(systemName: request.isSuitcase ? "suitcase" : "hanger")
                    .accessibilityHidden(true)
            }
            .nookTextStyle(.label)
            .foregroundStyle(.nook.accent)
            .padding(.horizontal, NookSpacing.medium)
            .frame(minHeight: 32)
            .background(Color.nook.accentSoft, in: Capsule())
            Text(
                "They become available to Style Me again. You can undo this.", bundle: .module,
                comment: "Laundry confirmation: what cleaning does"
            )
            .nookTextStyle(.body)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            NookFlowLayout(spacing: NookSpacing.medium, lineSpacing: NookSpacing.small) {
                ForEach(request.ids.compactMap(model.garment)) { garment in
                    VStack(spacing: NookSpacing.xSmall) {
                        GarmentPicture(garment, size: CGSize(width: 64, height: 72), presentation: .sticker(.centred))
                            .accessibilityHidden(true)
                        Text(garment.name)
                            .nookTextStyle(.chip)
                            .foregroundStyle(.nook.textPrimary)
                            .multilineTextAlignment(.center)
                            .frame(width: 96)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            NookButton(
                String(
                    localized: "Mark \(request.ids.count) clean", bundle: .module,
                    comment: "Button: confirms cleaning several, with how many"),
                systemImage: "checkmark", fillsWidth: true, action: confirm
            )
            .accessibilityIdentifier("laundry.confirm")
            NookButton(
                String(localized: "Cancel", bundle: .module, comment: "Button: closes without changing anything"),
                kind: .soft, fillsWidth: true, action: cancel)
        }
    }

    private var scopeLine: String {
        switch request.kind {
        case .all:
            String(
                localized: "Everything in the wash in \(request.scopeName)", bundle: .module,
                comment: "Laundry confirmation: cleaning all, with where")
        case .selected:
            String(
                localized: "Selected in \(request.scopeName)", bundle: .module,
                comment: "Laundry confirmation: cleaning the ticked pieces, with where")
        }
    }
}
