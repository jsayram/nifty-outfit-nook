import Foundation
import Models

// Sample data is compiled only in Debug: Release builds ship none (Phase 20a).
#if DEBUG
    /// The bundled sample wardrobe: AI-generated photos of clothing as she'd photograph it, the
    /// cutouts a subject-lifting step would make from them, a try-on photo and previews of looks
    /// worn. Test data only, with no real people (`SampleWardrobe/README.md`).
    ///
    /// A piece's picture is a `PhotoReference.sample` named for its asset, so it goes through the same
    /// path as a real photo: `Garment.photo` and `Garment.cutout`, `GarmentArtChoice`, the
    /// `ImageProvider` (`SampleWardrobeProvider`) and the image loader. A piece whose cutout the
    /// signals call unclean (lace, tiny jewellery) shows its photo in a tile, as it would on a phone.
    public enum SampleWardrobe {
        // MARK: References

        /// The photo of an asset, such as `g-navy-trousers`.
        public static func photo(_ asset: String) -> PhotoReference { .sample("wardrobe:photo:\(asset)") }

        /// The cutout of an asset: the piece alone, cropped to it.
        public static func cutout(_ asset: String) -> PhotoReference { .sample("wardrobe:cutout:\(asset)") }

        /// A try-on preview: one of the six looks worn (`TryOnPreview`).
        public static func preview(_ name: String) -> PhotoReference { .sample("wardrobe:tryon:\(name)") }

        /// The example try-on photo of her, standing. It is the reference the Profile's try-on photo
        /// sheet already used for its example.
        public static let person = PhotoReference.sample("try-on-example")

        /// What a sample reference points at.
        enum Resource: Hashable {
            case photo(String)
            case cutout(String)
            case preview(String)
            case person

            init?(_ reference: PhotoReference) {
                guard case .sample(let name) = reference else { return nil }
                if reference == SampleWardrobe.person {
                    self = .person
                    return
                }
                let parts = name.split(separator: ":", maxSplits: 2).map(String.init)
                guard parts.count == 3, parts[0] == "wardrobe" else { return nil }
                switch parts[1] {
                case "photo": self = .photo(parts[2])
                case "cutout": self = .cutout(parts[2])
                case "tryon": self = .preview(parts[2])
                default: return nil
                }
            }

            /// The file in the bundle, or `nil` if there isn't one.
            var url: URL? {
                let path: String
                switch self {
                case .photo(let asset): path = "photos/\(asset).jpg"
                case .cutout(let asset): path = "cutouts/\(asset).jp2"
                case .preview(let name): path = "tryon/\(name).jpg"
                case .person: path = "people/person.jpg"
                }
                guard !path.contains("..") else { return nil }
                let url = SampleWardrobe.folder.appendingPathComponent(path)
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            }
        }

        /// The folder of photos, or a folder that doesn't exist if there is none (then every piece
        /// keeps its drawing, as in Release).
        ///
        /// The photos aren't a resource of this package: SwiftPM would copy them into Release builds
        /// too. A Debug build of the app copies the folder into its own bundle, and the package tests
        /// find it in the `NookTestSupport` resource bundle, next to the test bundle.
        static let folder: URL = {
            let name = "SampleWardrobe"
            var places = [Bundle.main.resourceURL ?? Bundle.main.bundleURL]
            for bundle in Bundle.allBundles + Bundle.allFrameworks {
                places.append(bundle.resourceURL ?? bundle.bundleURL)
                places.append(bundle.bundleURL.deletingLastPathComponent())
            }
            for place in places {
                for base in [place, place.appendingPathComponent("NookKit_NookTestSupport.bundle", isDirectory: true)] {
                    let folder = base.appendingPathComponent(name, isDirectory: true)
                    if FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path) {
                        return folder
                    }
                }
            }
            return Bundle.main.bundleURL.appendingPathComponent(name, isDirectory: true)
        }()

        // MARK: Cutouts

        /// The cutout signals measured from each cutout by `scripts/build-sample-wardrobe.swift`.
        private struct Signals: Decodable {
            var instanceCount: Int
            var coverage: Double
            var largestInstanceShare: Double
            var touchedEdges: Int
            var softEdgeRatio: Double
            var x: Double
            var y: Double
            var width: Double
            var height: Double
            var pixelWidth: Int
            var pixelHeight: Int

            var aspectRatio: Double? {
                pixelHeight > 0 ? Double(pixelWidth) / Double(pixelHeight) : nil
            }

            var quality: CutoutQuality {
                CutoutQuality(
                    instanceCount: instanceCount, coverage: coverage, largestInstanceShare: largestInstanceShare,
                    touchedEdges: CutoutEdges(rawValue: touchedEdges), softEdgeRatio: softEdgeRatio,
                    subjectBounds: CutoutBounds(x: x, y: y, width: width, height: height))
            }
        }

        private static let signals: [String: Signals] = {
            let url = folder.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: url),
                let signals = try? JSONDecoder().decode([String: Signals].self, from: data)
            else { return [:] }
            return signals
        }()

        /// Every asset with a photo and a cutout, by name.
        public static var assets: Set<String> { Set(signals.keys) }

        /// The cutout of an asset with the signals measured from it, or `nil` for an unknown asset.
        public static func garmentCutout(_ asset: String) -> GarmentCutout? {
            signals[asset].map { GarmentCutout(image: cutout(asset), quality: $0.quality, aspectRatio: $0.aspectRatio) }
        }

        /// `garment` with the photo and cutout of `asset`.
        static func dressed(_ garment: Garment, asset: String) -> Garment {
            guard let cutout = garmentCutout(asset) else { return garment }
            var garment = garment
            garment.photo = photo(asset)
            garment.cutout = cutout
            return garment
        }

        // MARK: Demo pieces

        /// The demo closet's pieces with their real photos and cutouts. The photos are named for the
        /// piece's ID. A piece the demo lists with no photo (the brick knit top and the old gray
        /// leggings, added by words alone) keeps its drawing, so Closet and the bundles still show
        /// that state.
        static func dressedDemo(_ garments: [Garment]) -> [Garment] {
            garments.map { garment in
                guard garment.photo != .noPhoto else { return garment }
                return dressed(garment, asset: garment.id.rawValue)
            }
        }

        // MARK: Large closet

        /// One photo to choose from for a generated piece.
        struct PoolEntry: Sendable {
            let asset: String
            let category: GarmentCategory
            let colors: [ColorName]
            /// What the piece is, in the words the large closet names pieces with.
            let words: Set<String>
        }

        /// Words for what each demo piece is, since its name is her own.
        private static let demoWords: [String: Set<String>] = [
            "g-navy-trousers": ["trousers"], "g-olive-trousers": ["trousers"], "g-pink-blouse": ["blouse", "shirt"],
            "g-lace-top": ["blouse", "knit top"], "g-navy-cardigan": ["cardigan"], "g-brown-jacket": ["jacket"],
            "g-cream-sweater": ["sweater", "knit top"], "g-brick-top": ["knit top", "sweater"],
            "g-black-tee": ["tee", "tank"],
            "g-wide-jeans": ["jeans"], "g-black-skirt": ["skirt"], "g-blue-dress": ["midi dress", "shirt dress"],
            "g-nude-flats": ["heels"], "g-black-heels": ["heels"], "g-white-sneakers": ["sneakers"],
            "g-tan-loafers": ["loafers"], "g-burgundy-bag": ["crossbody bag"], "g-gray-blazer": ["blazer"],
            "g-cream-crop": ["blouse", "tank"], "g-camel-trench": ["coat"], "g-gray-leggings": ["trousers"],
        ]

        /// Every piece with a photo, demo pieces and extras, in a fixed order.
        static let pool: [PoolEntry] = {
            let demo = DemoCloset.garments(day: { _ in Date(timeIntervalSince1970: 0) }).map { garment in
                PoolEntry(
                    asset: garment.id.rawValue, category: garment.category, colors: garment.colors,
                    words: demoWords[garment.id.rawValue] ?? [])
            }
            let extras = Extra.all.map {
                PoolEntry(asset: $0.asset, category: $0.category, colors: $0.colors, words: $0.words)
            }
            return demo + extras
        }()

        /// The photo for generated piece number `index`: a photo of the same kind of piece if there is
        /// one, in the same colour if there is one, and picked by `index` among those, so the same
        /// closet gets the same pictures every run. The piece then takes its colours from the photo
        /// (`LargeCloset`), so colour search and filters match what she sees.
        static func pick(category: GarmentCategory, noun: String, color: ColorName?, index: Int) -> PoolEntry? {
            let ofCategory = pool.filter { $0.category == category }
            guard !ofCategory.isEmpty else { return nil }
            let sameKind = ofCategory.filter { $0.words.contains(noun) }
            var candidates = sameKind.isEmpty ? ofCategory : sameKind
            if let color {
                let sameColor = candidates.filter { $0.colors.first == color }
                if !sameColor.isEmpty { candidates = sameColor }
            }
            // A mixed-up index, so neighbouring pieces don't take neighbouring photos.
            var mixed = UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9_7F4A_7C15
            mixed ^= mixed >> 29
            return candidates[Int(mixed % UInt64(candidates.count))]
        }
    }
#endif
