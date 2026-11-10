import Foundation

/// Device facts every report carries. Foundation/Darwin only, so extensions can use it (no UIKit).
public struct DeviceSnapshot: Sendable, Equatable, Codable {
    /// e.g. "iPad14,3"; on the simulator, the simulated model.
    public var modelIdentifier: String
    public var osVersion: String
    /// e.g. "24A437" — FINDINGS entries require the build, not just the version.
    public var osBuild: String
    public var thermalState: String
    public var lowPowerModeEnabled: Bool
    public var physicalMemoryBytes: UInt64
    public var isSimulator: Bool

    public static func current() -> DeviceSnapshot {
        let info = ProcessInfo.processInfo
        let version = info.operatingSystemVersion
        #if targetEnvironment(simulator)
        let model = info.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machineIdentifier()
        let isSimulator = true
        #else
        let model = machineIdentifier()
        let isSimulator = false
        #endif
        return DeviceSnapshot(
            modelIdentifier: model,
            osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            osBuild: sysctlString("kern.osversion") ?? "unknown",
            thermalState: thermalStateName(info.thermalState),
            lowPowerModeEnabled: info.isLowPowerModeEnabled,
            physicalMemoryBytes: info.physicalMemory,
            isSimulator: isSimulator
        )
    }

    public static func currentThermalStateName() -> String {
        thermalStateName(ProcessInfo.processInfo.thermalState)
    }

    static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown(\(state.rawValue))"
        }
    }

    /// `uname().machine` is a fixed-size C char tuple.
    private static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { bytes in
            String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8) ?? "unknown"
        }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8)
    }
}

/// Identity of the running bundle (app or extension).
public struct BundleSnapshot: Sendable, Equatable, Codable {
    public var bundleID: String
    public var version: String
    public var build: String

    public static func current(_ bundle: Bundle = .main) -> BundleSnapshot {
        let info = bundle.infoDictionary ?? [:]
        return BundleSnapshot(
            bundleID: bundle.bundleIdentifier ?? "unknown",
            version: info["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info["CFBundleVersion"] as? String ?? "unknown"
        )
    }
}
