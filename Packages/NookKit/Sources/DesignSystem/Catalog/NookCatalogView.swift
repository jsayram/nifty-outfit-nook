#if DEBUG
    import SwiftUI

    /// Every DesignSystem component on one scrolling page, with switches for light or dark and
    /// the text size, so they can be checked side by side with the mockups.
    ///
    /// Debug builds only: launch the app with `-catalog`. Nothing in Catalog is compiled into a
    /// Release build.
    public struct NookCatalogView: View {
        nonisolated enum AppearanceChoice: Hashable { case system, light, dark }
        nonisolated enum TextSizeChoice: String, CaseIterable, Hashable {
            case system = "System"
            case large = "Default"
            case xxxLarge = "XXXL"
            case ax3 = "AX3"
            case ax5 = "AX5"

            var size: DynamicTypeSize? {
                switch self {
                case .system: nil
                case .large: .large
                case .xxxLarge: .xxxLarge
                case .ax3: .accessibility3
                case .ax5: .accessibility5
                }
            }
        }

        @State private var appearance = AppearanceChoice.system
        @State private var textSize = TextSizeChoice.system

        public init() {}

        public var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: NookSpacing.xxLarge) {
                        controls
                        ForEach(CatalogDemo.allCases) { demo in
                            VStack(alignment: .leading, spacing: NookSpacing.medium) {
                                Text(demo.title)
                                    .nookTextStyle(.lookTitle)
                                    .foregroundStyle(.nook.textPrimary)
                                    .accessibilityAddTraits(.isHeader)
                                demo.content
                            }
                            .accessibilityIdentifier("catalog.\(demo.rawValue)")
                        }
                    }
                    .padding(.horizontal, NookSpacing.screenMargin)
                    .padding(.vertical, NookSpacing.large)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                    .dynamicTypeSize(
                        textSize.size.map { $0...$0 } ?? DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5)
                }
                .background(Color.nook.wallGradient.ignoresSafeArea())
                .navigationTitle(Text(verbatim: "Component catalog"))
                .navigationBarTitleDisplayMode(.inline)
            }
            .preferredColorScheme(colorScheme)
            .accessibilityIdentifier("catalog")
        }

        private var controls: some View {
            VStack(alignment: .leading, spacing: NookSpacing.small) {
                CatalogCaption("Debug build only. Launch with -catalog.")
                NookSegmentedPicker(
                    "Appearance",
                    selection: $appearance,
                    options: [
                        .init(.system, title: "System"),
                        .init(.light, title: "Light", systemImage: "sun.max"),
                        .init(.dark, title: "Dark", systemImage: "moon"),
                    ]
                )
                NookChipBar("Text size", layout: .wrap) {
                    ForEach(TextSizeChoice.allCases, id: \.self) { choice in
                        NookChip(choice.rawValue, isSelected: textSize == choice) { textSize = choice }
                    }
                }
                .padding(.horizontal, -NookSpacing.screenMargin)
            }
        }

        private var colorScheme: ColorScheme? {
            switch appearance {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    #Preview {
        NookCatalogView()
    }
#endif
