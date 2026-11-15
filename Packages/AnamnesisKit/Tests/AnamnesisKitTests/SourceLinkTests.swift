import Foundation
import Testing
@testable import AnamnesisKit

@Suite("Source links")
struct SourceLinkTests {
    @Test("a pasted share link is found, alone or inside a note")
    func finds() {
        let reel = "https://www.instagram.com/reel/C9abc123/?igsh=xyz"
        #expect(SourceLink.url(in: reel)?.absoluteString == reel)
        #expect(SourceLink.url(in: "Saw it here: \(reel) — lovely")?.absoluteString == reel)
        #expect(SourceLink.url(in: "vm.tiktok.com/ZMabc/")?.host() == "vm.tiktok.com")
    }

    @Test("notes without a web link, and non-web schemes, give nothing")
    func rejects() {
        #expect(SourceLink.url(in: nil) == nil)
        #expect(SourceLink.url(in: "") == nil)
        #expect(SourceLink.url(in: "Instagram reel from @poet") == nil)
        #expect(SourceLink.url(in: "tel:+15551234567") == nil)
        #expect(SourceLink.url(in: "mailto:a@b.com") == nil)
    }

    @Test("known hosts get the platform's name; others their host")
    func names() throws {
        let cases = [("https://www.instagram.com/reel/x", "Instagram"), ("https://vm.tiktok.com/ZM/", "TikTok"),
                     ("https://youtu.be/abc", "YouTube"), ("https://x.com/p/status/1", "X"),
                     ("https://www.poetryfoundation.org/poems/1", "poetryfoundation.org")]
        for (link, name) in cases {
            #expect(SourceLink.name(of: try #require(URL(string: link))) == name)
        }
    }
}
