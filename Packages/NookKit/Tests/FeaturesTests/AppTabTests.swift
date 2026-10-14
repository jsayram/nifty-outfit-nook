import Testing

@testable import Features

struct AppTabTests {
    @Test func tabsAreHomeClosetSavedLooksInOrder() {
        #expect(AppTab.allCases == [.home, .closet, .savedLooks])
    }

    @Test func tabTitlesMatchTheRoomDirection() {
        #expect(AppTab.allCases.map(\.title) == ["Home", "Closet", "Saved Looks"])
    }

    @Test func tabIconsMatchTheMockups() {
        #expect(AppTab.allCases.map(\.systemImage) == ["house", "hanger", "bookmark"])
    }
}
