#if DEBUG
    import Models

    /// Sample looks for the catalog and the snapshot tests: 2 to 6 pieces, a dress look, and a
    /// Something new look with an idea piece. Drawn pieces only; photos come from the caller.
    ///
    /// Debug builds only.
    enum LookBundleSamples {
        static let blouse = LookBundlePiece(id: "blouse", name: "Cream blouse", category: .top, colors: [.cream])
        static let trousers = LookBundlePiece(
            id: "trousers", name: "Navy trousers", category: .bottom, colors: [.navy], isSameAsSimple: true)
        static let loafers = LookBundlePiece(
            id: "loafers", name: "Tan loafers", category: .shoes, colors: [.tan], isSameAsSimple: true)
        static let cardigan = LookBundlePiece(id: "cardigan", name: "Navy cardigan", category: .layer, colors: [.navy])
        static let bag = LookBundlePiece(id: "bag", name: "Burgundy bag", category: .bag, colors: [.burgundy])
        static let hat = LookBundlePiece(id: "hat", name: "Straw hat", category: .accessory, colors: [.beige])
        static let dress = LookBundlePiece(
            id: "dress", name: "Blue floral dress", category: .dress, colors: [.blue, .white])
        static let heels = LookBundlePiece(id: "heels", name: "Black block heels", category: .shoes, colors: [.black])
        static let jacket = LookBundlePiece(
            id: "jacket", name: "Brown leather jacket", category: .layer, colors: [.brown])
        static let blazerIdea = LookBundlePiece(
            id: "blazer-idea", idea: PieceIdea(name: "Camel blazer", category: .layer, colors: [.tan]))

        /// Looks of 2, 3, 4, 5 and 6 pieces, in that order.
        static let byPieceCount: [LookBundleContent] = [
            LookBundleContent(id: "sample-2", pieces: [dress, heels]),
            LookBundleContent(id: "sample-3", pieces: [blouse, trousers, loafers]),
            LookBundleContent(id: "sample-4", pieces: [cardigan, blouse, trousers, loafers]),
            LookBundleContent(id: "sample-5", pieces: [cardigan, blouse, trousers, loafers, bag]),
            LookBundleContent(id: "sample-6", pieces: [cardigan, blouse, trousers, loafers, bag, hat]),
        ]

        /// A dress under a jacket, with a bag and heels.
        static let dressLook = LookBundleContent(id: "sample-dress", pieces: [dress, jacket, heels, bag])

        /// Something new: the Simple outfit plus a camel blazer she doesn't own (LR-05b).
        static let somethingNew = LookBundleContent(
            id: "sample-something-new", name: "Office, something new", pieces: [blouse, trousers, loafers, blazerIdea])

        /// The three versions of one outfit, for a row of tappable thumbnails.
        static let versions: [(title: String, content: LookBundleContent)] = [
            ("Simple", LookBundleContent(id: "sample-simple", pieces: [blouse, trousers, loafers])),
            (
                "Dressed up",
                LookBundleContent(id: "sample-dressed-up", pieces: [blouse, trousers, heels, bag])
            ),
            ("Something new", somethingNew),
        ]

        /// From the sample photo pieces: the white tee, which falls back to a tile, and the satin
        /// skirt, a clean cutout.
        static func photoPieces(from garments: [Garment]) -> [Garment] {
            ["g-photo-white-on-white", "g-photo-shiny-skirt"].compactMap { id in
                garments.first { $0.id.rawValue == id }
            }
        }

        /// A look mixing her photos (stickers and tiles) with drawn pieces.
        static func withPhotos(_ garments: [Garment]) -> LookBundleContent {
            LookBundleContent(
                id: "sample-photos",
                pieces: garments.map { LookBundlePiece(id: $0.id.rawValue, garment: $0) } + [loafers, bag])
        }
    }
#endif
