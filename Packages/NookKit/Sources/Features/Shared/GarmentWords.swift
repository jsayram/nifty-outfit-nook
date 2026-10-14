import Models

// The words screens use for the fixed garment vocabulary. Models keeps cases as plain words with
// no display text, so the labels live here, localized.

extension GarmentCategory {
    /// The piece chip's label (LR-09): "Tops", "Bottoms" and so on.
    var chipTitle: String {
        switch self {
        case .top: String(localized: "Tops", bundle: .module, comment: "Piece chip")
        case .bottom: String(localized: "Bottoms", bundle: .module, comment: "Piece chip")
        case .dress: String(localized: "Dresses", bundle: .module, comment: "Piece chip")
        case .layer: String(localized: "Layers", bundle: .module, comment: "Piece chip")
        case .shoes: String(localized: "Shoes", bundle: .module, comment: "Piece chip")
        case .bag: String(localized: "Bags", bundle: .module, comment: "Piece chip")
        case .accessory: String(localized: "Accessories", bundle: .module, comment: "Piece chip")
        }
    }

    /// One piece of this kind, for search: "Top", "Shoes".
    var singularTitle: String {
        switch self {
        case .top: String(localized: "Top", bundle: .module, comment: "One piece of this kind, used in search")
        case .bottom: String(localized: "Bottom", bundle: .module, comment: "One piece of this kind, used in search")
        case .dress: String(localized: "Dress", bundle: .module, comment: "One piece of this kind, used in search")
        case .layer: String(localized: "Layer", bundle: .module, comment: "One piece of this kind, used in search")
        case .shoes: String(localized: "Shoe", bundle: .module, comment: "One piece of this kind, used in search")
        case .bag: String(localized: "Bag", bundle: .module, comment: "One piece of this kind, used in search")
        case .accessory:
            String(localized: "Accessory", bundle: .module, comment: "One piece of this kind, used in search")
        }
    }
}

extension ColorName {
    /// The colour swatch's name (LR-09.2), so a swatch is never told apart by colour alone.
    var title: String {
        switch self {
        case .black: String(localized: "Black", bundle: .module, comment: "Colour name")
        case .white: String(localized: "White", bundle: .module, comment: "Colour name")
        case .cream: String(localized: "Cream", bundle: .module, comment: "Colour name")
        case .beige: String(localized: "Beige", bundle: .module, comment: "Colour name")
        case .tan: String(localized: "Tan", bundle: .module, comment: "Colour name")
        case .brown: String(localized: "Brown", bundle: .module, comment: "Colour name")
        case .gray: String(localized: "Gray", bundle: .module, comment: "Colour name")
        case .navy: String(localized: "Navy", bundle: .module, comment: "Colour name")
        case .blue: String(localized: "Blue", bundle: .module, comment: "Colour name")
        case .denim: String(localized: "Denim", bundle: .module, comment: "Colour name")
        case .green: String(localized: "Green", bundle: .module, comment: "Colour name")
        case .olive: String(localized: "Olive", bundle: .module, comment: "Colour name")
        case .red: String(localized: "Red", bundle: .module, comment: "Colour name")
        case .brick: String(localized: "Brick", bundle: .module, comment: "Colour name")
        case .burgundy: String(localized: "Burgundy", bundle: .module, comment: "Colour name")
        case .pink: String(localized: "Pink", bundle: .module, comment: "Colour name")
        case .purple: String(localized: "Purple", bundle: .module, comment: "Colour name")
        case .yellow: String(localized: "Yellow", bundle: .module, comment: "Colour name")
        case .orange: String(localized: "Orange", bundle: .module, comment: "Colour name")
        case .multicolor: String(localized: "Multicolour", bundle: .module, comment: "Colour name")
        }
    }
}

extension GarmentFit {
    /// How a piece is cut, on garment detail: "Fitted", "Regular", "Relaxed".
    var title: String {
        switch self {
        case .fitted: String(localized: "Fitted", bundle: .module, comment: "How a piece is cut")
        case .regular: String(localized: "Regular", bundle: .module, comment: "How a piece is cut")
        case .relaxed: String(localized: "Relaxed", bundle: .module, comment: "How a piece is cut")
        }
    }
}

extension Season {
    var title: String {
        switch self {
        case .spring: String(localized: "Spring", bundle: .module, comment: "Season")
        case .summer: String(localized: "Summer", bundle: .module, comment: "Season")
        case .fall: String(localized: "Fall", bundle: .module, comment: "Season")
        case .winter: String(localized: "Winter", bundle: .module, comment: "Season")
        }
    }
}

extension Occasion {
    var title: String {
        switch self {
        case .office: String(localized: "Office", bundle: .module, comment: "Occasion")
        case .casual: String(localized: "Casual", bundle: .module, comment: "Occasion")
        case .brunch: String(localized: "Brunch", bundle: .module, comment: "Occasion")
        case .dateNight: String(localized: "Date night", bundle: .module, comment: "Occasion")
        case .event: String(localized: "Event", bundle: .module, comment: "Occasion")
        case .concert: String(localized: "Concert", bundle: .module, comment: "Occasion")
        case .other: String(localized: "Other", bundle: .module, comment: "Occasion")
        }
    }
}
