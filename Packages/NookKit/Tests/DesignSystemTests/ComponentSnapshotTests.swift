import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem

/// Snapshots of every catalog page in light, dark and the largest accessibility text size
/// (AX5) on an iPhone-wide canvas, plus the pages whose layout changes with width on an
/// iPad-wide canvas. The reference images are in `__Snapshots__/ComponentSnapshotTests`.
///
/// How they're drawn, and how to record new ones, is in `DesignSystem/README.md` under
/// "Snapshot tests".
@MainActor
@Suite
struct ComponentSnapshotTests {
    @Test(arguments: CatalogDemo.allCases)
    func iPhone(demo: CatalogDemo) {
        for look in SnapshotLook.allCases {
            assertComponentSnapshot(
                demo.content, canvas: .iPhone, look: look, named: "\(demo.rawValue)-\(look.rawValue)")
        }
    }

    /// Pages that stretch or centre on a wide screen. Light only, to keep the image count down.
    @Test(arguments: [CatalogDemo.segmented, .chips, .rows, .banners, .emptyState])
    func iPad(demo: CatalogDemo) {
        assertComponentSnapshot(demo.content, canvas: .iPad, look: .light, named: "\(demo.rawValue)-ipad")
    }

    /// The references were recorded on this simulator runtime. Fonts can render a little
    /// differently on another one, so a mismatch here explains a wave of snapshot failures.
    @Test func runsOnTheRecordedRuntime() {
        #expect(
            UIDevice.current.systemVersion == SnapshotCanvas.recordedSystemVersion,
            "Snapshots were recorded on iOS \(SnapshotCanvas.recordedSystemVersion). Run them on that simulator."
        )
    }
}
