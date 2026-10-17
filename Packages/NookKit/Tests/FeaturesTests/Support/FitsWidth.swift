import NookTestSupport
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem
@testable import Features

/// Fails when `view`, offered `width`, lays itself out wider than that.
///
/// A row that won't shrink (a button kept at its full size beside a long name, say) makes its
/// whole page wider than the screen. The page then sits off both edges, and a still image
/// cropped to the screen's width can hide it. This measures the page's own width instead, so a
/// snapshot helper can call it before it draws (QA, October 2026: Laundry at AX5 was 434.7 points
/// wide in a 402 point window).
@MainActor
func expectFitsWidth(
    _ view: some View,
    width: CGFloat,
    colorScheme: ColorScheme = .light,
    dynamicTypeSize: DynamicTypeSize = .large,
    named name: String,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) {
    let measured = fittedWidth(of: view, width: width, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize)
    #expect(
        measured <= width + 0.5,
        "\(name) is \(measured) points wide, wider than its \(width) point window",
        sourceLocation: SourceLocation(
            fileID: "\(fileID)", filePath: "\(filePath)", line: Int(line), column: Int(column)))
}

/// The width `view` takes when offered `width`, with the still-image settings the snapshot
/// helpers use.
@MainActor
func fittedWidth(
    of view: some View, width: CGFloat, colorScheme: ColorScheme = .light,
    dynamicTypeSize: DynamicTypeSize = .large
) -> CGFloat {
    let content =
        view
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.closetIsStillImage, true)
        .environment(\.roomIsStillImage, true)
        .environment(\.nookStaticRendering, true)
        .environment(\.colorScheme, colorScheme)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .environment(\.locale, TestTime.locale)
        .environment(\.calendar, TestTime.calendar)
    let host = UIHostingController(rootView: content)
    return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).width
}

/// The height `view` takes when offered `width`, with the still-image settings.
@MainActor
func fittedHeight(of view: some View, width: CGFloat, dynamicTypeSize: DynamicTypeSize = .large) -> CGFloat {
    let content =
        view
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.closetIsStillImage, true)
        .environment(\.nookStaticRendering, true)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .environment(\.locale, TestTime.locale)
    let host = UIHostingController(rootView: content)
    return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
}
