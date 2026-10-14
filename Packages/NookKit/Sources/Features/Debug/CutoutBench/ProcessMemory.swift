#if DEBUG
    import Darwin
    import Foundation
    import os

    /// The app's memory, read the way the system judges it. Debug builds only (the cutout
    /// benchmark, Phase 8a).
    nonisolated enum ProcessMemory {
        /// The app's physical footprint: what iOS counts against its memory limit. Zero if unreadable.
        static func footprint() -> UInt64 {
            vmInfo()?.phys_footprint ?? 0
        }

        /// The highest footprint since the app started. Zero if unreadable.
        static func lifetimePeak() -> UInt64 {
            vmInfo()?.ledger_phys_footprint_peak.magnitude ?? 0
        }

        /// How much more the app may use before iOS stops it, or `nil` where that isn't
        /// reported (the simulator returns zero).
        static func available() -> UInt64? {
            let available = os_proc_available_memory()
            return available > 0 ? UInt64(available) : nil
        }

        private static func vmInfo() -> task_vm_info_data_t? {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            return status == KERN_SUCCESS ? info : nil
        }
    }

    /// Samples the footprint in the background while some work runs, keeping the highest value
    /// and the least memory left.
    nonisolated struct MemorySampler {
        struct Reading: Hashable, Sendable {
            var peakFootprint: UInt64
            var leastAvailable: UInt64?
        }

        /// Runs `work`, sampling every `interval`, and returns its value with the reading.
        static func measure<T>(
            every interval: Duration = .milliseconds(5),
            isolation: isolated (any Actor)? = #isolation,
            _ work: () async -> T
        ) async -> (T, Reading) {
            let sampler = Task.detached(priority: .high) { () -> Reading in
                var reading = Reading(
                    peakFootprint: ProcessMemory.footprint(), leastAvailable: ProcessMemory.available())
                while !Task.isCancelled {
                    reading.add(footprint: ProcessMemory.footprint(), available: ProcessMemory.available())
                    try? await Task.sleep(for: interval)
                }
                reading.add(footprint: ProcessMemory.footprint(), available: ProcessMemory.available())
                return reading
            }
            let value = await work()
            sampler.cancel()
            return (value, await sampler.value)
        }
    }

    nonisolated extension MemorySampler.Reading {
        mutating func add(footprint: UInt64, available: UInt64?) {
            peakFootprint = max(peakFootprint, footprint)
            if let available {
                leastAvailable = min(leastAvailable ?? available, available)
            }
        }
    }
#endif
