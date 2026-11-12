import Foundation
import Testing
@testable import AnamnesisKit

@Suite("CaptureLaunchLink")
struct CaptureLaunchLinkTests {
    @Test("round-trips rung and tap time through the URL", arguments: CaptureLaunchLink.Rung.allCases)
    func roundTrip(_ rung: CaptureLaunchLink.Rung) throws {
        let tappedAt = Date(timeIntervalSince1970: 1_794_000_000.25)
        let link = CaptureLaunchLink(rung: rung, tappedAt: tappedAt)
        let parsed = try #require(CaptureLaunchLink(url: link.url))
        #expect(parsed.rung == rung)
        let parsedTap = try #require(parsed.tappedAt)
        #expect(abs(parsedTap.timeIntervalSince(tappedAt)) < 0.001)
    }

    @Test("uses the app's URL scheme and the capture host")
    func shape() {
        let url = CaptureLaunchLink(rung: .onTap, tappedAt: nil).url
        #expect(url.scheme == AppIdentifiers.urlScheme)
        #expect(url.host() == "capture")
        #expect(url.absoluteString == "anamnesis://capture?rung=1")
    }

    @Test("a bare or unknown-rung capture URL opens the screen without presenting the picker",
          arguments: ["anamnesis://capture", "anamnesis://capture?rung=9"])
    func defaults(_ string: String) throws {
        let parsed = try #require(CaptureLaunchLink(url: URL(string: string)!))
        #expect(parsed.rung == .onTap)
        #expect(parsed.tappedAt == nil)
    }

    @Test("rejects other schemes and hosts", arguments: ["https://capture?rung=2", "anamnesis://library"])
    func rejects(_ string: String) {
        #expect(CaptureLaunchLink(url: URL(string: string)!) == nil)
    }

    @Test("ignores a malformed tap time")
    func malformedTime() throws {
        let parsed = try #require(CaptureLaunchLink(url: URL(string: "anamnesis://capture?rung=2&t=soon")!))
        #expect(parsed.rung == .onArrival)
        #expect(parsed.tappedAt == nil)
    }
}
