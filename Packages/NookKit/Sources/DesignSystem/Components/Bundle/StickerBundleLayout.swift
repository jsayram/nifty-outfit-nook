import CoreGraphics

/// What a piece is to a look bundle's layout: where on the body it goes decides where it lies.
nonisolated public enum BundleRole: Int, CaseIterable, Hashable, Sendable {
    case layer
    case top
    case dress
    case bottom
    case shoes
    case bag
    case accessory

    /// Drawn in this order, back to front: trousers under the top's hem and the shoes over the
    /// trousers' hem, as in the mockups' `ORDER` (bottom, layer, top, bag, shoes).
    var zIndex: Double {
        switch self {
        case .dress, .bottom: 0
        case .layer: 1
        case .top: 2
        case .accessory: 3
        case .bag: 4
        case .shoes: 5
        }
    }

    /// Where a piece of this kind goes when its usual spot is taken or doesn't suit the others,
    /// in design points: an accessory beside a bag goes low on the left.
    var preferredCentre: CGPoint {
        switch self {
        case .layer, .top: CGPoint(x: 150, y: 90)
        case .dress: CGPoint(x: 150, y: 180)
        case .bottom: CGPoint(x: 140, y: 246)
        case .shoes: CGPoint(x: 232, y: 318)
        case .bag: CGPoint(x: 246, y: 210)
        case .accessory: CGPoint(x: 50, y: 300)
        }
    }

    /// The space a leftover piece of this kind gets (a second top, or an accessory beside a bag), in design points.
    var spareSize: CGSize {
        switch self {
        case .layer: CGSize(width: 104, height: 120)
        case .top: CGSize(width: 104, height: 112)
        case .dress: CGSize(width: 110, height: 162)
        case .bottom: CGSize(width: 82, height: 132)
        case .shoes: CGSize(width: 100, height: 42)
        case .bag: CGSize(width: 72, height: 78)
        case .accessory: CGSize(width: 80, height: 40)
        }
    }
}

/// One piece as the layout sees it: its role, and for a photo cutout, its shape.
nonisolated public struct BundleItem: Hashable, Sendable {
    public let role: BundleRole
    /// The cutout's width over its height, or `nil` for a drawing or a photo tile, which keep
    /// the role's usual space. Only shoes use it so far (`StickerBundleLayout.shoeSize`).
    public let aspectRatio: CGFloat?

    public init(_ role: BundleRole, aspectRatio: CGFloat? = nil) {
        self.role = role
        self.aspectRatio = aspectRatio.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }
}

