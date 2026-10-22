import Foundation
import Models

/// Real try-on pictures with her face kept on the phone (Phase 33a, closet THREAT_MODEL.md D1).
///
/// 1. `prepare`, on the phone: her try-on photo at up to 1,280 pixels, her outline, face and pose
///    from `PersonAnalyzing` (Apple Vision on an iPhone), her head and hair filled with flat grey
///    and her room replaced by the studio backdrop (`HeadMasking`). Then the check that matters:
///    the analyzer looks for a face in the faceless photo, as the exact JPEG that would be sent,
///    and must find none. Any doubt (no person, no face, two people, an unclear outline, a face
///    still found) refuses, and nothing is sent.
/// 2. `dress`: only that JPEG and the garment photos go to the backend's POST /v1/try-on as one
///    paid action with the job's key.
/// 3. `restore`, on the phone: her real head back over the grey (`HeadRestore`), saved as a file.
///
/// The files are kept in her photo folder (Data Protection `complete`): what was sent stays with
/// the picture for "See what was sent"; the rest goes once the picture is made.
public struct PhoneTryOn: TryOnPipeline {
    let analyzer: any PersonAnalyzing
    let paid: any PaidActionService
    let files: PhotoFileStore
    let images: any ImageProvider

    /// Her photo is worked on at up to this size on the long side (the model's output is about
    /// a megapixel).
    public static let workingSize = 1_280
    /// Garment photos are sent at up to this size.
    public static let garmentSize = 768
    static let personQuality = 0.85
    static let garmentQuality = 0.85

    public init(
        analyzer: any PersonAnalyzing, paid: any PaidActionService, files: PhotoFileStore, images: any ImageProvider
    ) {
        self.analyzer = analyzer
        self.paid = paid
        self.files = files
        self.images = images
    }

    // MARK: Before sending

    public func prepare(photo: PhotoReference, pieces: [Garment]) async throws(TryOnPrepareProblem) -> TryOnUpload {
        guard photo != .noPhoto else { throw .noTryOnPhoto }
        guard let original = await data(for: photo, maxPixelSize: 2 * Self.workingSize),
            let bitmap = TryOnBitmap.decode(original, maxPixelSize: Self.workingSize)
        else { throw .photoUnreadable }

        let analysis: PersonAnalysis
        do {
            analysis = try await analyzer.analyze(bitmap)
        } catch {
            throw .checksUnavailable
        }
        let portrait = try HeadMasking.mask(bitmap, analysis: analysis)

        // The check that matters: no face can be found in what would be sent, both in the pixels
        // and in the JPEG made from them.
        guard let personJPEG = Self.jpeg(portrait.faceless, quality: Self.personQuality, limit: TryOnCall.personMaxBytes),
            let sentPixels = TryOnBitmap.decode(personJPEG, maxPixelSize: Self.workingSize)
        else { throw .notSaved }
        do {
            guard try await analyzer.faces(in: portrait.faceless).isEmpty,
                try await analyzer.faces(in: sentPixels).isEmpty
            else { throw TryOnPrepareProblem.faceStillVisible }
        } catch let problem as TryOnPrepareProblem {
            throw problem
        } catch {
            throw .checksUnavailable
        }

        var garments: [(Garment, Data)] = []
        for piece in pieces where garments.count < TryOnCall.maximumGarments {
            if let jpeg = await garmentJPEG(piece) { garments.append((piece, jpeg)) }
        }
        guard !garments.isEmpty else { throw .noGarmentPhotos }

        // Every file or none.
        var written: [String] = []
        func add(_ data: Data?) throws(TryOnPrepareProblem) -> PhotoReference {
            guard let data, let id = try? files.add(data) else {
                for id in written { files.remove(id) }
                throw .notSaved
            }
            written.append(id)
            return .stored(EntityID(id))
        }
        let person = try add(personJPEG)
        var sentGarments: [SentGarment] = []
        for (piece, jpeg) in garments {
            sentGarments.append(
                SentGarment(garmentID: piece.id, category: piece.category, subKind: piece.subKind, image: try add(jpeg)))
        }
        let work = TryOnWorkFiles(
            studio: try add(portrait.studio.jpeg(quality: 0.92)), matte: try add(portrait.matte.png()),
            head: try add(portrait.head.png()))
        let box = portrait.face.box
        let geometry = TryOnGeometry(
            width: bitmap.width, height: bitmap.height, face: [box.minX, box.minY, box.width, box.height],
            neck: portrait.pose.map { .init(x: $0.neck.x, y: $0.neck.y) },
            leftShoulder: portrait.pose?.leftShoulder.map { .init(x: $0.x, y: $0.y) },
            rightShoulder: portrait.pose?.rightShoulder.map { .init(x: $0.x, y: $0.y) })
        return TryOnUpload(
            sent: TryOnSent(person: person, garments: sentGarments), work: work, geometry: geometry,
            contextRevision: TryOnCall.revision(person: personJPEG, garments: garments.map(\.1)))
    }

