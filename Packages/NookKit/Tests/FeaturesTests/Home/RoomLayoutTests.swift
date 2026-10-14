import CoreGraphics
import SwiftUI
import Testing

@testable import Features

/// The room scales to each phone and keeps every control a real target.
struct RoomLayoutTests {
    @Test(arguments: PhoneScreen.allCases)
    func everyControlIsAtLeast44Points(phone: PhoneScreen) {
        let layout = phone.layout
        for control in RoomControl.allCases {
            let target = layout.target(control.stageRect)
            #expect(target.width >= 44 && target.height >= 44, "\(control) on \(phone) is \(target.size)")
        }
    }

    /// Neighbouring controls don't steal each other's taps. The wardrobe is the exception: the
    /// suitcase stands in front of its lower half, as in the mockup, and wins there.
    @Test(arguments: PhoneScreen.allCases)
    func controlsDoNotOverlap(phone: PhoneScreen) {
        let layout = phone.layout
        let controls = RoomControl.allCases.filter { $0 != .wardrobe }
        for (index, first) in controls.enumerated() {
            for second in controls.dropFirst(index + 1) {
                let overlap = layout.target(first.stageRect).intersection(layout.target(second.stageRect))
                #expect(
                    overlap.isNull || overlap.width < 0.5 || overlap.height < 0.5,
                    "\(first) and \(second) overlap by \(overlap.size) on \(phone)")
            }
        }
    }

    @Test(arguments: PhoneScreen.allCases)
    func everyControlIsBetweenTheBarsOrReachableByScrolling(phone: PhoneScreen) {
        let layout = phone.layout
        for control in RoomControl.allCases {
            let target = layout.target(control.stageRect)
            #expect(target.minY >= layout.insets.top - 0.5, "\(control) is under the navigation bar on \(phone)")
            #expect(
                target.maxY <= layout.contentHeight - layout.insets.bottom + 0.5,
                "\(control) is under the tab bar on \(phone)")
        }
    }

    @Test func largerPhonesFitWithoutScrolling() {
        #expect(!PhoneScreen.iPhone17.layout.scrolls)
        #expect(!PhoneScreen.iPhone17ProMax.layout.scrolls)
    }

    /// The SE is too short to show the whole room with 44 pt targets, so it scrolls a little
    /// rather than shrinking the drawers below 44 pt.
    @Test func iPhoneSEScrollsInsteadOfShrinkingTargets() {
        let layout = PhoneScreen.iPhoneSE.layout
        #expect(layout.scrolls)
        #expect(layout.scale >= RoomLayout.minimumScale)
        #expect(layout.contentHeight < layout.size.height * 1.3, "It should only scroll a little")
    }

    @Test(arguments: PhoneScreen.allCases)
    func roomIsCentredAndNeverWiderThanTheScreen(phone: PhoneScreen) {
        let layout = phone.layout
        #expect(layout.originX >= -0.01)
        #expect(
            abs(layout.rect(CGRect(x: 0, y: 0, width: RoomStage.width, height: 1)).midX - layout.size.width / 2) < 0.01)
    }

    @Test func bedStaysClearOfTheDrawers() {
        for phone in PhoneScreen.allCases {
            let layout = phone.layout
            let privacy = layout.rect(RoomStage.drawers[2])
            #expect(layout.bed.minY >= privacy.minY + 20, "The bed covers the bottom drawer's plate on \(phone)")
        }
    }

    @Test func tinyTargetsGrowAroundTheirCentre() {
        let layout = RoomLayout(size: CGSize(width: 390, height: 844), insets: EdgeInsets())
        let target = layout.target(CGRect(x: 100, y: 100, width: 10, height: 10))
        #expect(target.size.width >= 44 && target.size.height >= 44)
        #expect(abs(target.midX - layout.rect(CGRect(x: 100, y: 100, width: 10, height: 10)).midX) < 0.01)
    }
}

/// Phone screens in portrait, with the bar heights measured on the iOS 26.5 simulator: the
/// navigation bar's bottom edge and the tab bar's top edge from the bottom of the screen.
enum PhoneScreen: String, CaseIterable, CustomTestStringConvertible {
    case iPhoneSE
    case iPhone17
    case iPhone17ProMax

    var size: CGSize {
        switch self {
        case .iPhoneSE: CGSize(width: 375, height: 667)
        case .iPhone17: CGSize(width: 402, height: 874)
        case .iPhone17ProMax: CGSize(width: 440, height: 956)
        }
    }

    var insets: EdgeInsets {
        switch self {
        case .iPhoneSE: EdgeInsets(top: 74, leading: 0, bottom: 83, trailing: 0)
        case .iPhone17, .iPhone17ProMax: EdgeInsets(top: 116, leading: 0, bottom: 83, trailing: 0)
        }
    }

    var layout: RoomLayout { RoomLayout(size: size, insets: insets) }

    var testDescription: String { rawValue }
}
