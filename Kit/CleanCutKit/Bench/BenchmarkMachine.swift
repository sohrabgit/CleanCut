import Foundation

/// Names the hardware a benchmark ran on, for report footers.
public enum BenchmarkMachine {
    /// The chip on a Mac ("Apple M4 Max"), the model identifier on an iPhone
    /// or iPad ("iPhone12,8"), in the Simulator the Mac's chip.
    public static var hardware: String {
        #if os(macOS)
        return sysctlString("machdep.cpu.brand_string") ?? "Mac"
        #else
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) Simulator"
        }
        return sysctlString("hw.machine") ?? "iOS device"
        #endif
    }

    /// "iOS 26.0 (Build 23A341)".
    public static var operatingSystem: String {
        #if os(macOS)
        let name = "macOS"
        #else
        let name = "iOS"
        #endif
        let version = ProcessInfo.processInfo.operatingSystemVersionString.replacingOccurrences(of: "Version ", with: "")
        return "\(name) \(version)"
    }

    /// A phone that heats up throttles, so reports say how warm it was.
    public static var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    /// "Apple M4 Max, macOS 26.6 (Build 25G83)".
    public static var description: String {
        "\(hardware), \(operatingSystem)"
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
