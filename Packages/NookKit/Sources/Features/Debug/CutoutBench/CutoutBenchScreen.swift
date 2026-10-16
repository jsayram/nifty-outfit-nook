#if DEBUG
    import DesignSystem
    import Models
    import PhotosUI
    import SwiftUI
    import UIKit

    /// The cutout benchmark (Phase 8a): pick photos, cut each one out twice, and see the times,
    /// memory and quality signals next to the original and the cutout. Export results copies the
    /// numbers as text for `docs/cutout-feasibility.md`.
    ///
    /// Debug builds only: launch with `-cutout-bench`. Photos come through the system photo
    /// picker, which runs outside the app, so it needs no photo-library permission. Nothing is
    /// saved or sent anywhere.
    public struct CutoutBenchScreen: View {
        @State private var model: CutoutBenchModel
        @State private var selection: [PhotosPickerItem] = []
        @State private var copied = false
        @State private var stickers = StickerCache()
        private let samples: @Sendable () -> [CutoutBenchModel.Input]

        /// - Parameters:
        ///   - makeService: the cutout service to measure, for a working size in pixels.
        ///   - samples: drawn sample photos, for a run without real photos.
        public init(
            makeService: @escaping @Sendable (Int) -> any CutoutService,
            samples: @escaping @Sendable () -> [(label: String, data: Data)]
        ) {
            _model = State(initialValue: CutoutBenchModel(device: DeviceName.current, makeService: makeService))
            self.samples = { samples().map { CutoutBenchModel.Input(label: $0.label, data: $0.data) } }
        }

        public var body: some View {
            NavigationStack {
                List {
                    photosSection
                    if !model.rows.isEmpty { resultsSection }
                    ForEach(model.rows) { row in
                        CutoutBenchRowView(row: row, thresholds: model.report.thresholds) { usable in
                            model.mark(row.id, usable: usable)
                        }
                    }
                }
                .navigationTitle(Text(verbatim: "Cutout benchmark"))
                .onChange(of: selection) { _, items in
                    guard !items.isEmpty else { return }
                    model.load { await Self.load(items) }
                }
                .onDisappear { model.cancel() }
            }
            .environment(\.stickerCache, stickers)
            .accessibilityIdentifier("cutoutBench")
        }

        // MARK: Sections

        private var photosSection: some View {
            Section {
                PhotosPicker(
                    selection: $selection, maxSelectionCount: 40, matching: .images,
                    preferredItemEncoding: .current
                ) {
                    Label {
                        Text(verbatim: "Choose photos")
                    } icon: {
                        Image(systemName: "photo.on.rectangle")
                    }
                }
                .disabled(model.isRunning || model.isLoading)

                Button {
                    let samples = samples
                    model.load { samples() }
                } label: {
                    Label {
                        Text(verbatim: "Use drawn samples")
                    } icon: {
                        Image(systemName: "scribble")
                    }
                }
                .disabled(model.isRunning || model.isLoading)
                .accessibilityIdentifier("cutoutBench.samples")

                Picker(selection: $model.maxPixelSize) {
                    ForEach(CutoutBenchModel.sizes, id: \.self) { Text(verbatim: "\($0) px").tag($0) }
                } label: {
                    Text(verbatim: "Working size")
                }
                .pickerStyle(.segmented)
                .disabled(model.isRunning)

                Button {
                    model.runAgain()
                } label: {
                    Label {
                        Text(verbatim: "Run again")
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(model.isRunning || model.isLoading || model.rows.isEmpty)
            } footer: {
                Text(
                    verbatim:
                        "Each photo is cut out twice in a row. Relaunch the app before a run to measure the cold start. Photos stay in memory only, and nothing leaves the phone."
                )
            }
        }

        private var resultsSection: some View {
            let report = model.report
            return Section {
                if model.isLoading || model.isRunning {
                    HStack {
                        ProgressView()
                        Text(verbatim: model.isLoading ? "Loading photos" : "Measuring")
                    }
                }
                summaryLine("Photos done", "\(report.records.count) of \(model.rows.count)")
                summaryLine("Device", report.device)
                summaryLine("Cold start", report.coldStart.map(CutoutBenchReport.ms) ?? "-")
                summaryLine("Warm median", report.medianWarm.map(CutoutBenchReport.ms) ?? "-")
                summaryLine("Warm p90", report.p90Warm.map(CutoutBenchReport.ms) ?? "-")
                summaryLine("Peak footprint", report.peakFootprint.map(CutoutBenchReport.mb) ?? "-")
                summaryLine("Least headroom", report.leastAvailable.map(CutoutBenchReport.mb) ?? "not reported")
                summaryLine("Suggested stickers", "\(report.suggestedStickers) of \(report.measured.count)")
                summaryLine("Marked usable", report.usableShare.map(CutoutBenchReport.percent) ?? "mark each photo")
                ForEach(report.checks, id: \.name) { check in
                    HStack(alignment: .firstTextBaseline) {
                        Image(
                            systemName: check.passes.map { $0 ? "checkmark.circle" : "xmark.circle" } ?? "circle.dotted"
                        )
                        .foregroundStyle(check.passes.map { $0 ? Color.green : Color.red } ?? Color.secondary)
                        .accessibilityHidden(true)
                        Text(verbatim: "\(check.name): \(check.value)").font(.footnote)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(
                        Text(verbatim: check.passes.map { $0 ? "Passes" : "Fails" } ?? "Not enough data"))
                }
                ShareLink(item: report.text()) {
                    Label {
                        Text(verbatim: "Export results")
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(model.isRunning)
                Button {
                    UIPasteboard.general.string = report.text()
                    copied = true
                } label: {
                    Label {
                        Text(verbatim: copied ? "Copied" : "Copy results")
                    } icon: {
                        Image(systemName: "doc.on.doc")
                    }
                }
                .disabled(model.isRunning)
            } header: {
                Text(verbatim: "Results at \(model.maxPixelSize) px")
            }
        }

        private func summaryLine(_ name: String, _ value: String) -> some View {
            LabeledContent {
                Text(verbatim: value)
            } label: {
                Text(verbatim: name)
            }
        }

        /// Reads the picked photos as they're stored (HEIC or JPEG), without re-encoding.
        private static func load(_ items: [PhotosPickerItem]) async -> [CutoutBenchModel.Input] {
            var inputs: [CutoutBenchModel.Input] = []
            for (index, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    inputs.append(CutoutBenchModel.Input(label: "Photo \(index + 1)", data: data))
                }
            }
            return inputs
        }
    }

    /// One photo: the original, the cutout as a sticker and the photo as the fallback tile
    /// (Phase 8b), with the one the signals pick marked, then its numbers.
    private struct CutoutBenchRowView: View {
        let row: CutoutBenchModel.Row
        let thresholds: CutoutThresholds
        let mark: (Bool?) -> Void

        private static let previewSize = CGSize(width: 92, height: 115)

        var body: some View {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    preview("Photo") { picture(row.original, checkerboard: false) }
                    preview(suggestsSticker == true ? "Sticker (pick)" : "Sticker") { stickerPreview }
                    preview(suggestsSticker == false ? "Tile (pick)" : "Tile") { tilePreview }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "Photo, sticker and tile"))

                details
            } header: {
                Text(verbatim: "\(row.id). \(row.label)")
            }
        }

        @ViewBuilder private var details: some View {
            if row.isRunning {
                HStack {
                    ProgressView()
                    Text(verbatim: "Cutting out")
                }
            } else if let record = row.record {
                switch record.outcome {
                case .failed(let error):
                    Text(verbatim: Self.describe(error)).foregroundStyle(.red)
                case .measured(let measured):
                    measuredDetails(measured)
                    markButtons(record.usable)
                }
            } else {
                Text(verbatim: "Waiting").foregroundStyle(.secondary)
            }
        }

        private func measuredDetails(_ measured: CutoutBenchRecord.Measured) -> some View {
            let quality = measured.quality
            let concerns = thresholds.concerns(with: quality)
            let lines = [
                "First \(CutoutBenchReport.ms(measured.first))\(measured.isColdStart ? " (cold start)" : ""), second \(CutoutBenchReport.ms(measured.second))",
                "Decode \(CutoutBenchReport.number(measured.timings.decode)), lift \(CutoutBenchReport.number(measured.timings.lift)), render \(CutoutBenchReport.number(measured.timings.render)), encode \(CutoutBenchReport.number(measured.timings.encode)) ms",
                "Peak \(CutoutBenchReport.mb(measured.memory.peakFootprint)) (from \(CutoutBenchReport.mb(measured.baselineFootprint)))",
                "\(measured.pixelWidth) x \(measured.pixelHeight) px, \(quality.instanceCount) subject\(quality.instanceCount == 1 ? "" : "s")",
                String(
                    format: "Coverage %.1f%%, largest %.0f%%, soft edges %.1f%%", quality.coverage * 100,
                    quality.largestInstanceShare * 100, quality.softEdgeRatio * 100),
                "Edges touched: \(CutoutBenchReport.edges(quality.touchedEdges))",
                concerns.isEmpty
                    ? "Suggested: sticker" : "Suggested: tile (\(concerns.map(\.rawValue).joined(separator: ", ")))",
            ]
            return VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { Text(verbatim: $0) }
            }
            .font(.footnote.monospacedDigit())
            .accessibilityElement(children: .combine)
        }

        private func markButtons(_ usable: Bool?) -> some View {
            HStack {
                Text(verbatim: "Usable as a sticker?")
                Spacer()
                Button {
                    mark(usable == true ? nil : true)
                } label: {
                    Text(verbatim: "Yes")
                }
                .buttonStyle(.bordered)
                .tint(usable == true ? .green : .secondary)
                .accessibilityAddTraits(usable == true ? .isSelected : [])
                Button {
                    mark(usable == false ? nil : false)
                } label: {
                    Text(verbatim: "No")
                }
                .buttonStyle(.bordered)
                .tint(usable == false ? .red : .secondary)
                .accessibilityAddTraits(usable == false ? .isSelected : [])
            }
        }

        private var measured: CutoutBenchRecord.Measured? {
            if case .measured(let measured) = row.record?.outcome { return measured }
            return nil
        }

        /// Whether the signals pick the sticker, once the photo has been measured.
        private var suggestsSticker: Bool? {
            measured.map { thresholds.suggestsSticker($0.quality) }
        }

        private func preview(_ title: String, @ViewBuilder content: () -> some View) -> some View {
            VStack(spacing: 4) {
                content()
                    .frame(width: Self.previewSize.width, height: Self.previewSize.height)
                    .padding(6)
                    .background(Color.nook.floor, in: RoundedRectangle(cornerRadius: 8))
                Text(verbatim: title).font(.caption2)
            }
        }

        /// The cutout with its white edge, as Closet and looks will show it.
        @ViewBuilder private var stickerPreview: some View {
            if let cutout = row.cutout {
                NookSticker("bench:\(row.cutoutID)", size: Self.previewSize, source: .image(cutout))
            }
        }

        /// The original in a rounded tile, framed on the subject when there are signals.
        @ViewBuilder private var tilePreview: some View {
            if let original = row.original {
                NookPhotoTile(
                    TileFraming.crop(original, subject: measured?.quality.subjectBounds, tileSize: Self.previewSize),
                    size: Self.previewSize)
            }
        }

        private func picture(_ image: CGImage?, checkerboard: Bool) -> some View {
            ZStack {
                if checkerboard { Checkerboard() } else { Color.secondary.opacity(0.1) }
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFit().padding(4)
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        static func describe(_ error: CutoutError) -> String {
            switch error {
            case .unreadableImage: "Couldn't read this photo."
            case .imageTooLarge: "This photo is over the size limit."
            case .noSubject: "No subject found."
            case .unsupported: "Subject lifting isn't supported here (the simulator can't run it)."
            case .failed: "Subject lifting failed."
            case .cancelled: "Cancelled."
            }
        }
    }

    /// Grey squares behind a cutout, so its transparent parts show.
    private struct Checkerboard: View {
        var body: some View {
            Canvas { context, size in
                let side: CGFloat = 10
                for row in 0..<Int((size.height / side).rounded(.up)) {
                    for column in 0..<Int((size.width / side).rounded(.up)) where (row + column).isMultiple(of: 2) {
                        context.fill(
                            Path(CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)),
                            with: .color(.secondary.opacity(0.2)))
                    }
                }
            }
        }
    }

    /// The device model and system version, for the exported results.
    private enum DeviceName {
        static var current: String {
            var name = utsname()
            uname(&name)
            let machine = withUnsafeBytes(of: name.machine) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            let model =
                ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"].map { "\($0) simulator" } ?? machine
            return "\(model), iOS \(UIDevice.current.systemVersion)"
        }
    }
#endif
