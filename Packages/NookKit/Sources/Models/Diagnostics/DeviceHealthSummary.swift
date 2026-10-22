import Foundation

// The phone's own crash and speed reports, cut down to what she can read and approve (Phase 31,
// PRD 23.2, SECURITY_STANDARD §5).
//
// Apple's MetricKit hands the app crash, hang and speed reports. They are full of things that
// don't belong in a support note: call stacks, library names, addresses, a region setting, process
// IDs, and sometimes the text of an exception. The app keeps none of that. It keeps a few numbers
// and fixed names per event (`DiagnosticRecord`, `MetricSample`), on the phone, for 30 days, and
// this summary adds them up. The summary is the only thing that can leave the phone: only when
// she turns on "Share crash and speed details" on Send feedback, only on the note she is sending,
// and she reads every line first. Nothing here can hold text she wrote, a name, a place or a time.

/// What kind of Mach exception ended a crash. A fixed list, so no text can ride in it.
public enum CrashExceptionKind: String, CaseIterable, Hashable, Sendable, Codable {
    case badAccess
    case badInstruction
    case arithmetic
    case software
    case breakpoint
    case syscall
    case crash
    case resource
    case `guard`
    case other

    /// From the Mach exception type number MetricKit reports (`<mach/exception_types.h>`).
    public init(machType: Int?) {
        switch machType {
        case 1: self = .badAccess
        case 2: self = .badInstruction
        case 3: self = .arithmetic
        case 5: self = .software
        case 6: self = .breakpoint
        case 7, 8: self = .syscall
        case 10: self = .crash
        case 11: self = .resource
        case 12: self = .guard
        default: self = .other
        }
    }
}

/// Which signal ended a crash. A fixed list.
public enum CrashSignalKind: String, CaseIterable, Hashable, Sendable, Codable {
    case sigabrt
    case sigsegv
    case sigbus
    case sigill
    case sigtrap
    case sigfpe
    case sigkill
    case sigterm
    case sigpipe
    case none
    case other

    /// From the Darwin signal number MetricKit reports. 0 or missing is `none`.
    public init(number: Int?) {
        switch number {
        case nil, 0: self = .none
        case 4: self = .sigill
        case 5: self = .sigtrap
        case 6: self = .sigabrt
        case 8: self = .sigfpe
        case 9: self = .sigkill
        case 10: self = .sigbus
        case 11: self = .sigsegv
        case 13: self = .sigpipe
        case 15: self = .sigterm
        default: self = .other
        }
    }
}

/// The counts and timings she can share with a note. Mirrors the contract's `FeedbackDeviceHealth`.
public struct DeviceHealthSummary: Hashable, Sendable, Codable {
    /// One kind of crash and how many times it happened.
    public struct CrashKind: Hashable, Sendable, Codable {
        public var exception: CrashExceptionKind
        public var signal: CrashSignalKind
        public var count: Int

        public init(exception: CrashExceptionKind, signal: CrashSignalKind, count: Int) {
            self.exception = exception
            self.signal = signal
            self.count = count
        }
    }

    /// How many days the numbers cover (at most 30: the phone keeps no more).
    public var windowDays: Int
    public var crashes: Int
    /// Times the app stopped answering for a while.
    public var hangs: Int
    /// Times the app used a lot of processor time in a short while.
    public var cpuExceptions: Int
    public var diskWriteExceptions: Int
    /// Times the system ended the app for using too much memory.
    public var memoryExits: Int
    /// Times the system ended the app for taking too long to start or answer.
    public var watchdogExits: Int
    /// The longest hang, in milliseconds.
    public var longestHangMs: Int?
    /// The typical time from tapping the icon to the first screen, in milliseconds.
    public var launchMedianMs: Int?
    /// The most memory the app used, in megabytes.
    public var peakMemoryMB: Int?
    /// At most eight, the most frequent first.
    public var crashKinds: [CrashKind]

