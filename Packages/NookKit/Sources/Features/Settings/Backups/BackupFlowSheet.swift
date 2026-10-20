import DesignSystem
import Models
import SwiftUI
import UniformTypeIdentifiers

/// The one sheet for Export a copy, Check a copy and Restore from a copy, showing the model's
/// current step. The Files sheet that saves an export opens from here, over it.
struct BackupFlowSheet: View {
    @Bindable var model: BackupsModel
    let flow: BackupsModel.Flow
    @State private var isAskingReplace = false
    @State private var toast: NookToastMessage?
    @Environment(\.dismiss) private var dismiss

    static func title(_ flow: BackupsModel.Flow) -> String {
        switch flow {
        case .export: BackupsText.exportTitle
        case .check: BackupsText.checkTitle
        case .restore: BackupsText.restoreTitle
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The passphrase and her counts stay out of the app switcher's snapshot.
        .hiddenWhenInactive()
        .fileMover(
            isPresented: Binding(get: { savingFile != nil }, set: { _ in }), file: savingFile?.url,
            onCompletion: { result in
                guard let file = savingFile else { return }
                Task { await model.saved(file, as: (try? result.get())?.lastPathComponent) }
            },
            onCancellation: {
                guard let file = savingFile else { return }
                Task { await model.saved(file, as: nil) }
            }
        )
        .alert(BackupsText.askReplaceTitle, isPresented: $isAskingReplace) {
            Button(BackupsText.replace, role: .destructive) { replace() }
            Button(BackupsText.cancel, role: .cancel) {}
        } message: {
            Text(BackupsText.askReplaceMessage)
        }
        .nookToast($toast)
    }

    private var savingFile: BackupFile? {
        if case .saving(let file) = model.step { return file }
        return nil
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .passphrase: exportForm
        case .exporting, .saving: working(BackupsText.exporting)
        case .exported(let name):
            message(BackupsText.exported(name), systemImage: "checkmark.circle")
            if model.offersCheck {
                NookButton(BackupsText.checkThisCopy, systemImage: "checkmark.shield", kind: .soft, fillsWidth: true) {
                    dismiss()
                    model.pick(for: .check)
                }
            }
            doneButton
        case .unlock: unlockForm
        case .checking: working(BackupsText.checking)
        case .preview(let preview):
            if flow == .check { checked(preview) } else { restorePreview(preview) }
        case .restoring: working(BackupsText.restoring)
        case .restored(let outcome): restored(outcome)
        case .failed(let error):
            NookBanner(BackupsText.failed(error), systemImage: "exclamationmark.triangle", tone: .warning)
                .accessibilityIdentifier("backups.failed")
            doneButton
        }
    }

    // MARK: Export

