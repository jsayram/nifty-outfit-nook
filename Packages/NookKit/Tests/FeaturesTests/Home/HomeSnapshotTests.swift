import DesignSystem
import Fixtures
import Models
import NookTestSupport
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import Features

/// The room on three phone sizes in light appearance, compared with the PNGs in
/// `__Snapshots__/HomeSnapshotTests`, plus every window and hamper state in light and dark on
/// one sheet each (Phase 5a), and the dark room (Phase 5b). The large-text and sideways layouts are
/// in `HomeLayoutSnapshotTests`.
///
/// The canvas is drawn the way the screen draws it, between bars of the measured height; the
/// system navigation bar and tab bar themselves aren't in the picture. The iPhone SE room is
/// taller than its screen because it scrolls. How to record new references is in
/// `DesignSystem/README.md` under "Snapshot tests".
@MainActor
@Suite(.heavyMainActorWork)
struct HomeSnapshotTests {
    /// The mockup's room: 58° and rain, laundry tracking off.
    static let demo = HomeRoomContent(
        signName: "Lily", source: SourcePlate(kind: .mainCloset, pieceCount: 17), hamper: .off,
        weather: WeatherSnapshot(condition: .rain, temperatureCelsius: 14.5, observedAt: .distantPast))

    @Test(arguments: PhoneScreen.allCases)
    func room(phone: PhoneScreen) {
        assertRoomSnapshot(Self.demo, on: phone, named: phone.rawValue)
    }

    /// A fresh install: no name on the sign, an empty closet.
    @Test func emptyRoom() {
        let empty = HomeRoomContent(signName: "", source: SourcePlate(kind: .mainCloset, pieceCount: 0), hamper: .off)
        assertRoomSnapshot(empty, on: .iPhone17, named: "empty")
    }

    /// A long name wraps and shrinks on the sign; a suitcase source turns its plate green.
    @Test func longNameAndSuitcase() {
        let content = HomeRoomContent(
            signName: "Anna-Katharina Lee",
            source: SourcePlate(kind: .suitcase(name: "Jose’s house"), pieceCount: 5),
            hamper: .toWash(2)
        )
        assertRoomSnapshot(content, on: .iPhoneSE, named: "long-name-suitcase")
    }

    /// A suitcase source takes the suitcase's own drawing, and the calendar shows her last
    /// occasion (Phase 13), in light and dark.
    @Test func suitcaseSourceAndOccasion() {
        var content = Self.demo
        content.source = SourcePlate(kind: .suitcase(name: "Weekend", icon: .duffel), pieceCount: 8)
        content.occasion = .dateNight
        assertRoomSnapshot(content, on: .iPhone17, named: "suitcase-source")
        assertRoomSnapshot(content, on: .iPhone17, colorScheme: .dark, named: "suitcase-source-dark")
    }

    /// Her three newest saved looks in the frames under the shelf (Phase 12a), light and dark.
    @Test func framedLooks() {
        let data = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)
        var content = Self.demo
        content.framedLooks = HomeModel.framedLooks(from: data.looks, garments: data.garments)
        assertRoomSnapshot(content, on: .iPhone17, named: "framed-looks")
        assertRoomSnapshot(content, on: .iPhone17, colorScheme: .dark, named: "framed-looks-dark")
    }

    /// A snowy night with a full hamper and tracking on: the night window, the lamp's glow and
    /// the tall heap, with Maya asleep (RD-01.4, RD-11, RD-12).
    @Test func nightWithAFullHamper() {
        let content = HomeRoomContent(
            signName: "Lily",
            source: SourcePlate(kind: .mainCloset, pieceCount: 17),
            hamper: .toWash(8),
            weather: WeatherSnapshot(
                condition: .snow, temperatureCelsius: -1.1, isNight: true, observedAt: .distantPast)
        )
        assertRoomSnapshot(content, on: .iPhone17, named: "night-full-hamper")
    }

    /// Dark appearance (Phase 5b): the same room at night, with the lamp's low glow, the dimmed
    /// art and the quiet faded hamper.
    @Test func darkRoom() {
        assertRoomSnapshot(Self.demo, on: .iPhone17, colorScheme: .dark, named: "dark")
    }

    /// Sun, cloudy, rain, snow, night and plain, light above dark (RD-01.4).
    @Test func windows() {
        let row = HStack(spacing: 12) {
            ForEach(RoomWindow.allCases, id: \.self) { window in
                RoomArtImage(window.art).frame(width: 81.6, height: 156.4)
            }
        }
        .padding(12)
        assertStatesSnapshot(row, named: "windows")
    }

    /// Off (faded), all clean, a few to wash and full, each with its plate, light above dark (RD-11).
    @Test func hampers() {
        let states: [(HamperLook, HamperState)] = [
            (.faded, .off), (.empty, .allClean), (.some, .toWash(2)), (.full, .toWash(8)),
        ]
        let row = HStack(alignment: .bottom, spacing: 16) {
            ForEach(states, id: \.0) { look, hamper in
                let art = look.stageRect
                let base = RoomStage.hamperArt
                ZStack(alignment: .topLeading) {
                    RoomArtImage(look.art).frame(width: art.width, height: art.height)
                    LaundryPlate(hamper: hamper)
                        .frame(width: RoomStage.laundryPlate.width, height: RoomStage.laundryPlate.height)
                        .offset(
                            x: RoomStage.laundryPlate.minX - base.minX,
                            y: RoomStage.laundryPlate.minY - art.minY)
                }
                .frame(width: art.width, height: art.height, alignment: .topLeading)
            }
        }
        .padding(16)
        .background(Color.nook.floorGradient)
        assertStatesSnapshot(row, named: "hampers")
    }

    @Test func runsOnTheRecordedRuntime() {
        #expect(
            UIDevice.current.systemVersion == "26.5", "Snapshots were recorded on iOS 26.5. Run them on that simulator."
        )
    }

    private func assertRoomSnapshot(
        _ content: HomeRoomContent,
        on phone: PhoneScreen,
        colorScheme: ColorScheme = .light,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let layout = phone.layout
        let view = RoomCanvas(layout: layout, content: content, open: { _ in })
            .environment(\.roomIsStillImage, true)
            .environment(\.closetIsStillImage, true)
            .environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.locale, Locale(identifier: "en_US"))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: layout.size.width, height: layout.contentHeight)
        guard let image = renderer.uiImage else {
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

    /// `states` twice, on the wall in light and then in dark.
    private func assertStatesSnapshot<States: View>(
        _ states: States,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let view = VStack(spacing: 0) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                states
                    .background(Color.nook.wallGradient)
                    .environment(\.colorScheme, scheme)
            }
        }
        .environment(\.dynamicTypeSize, .large)
        .environment(\.locale, Locale(identifier: "en_US"))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.uiImage else {
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
}
