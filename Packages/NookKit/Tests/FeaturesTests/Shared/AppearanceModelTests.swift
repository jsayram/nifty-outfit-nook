import Models
import SwiftUI
import Testing

@testable import Features

/// N3: one appearance choice behind the lamp and the Dark mode switch. It follows the iPhone
/// until she chooses, keeps her choice, and the two controls always agree.
@MainActor
struct AppearanceModelTests {
    @Test func followsTheIPhoneByDefault() {
        let model = AppearanceModel(store: InMemoryAppearanceStore())
        #expect(model.choice == .system)
        #expect(model.colorScheme == nil)
    }

    @Test func startsFromTheKeptChoice() {
        #expect(AppearanceModel(store: InMemoryAppearanceStore(.dark)).colorScheme == .dark)
        #expect(AppearanceModel(store: InMemoryAppearanceStore(.light)).colorScheme == .light)
    }

    @Test func herChoiceIsKeptForTheNextLaunch() {
        let store = InMemoryAppearanceStore()
        AppearanceModel(store: store).setDark(true)
        #expect(store.current() == .dark)
        #expect(AppearanceModel(store: store).colorScheme == .dark)
        AppearanceModel(store: store).setDark(false)
        #expect(AppearanceModel(store: store).colorScheme == .light)
    }

    /// The lamp turns the lights off when the app shows light, including the iPhone's own light
    /// appearance before she has chosen, and on again when it shows dark.
    @Test func theLampTogglesWhatsShowing() {
        let model = AppearanceModel(store: InMemoryAppearanceStore())
        model.toggleLights(showing: .light)
        #expect(model.choice == .dark)
        model.toggleLights(showing: .dark)
        #expect(model.choice == .light)

        // The iPhone is dark and she hasn't chosen: the lamp turns the lights on.
        let following = AppearanceModel(store: InMemoryAppearanceStore())
        following.toggleLights(showing: .dark)
        #expect(following.choice == .light)
    }

    /// The lamp and the switch change the same choice, so each shows what the other did.
    @Test func lampAndSwitchStayInStep() {
        let store = InMemoryAppearanceStore()
        let model = AppearanceModel(store: store)
        // The lamp turns the lights off: the switch reads on.
        model.toggleLights(showing: .light)
        #expect(model.colorScheme == .dark)
        // The switch turns dark mode off: the lamp's lights are on.
        model.setDark(false)
        #expect(model.colorScheme == .light)
        model.toggleLights(showing: model.colorScheme ?? .light)
        #expect(model.colorScheme == .dark)
        #expect(store.current() == .dark)
    }

    @Test func afterDeleteMyDataItFollowsTheIPhoneAgain() async throws {
        let store = InMemoryAppearanceStore()
        let model = AppearanceModel(store: store)
        model.setDark(true)
        try await store.eraseAll()
        model.reload()
        #expect(model.choice == .system)
        #expect(model.colorScheme == nil)
    }
}
