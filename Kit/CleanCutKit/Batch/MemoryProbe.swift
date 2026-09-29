import Darwin
import Foundation
import os

/// Reads this process's memory footprint — the number Xcode's memory gauge and
/// iOS's jetsam limits use (`phys_footprint`), not resident size.
public enum MemoryProbe {
    public static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

/// Samples the footprint on a timer and remembers the peak.
public final class PeakMemorySampler: Sendable {
    private let peak = OSAllocatedUnfairLock(initialState: UInt64(0))
    private let task = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    public init() {}

    public func start(interval: Duration = .milliseconds(20)) {
        peak.withLock { $0 = MemoryProbe.footprint() }
        let sampler = Task { [peak] in
            while !Task.isCancelled {
                let now = MemoryProbe.footprint()
                peak.withLock { $0 = max($0, now) }
                try? await Task.sleep(for: interval)
            }
        }
        task.withLock { $0 = sampler }
    }

    /// Stops sampling and returns the peak footprint in bytes.
    @discardableResult
    public func stop() -> UInt64 {
        task.withLock { $0?.cancel(); $0 = nil }
        let now = MemoryProbe.footprint()
        return peak.withLock { $0 = max($0, now); return $0 }
    }
}
