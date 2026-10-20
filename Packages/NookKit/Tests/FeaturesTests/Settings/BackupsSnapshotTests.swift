import DesignSystem
import Models
import NookTestSupport
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem
@testable import Features

/// Backups (Phase 21b), compared with the PNGs in `__Snapshots__/BackupsSnapshotTests`. Drawn
/// 402 points wide at full height, like the other settings screens:
/// - Backups with what goes and Undo restore, in light and at AX5 in dark.
/// - Export a copy with a generated passphrase, and with her own passphrase too short (dark).
/// - Restore's preview, the done step, and a damaged copy.
/// - Privacy and terms with the Backups row.
@MainActor
@Suite(.heavyMainActorWork)
struct BackupsSnapshotTests {
    static let width: CGFloat = 402
    private let us = Locale(identifier: "en_US")

    private func model(_ flow: BackupsModel.Flow? = nil, step: BackupsModel.Step = .passphrase) -> BackupsModel {
        let model = BackupsModel()
        model.show(
            summary: BackupSummary(
                counts: BackupCounts(pieces: 21, recentlyDeleted: 2, looks: 6, suitcases: 6, pictures: 3, drafts: 1),
                photos: 24, estimatedBytes: 112_000_000, includesBodyData: true, includesTryOnPhoto: true),
            undo: UndoRestore(takenAt: TestTime.day(-1), until: TestTime.day(6)), flow: flow, step: step)
        return model
    }

    private func sheet(_ model: BackupsModel, _ flow: BackupsModel.Flow) -> some View {
        NookSheetContainer(title: BackupFlowSheet.title(flow)) {
            BackupFlowSheet(model: model, flow: flow)
        }
        .background(Color.nook.wallGradient)
    }

    @Test func backupsScreen() {
        assertSnapshot(BackupsPage(model: model()), named: "backups")
        assertSnapshot(
            BackupsPage(model: model()), colorScheme: .dark, dynamicTypeSize: .accessibility5,
            named: "backups-ax5-dark")
    }

    @Test func exportSheet() {
        assertSnapshot(sheet(model(.export), .export), named: "export-generated")
        let own = model(.export)
        own.passphraseKind = .own
        own.ownPassphrase = "too short"
        assertSnapshot(sheet(own, .export), colorScheme: .dark, named: "export-own-dark")
    }

    @Test func restoreSheet() {
        assertSnapshot(
            sheet(model(.restore, step: .preview(ScriptedBackups.preview)), .restore), named: "restore-preview")
        let outcome = RestoreOutcome(
            counts: ScriptedBackups.preview.inCopy, added: 40, conflicts: 2, deletedForGood: 1,
            undoUntil: TestTime.day(7))
        assertSnapshot(sheet(model(.restore, step: .restored(outcome)), .restore), named: "restored")
        assertSnapshot(sheet(model(.restore, step: .failed(.damaged)), .restore), named: "restore-damaged")
    }

    @Test func privacyWithBackups() {
        assertSnapshot(PrivacyPage(keepsChanges: true, backups: {}), named: "privacy-backups")
    }

    // MARK: Drawing

    private func assertSnapshot(
        _ view: some View,
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        expectFitsWidth(
            view, width: Self.width, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize, named: name,
            fileID: fileID, filePath: filePath, line: line, column: column)
        let content =
            view
            .frame(width: Self.width)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.closetIsStillImage, true)
            .environment(\.nookStaticRendering, true)
            .environment(\.colorScheme, colorScheme)
            .environment(\.displayScale, 1)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, us)
            .environment(\.calendar, TestTime.calendar)
            .environment(\.timeZone, TestTime.calendar.timeZone)
            .environment(\.scenePhase, .active)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: Self.width, height: nil)
        guard let image = renderer.uiImage else {
            Issue.record("ImageRenderer produced no image for \(name)")
            return
        }
        SnapshotTesting.assertSnapshot(
            of: image,
            as: .image(precision: 0.995, perceptualPrecision: 0.98, scale: 1),
            named: name,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }
}