    public init(
        windowDays: Int, crashes: Int = 0, hangs: Int = 0, cpuExceptions: Int = 0, diskWriteExceptions: Int = 0,
        memoryExits: Int = 0, watchdogExits: Int = 0, longestHangMs: Int? = nil, launchMedianMs: Int? = nil,
        peakMemoryMB: Int? = nil, crashKinds: [CrashKind] = []
    ) {
        self.windowDays = windowDays
        self.crashes = crashes
        self.hangs = hangs
        self.cpuExceptions = cpuExceptions
        self.diskWriteExceptions = diskWriteExceptions
        self.memoryExits = memoryExits
        self.watchdogExits = watchdogExits
        self.longestHangMs = longestHangMs
        self.launchMedianMs = launchMedianMs
        self.peakMemoryMB = peakMemoryMB
        self.crashKinds = crashKinds
    }

    /// The most kinds listed.
    public static let maximumCrashKinds = 8

    /// True when there is nothing to report: no event, no timing. Then there is nothing to share.
    public var isEmpty: Bool {
        crashes + hangs + cpuExceptions + diskWriteExceptions + memoryExits + watchdogExits == 0
            && longestHangMs == nil && launchMedianMs == nil && peakMemoryMB == nil
    }

    /// Every piece of text the request carries for this summary: each number, and the fixed names.
    /// Send feedback shows each of these on the page before she sends, as `FeedbackNote.sentValues`
    /// does for the rest of the note.
    public var sentValues: [String] {
        var values = [windowDays, crashes, hangs, cpuExceptions, diskWriteExceptions, memoryExits, watchdogExits]
            .map(String.init)
        for optional in [longestHangMs, launchMedianMs, peakMemoryMB] {
            if let optional { values.append(String(optional)) }
        }
        for kind in crashKinds {
            values += [kind.exception.rawValue, kind.signal.rawValue, String(kind.count)]
        }
        return values
    }

    // The contract's bounds (`FeedbackDeviceHealth`), so a summary that can't be sent is never built.
    private enum Limits {
        static let count = 10_000
        static let hangMs = 3_600_000
        static let launchMs = 600_000
        static let memoryMB = 65_536
    }

    /// Whether the contract will take it: counts and timings in range, at most eight kinds.
    public var isWithinContract: Bool {
        (1...90).contains(windowDays)
            && [crashes, hangs, cpuExceptions, diskWriteExceptions, memoryExits, watchdogExits]
                .allSatisfy { (0...Limits.count).contains($0) }
            && (longestHangMs ?? 0) <= Limits.hangMs && (longestHangMs ?? 0) >= 0
            && (launchMedianMs ?? 0) <= Limits.launchMs && (launchMedianMs ?? 0) >= 0
            && (peakMemoryMB ?? 0) <= Limits.memoryMB && (peakMemoryMB ?? 0) >= 0
            && crashKinds.count <= Self.maximumCrashKinds
            && crashKinds.allSatisfy { (0...Limits.count).contains($0.count) }
    }

    /// The same summary with every number held inside the contract's bounds, for a phone that
    /// kept more than the contract allows (it never should; this makes sure of it).
    public func clamped() -> DeviceHealthSummary {
        func cap(_ value: Int, _ upper: Int) -> Int { min(max(value, 0), upper) }
        return DeviceHealthSummary(
            windowDays: min(max(windowDays, 1), 90), crashes: cap(crashes, Limits.count),
            hangs: cap(hangs, Limits.count),
            cpuExceptions: cap(cpuExceptions, Limits.count),
            diskWriteExceptions: cap(diskWriteExceptions, Limits.count),
            memoryExits: cap(memoryExits, Limits.count), watchdogExits: cap(watchdogExits, Limits.count),
            longestHangMs: longestHangMs.map { cap($0, Limits.hangMs) },
            launchMedianMs: launchMedianMs.map { cap($0, Limits.launchMs) },
            peakMemoryMB: peakMemoryMB.map { cap($0, Limits.memoryMB) },
            crashKinds: crashKinds.prefix(Self.maximumCrashKinds).map {
                CrashKind(exception: $0.exception, signal: $0.signal, count: cap($0.count, Limits.count))
            })
    }
}