    @ViewBuilder private var exportForm: some View {
        Text(BackupsText.exportDetail)
            .nookTextStyle(.body)
            .foregroundStyle(.nook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        NookSegmentedPicker(
            BackupsText.passphraseField, selection: $model.passphraseKind,
            options: [
                .init(.generated, title: BackupsText.makeOne, identifier: "backups.generated"),
                .init(.own, title: BackupsText.useMine, identifier: "backups.own"),
            ])
        switch model.passphraseKind {
        case .generated:
            Text(verbatim: model.generated)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(.nook.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .padding(NookSpacing.medium)
                .floorCard()
                .accessibilityIdentifier("backups.passphrase")
            NookButton(BackupsText.copyPassphrase, systemImage: "doc.on.doc", kind: .soft, fillsWidth: true) {
                copy(model.generated)
            }
        case .own:
            PassphraseField(
                title: BackupsText.passphraseField, text: $model.ownPassphrase, identifier: "backups.ownPassphrase",
                isNew: true)
            PassphraseField(
                title: BackupsText.confirmField, text: $model.ownConfirmation, identifier: "backups.ownConfirmation",
                isNew: true)
            if let problem = model.passphraseProblem {
                Text(BackupsText.problem(problem))
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
            }
        }
        NookBanner(BackupsText.cantRecover, systemImage: "key", tone: .neutral)
        NookButton(BackupsText.exportButton, systemImage: "square.and.arrow.up", fillsWidth: true) {
            Task { await model.export() }
        }
        .disabled(!model.canExport)
        .accessibilityIdentifier("backups.exportButton")
    }

    /// Copies the generated passphrase for 2 minutes, on this iPhone only (not Universal
    /// Clipboard), and only because she asked.
    private func copy(_ passphrase: String) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: passphrase]],
            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)])
        toast = NookToastMessage(BackupsText.copied, systemImage: "doc.on.doc")
    }

    // MARK: Check and Restore

    @ViewBuilder private var unlockForm: some View {
        Text(BackupsText.unlockLine)
            .nookTextStyle(.body)
            .foregroundStyle(.nook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        PassphraseField(
            title: BackupsText.passphraseField, text: $model.unlockPassphrase, identifier: "backups.unlockPassphrase",
            submit: { Task { await model.unlock() } }
        )
        .onChange(of: model.unlockPassphrase) { model.wrongPassphrase = false }
        if model.wrongPassphrase {
            Text(BackupsText.wrongPassphrase)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .accessibilityIdentifier("backups.wrongPassphrase")
        }
        NookButton(BackupsText.open, systemImage: "lock.open", fillsWidth: true) {
            Task { await model.unlock() }
        }
        .disabled(model.unlockPassphrase.isEmpty)
        .accessibilityIdentifier("backups.open")
    }

    @ViewBuilder private func checked(_ preview: BackupPreview) -> some View {
        message(BackupsText.copyWorks, systemImage: "checkmark.shield")
        previewDetails(preview)
        doneButton
    }

    @ViewBuilder private func restorePreview(_ preview: BackupPreview) -> some View {
        previewDetails(preview)
        VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
            NookButton(BackupsText.replace, systemImage: "arrow.counterclockwise", fillsWidth: true) {
                if preview.onPhone.isEmpty { replace() } else { isAskingReplace = true }
            }
            .accessibilityIdentifier("backups.replace")
            note(BackupsText.replaceDetail)
        }
        VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
            NookButton(BackupsText.addMissing, systemImage: "plus.square.on.square", kind: .soft, fillsWidth: true) {
                Task { await model.restore(preview, as: .addMissing) }
            }
            .accessibilityIdentifier("backups.addMissing")
            note(BackupsText.addMissingDetail)
        }
    }

    @ViewBuilder private func previewDetails(_ preview: BackupPreview) -> some View {
        Text(BackupsText.copyFrom(preview.createdAt))
            .nookTextStyle(.body)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("backups.copyDate")
        SettingsGroup(header: BackupsText.inCopyHeader, identifier: "backups.inCopy") {
            BackupCountRows(counts: preview.inCopy)
            if preview.includesBodyData { SettingsInfoRow(title: BackupsText.bodyData, systemImage: "ruler") }
            if preview.includesTryOnPhoto {
                SettingsInfoRow(title: BackupsText.tryOnPhoto, systemImage: "person.crop.square")
            }
            if preview.deletedForGood > 0 { SettingsNote(BackupsText.deletedForGood(preview.deletedForGood)) }
            if preview.missingReferences > 0 { SettingsNote(BackupsText.missing(preview.missingReferences)) }
        }
        if flow == .restore {
            SettingsGroup(header: BackupsText.onPhoneHeader, identifier: "backups.onPhone") {
                BackupCountRows(counts: preview.onPhone)
            }
        }
    }

    @ViewBuilder private func restored(_ outcome: RestoreOutcome) -> some View {
        message(BackupsText.restored, systemImage: "checkmark.circle")
        SettingsGroup(identifier: "backups.restored") {
            BackupCountRows(counts: outcome.counts)
            if outcome.conflicts > 0 { SettingsNote(BackupsText.conflicts(outcome.conflicts)) }
            if outcome.deletedForGood > 0 { SettingsNote(BackupsText.deletedForGood(outcome.deletedForGood)) }
            if let until = outcome.undoUntil { SettingsNote(BackupsText.undoUntil(until)) }
        }
        doneButton
    }

    private func replace() {
        guard case .preview(let preview) = model.step else { return }
        Task { await model.restore(preview, as: .replace) }
    }

    // MARK: Pieces

    private var doneButton: some View {
        NookButton(BackupsText.done, fillsWidth: true) { dismiss() }
            .accessibilityIdentifier("backups.done")
    }

    private func working(_ text: String) -> some View {
        HStack(spacing: NookSpacing.medium) {
            NookLoadingIndicator(size: .small)
            Text(text)
                .nookTextStyle(.body)
                .foregroundStyle(.nook.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("backups.working")
    }

    private func message(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text)
                .nookTextStyle(.body)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.nook.accent)
        }
        .accessibilityIdentifier("backups.message")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
