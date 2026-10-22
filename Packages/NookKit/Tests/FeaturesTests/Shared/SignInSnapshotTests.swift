import DesignSystem
import Fixtures
import Models
import NookTestSupport
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem
@testable import Features

/// Release: the sign-in sheet, Profile's account row and the Report a problem sheet, compared with
/// the PNGs in `__Snapshots__/SignInSnapshotTests`. Drawn 402 points wide (iPhone 17) at 1x.
/// - The sign-in sheet for try-on (light, dark with a problem, AX5).
/// - Profile with the account row: signed out (light), signed in (dark).
/// - Report a problem on a try-on picture (light, and AX5 with the picture ticked).
@MainActor
@Suite(.heavyMainActorWork)
struct SignInSnapshotTests {
    static let width: CGFloat = 402
    private let us = Locale(identifier: "en_US")

    // MARK: The sign-in sheet

    @Test func signInSheet() {
        assertSnapshot(SignInSheetContent(reason: .tryOn), named: "sign-in-sheet")
        assertSnapshot(
            SignInSheetContent(reason: .styling, problem: .offline), colorScheme: .dark, named: "sign-in-sheet-dark")
    }

    @Test func signInSheetAX5() {
        assertSnapshot(
            SignInSheetContent(reason: .stylingAccess), dynamicTypeSize: .accessibility5, named: "sign-in-sheet-ax5")
    }

    // MARK: Profile's account row

    private func profile(_ account: ProfileModel.Account) -> ProfileModel {
        let model = ProfileModel()
        model.show(FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar).profile, locale: us)
        model.show(account: account)
        return model
    }

    @Test func profileAccountRow() {
        assertSnapshot(ProfilePage(model: profile(.signedOut)), named: "profile-signed-out")
        assertSnapshot(ProfilePage(model: profile(.signedIn)), colorScheme: .dark, named: "profile-signed-in-dark")
    }

    // MARK: Report a problem

    private func report(picture: Bool) -> AIReportModel {
        let target = AIReportTarget(
            subject: .tryOnPicture, resultID: "act_0f1e2d3c4b5a69788796a5b4c3d2e1f0", madeBy: .cloud,
            madeAt: TestTime.now, picture: .stored("photo-1"))
        let model = AIReportModel(target: target, canHide: true)
        model.reason = .looksWrongOnMe
        model.includesPicture = picture
        return model
    }

    @Test func reportSheet() {
        assertSnapshot(AIReportContent(model: report(picture: false)), named: "report-sheet")
    }

    @Test func reportSheetAX5() {
        assertSnapshot(
            AIReportContent(model: report(picture: true)), dynamicTypeSize: .accessibility5, named: "report-sheet-ax5")
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
            .background(Color.nook.background)
            .environment(\.closetIsStillImage, true)
            .environment(\.nookStaticRendering, true)
            .environment(\.colorScheme, colorScheme)
            .environment(\.displayScale, 1)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, us)
            .environment(\.calendar, TestTime.calendar)
        let renderer = ImageRenderer(content: content.snapshotPhotos())
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
