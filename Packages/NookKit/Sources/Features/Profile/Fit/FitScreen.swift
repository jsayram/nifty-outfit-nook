import DesignSystem
import Models
import SwiftUI

/// Fit and measurements (Phase 14a, `fit.html`), pushed from Profile with Profile's model.
///
/// Usual fit and the units save as soon as she taps. Each measurement opens its own sheet, which
/// checks the number before saving. A piece that fits her well is added in a sheet and removed
/// with Undo. Nothing here is sent anywhere; changing it never restyles a saved look.
struct FitScreen: View {
    let model: ProfileModel

    @Environment(\.services) private var services
    @Environment(\.locale) private var locale
    @State private var form: MeasurementForm?
    @State private var addsPiece = false
    @State private var toast: NookToastMessage?

    var body: some View {
        FitPage(
            model: model,
            actions: FitActions(
                retry: { Task { await model.load(from: services, locale: locale) } },
                chooseFit: { fit in saving { await model.setUsualFit(fit, in: services) } },
                chooseUnits: { units in saving { await model.setUnits(units, in: services) } },
                edit: { field in
                    form = MeasurementForm(
                        field: field, measurements: model.profile.measurements, units: model.units, locale: locale)
                },
                addPiece: { addsPiece = true },
                removePiece: remove
            )
        )
        .navigationTitle(FitText.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The title is on the wall.
            ToolbarItem(placement: .principal) {
                Text(verbatim: "").accessibilityHidden(true)
            }
        }
        .nookSheet(
            item: $form, title: { FitText.name($0.field) },
            subtitle: { "\(FitText.help($0.field)) \(FitText.leaveEmpty)" }
        ) { form in
            MeasurementSheet(form: form) { value in
                await save(value, for: form.field)
            } clear: {
                guard await model.clear(form.field, in: services) else { return false }
                self.form = nil
                toast = NookToastMessage(FitText.cleared(FitText.name(form.field)), systemImage: "checkmark")
                return true
            }
        }
        .nookSheet(isPresented: $addsPiece, title: FitText.addPiece, detents: [.large]) {
            FitPieceSheet { piece in
                guard await model.add(piece, in: services) else { return false }
                addsPiece = false
                toast = NookToastMessage(FitText.added(piece.brand), systemImage: "checkmark")
                return true
            }
        }
        .overlay {
            Color.clear
                .nookToast($toast)
        }
        // Fit and measurements' quick tour (Phase 16b), once Profile's model has loaded.
        .screenTour(
            FitTour.definition, isReady: model.phase == .loaded && form == nil && !addsPiece && toast == nil)
    }

    private func save(_ value: MeasurementForm.Value, for field: MeasurementField) async -> Bool {
        let saved: Bool
        let isEmpty: Bool
        switch value {
        case .length(let length):
            saved = await model.save(length, for: field, in: services)
            isEmpty = length == nil
        case .weight(let weight):
            saved = await model.save(weight: weight, in: services)
            isEmpty = weight == nil
        }
        guard saved else { return false }
        form = nil
        let name = FitText.name(field)
        toast = NookToastMessage(isEmpty ? FitText.cleared(name) : FitText.saved(name), systemImage: "checkmark")
        return true
    }

    private func remove(_ piece: FitPiece) {
        Task {
            guard let removed = await model.remove(piece.id, in: services) else {
                toast = NookToastMessage(ProfileText.failed, systemImage: "exclamationmark.circle")
                return
            }
            toast = NookToastMessage(
                FitText.removed(piece.brand), systemImage: "minus.circle", actionTitle: FitText.undo
            ) {
                Task { _ = await model.restore(removed, in: services) }
            }
        }
    }

    /// Saves a tap straight away, and says so only if it didn't save.
    private func saving(_ change: @escaping () async -> Bool) {
        Task {
            if !(await change()) {
                toast = NookToastMessage(ProfileText.failed, systemImage: "exclamationmark.circle")
            }
        }
    }
}
