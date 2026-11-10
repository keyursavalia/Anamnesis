import Foundation
import Testing
@testable import AnamnesisKit

@Suite("LevelMath")
struct LevelMathTests {
    static let sampleRate = 16_000.0

    static func sine(amplitude: Float, count: Int = 16_000, frequency: Double = 440) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    /// Deterministic uniform noise (LCG) so tests never flake.
    static func noise(amplitude: Float, count: Int = 16_000) -> [Float] {
        var state: UInt32 = 12_345
        return (0..<count).map { _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            return amplitude * (Float(state) / Float(UInt32.max) * 2 - 1)
        }
    }

    static func toInt16(_ samples: [Float]) -> [Int16] {
        samples.map { Int16(max(-32_768, min(32_767, ($0 * 32_768).rounded()))) }
    }

    static func measure(_ samples: [Float]) -> LevelMeasurement {
        var accumulator = LevelAccumulator()
        samples.withUnsafeBufferPointer { accumulator.add(float32: $0) }
        return accumulator.measurement
    }

    static func measure(_ samples: [Int16]) -> LevelMeasurement {
        var accumulator = LevelAccumulator()
        samples.withUnsafeBufferPointer { accumulator.add(int16: $0) }
        return accumulator.measurement
    }

    @Test("digital silence has zero level and is silent")
    func digitalSilence() {
        let level = Self.measure([Float](repeating: 0, count: 1_024))
        #expect(level.peak == 0)
        #expect(level.rms == 0)
        #expect(level.rmsDBFS == LevelMath.floorDBFS)
        #expect(level.isSilent())
    }

    @Test("a -6 dBFS sine measures -6 dBFS peak and -9 dBFS RMS in both sample formats")
    func sineLevels() {
        let amplitude = Float(pow(10, -6.0 / 20))
        let sine = Self.sine(amplitude: amplitude)
        for level in [Self.measure(sine), Self.measure(Self.toInt16(sine))] {
            #expect(abs(level.peakDBFS - -6) < 0.05)
            // RMS of a sine is peak / sqrt(2), i.e. 3.01 dB lower.
            #expect(abs(level.rmsDBFS - -9.01) < 0.05)
            #expect(!level.isSilent())
        }
    }

    @Test("-60 dBFS noise is quiet but not digital silence")
    func quietNoise() {
        let level = Self.measure(Self.noise(amplitude: Float(pow(10, -60.0 / 20))))
        #expect(level.peakDBFS <= -60 && level.peakDBFS > -61)
        #expect(!level.isSilent())
        #expect(level.isSilent(threshold: 0.01))
    }

    @Test("full-scale Int16 reaches 0 dBFS without overflow")
    func fullScaleInt16() {
        let level = Self.measure([Int16.min, Int16.max, 0, Int16.min])
        #expect(level.peak == 1)
        #expect(level.peakDBFS == 0)
    }

    @Test("non-interleaved channel buffers measure the same as one interleaved buffer")
    func interleavedEquivalence() {
        let left = Self.sine(amplitude: 0.5, count: 512)
        let right = Self.noise(amplitude: 0.1, count: 512)
        let interleaved = zip(left, right).flatMap { [$0, $1] }

        var planar = LevelAccumulator()
        left.withUnsafeBufferPointer { planar.add(float32: $0) }
        right.withUnsafeBufferPointer { planar.add(float32: $0) }

        let reference = Self.measure(interleaved)
        #expect(planar.measurement.peak == reference.peak)
        #expect(abs(planar.measurement.rms - reference.rms) < 1e-6)
    }

    @Test("an empty accumulator reports silence")
    func empty() {
        #expect(LevelAccumulator().measurement == LevelMeasurement(peak: 0, rms: 0))
    }

    @Test("dBFS conversion clamps at the floor", arguments: [
        (Float(1), Float(0)), (Float(0.1), Float(-20)),
        (Float(0), LevelMath.floorDBFS), (Float(1e-12), LevelMath.floorDBFS)
    ])
    func dbfs(linear: Float, expected: Float) {
        #expect(abs(LevelMath.dbfs(linear) - expected) < 0.001)
    }

    @Test("histogram bins are 10 dB wide from <= -110 to > -10", arguments: [
        (LevelMath.floorDBFS, 0), (Float(-110), 0), (Float(-109.9), 1), (Float(-100), 1),
        (Float(-60), 5), (Float(-55), 6), (Float(-10), 10), (Float(-9.99), 11), (Float(0), 11)
    ])
    func histogramBin(dbfs: Float, bin: Int) {
        #expect(LevelMath.histogramBin(forDBFS: dbfs) == bin)
        #expect(LevelMath.histogramBinCount == 12)
    }
}
