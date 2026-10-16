#if DEBUG
    import SwiftUI

    /// One page of the component catalog. The snapshot tests draw each one in light, dark and
    /// the largest text size, so every component and state shown here is also under test.
    ///
    /// Debug builds only. Nothing in Catalog ships in a Release build.
    enum CatalogDemo: String, CaseIterable, Identifiable {
        case buttons
        case chips
        case segmented
        case rows
        case cards
        case search
        case banners
        case badges
        case toast
        case emptyState
        case loadingState
        case errorState
        case sheet
        case stickers
        case tour

        var id: Self { self }

        var title: String {
            switch self {
            case .buttons: "Buttons"
            case .chips: "Chips"
            case .segmented: "Segmented switch"
            case .rows: "Rows"
            case .cards: "Cards and sections"
            case .search: "Search field"
            case .banners: "Banners"
            case .badges: "Badges"
            case .toast: "Toast"
            case .emptyState: "Empty state"
            case .loadingState: "Loading state"
            case .errorState: "Error state"
            case .sheet: "Bottom sheet"
            case .stickers: "Stickers and photo tiles"
            case .tour: "Quick tour card"
            }
        }

        @ViewBuilder var content: some View {
            switch self {
            case .buttons: ButtonsDemo()
            case .chips: ChipsDemo()
            case .segmented: SegmentedDemo()
            case .rows: RowsDemo()
            case .cards: CardsDemo()
            case .search: SearchDemo()
            case .banners: BannersDemo()
            case .badges: BadgesDemo()
            case .toast: ToastDemo()
            case .emptyState: EmptyStateDemo()
            case .loadingState: NookLoadingState("Getting your looks", message: "This takes a few seconds.")
            case .errorState: ErrorStateDemo()
            case .sheet: SheetDemo()
            case .stickers: StickerDemo()
            case .tour: TourDemo()
            }
        }
    }

    /// A small caption above each example, so the catalog says which state is which.
    struct CatalogCaption: View {
        let text: String

        init(_ text: String) {
            self.text = text
        }

        var body: some View {
            Text(text)
                .nookTextStyle(.caption)
                .foregroundStyle(.nook.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct ButtonsDemo: View {
        var body: some View {
            VStack(alignment: .leading, spacing: NookSpacing.medium) {
                CatalogCaption("Primary")
                NookButton("Style me", systemImage: "sparkles", fillsWidth: true) {}
                CatalogCaption("Primary, pressed · disabled · loading")
                NookButtonChrome(kind: .primary, size: .regular, isPressed: true) {
                    NookButtonLabel(title: "Style me", systemImage: "sparkles", fillsWidth: true)
                }
                NookButton("Style me", systemImage: "sparkles", fillsWidth: true) {}
                    .disabled(true)
                NookButton("Styling", isLoading: true, fillsWidth: true) {}
                CatalogCaption("Soft · soft pressed")
                NookAdaptiveStack {
                    NookButton("Save", systemImage: "bookmark", kind: .soft, fillsWidth: true) {}
                    NookButtonChrome(kind: .soft, size: .regular, isPressed: true) {
                        NookButtonLabel(title: "Save", systemImage: "bookmark", fillsWidth: true)
                    }
                }
                CatalogCaption("Small primary and soft, stacked at the largest sizes")
                NookAdaptiveStack {
                    NookButton("Wear today", systemImage: "checkmark", size: .small, fillsWidth: true) {}
                    NookButton(
                        "Swap", systemImage: "arrow.left.arrow.right", kind: .soft, size: .small, fillsWidth: true
                    ) {}
                }
                CatalogCaption("Pill · text")
                NookAdaptiveStack {
                    NookButton("Show 3 more", systemImage: "plus", kind: .pill) {}
                    NookButton("See all", kind: .text) {}
                }
            }
        }
    }

    private struct ChipsDemo: View {
        @State private var occasion = "Work"
        @State private var pieces: Set<String> = ["Tops"]

        var body: some View {
            VStack(alignment: .leading, spacing: NookSpacing.medium) {
                CatalogCaption("Single choice")
                NookChipBar("Occasion", layout: .wrap) {
                    ForEach(["Work", "Weekend", "Date night"], id: \.self) { name in
                        NookChip(name, isSelected: occasion == name) { occasion = name }
                    }
                }
                .padding(.horizontal, -NookSpacing.screenMargin)
                CatalogCaption("Filter bar, scrolls sideways")
                NookChipBar("Piece type") {
                    ForEach(["Tops", "Bottoms", "Dresses", "Layers", "Shoes", "Bags"], id: \.self) { name in
                        NookChip(name, isSelected: pieces.contains(name)) {
                            if pieces.contains(name) { pieces.remove(name) } else { pieces.insert(name) }
                        }
                    }
                }
                .padding(.horizontal, -NookSpacing.screenMargin)
                CatalogCaption("With icons · disabled")
                NookFlowLayout {
                    NookChip("In a suitcase", systemImage: "suitcase", isSelected: true) {}
                    NookChip("Not packed", isSelected: false) {}
                        .disabled(true)
                }
            }
        }
    }

    private struct SegmentedDemo: View {
        enum Tab: Hashable { case looks, pictures }
        enum Version: Hashable { case simple, dressedUp, somethingNew }

        @State private var tab = Tab.looks
        @State private var version = Version.simple

        var body: some View {
            VStack(alignment: .leading, spacing: NookSpacing.medium) {
                CatalogCaption("Two options with icons")
                NookSegmentedPicker(
                    "Show",
                    selection: $tab,
                    options: [
                        .init(.looks, title: "Looks", systemImage: "hanger"),
                        .init(.pictures, title: "Pictures", systemImage: "photo"),
                    ]
                )
                CatalogCaption("Three options")
                NookSegmentedPicker(
                    "Version",
                    selection: $version,
                    options: [
                        .init(.simple, title: "Simple"),
                        .init(.dressedUp, title: "Dressed up"),
                        .init(.somethingNew, title: "Something new"),
                    ]
                )
            }
        }
    }

    private struct RowsDemo: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                NookSection("Your details") {
                    Button {
                    } label: {
                        NookRow(
                            "Fit and measurements",
                            subtitle: "Used for size suggestions",
                            systemImage: "ruler",
                            accessory: .chevron
                        )
                    }
                    .buttonStyle(.nookRow)
                    Button {
                    } label: {
                        NookRow(
                            "Avoid repeating outfits",
                            value: "1 week",
                            systemImage: "calendar",
                            iconFill: .nook.successSurface,
                            accessory: .chevron
                        )
                    }
                    .buttonStyle(.nookRow)
                    NookRow(
                        "Name on your sign", value: "Lily", systemImage: "signature", iconFill: .nook.warningSurface)
                }
                NookDivider()
                NookSection("Help", footer: "Rows have no box and no lines. Space and the round icons tell them apart.")
                {
                    Button {
                    } label: {
                        NookRow("Send feedback", systemImage: "bubble.left", accessory: .chevron)
                    }
                    .buttonStyle(.nookRow)
                }
            }
        }
    }

    private struct CardsDemo: View {
        var body: some View {
            VStack(alignment: .leading, spacing: NookSpacing.large) {
                NookSectionHeader("Section header", detail: "3 of 5")
                Text(verbatim: "A soft card: a tint and a shadow that falls only below. No outline.")
                    .nookTextStyle(.body)
                    .foregroundStyle(.nook.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nookCard()
                Text(verbatim: "The strong tint, for cards that sit on drawn art.")
                    .nookTextStyle(.body)
                    .foregroundStyle(.nook.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nookCard(.strong)
                Text(verbatim: "The butter note, for a gentle heads-up.")
                    .nookTextStyle(.body)
                    .foregroundStyle(.nook.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nookCard(.warning)
                CatalogCaption("Divider between groups")
                NookDivider()
            }
        }
    }

    private struct SearchDemo: View {
        @State private var empty = ""
        @State private var filled = "black jeans"

        var body: some View {
            VStack(alignment: .leading, spacing: NookSpacing.medium) {
                CatalogCaption("Empty")
                NookSearchField("Search your looks", text: $empty)
                CatalogCaption("With text, clear button")
                NookSearchField("Search your looks", text: $filled)
            }
        }
    }

    private struct BannersDemo: View {
        var body: some View {
            VStack(alignment: .leading, spacing: NookSpacing.medium) {
                CatalogCaption("Offline")
                NookOfflineBanner(detail: "These looks are kept on this iPhone.")
                CatalogCaption("Offline with retry")
                NookOfflineBanner(retry: {})
                CatalogCaption("Neutral note with an action")
                NookBanner(
                    "Two pieces are in the wash.",
                    systemImage: "washer",
                    tone: .neutral,
                    actionTitle: "Show",
                    action: {}
                )
            }
        }
    }

    private struct BadgesDemo: View {
        var body: some View {
            NookFlowLayout(spacing: NookSpacing.small, lineSpacing: NookSpacing.small) {
                NookBadge("Simulated", tone: .neutral)
                NookBadge("Not in your closet", systemImage: "bag", tone: .accent)
                NookBadge("Fits well", systemImage: "checkmark", tone: .success)
                NookBadge("In the wash", systemImage: "drop", tone: .warning)
            }
        }
    }

    private struct ToastDemo: View {
        @State private var toast: NookToastMessage?

        var body: some View {
            VStack(alignment: .leading, spacing: NookSpacing.medium) {
                NookToast(NookToastMessage("Added to Weekend", systemImage: "checkmark.circle"))
                NookToast(NookToastMessage("Removed the cardigan", actionTitle: "Undo", action: {}))
                NookButton("Show a toast", kind: .soft) {
                    toast = NookToastMessage("Saved to your looks", systemImage: "bookmark", actionTitle: "Undo") {}
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .nookToast($toast)
        }
    }

    /// The quick tour's card (Phase 16a) on the tour's dim: a first step, and a last step with
    /// Back and its own finishing button.
    private struct TourDemo: View {
        var body: some View {
            VStack(alignment: .leading, spacing: NookSpacing.medium) {
                CatalogCaption("First step")
                NookTourCard(
                    step: NookTourStep(
                        title: "Style Me", message: "Tap the laptop for an outfit idea made from your clothes.",
                        index: 0, count: 4, finishTitle: "Start styling"),
                    onNext: {}, onBack: {}, onSkip: {})
                CatalogCaption("Last step")
                NookTourCard(
                    step: NookTourStep(
                        title: "That is you", message: "Your name sign opens Profile.", index: 3, count: 4,
                        finishTitle: "Start styling"),
                    onNext: {}, onBack: {}, onSkip: {})
            }
            .padding(NookSpacing.large)
            .background(Color.nook.tourScrim, in: NookRadius.shape(NookRadius.sheet))
        }
    }

    private struct EmptyStateDemo: View {
        var body: some View {
            NookEmptyState(
                "Your closet is empty",
                message: "Add a piece you own to get started. Photos stay on this iPhone.",
                systemImage: "hanger"
            ) {
                NookButton("Add a piece", systemImage: "plus", fillsWidth: true) {}
            }
        }
    }

    private struct ErrorStateDemo: View {
        var body: some View {
            NookErrorState(
                "Styling didn’t finish",
                message: "Nothing was charged, and your request is kept as you left it.",
                retry: {},
                actions: { NookButton("Back to Style Me", kind: .soft, fillsWidth: true) {} }
            )
        }
    }

    private struct SheetDemo: View {
        @State private var isPresented = false

        var body: some View {
            VStack(alignment: .leading, spacing: NookSpacing.medium) {
                NookButton("Open the sheet", systemImage: "rectangle.bottomthird.inset.filled", kind: .soft) {
                    isPresented = true
                }
                CatalogCaption("Its header and content, as drawn inside the sheet")
                NookSheetContainer(title: "Weather", subtitle: "Your looks are picked for today’s weather.") {
                    SheetSampleContent()
                }
                .background(Color.nook.wallGradient, in: NookRadius.shape(NookRadius.sheet))
            }
            .nookSheet(
                isPresented: $isPresented, title: "Weather", subtitle: "Your looks are picked for today’s weather."
            ) {
                SheetSampleContent()
            }
        }
    }

    private struct SheetSampleContent: View {
        @State private var choice = "Use today’s weather"

        var body: some View {
            VStack(spacing: NookSpacing.xxSmall) {
                ForEach(["Use today’s weather", "I’ll be indoors", "Ignore the weather"], id: \.self) { option in
                    Button {
                        choice = option
                    } label: {
                        NookRow(option, systemImage: choice == option ? "checkmark" : "circle")
                    }
                    .buttonStyle(.nookRow)
                    .accessibilityAddTraits(choice == option ? .isSelected : [])
                }
            }
        }
    }
#endif
