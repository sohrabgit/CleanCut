import CoreGraphics
import Foundation

/// Everything the app's Benchmarks screen measures in one run, written as the
/// Markdown that goes into docs/BENCHMARKS.md, plus the segmentation CSV.
public struct DeviceBenchmarkReport: Sendable {
    /// "iPhone12,8"; names the report file.
    public var hardware: String
    /// Hardware and OS, for footers.
    public var machine: String
    public var date: Date
    /// Throttling changes the numbers, so a report says how warm it started and ended.
    public var thermalStateAtStart: String
    public var thermalStateAtEnd: String

    public var segmentation: [BenchmarkResult]
    public var photoCount: Int
    public var preview: [PreviewBenchmark.Row]
    public var previewSize: CGSize
    public var capture: CaptureBenchmark.Result?

    public init(
        hardware: String = BenchmarkMachine.hardware,
        machine: String = BenchmarkMachine.description,
        date: Date = .now,
        thermalStateAtStart: String,
        thermalStateAtEnd: String,
        segmentation: [BenchmarkResult],
        photoCount: Int,
        preview: [PreviewBenchmark.Row],
        previewSize: CGSize,
        capture: CaptureBenchmark.Result?
    ) {
        self.hardware = hardware
        self.machine = machine
        self.date = date
        self.thermalStateAtStart = thermalStateAtStart
        self.thermalStateAtEnd = thermalStateAtEnd
        self.segmentation = segmentation
        self.photoCount = photoCount
        self.preview = preview
        self.previewSize = previewSize
        self.capture = capture
    }

    public var markdown: String {
        let day = date.formatted(.iso8601.year().month().day())
        var sections = [
            "# CleanCut benchmarks: \(machine)",
            "\(day). Thermal state \(thermalStateAtStart) at the start, \(thermalStateAtEnd) at the end.",
            "## Segmentation\n\n" + BenchmarkReport.markdown(segmentation, imageCount: photoCount, machine: machine),
        ]
        if !preview.isEmpty {
            sections.append(
                "## Live preview frame time\n\n" + PreviewBenchmark.markdown(preview)
                    + "\n\(preview.count) scenarios at \(Int(previewSize.width))×\(Int(previewSize.height)) (this screen's width in pixels). \(machine).\n"
            )
        }
        if let capture {
            sections.append(
                "## Guided capture analysis\n\n" + CaptureBenchmark.markdown(capture)
                    + "\nReplay frames at \(Int(capture.frameSize.width))×\(Int(capture.frameSize.height)) in camera-like pixel buffers. "
                    + String(format: "Budget at 15 fps: %.1f ms. %@.\n", CaptureBenchmark.budgetMS, machine)
            )
        }
        return sections.joined(separator: "\n\n")
    }

    public var csv: String { BenchmarkReport.csv(segmentation) }

    /// A file name without extension: "iPhone12-8-20260929-2341".
    public var fileStem: String {
        let name = String(hardware.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(format: "%04d%02d%02d-%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
        return "\(name)-\(stamp)"
    }
}
