import Foundation
import SwiftData

// Phase 20a persistence spike: the kill harness. Built for macOS by run.sh with the files in
// ../Spike, it seeds a V1 store, migrates it in a child process that kills itself with SIGKILL
// at a checkpoint (or is killed from outside at a random moment), then opens the store again and
// checks it against the manifest taken before the migration.
//
//   spike-kill seed <folder> <garments>   make a V1 store with photo files
//   spike-kill open <folder> [checkpoint] open (and migrate); SIGKILL at the checkpoint if given
//   spike-kill verify <folder> <manifest> check the store against a manifest file
//   spike-kill raw <folder> [checkpoint]  SwiftData alone, without the coordinator

@main
enum SpikeKill {
    static func main() async {
        run()
    }

    /// The command, run inside the main task: a task-local handler set from top-level code
    /// outside any task crashed in `swift_task_localValuePushImpl` on macOS 26.
    static func run() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3 else {
            FileHandle.standardError.write(Data("usage: spike-kill seed|manifest|open|verify <folder> ...\n".utf8))
            exit(2)
        }
        let location = SpikeStoreLocation(directory: URL(filePath: arguments[2]))

        @Sendable func say(_ line: String) {
            FileHandle.standardOutput.write(Data((line + "\n").utf8))
        }

        do {
            switch arguments[1] {
            case "seed":
                let garments = Int(arguments[3]) ?? 2_400
                try SpikeSeed.makeV1Store(
                    at: location, counts: .init(garments: garments, photoEvery: 8, looks: garments / 4, suitcases: 40))
                say("seeded \(garments)")

            case "manifest":
                let manifest = try SpikeSQLite.manifest(of: location.storeURL, images: location.imagesDirectory)
                try JSONEncoder().encode(manifest).write(to: URL(filePath: arguments[3]))
                say("manifest \(manifest.garmentIDs.count) garments, \(manifest.photoHashes.count) photos")

            case "open":
                let killAt = arguments.count > 3 ? arguments[3] : nil
                let outcome = try SpikeCheckpoint.$handler.withValue(
                    { name in
                        say("checkpoint \(name)")
                        if name == killAt { kill(getpid(), SIGKILL) }
                    },
                    operation: {
                        try SpikeMigrationCoordinator(location: location).open()
                    })
                switch outcome {
                case .ready(_, let report):
                    say(
                        "ready resumedAfter=\(report.resumedAfter.map(\.rawValue) ?? "-") restored=\(report.snapshotRestored)"
                    )
                case .recovery(let reason):
                    say("recovery \(reason)")
                    exit(3)
                }

            case "raw":
                // SwiftData on its own, without the coordinator: open (and migrate), killed at
                // the checkpoint if given; then, run again without one, report what's there.
                let killAt = arguments.count > 3 ? arguments[3] : nil
                let coordinator = SpikeMigrationCoordinator(location: location)
                let container = try SpikeCheckpoint.$handler.withValue(
                    { name in
                        if name == killAt { kill(getpid(), SIGKILL) }
                    },
                    operation: {
                        try coordinator.container()
                    })
                let images = try ModelContext(container).fetchCount(FetchDescriptor<SpikeSchemaV3.ImageAssetRecord>())
                say(
                    "raw version=\(try coordinator.storedVersion().map { "\($0.rawValue)" } ?? "unknown") images=\(images)"
                )

            case "verify":
                let manifest = try JSONDecoder().decode(
                    SpikeManifest.self, from: Data(contentsOf: URL(filePath: arguments[3])))
                let coordinator = SpikeMigrationCoordinator(location: location)
                guard try coordinator.storedVersion() == .current else {
                    say("FAIL store is not at the current version")
                    exit(1)
                }
                let problems = try SpikeMigrationCoordinator.verify(try coordinator.container(), against: manifest)
                if problems.isEmpty {
                    say("OK")
                } else {
                    say("FAIL \(problems.prefix(5).joined(separator: "; "))")
                    exit(1)
                }

            default:
                say("unknown command \(arguments[1])")
                exit(2)
            }
        } catch {
            say("ERROR \(error)")
            exit(1)
        }
    }
}
