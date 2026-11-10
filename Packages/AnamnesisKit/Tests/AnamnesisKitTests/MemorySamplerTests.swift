import Testing
@testable import AnamnesisKit

@Suite("MemorySampler")
struct MemorySamplerTests {
    @Test("reads a plausible footprint for this process")
    func readsFootprint() throws {
        let reading = try #require(MemorySampler.read())
        #expect(reading.physFootprintBytes > 1_048_576)
        #expect(reading.physFootprintMB < 65_536)
        #if os(iOS)
        #expect(reading.availableBytes != nil)
        #else
        #expect(reading.availableBytes == nil)
        #endif
    }

    @Test("converts bytes to MB")
    func megabytes() {
        let reading = MemoryReading(physFootprintBytes: 30 * 1_048_576, availableBytes: 20 * 1_048_576)
        #expect(reading.physFootprintMB == 30)
        #expect(reading.availableMB == 20)
        #expect(MemoryReading(physFootprintBytes: 0, availableBytes: nil).availableMB == nil)
    }
}
