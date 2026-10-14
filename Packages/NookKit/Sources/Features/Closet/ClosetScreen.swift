import Models
import SwiftUI

/// Placeholder until the Closet phase builds the real screen. For now it shows how many pieces
/// the sample closet has, which proves the fixture set reached the screens.
struct ClosetScreen: View {
    @Environment(\.services) private var services
    @State private var pieceCount: Int?

    var body: some View {
        PlaceholderScreen(
            tab: .closet,
            detail: pieceCount.map { count in
                Text("\(count) pieces in the sample closet", bundle: .module, comment: "Placeholder detail on Closet")
            }
        )
        .task {
            guard let closet = services?.closet else { return }
            pieceCount = try? await closet.garments().count(where: \.isInCloset)
        }
    }
}
