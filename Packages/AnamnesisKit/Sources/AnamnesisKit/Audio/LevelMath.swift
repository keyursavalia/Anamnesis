import Foundation

/// Peak and RMS of a block of audio, linear full-scale (0...1).
public struct LevelMeasurement: Sendable, Equatable, Codable {
    public var peak: Float
    public var rms: Float

    public init(peak: Float, rms: Float) {
        self.peak = peak
        self.rms = rms
    }

    public var peakDBFS: Float { LevelMath.dbfs(peak) }
    public var rmsDBFS: Float { LevelMath.dbfs(rms) }

    /// Spec 001 §4.3: a buffer is silent when its peak is below `threshold` full scale.
    public func isSilent(threshold: Float = LevelMath.defaultSilenceThreshold) -> Bool {
        peak < threshold
    }
}

/// Single-pass peak/RMS over one or more sample blocks. Real-time safe: no allocation, no locks.
/// Feed every channel buffer of a non-interleaved list, or one interleaved buffer — the result is the same.
public struct LevelAccumulator: Sendable {
    private var peak: Float = 0
    private var sumOfSquares: Double = 0
    private var sampleCount = 0

    public init() {}

    public mutating func add(float32 samples: UnsafeBufferPointer<Float>) {
        for sample in samples {
            let magnitude = abs(sample)
            if magnitude > peak { peak = magnitude }
            sumOfSquares += Double(sample) * Double(sample)
        }
        sampleCount += samples.count
    }

    public mutating func add(int16 samples: UnsafeBufferPointer<Int16>) {
        // Normalize by 32768 so Int16.min maps to exactly -1.0 (0 dBFS).
        let scale: Float = 1 / 32_768
        for sample in samples {
            let value = Float(sample) * scale
            let magnitude = abs(value)
            if magnitude > peak { peak = magnitude }
            sumOfSquares += Double(value) * Double(value)
        }
        sampleCount += samples.count
    }

    public var measurement: LevelMeasurement {
        guard sampleCount > 0 else { return LevelMeasurement(peak: 0, rms: 0) }
        return LevelMeasurement(peak: peak, rms: Float((sumOfSquares / Double(sampleCount)).squareRoot()))
    }
}

public enum LevelMath {
    /// Lowest reported level; keeps digital silence finite so it encodes to JSON.
    public static let floorDBFS: Float = -160
    public static let defaultSilenceThreshold: Float = 1e-4

    /// Histogram edges in dBFS: bin 0 is ≤ -110, then 10 dB bins up to (-20, -10], bin 11 is > -10.
    /// Spec 001 §4.3 asks for 12 bins; the floor sits at -110 so digital silence and a quiet noise floor separate.
    public static let histogramLowestEdge: Float = -110
    public static let histogramBinWidth: Float = 10
    public static let histogramBinCount = 12

    public static func dbfs(_ linear: Float) -> Float {
        guard linear > 0 else { return floorDBFS }
        return max(floorDBFS, 20 * log10(linear))
    }

    public static func histogramBin(forDBFS dbfs: Float) -> Int {
        guard dbfs > histogramLowestEdge else { return 0 }
        let bin = Int(((dbfs - histogramLowestEdge) / histogramBinWidth).rounded(.up))
        return min(bin, histogramBinCount - 1)
    }
}
