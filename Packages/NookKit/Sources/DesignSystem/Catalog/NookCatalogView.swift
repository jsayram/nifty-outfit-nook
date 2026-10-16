#if DEBUG
    import SwiftUI

    /// Every DesignSystem component on one scrolling page, with switches for light or dark and
    /// the text size, so they can be checked side by side with the mockups.
    ///
    /// Debug builds only: launch the app with `-catalog`, or `-catalog -catalog-page <id>` for one
    /// page alone (`search`, `sheet`, `lookBundles` and so on), which UI tests use so they don't
    /// have to scroll the whole catalog. Nothing in Catalog is compiled into a Release build.
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
        @State private var stickers = StickerCache()
        private let extraPages: [NookCatalogPage]
        private let onlyPage: String?

        /// - Parameters:
        ///   - extraPages: pages from other modules, shown after the components. Features adds its
        ///     look bundles this way, since DesignSystem can't see garments.
        ///   - onlyPage: the ID of one page to show alone (a `CatalogDemo` case or an extra page's
        ///     ID), or `nil` for every page.
        public init(extraPages: [NookCatalogPage] = [], onlyPage: String? = nil) {
            self.extraPages = extraPages
            self.onlyPage = onlyPage
        }

        /// The page ID after `-catalog-page` in the launch arguments, if there is one.
        public static func onlyPage(in arguments: [String]) -> String? {
            guard let index = arguments.firstIndex(of: "-catalog-page"), arguments.indices.contains(index + 1)
            else { return nil }
            return arguments[index + 1]
        }

        private func isShown(_ id: String) -> Bool {
            onlyPage == nil || onlyPage == id
        }

        public var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: NookSpacing.xxLarge) {
                        controls
                        ForEach(CatalogDemo.allCases.filter { isShown($0.rawValue) }) { demo in
                            VStack(alignment: .leading, spacing: NookSpacing.medium) {
                                Text(demo.title)
                                    .nookTextStyle(.lookTitle)
                                    .foregroundStyle(.nook.textPrimary)
                                    .accessibilityAddTraits(.isHeader)
                                demo.content
                            }
                            .accessibilityIdentifier("catalog.\(demo.rawValue)")
                        }
                        ForEach(extraPages.filter { isShown($0.id) }) { page in
                            VStack(alignment: .leading, spacing: NookSpacing.medium) {
                                Text(page.title)
                                    .nookTextStyle(.lookTitle)
                                    .foregroundStyle(.nook.textPrimary)
                                    .accessibilityAddTraits(.isHeader)
                                page.content
                            }
                            .accessibilityIdentifier("catalog.\(page.id)")
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
            .environment(\.stickerCache, stickers)
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

    /// A catalog page from another module.
    public struct NookCatalogPage: Identifiable {
        public let id: String
        public let title: String
        public let content: AnyView

        public init(id: String, title: String, @ViewBuilder content: () -> some View) {
            self.id = id
            self.title = title
            self.content = AnyView(content())
        }
    }

    #Preview {
        NookCatalogView()
    }
#endif
