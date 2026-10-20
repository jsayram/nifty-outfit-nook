import NookTestSupport
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem

/// The width a snapshot is drawn at.
enum SnapshotCanvas {
    /// An iPhone 13 to 16 width.
    case iPhone
    /// An iPad Air width in portrait.
    case iPad

    var width: CGFloat {
        switch self {
        case .iPhone: 390
        case .iPad: 820
        }
    }

    /// The iOS simulator runtime the reference images were recorded on, locally and on CI.
    static let recordedSystemVersion = "27.0"
}

/// Light, dark, and the largest accessibility text size (in light).
enum SnapshotLook: String, CaseIterable {
    case light
    case dark
    case ax5

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var dynamicTypeSize: DynamicTypeSize { self == .ax5 ? .accessibility5 : .large }
}

/// Draws `view` with SwiftUI's `ImageRenderer` and compares it with the reference image.
///
/// `ImageRenderer` is used instead of the library's UIKit host because it draws SwiftUI's blur,
/// so the soft shadows show up, and it lays out at the given text size before measuring, so
/// tall AX5 layouts aren't cut off. It can't draw UIKit-backed views (text fields, scroll
/// views), so `nookStaticRendering` makes the components draw plain SwiftUI stand-ins.
///
/// The tolerances absorb anti-aliasing differences between Macs; anything a person would
/// notice (a colour, a shadow, a line of text moving) still fails.
@MainActor
func assertComponentSnapshot(
    _ view: some View,
    canvas: SnapshotCanvas,
    look: SnapshotLook,
    named name: String,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    let content =
        view
        .padding(NookSpacing.large)
        .frame(width: canvas.width)
        .background(Color.nook.background)
        .environment(\.colorScheme, look.colorScheme)
        .environment(\.dynamicTypeSize, look.dynamicTypeSize)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.nookStaticRendering, true)

    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    renderer.proposedSize = ProposedViewSize(width: canvas.width, height: nil)
    guard let image = stillImage(from: renderer, scale: 2) else {
        Issue.record("ImageRenderer produced no image for \(name)")
        return
    }
    assertSnapshot(
        of: image,
        as: .image(precision: 0.995, perceptualPrecision: 0.98, scale: 2),
        named: name,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column
    )
}
