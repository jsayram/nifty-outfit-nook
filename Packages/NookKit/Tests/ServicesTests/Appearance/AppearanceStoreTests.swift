import Foundation
import Models
import Testing

@testable import Services

/// N3: her light or dark choice is kept on the iPhone, follows the iPhone until she chooses, and
/// Delete my data forgets it.
struct AppearanceStoreTests {
    private func suiteName() -> String { "test.appearance.\(UUID().uuidString)" }

    @Test func followsTheIPhoneUntilSheChooses() {
        #expect(DefaultsAppearanceStore(suiteName: suiteName()).current() == .system)
    }

    @Test(arguments: [AppearanceChoice.light, .dark])
    func keepsHerChoiceAcrossLaunches(choice: AppearanceChoice) {
        let name = suiteName()
        DefaultsAppearanceStore(suiteName: name).save(choice)
        // A new store on the same suite is the next launch.
        #expect(DefaultsAppearanceStore(suiteName: name).current() == choice)
    }

    @Test func deleteMyDataForgetsIt() async throws {
        let name = suiteName()
        let store = DefaultsAppearanceStore(suiteName: name)
        store.save(.dark)
        try await store.eraseAll()
        #expect(DefaultsAppearanceStore(suiteName: name).current() == .system)
    }

    @Test func anUnreadableValueFollowsTheIPhone() {
        let name = suiteName()
        UserDefaults(suiteName: name)?.set("sepia", forKey: DefaultsAppearanceStore.key)
        #expect(DefaultsAppearanceStore(suiteName: name).current() == .system)
    }
}
