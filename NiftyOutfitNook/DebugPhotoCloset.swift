#if DEBUG
    import CoreGraphics
    import Fixtures
    import Foundation
    import ImageIO
    import Models
    import QuartzCore
    import Services
    import UIKit
    import UniformTypeIdentifiers

    /// Debug-only tools for measuring a large closet of real-sized photos (Phase 22b). None of
    /// this is in Release builds, and nothing here is a sample photo: every picture is drawn.
    enum DebugLaunchArgument {
        /// The word after `flag`, as in `-thumbnails off`.
        static func value(after flag: String, in arguments: [String]) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
    }

    /// `-seed-photo-closet <count>`: fills her own closet in the store with `count` pieces from the
    /// large fixture set (at most its 2,400), each with a full-size photo (3,024 by 4,032, as an iPhone 12 takes)
    /// and a cutout next to it, then finishes onboarding on her own closet. Only an empty closet is
    /// filled, so relaunching with the flag measures the same closet again.
    ///
    /// The photos are the synthetic garment scenes with grain added, so each JPEG is about the
    /// size of a real photo rather than a flat drawing's few hundred kilobytes.
    enum DebugPhotoCloset {
        static func seedIfAsked(arguments: [String], storage: NookStorage, photos: PhotoFileStore) async {
            guard let value = DebugLaunchArgument.value(after: "-seed-photo-closet", in: arguments),
                let count = Int(value), count > 0,
                (try? await storage.closet.garments().isEmpty) ?? false
            else { return }
            let scenes = SyntheticGarmentPhotos.Scene.allCases.filter { $0 != .emptyBed }
            let bases = scenes.enumerated().map { index, scene in
                (photo: grainyJPEG(scene, seed: UInt32(index + 1)), cutout: cutout(scene))
            }
            let garments = FixtureSet.large.data(now: .now, calendar: .current).garments
            for (index, var garment) in garments.prefix(count).enumerated() {
                let base = bases[index % bases.count]
                guard let photo = try? photos.add(base.photo), let cutout = try? photos.addCutout(base.cutout)
                else { break }
                garment.photo = .stored(EntityID(photo))
                garment.cutout = cutout
                try? await storage.closet.save(garment)
            }
            try? await storage.onboarding.complete(startingCloset: .empty)
        }

        /// A scene at an iPhone 12 photo's size with grain, as JPEG at the cleaner's quality.
        private static func grainyJPEG(_ scene: SyntheticGarmentPhotos.Scene, seed: UInt32) -> Data {
            let width = 3_024
            let height = 4_032
            guard let drawn = SyntheticGarmentPhotos.draw(scene, width: width, height: height),
                let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return Data() }
            context.draw(drawn, in: CGRect(x: 0, y: 0, width: width, height: height))
            if let pixels = context.data?.assumingMemoryBound(to: UInt8.self) {
                var state = seed
                for offset in 0..<(width * height * 4) where offset % 4 != 3 {
                    state = state &* 1_664_525 &+ 1_013_904_223
                    let grain = Int(state >> 29) - 4
                    pixels[offset] = UInt8(clamping: Int(pixels[offset]) + grain)
                }
            }
            guard let image = context.makeImage() else { return Data() }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
            else { return Data() }
            CGImageDestinationAddImage(
                destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            CGImageDestinationFinalize(destination)
            return data as Data
        }

        /// The scene's garments on transparency at the cutout bench's working size.
        private static func cutout(_ scene: SyntheticGarmentPhotos.Scene) -> CutoutResult {
            let crop = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
            let png = SyntheticGarmentPhotos.cutoutPNG(scene, width: 1_152, height: 1_536, crop: crop)
            return CutoutResult(
                imageData: png, pixelWidth: 922, pixelHeight: 1_229, quality: StandInCutoutService.cleanQuality)
        }
    }

    /// `-frame-stats`: counts frames and hitches with a display link and writes them, with the
    /// app's memory footprint, to `Library/Caches/frame-stats.json`, one line a second. A frame
    /// that arrives more than half a frame late is a hitch, and the time past its deadline is hitch
    /// time, as in Apple's hitch time ratio. The simulator's numbers are only a guide to a phone's,
    /// but they show main-thread stalls and compare runs.
    ///
    /// `-auto-scroll` also scrolls the closet grid itself, 3 seconds after it shows: down at 4,000 points a second for 20 seconds, then back up, as a hard fling would, with no
    /// test runner reading the screen meanwhile (its queries stall the main thread too). The frames
    /// while it scrolls are summed in a last `"scroll"` line.
    @MainActor
    final class FrameStats: NSObject {
        static let shared = FrameStats()
        private var link: CADisplayLink?
        private var last: CFTimeInterval = 0
        private var second = Bucket()
        private var scroll = Bucket()
        private var peakFootprint: UInt64 = 0
        private var lines: [String] = []
        private weak var scrollView: UIScrollView?
        private var scrollStarted: CFTimeInterval = 0
        private var scrollDone = false
        static let speed: CGFloat = 4_000
        static let seconds: CFTimeInterval = 20

        private struct Bucket {
            var frames = 0
            var hitches = 0
            var hitchMilliseconds = 0.0
            var longestMilliseconds = 0.0
            var started = Date()
        }

        func start(autoScroll: Bool) {
            guard link == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
            waitsToScroll = autoScroll
        }

        private var waitsToScroll = false
        private var foundAt: CFTimeInterval?

        /// Once a second until it starts: a scroll view at least 20,000 points long (the closet
        /// grid), left to settle for 3 seconds, starts the scroll.
        private func lookForScrollView(at time: CFTimeInterval) {
            if let foundAt {
                guard time - foundAt >= 3 else { return }
                waitsToScroll = false
                scrollStarted = time
                scroll = Bucket()
                return
            }
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            let views = windows.compactMap(Self.largestScrollView)
            guard let found = views.max(by: { $0.contentSize.height < $1.contentSize.height }),
                found.contentSize.height > 20_000
            else { return }
            scrollView = found
            foundAt = time
        }

        private static func largestScrollView(in view: UIView) -> UIScrollView? {
            var best = view as? UIScrollView
            let size = { (view: UIScrollView?) in view.map { $0.bounds.height * $0.contentSize.height } ?? 0 }
            for subview in view.subviews {
                if let found = largestScrollView(in: subview), size(found) > size(best) {
                    best = found
                }
            }
            return best
        }

        @objc private func tick(_ link: CADisplayLink) {
            defer { last = link.timestamp }
            guard last > 0 else { return }
            let interval = link.timestamp - last
            let budget = link.targetTimestamp - link.timestamp
            let hitch = budget > 0 && interval > budget * 1.5
            count(&second, interval: interval, budget: budget, hitch: hitch)
            if waitsToScroll {
                if second.frames == 1 { lookForScrollView(at: link.timestamp) }
            } else if let scrollView, !scrollDone {
                count(&scroll, interval: interval, budget: budget, hitch: hitch)
                let elapsed = link.timestamp - scrollStarted
                let distance = Self.speed * CGFloat(elapsed < Self.seconds ? elapsed : 2 * Self.seconds - elapsed)
                let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
                scrollView.contentOffset.y = min(max(0, distance), maxY)
                if elapsed >= 2 * Self.seconds {
                    scrollDone = true
                    writeScrollSummary(seconds: elapsed)
                }
            }
            if Date().timeIntervalSince(second.started) >= 1 { flush() }
        }

        private func count(_ bucket: inout Bucket, interval: CFTimeInterval, budget: CFTimeInterval, hitch: Bool) {
            bucket.frames += 1
            bucket.longestMilliseconds = max(bucket.longestMilliseconds, interval * 1_000)
            if hitch {
                bucket.hitches += 1
                bucket.hitchMilliseconds += (interval - budget) * 1_000
            }
        }

        private func writeScrollSummary(seconds: CFTimeInterval) {
            lines.append(
                String(
                    format: "{\"scroll\":true,\"seconds\":%.1f,\"frames\":%d,\"hitches\":%d,\"hitchMs\":%.1f,"
                        + "\"hitchRatioMsPerS\":%.2f,\"longestMs\":%.1f,\"peakFootprintMB\":%.1f}",
                    seconds, scroll.frames, scroll.hitches, scroll.hitchMilliseconds,
                    scroll.hitchMilliseconds / seconds, scroll.longestMilliseconds,
                    Double(peakFootprint) / 1_048_576))
            save()
        }

        private func flush() {
            let footprint = Self.footprint()
            if scrollView != nil, !waitsToScroll, !scrollDone { peakFootprint = max(peakFootprint, footprint) }
            lines.append(
                String(
                    format: "{\"at\":%.3f,\"frames\":%d,\"hitches\":%d,\"hitchMs\":%.1f,"
                        + "\"longestMs\":%.1f,\"footprintMB\":%.1f}",
                    second.started.timeIntervalSince1970, second.frames, second.hitches, second.hitchMilliseconds,
                    second.longestMilliseconds, Double(footprint) / 1_048_576))
            second = Bucket()
            save()
        }

        private func save() {
            let url = URL.cachesDirectory.appending(path: "frame-stats.json")
            try? (lines.joined(separator: "\n") + "\n").data(using: .utf8)?.write(to: url, options: .atomic)
        }

        /// The app's physical footprint, the number Xcode's memory gauge shows.
        nonisolated static func footprint() -> UInt64 {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            return result == KERN_SUCCESS ? info.phys_footprint : 0
        }
    }
#endif