/// Where one piece lies in a bundle.
nonisolated public struct BundlePlacement: Hashable, Sendable {
    /// The piece's position in the list given to `StickerBundleLayout.place`.
    public let index: Int
    /// The space the sticker fits into, before its tilt, in design points
    /// (`StickerBundleLayout.designSize`).
    public let frame: CGRect
    /// The tilt in degrees, clockwise.
    public let angle: Double
    /// Higher is drawn on top.
    public let zIndex: Double

    public init(index: Int, frame: CGRect, angle: Double, zIndex: Double) {
        self.index = index
        self.frame = frame
        self.angle = angle
        self.zIndex = zIndex
    }

    /// The frame for a bundle `width` points wide.
    public func frame(forWidth width: CGFloat) -> CGRect {
        let scale = width / StickerBundleLayout.designSize.width
        return CGRect(
            x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
    }
}

/// The flat-lay arrangement of a look bundle (RD-07): 2 to 6 stickers placed where they're
/// worn, slightly tilted and overlapping, like an outfit laid out on a bed.
///
/// The spots come from the mockups' `spots()` in `results.html`, in the same 300 x 356 box:
/// tops and layers across the top (a layer on the left and the top on the right when there are
/// both), trousers or a skirt in the middle, shoes low on the right over the trousers' hem, the
/// bag at the right side and an accessory low on the left. A dress takes the top and middle.
/// A second piece of a kind goes to the nearest free spot where it overlaps the others little.
///
/// The tilts and small nudges come from a seed, normally the look's ID, so a look is laid out
/// the same way on every screen and every launch, and two looks don't look stamped from one
/// mould. Then the whole arrangement is scaled and centred to fill the box, tilted corners
/// included, so nothing is clipped and a small look isn't lost in empty space.
///
/// Pure arithmetic: no views, no randomness the system picks. The same pieces and seed always
/// give the same placements.
nonisolated public enum StickerBundleLayout {
    /// The design box, from the mockups. A bundle keeps this shape at every size.
    public static let designSize = CGSize(width: 300, height: 356)

    /// Width over height.
    public static var aspectRatio: CGFloat { designSize.width / designSize.height }

    /// The most two pieces' frames may overlap, as a share of the smaller one. The pieces are
    /// meant to overlap a little, as in the mockups, but never so much that one hides another.
    public static let maximumOverlap: CGFloat = 0.3

    /// The space kept clear around the arrangement, in design points.
    static let margin: CGFloat = 6

    /// How much a small arrangement may grow to fill the box.
    static let maximumGrowth: CGFloat = 1.25

    /// Places `roles`, one placement per role in the same order, each in its role's usual space.
    public static func place(_ roles: [BundleRole], seed: String) -> [BundlePlacement] {
        place(roles.map { BundleItem($0) }, seed: seed)
    }

    /// Places `items`, one placement per item in the same order. A cutout's shape sizes its space
    /// where the role's usual space would be the wrong shape (shoes).
    public static func place(_ items: [BundleItem], seed: String) -> [BundlePlacement] {
        guard !items.isEmpty else { return [] }
        let roles = items.map(\.role)
        var generator = BundleSeed(seed)
        // Small nudges and tilts, drawn in piece order so the same seed gives the same look.
        let nudges = roles.map { _ in CGPoint(x: generator.unit(in: -3...3), y: generator.unit(in: -3...3)) }
        let tilts = roles.map { _ in generator.unit(in: -2.5...2.5) }
        var spots = assignSpots(roles, aspects: items.map(\.aspectRatio), nudges: nudges)
        for index in spots.indices {
            spots[index].angle += Double(tilts[spots[index].index])
        }
        return fitted(spots).map { spot in
            BundlePlacement(
                index: spot.index, frame: spot.frame, angle: spot.angle,
                zIndex: spot.role.zIndex + Double(spot.index) * 0.01)
        }
    }

    /// How much two frames overlap, as a share of the smaller one's area (0 to 1).
    public static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let shared = a.intersection(b)
        guard !shared.isNull, !shared.isEmpty else { return 0 }
        let smaller = min(a.width * a.height, b.width * b.height)
        guard smaller > 0 else { return 0 }
        return (shared.width * shared.height) / smaller
    }

    /// The upright box around `rect` turned by `degrees` about its centre.
    public static func rotatedBounds(_ rect: CGRect, degrees: Double) -> CGRect {
        let radians = degrees * .pi / 180
        let cosine = abs(cos(radians))
        let sine = abs(sin(radians))
        let width = rect.width * cosine + rect.height * sine
        let height = rect.width * sine + rect.height * cosine
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    // MARK: Spots

    struct Spot {
        let index: Int
        let role: BundleRole
        var frame: CGRect
        var angle: Double
    }

    /// A spot in the design box: centre, size and tilt.
    private static func spot(
        _ index: Int, _ role: BundleRole, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ angle: Double
    )
        -> Spot
    {
        Spot(index: index, role: role, frame: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h), angle: angle)
    }

    /// Gives each piece its usual spot, moved by its nudge, then the leftovers the free space
    /// that overlaps least. Nudging before checking the overlaps means a nudge can't push two
    /// pieces over the limit.
    static func assignSpots(_ roles: [BundleRole], aspects: [CGFloat?]? = nil, nudges: [CGPoint]) -> [Spot] {
        func aspect(_ index: Int) -> CGFloat? { aspects.flatMap { $0.indices.contains(index) ? $0[index] : nil } }
        func indices(_ role: BundleRole) -> [Int] { roles.indices.filter { roles[$0] == role } }
        let dresses = indices(.dress)
        let uppers = indices(.layer) + indices(.top)
        let bottoms = indices(.bottom)
        let shoes = indices(.shoes)
        let bags = indices(.bag)
        let accessories = indices(.accessory)
        let hasDress = !dresses.isEmpty
        let hasLowerBody = hasDress || !bottoms.isEmpty

        // Usual spots in the order they're claimed; anything left over goes in `spare`.
        var usual: [Spot] = []
        var spare: [Int] = []

        if let dress = dresses.first {
            usual.append(spot(dress, .dress, 120, 182, 176, 262, -2))
            spare += dresses.dropFirst()
            if let upper = uppers.first {
                usual.append(spot(upper, roles[upper], 226, 92, 112, 122, 6))
            }
            spare += uppers.dropFirst()
            spare += bottoms
        } else {
            switch uppers.count {
            case 0: break
            case 1: usual.append(spot(uppers[0], roles[uppers[0]], 146, 92, 150, 152, -3))
            default:
                usual.append(spot(uppers[0], roles[uppers[0]], 98, 90, 140, 150, -7))
                usual.append(spot(uppers[1], roles[uppers[1]], 202, 100, 128, 132, 5))
                spare += uppers.dropFirst(2)
            }
            if let bottom = bottoms.first {
                usual.append(spot(bottom, .bottom, 138, 246, 124, 200, -2))
            }
            spare += bottoms.dropFirst()
        }

        if let shoe = shoes.first {
            // Over the trousers' hem; higher up and nearer the middle when nothing hangs there.
            // A drawing is a wide side view and keeps the wide box. A photo cutout gets a space of
            // its own shape, standing on the same line, so heels, sneakers and knee boots all read
            // at about a real size next to the bag.
            if let aspect = aspect(shoe) {
                let size = shoeSize(aspect: aspect, area: hasLowerBody ? shoeArea : shoeAreaAlone)
                usual.append(
                    hasLowerBody
                        ? spot(shoe, .shoes, 232, shoeFloor - size.height / 2, size.width, size.height, -8)
                        : spot(shoe, .shoes, 176, 228, size.width, size.height, -6))
            } else {
                usual.append(
                    hasLowerBody
                        ? spot(shoe, .shoes, 232, 318, 116, 48, -8) : spot(shoe, .shoes, 176, 228, 128, 54, -6))
            }
        }
        spare += shoes.dropFirst()

        if let bag = bags.first {
            usual.append(spot(bag, .bag, 246, 210, 88, 96, 8))
        }
        spare += bags.dropFirst()

        if bags.isEmpty, let accessory = accessories.first {
            // In the bag's place at the side.
            usual.append(spot(accessory, .accessory, 242, 210, 96, 48, 7))
            spare += accessories.dropFirst()
        } else {
            spare += accessories
        }

        // A usual spot that would cover too much of one claimed before it (a hat beside shoes
        // with no trousers, say) is given up and the piece placed like a leftover.
        var placed: [Spot] = []
        for var candidate in usual {
            candidate.frame = candidate.frame.offsetBy(dx: nudges[candidate.index].x, dy: nudges[candidate.index].y)
            let crowding = placed.map { overlap($0.frame, candidate.frame) }.max() ?? 0
            if crowding <= usualOverlap { placed.append(candidate) } else { spare.append(candidate.index) }
        }
        for index in spare.sorted() {
            let size = roles[index] == .shoes ? aspect(index).map { shoeSize(aspect: $0, area: shoeSpareArea) } : nil
            placed.append(leastCrowdedSpot(for: index, role: roles[index], size: size, among: placed))
        }
        return placed.sorted { $0.index < $1.index }
    }

    /// The spot for a leftover piece: the one nearest where pieces of its kind usually go whose
    /// frame overlaps the placed pieces by at most `spareOverlap`. The search spirals out from
    /// there and reaches well past the box, so such a spot is found; `fitted` then shrinks the
    /// arrangement back inside.
    private static func leastCrowdedSpot(for index: Int, role: BundleRole, size: CGSize?, among placed: [Spot])
        -> Spot
    {
        let size = size ?? role.spareSize
        let preferred = role.preferredCentre
        let tilt: Double = index.isMultiple(of: 2) ? -5 : 5
        var leastCrowded: (spot: Spot, crowding: CGFloat)?
        for offset in searchOffsets {
            let candidate = spot(
                index, role, preferred.x + offset.x, preferred.y + offset.y, size.width, size.height, tilt)
            var crowding: CGFloat = 0
            for other in placed {
                crowding = max(crowding, overlap(other.frame, candidate.frame))
                if crowding > spareOverlap { break }
            }
            if crowding <= spareOverlap { return candidate }
            if leastCrowded.map({ crowding < $0.crowding }) ?? true { leastCrowded = (candidate, crowding) }
        }
        return leastCrowded?.spot ?? spot(index, role, preferred.x, preferred.y, size.width, size.height, tilt)
    }

    /// Where to look for a leftover piece's spot, nearest first: every 6 points up to 300 points
    /// away in each direction. Worked out once.
    private static let searchOffsets: [CGPoint] = {
        let steps = -50...50
        let offsets = steps.flatMap { y in steps.map { x in CGPoint(x: CGFloat(x) * 6, y: CGFloat(y) * 6) } }
        return offsets.sorted {
            let first = $0.x * $0.x + $0.y * $0.y
            let second = $1.x * $1.x + $1.y * $1.y
            return first != second ? first < second : ($0.y, $0.x) < ($1.y, $1.x)
        }
    }()

    // MARK: Shoes

    /// Where the shoes stand over the trousers' hem: the bottom of the drawn shoes' box.
    static let shoeFloor: CGFloat = 342

    /// The space a pair of shoes from a photo gets, in square design points: a little less than
    /// the bag's 88 x 96, as a pair of shoes and a bag are next to each other on a bed.
    public static let shoeArea: CGFloat = 6_200
    /// With no trousers or dress, the shoes sit higher and nearer the middle, a little larger.
    static let shoeAreaAlone: CGFloat = 6_800
    /// A second pair, placed like any leftover piece.
    static let shoeSpareArea: CGFloat = 4_600

    /// The tallest and widest a pair of shoes may be, in design points. Knee boots stop at the
    /// height of a skirt's lower half; a wide side view stops short of the box's middle.
    public static let shoeMaximumSize = CGSize(width: 124, height: 104)

    /// The space for shoes whose cutout is `aspect` (width over height) wide: the cutout's own
    /// shape with `area` square design points, kept inside `shoeMaximumSize`. Shapes past 0.5
    /// and 2.4 are treated as those.
    public static func shoeSize(aspect: CGFloat, area: CGFloat = shoeArea) -> CGSize {
        let shape = min(max(aspect, 0.5), 2.4)
        var size = CGSize(width: (area * shape).squareRoot(), height: (area / shape).squareRoot())
        if size.height > shoeMaximumSize.height {
            size = CGSize(width: shoeMaximumSize.height * shape, height: shoeMaximumSize.height)
        }
        if size.width > shoeMaximumSize.width {
            size = CGSize(width: shoeMaximumSize.width, height: shoeMaximumSize.width / shape)
        }
        return size
    }

    /// The most a leftover piece may overlap the others.
    static let spareOverlap: CGFloat = 0.2

    /// The most a usual spot may overlap the ones claimed before it. The mockups' own spots
    /// overlap up to about a fifth (the shoes over the trousers' hem).
    static let usualOverlap: CGFloat = 0.24

    /// Scales and centres the arrangement, tilted corners included, to fill the box inside the
    /// margin. It grows at most `maximumGrowth` times, so two pieces don't become giants.
    static func fitted(_ spots: [Spot]) -> [Spot] {
        let bounds = spots.map { rotatedBounds($0.frame, degrees: $0.angle) }.reduce(CGRect.null) { $0.union($1) }
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return spots }
        let room = CGSize(width: designSize.width - 2 * margin, height: designSize.height - 2 * margin)
        let scale = min(room.width / bounds.width, room.height / bounds.height, maximumGrowth)
        let offset = CGPoint(
            x: designSize.width / 2 - bounds.midX * scale, y: designSize.height / 2 - bounds.midY * scale)
        return spots.map { spot in
            var moved = spot
            moved.frame = CGRect(
                x: spot.frame.minX * scale + offset.x, y: spot.frame.minY * scale + offset.y,
                width: spot.frame.width * scale, height: spot.frame.height * scale)
            return moved
        }
    }
}

/// Numbers from a string seed: FNV-1a to hash the string, then SplitMix64. Swift's own `Hasher`
/// is seeded differently on every launch, so it can't be used for a layout that must not move.
nonisolated struct BundleSeed {
    private var state: UInt64

    init(_ seed: String) {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        state = hash
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }

    /// A number in `range`, evenly spread.
    mutating func unit(in range: ClosedRange<Double>) -> CGFloat {
        let fraction = Double(next() >> 11) / Double(1 << 53)
        return CGFloat(range.lowerBound + fraction * (range.upperBound - range.lowerBound))
    }
}
