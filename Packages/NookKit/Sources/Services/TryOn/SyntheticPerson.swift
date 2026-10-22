#if DEBUG
    import CoreGraphics
    import Foundation

    /// A drawn stand-in for a try-on photo (Phase 33a): a simple figure in a simple room, never a
    /// photo of anyone. Debug builds and tests only. Simulators can't run Apple Vision's person,
    /// face and pose requests, so the simulator tests and the debug checkpoint use this figure with
    /// `SyntheticPersonAnalyzer`, which reads it back from its colours.
    public enum SyntheticPerson {
        /// The colours the drawing uses. The analyzer tells the room from the person by them.
        public enum Palette {
            public static let wall: (UInt8, UInt8, UInt8) = (170, 190, 180)
            public static let floor: (UInt8, UInt8, UInt8) = (120, 90, 60)
            public static let window: (UInt8, UInt8, UInt8) = (170, 205, 230)
            public static let plant: (UInt8, UInt8, UInt8) = (60, 140, 70)
            public static let skin: (UInt8, UInt8, UInt8) = (224, 182, 150)
            public static let hair: (UInt8, UInt8, UInt8) = (92, 58, 36)
            public static let eye: (UInt8, UInt8, UInt8) = (10, 10, 110)
            public static let mouth: (UInt8, UInt8, UInt8) = (190, 80, 90)
            public static let top: (UInt8, UInt8, UInt8) = (90, 110, 170)
            public static let trousers: (UInt8, UInt8, UInt8) = (54, 58, 70)
            public static let shoes: (UInt8, UInt8, UInt8) = (150, 40, 40)
            static let room = [wall, floor, window, plant]
            /// The room's colours and the blends at their edges, which belong to the room too.
            static let roomAndEdges: [(UInt8, UInt8, UInt8)] = {
                var colors = room
                for other in [floor, window, plant] {
                    for step in 1..<10 { colors.append(blend(wall, other, Double(step) / 10)) }
                }
                return colors
            }()

            private static func blend(_ a: (UInt8, UInt8, UInt8), _ b: (UInt8, UInt8, UInt8), _ t: Double)
                -> (UInt8, UInt8, UInt8)
            {
                let red = Double(a.0) + (Double(b.0) - Double(a.0)) * t
                let green = Double(a.1) + (Double(b.1) - Double(a.1)) * t
                let blue = Double(a.2) + (Double(b.2) - Double(a.2)) * t
                return (UInt8(red.rounded()), UInt8(green.rounded()), UInt8(blue.rounded()))
            }
        }

        /// Where a figure's parts are, in pixels (origin top left).
        public struct Figure: Sendable, Equatable {
            public var face: CGRect
            public var neck: CGPoint
            public var leftShoulder: CGPoint
            public var rightShoulder: CGPoint
        }

        /// Draws the room and one figure (or two), returning the picture and where each figure is.
        /// - Parameters:
        ///   - centers: each figure's middle, as a share of the width.
        ///   - facingAway: hair drawn over the face, so there's no face to find.
        public static func draw(
            width: Int = 480, height: Int = 640, centers: [Double] = [0.5], facingAway: Bool = false
        ) -> (bitmap: TryOnBitmap, figures: [Figure]) {
            var pixels = [UInt8](repeating: 255, count: width * height * 4)
            var figures: [Figure] = []
            pixels.withUnsafeMutableBytes { buffer in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
                else { return }
                // Top-left origin, like the bitmap.
                context.translateBy(x: 0, y: Double(height))
                context.scaleBy(x: 1, y: -1)
                context.setShouldAntialias(true)
                let w = Double(width)
                let h = Double(height)
                fill(context, Palette.wall, CGRect(x: 0, y: 0, width: w, height: h * 0.78))
                fill(context, Palette.floor, CGRect(x: 0, y: h * 0.78, width: w, height: h * 0.22))
                fill(context, Palette.window, CGRect(x: w * 0.06, y: h * 0.1, width: w * 0.22, height: h * 0.3))
                fillEllipse(context, Palette.plant, CGRect(x: w * 0.8, y: h * 0.55, width: w * 0.16, height: h * 0.25))
                let scale = centers.count > 1 ? 0.8 : 1.0
                for center in centers {
                    figures.append(
                        figure(context, centerX: w * center, width: w, height: h, scale: scale, facingAway: facingAway))
                }
            }
            for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 255 }
            return (TryOnBitmap(width: width, height: height, pixels: pixels), figures)
        }

        private static func figure(
            _ context: CGContext, centerX: Double, width w: Double, height h: Double, scale: Double, facingAway: Bool
        ) -> Figure {
            let unit = h * 0.11 * scale  // head height
            let headTop = h * 0.1
            let face = CGRect(x: centerX - unit * 0.4, y: headTop + unit * 0.15, width: unit * 0.8, height: unit)
            let neckTop = face.maxY - unit * 0.05
            let shoulders = neckTop + unit * 0.35
            // Legs, then the top, then the neck and head over them.
            fill(context, Palette.trousers, CGRect(x: centerX - unit * 0.75, y: shoulders + unit * 2.2, width: unit * 0.65, height: unit * 3))
            fill(context, Palette.trousers, CGRect(x: centerX + unit * 0.1, y: shoulders + unit * 2.2, width: unit * 0.65, height: unit * 3))
            fill(context, Palette.shoes, CGRect(x: centerX - unit * 0.85, y: shoulders + unit * 5.2, width: unit * 0.75, height: unit * 0.3))
            fill(context, Palette.shoes, CGRect(x: centerX + unit * 0.1, y: shoulders + unit * 5.2, width: unit * 0.75, height: unit * 0.3))
            fill(context, Palette.top, CGRect(x: centerX - unit * 1.0, y: shoulders, width: unit * 2.0, height: unit * 2.4))
            fill(context, Palette.skin, CGRect(x: centerX - unit * 1.35, y: shoulders + unit * 0.1, width: unit * 0.32, height: unit * 2.3))
            fill(context, Palette.skin, CGRect(x: centerX + unit * 1.03, y: shoulders + unit * 0.1, width: unit * 0.32, height: unit * 2.3))
            fill(context, Palette.skin, CGRect(x: centerX - unit * 0.17, y: neckTop, width: unit * 0.34, height: unit * 0.45))
            // Hair behind and around the face.
            fillEllipse(context, Palette.hair, face.insetBy(dx: -unit * 0.18, dy: -unit * 0.15).offsetBy(dx: 0, dy: -unit * 0.08))
            fillEllipse(context, Palette.skin, face)
            if facingAway {
                fillEllipse(context, Palette.hair, face.insetBy(dx: -unit * 0.05, dy: -unit * 0.05))
            } else {
                let eyeY = face.minY + face.height * 0.42
                let eye = unit * 0.11
                fillEllipse(context, Palette.eye, CGRect(x: centerX - unit * 0.2 - eye / 2, y: eyeY - eye / 2, width: eye, height: eye))
                fillEllipse(context, Palette.eye, CGRect(x: centerX + unit * 0.2 - eye / 2, y: eyeY - eye / 2, width: eye, height: eye))
                fill(context, Palette.mouth, CGRect(x: centerX - unit * 0.14, y: face.minY + face.height * 0.72, width: unit * 0.28, height: unit * 0.06))
            }
            return Figure(
                face: face, neck: CGPoint(x: centerX, y: neckTop + unit * 0.3),
                leftShoulder: CGPoint(x: centerX + unit * 0.9, y: shoulders + unit * 0.1),
                rightShoulder: CGPoint(x: centerX - unit * 0.9, y: shoulders + unit * 0.1))
        }

        private static func fill(_ context: CGContext, _ color: (UInt8, UInt8, UInt8), _ rect: CGRect) {
            context.setFillColor(cgColor(color))
            context.fill(rect)
        }

        private static func fillEllipse(_ context: CGContext, _ color: (UInt8, UInt8, UInt8), _ rect: CGRect) {
            context.setFillColor(cgColor(color))
            context.fillEllipse(in: rect)
        }

        private static func cgColor(_ color: (UInt8, UInt8, UInt8)) -> CGColor {
            CGColor(
                srgbRed: Double(color.0) / 255, green: Double(color.1) / 255, blue: Double(color.2) / 255, alpha: 1)
        }

        @inline(__always) static func distance(_ a: (UInt8, UInt8, UInt8), _ b: (UInt8, UInt8, UInt8)) -> Int {
            abs(Int(a.0) - Int(b.0)) + abs(Int(a.1) - Int(b.1)) + abs(Int(a.2) - Int(b.2))
        }
    }

    /// Reads `SyntheticPerson` drawings back from their colours, the way Apple Vision reads a
    /// photo: the person's outline (everything that isn't the room's colours), each face (a pair
    /// of eyes inside skin) and the neck and shoulders. Covering the eyes with grey leaves no face
    /// to find, which is what the check after masking needs.
    ///
    /// `adjust` lets a test change what it reports (a softer outline, a face box in the wrong
    /// place), to prove the checks refuse.
    public struct SyntheticPersonAnalyzer: PersonAnalyzing {
        public var adjust: @Sendable (PersonAnalysis) -> PersonAnalysis

        public init(adjust: @escaping @Sendable (PersonAnalysis) -> PersonAnalysis = { $0 }) {
            self.adjust = adjust
        }

        public func analyze(_ image: TryOnBitmap) async throws(PersonAnalysisFailed) -> PersonAnalysis {
            var matte = TryOnMask(width: image.width, height: image.height)
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let pixel = image.rgb(x, y)
                    let nearest = SyntheticPerson.Palette.roomAndEdges.map { SyntheticPerson.distance(pixel, $0) }.min() ?? 0
                    // Clearly the room below 24, clearly the person above 60, soft in between (edges).
                    matte[x, y] = UInt8(min(255, max(0, (nearest - 24) * 255 / 36)))
                }
            }
            let faces = Self.faces(image)
            let pose = faces.count == 1 ? Self.pose(for: faces[0].box) : nil
            return adjust(PersonAnalysis(matte: matte, faces: faces, pose: pose))
        }

        public func faces(in image: TryOnBitmap) async throws(PersonAnalysisFailed) -> [DetectedFace] {
            Self.faces(image)
        }

        public func pose(in image: TryOnBitmap) async -> BodyPose? {
            let faces = Self.faces(image)
            return faces.count == 1 ? Self.pose(for: faces[0].box) : nil
        }

        /// Where the drawing puts the neck and shoulders for a face box.
        static func pose(for face: CGRect) -> BodyPose {
            let unit = face.height
            let neckTop = face.maxY - unit * 0.05
            return BodyPose(
                neck: CGPoint(x: face.midX, y: neckTop + unit * 0.3),
                leftShoulder: CGPoint(x: face.midX + unit * 0.9, y: neckTop + unit * 0.45),
                rightShoulder: CGPoint(x: face.midX - unit * 0.9, y: neckTop + unit * 0.45))
        }

        /// Eye blobs, paired side by side; the face's box follows the drawing's proportions.
        static func faces(_ image: TryOnBitmap) -> [DetectedFace] {
            let eyes = blobs(in: image) { SyntheticPerson.distance($0, SyntheticPerson.Palette.eye) < 60 }
                .filter { $0.count >= 4 }
            var faces: [DetectedFace] = []
            var used = Set<Int>()
            for (i, left) in eyes.enumerated() where !used.contains(i) {
                for (j, right) in eyes.enumerated() where j > i && !used.contains(j) {
                    let gap = abs(right.center.x - left.center.x)
                    let size = max(left.size, right.size)
                    guard abs(right.center.y - left.center.y) < size * 1.5, gap > size * 1.5, gap < size * 8 else {
                        continue
                    }
                    used.insert(i)
                    used.insert(j)
                    // In the drawing the eyes are 0.4 of the head height apart, 0.42 down the face.
                    let unit = gap / 0.4
                    let midX = (left.center.x + right.center.x) / 2
                    let eyeY = (left.center.y + right.center.y) / 2
                    let box = CGRect(x: midX - unit * 0.4, y: eyeY - unit * 0.42, width: unit * 0.8, height: unit)
                    faces.append(DetectedFace(box: box, confidence: 0.9))
                    break
                }
            }
            return faces
        }

        private struct Blob {
            var count: Int
            var center: CGPoint
            var size: Double
        }

        private static func blobs(in image: TryOnBitmap, where test: ((UInt8, UInt8, UInt8)) -> Bool) -> [Blob] {
            let width = image.width
            let height = image.height
            var marked = [Bool](repeating: false, count: width * height)
            for y in 0..<height {
                for x in 0..<width { marked[y * width + x] = test(image.rgb(x, y)) }
            }
            var seen = [Bool](repeating: false, count: marked.count)
            var found: [Blob] = []
            for start in marked.indices where marked[start] && !seen[start] {
                var stack = [start]
                seen[start] = true
                var count = 0
                var sumX = 0.0
                var sumY = 0.0
                var minX = width
                var maxX = 0
                while let index = stack.popLast() {
                    let x = index % width
                    let y = index / width
                    count += 1
                    sumX += Double(x)
                    sumY += Double(y)
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                    where nx >= 0 && ny >= 0 && nx < width && ny < height {
                        let next = ny * width + nx
                        if marked[next] && !seen[next] {
                            seen[next] = true
                            stack.append(next)
                        }
                    }
                }
                found.append(
                    Blob(
                        count: count, center: CGPoint(x: sumX / Double(count) + 0.5, y: sumY / Double(count) + 0.5),
                        size: Double(maxX - minX + 1)))
            }
            return found
        }
    }
#endif
