import Darwin
#if os(iOS)
import os
#endif

/// One reading of this process's memory, in the units jetsam uses (CONVENTIONS §4).
public struct MemoryReading: Sendable, Equatable, Codable {
    /// `task_vm_info.phys_footprint` — what jetsam compares against the process limit.
    public var physFootprintBytes: UInt64
    /// `os_proc_available_memory()` — headroom before jetsam; nil where the API does not exist (macOS).
    public var availableBytes: UInt64?

    public init(physFootprintBytes: UInt64, availableBytes: UInt64?) {
        self.physFootprintBytes = physFootprintBytes
        self.availableBytes = availableBytes
    }

    public var physFootprintMB: Double { Double(physFootprintBytes) / 1_048_576 }
    public var availableMB: Double? { availableBytes.map { Double($0) / 1_048_576 } }
}

public enum MemorySampler {
    /// Cheap (one syscall each); safe to call from a timer every few seconds, not per audio buffer.
    /// Returns nil only if `task_info` fails.
    public static func read() -> MemoryReading? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return MemoryReading(physFootprintBytes: info.phys_footprint, availableBytes: availableBytes())
    }

    private static func availableBytes() -> UInt64? {
        #if os(iOS)
        UInt64(os_proc_available_memory())
        #else
        nil
        #endif
    }
}