    /// A garment's picture to send: its cutout on white when it has one (the clearest view of the
    /// piece), otherwise its photo, as a JPEG with no metadata.
    private func garmentJPEG(_ piece: Garment) async -> Data? {
        for reference in [piece.cutout?.image, piece.photo].compactMap({ $0 }) where reference != .noPhoto {
            if let data = await data(for: reference, maxPixelSize: Self.garmentSize),
                let bitmap = TryOnBitmap.decode(data, maxPixelSize: Self.garmentSize),
                let jpeg = Self.jpeg(bitmap, quality: Self.garmentQuality, limit: TryOnCall.garmentSendBytes)
            {
                return jpeg
            }
        }
        return nil
    }

    /// A JPEG no larger than the backend takes: lower quality first, then smaller.
    static func jpeg(_ bitmap: TryOnBitmap, quality: Double, limit: Int) -> Data? {
        var current = bitmap
        for _ in 0..<4 {
            for step in [quality, quality - 0.15, quality - 0.3] {
                if let data = current.jpeg(quality: step), data.count <= limit { return data }
            }
            guard let smaller = current.resized(width: current.width * 3 / 4, height: current.height * 3 / 4) else {
                return nil
            }
            current = smaller
        }
        return nil
    }

    private func data(for reference: PhotoReference, maxPixelSize: Int) async -> Data? {
        if case .stored(let id) = reference { return files.data(for: id.rawValue) }
        return try? await images.imageData(for: reference, maxPixelSize: maxPixelSize)
    }

    // MARK: Sending

    public func dress(_ upload: TryOnUpload, consentVersion: String, idempotencyKey: String)
        async throws(CloudLimitProblem) -> Data
    {
        guard let person = stored(upload.sent.person) else { throw .didNotFinish(retryAfterSeconds: nil) }
        var garments: [TryOnCall.Garment] = []
        for garment in upload.sent.garments {
            guard let jpeg = stored(garment.image) else { throw .didNotFinish(retryAfterSeconds: nil) }
            garments.append(.init(id: garment.garmentID, category: garment.category, subKind: garment.subKind, jpeg: jpeg))
        }
        let call = TryOnCall(
            contextRevision: upload.contextRevision, consentVersion: consentVersion, person: person, garments: garments)
        let receipt = try await paid.run(.tryOn(call), idempotencyKey: idempotencyKey)
        guard let image = receipt.tryOnImage else { throw .didNotFinish(retryAfterSeconds: nil) }
        return image
    }

    private func stored(_ reference: PhotoReference) -> Data? {
        guard case .stored(let id) = reference else { return nil }
        return files.data(for: id.rawValue)
    }

    // MARK: After

    public func restore(_ dressed: Data, upload: TryOnUpload) async throws(TryOnError) -> PhotoReference {
        let geometry = upload.geometry
        guard let work = upload.work, let studioData = stored(work.studio),
            let studio = TryOnBitmap.decode(studioData, maxPixelSize: max(geometry.width, geometry.height))?
                .resized(width: geometry.width, height: geometry.height),
            let matte = stored(work.matte).flatMap(TryOnMask.decode)?.resized(
                width: geometry.width, height: geometry.height),
            let head = stored(work.head).flatMap(TryOnMask.decode)?.resized(width: geometry.width, height: geometry.height),
            let picture = TryOnBitmap.decode(dressed, maxPixelSize: 4 * Self.workingSize)?.fitted(
                width: geometry.width, height: geometry.height)
        else { throw .notCompleted }
        let before = geometry.neck.map { neck in
            BodyPose(
                neck: CGPoint(x: neck.x, y: neck.y),
                leftShoulder: geometry.leftShoulder.map { CGPoint(x: $0.x, y: $0.y) },
                rightShoulder: geometry.rightShoulder.map { CGPoint(x: $0.x, y: $0.y) })
        }
        let after = await analyzer.pose(in: picture)
        let alignment = HeadRestore.alignment(from: before, to: after, width: geometry.width)
        let faceWidth = geometry.face.count == 4 ? geometry.face[2] : Double(geometry.width) / 6
        guard
            let finished = HeadRestore.restore(
                dressed: picture, studio: studio, matte: matte, head: head, faceWidth: faceWidth,
                alignment: alignment),
            let jpeg = finished.jpeg(quality: 0.9), let id = try? files.add(jpeg)
        else { throw .notCompleted }
        return .stored(EntityID(id))
    }

    public func discard(_ upload: TryOnUpload, keepingSent: Bool) async {
        var references = upload.work?.imageReferences ?? []
        if !keepingSent { references += upload.sent.imageReferences }
        for case .stored(let id) in references { files.remove(id.rawValue) }
    }
}
