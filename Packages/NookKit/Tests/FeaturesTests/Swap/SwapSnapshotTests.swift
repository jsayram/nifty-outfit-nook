import DesignSystem
import Fixtures
import Models
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem
@testable import Features

/// Swap a piece (Phase 11), compared with the PNGs in `__Snapshots__/SwapSnapshotTests`.
///
/// Drawn 402 points wide (iPhone 17) at full height, without the navigation and tab bars, on the
/// demo's rainy Office result:
/// - the top, as it opens, in light and at AX5;
/// - the shoes with the heels being tried, in light and dark;
/// - from the Weekend suitcase (no Find one);
/// - See all tops in its sheet;
/// - Your looks after a swap, marked Swapped, with Undo.
@MainActor
@Suite(.heavyMainActorWork)
struct SwapSnapshotTests {
    static let width: CGFloat = 402

    private func swap(
        _ request: StyleRequest = lookRequest(), on category: GarmentCategory? = nil
    ) async throws -> (YourLooksModel, SwapModel) {
        let looks = await swappableLooks(request)
        let swap = try #require(
            looks.swapModel(sourceName: YourLooksText(request: request, suitcaseName: looks.suitcaseName).sourceName))
        if let category, let piece = swap.pieces.first(where: { swap.category(of: $0) == category }) {
            swap.choosePiece(piece.id)
        }
        return (looks, swap)
    }

    @Test func top() async throws {
        let (_, model) = try await swap()
        assertSnapshot(SwapPage(model: model), named: "top")
    }

    @Test func topAX5() async throws {
        let (_, model) = try await swap()
        assertSnapshot(SwapPage(model: model), dynamicTypeSize: .accessibility5, scale: 1, named: "top-ax5")
    }

    @Test func shoesTrying() async throws {
        let (_, model) = try await swap(on: .shoes)
        model.select("g-black-heels")
        assertSnapshot(SwapPage(model: model), named: "shoes-trying")
    }

    @Test func shoesTryingDark() async throws {
        let (_, model) = try await swap(on: .shoes)
        model.select("g-black-heels")
        assertSnapshot(SwapPage(model: model), colorScheme: .dark, named: "shoes-trying-dark")
    }

    /// From a suitcase: only what's packed, and no Find one (LR-07.4).
    @Test func fromASuitcase() async throws {
        let (_, model) = try await swap(lookRequest(source: .suitcase("s-weekend"), occasion: .casual))
        assertSnapshot(SwapPage(model: model), named: "suitcase")
    }

    /// LR-07.3: See all tops, with the weaker matches marked.
    @Test func seeAll() async throws {
        let (_, model) = try await swap()
        let picker = ClosetModel(scope: model.seeAllScope)
        picker.show(
            Array(model.setup.garments.values), suitcases: model.setup.suitcases, profile: Profile(),
            now: ClosetTestTime.now)
        let text = SwapText(category: model.category, sourceName: model.setup.sourceName)
        assertSnapshot(
            NookSheetContainer(title: text.seeAllTitle) {
                PiecePicker(
                    model: picker, lead: text.seeAllLead, prompt: "Search these pieces", hint: "",
                    emptyTitle: "", emptyMessage: ""
                ) { _ in }
            }
            .background(Color.nook.wallGradient),
            named: "see-all")
    }

    /// Back on Your looks: the heels marked Swapped and Undo under the pieces.
    @Test func yourLooksAfterASwap() async throws {
        let (looks, model) = try await swap(on: .shoes)
        model.select("g-black-heels")
        looks.apply(try #require(model.swapped()))
        assertSnapshot(YourLooksPage(model: looks), named: "your-looks-swapped")
    }

    private func assertSnapshot(
        _ view: some View,
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
        scale: CGFloat = 2,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let content =
            view
            .frame(width: Self.width)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.closetIsStillImage, true)
            .environment(\.nookStaticRendering, true)
            .environment(\.colorScheme, colorScheme)
            .environment(\.displayScale, scale)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, ClosetTestTime.locale)
            .environment(\.calendar, ClosetTestTime.calendar)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: Self.width, height: nil)
        guard let image = renderer.uiImage else {
            Issue.record("ImageRenderer produced no image for \(name)")
            return
        }
        SnapshotTesting.assertSnapshot(
            of: image,
            as: .image(precision: 0.995, perceptualPrecision: 0.98, scale: scale),
            named: name,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }
}
