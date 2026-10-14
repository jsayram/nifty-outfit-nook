import SwiftUI

/// A stand-in for a screen Home opens whose real content comes in a later phase.
struct HomeStubScreen: View {
    let destination: HomeDestination

    var body: some View {
        StubScreen(title: destination.title, systemImage: destination.systemImage, identifier: destination.identifier)
    }
}

#Preview {
    NavigationStack {
        HomeStubScreen(destination: .styleMe(choosingOccasion: false))
    }
}
