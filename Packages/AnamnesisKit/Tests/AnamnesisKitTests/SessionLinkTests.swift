import Foundation
import Testing
@testable import AnamnesisKit

@Suite("SessionLink")
struct SessionLinkTests {
    @Test("round-trips a session id through the URL")
    func roundTrip() throws {
        let link = SessionLink(sessionID: "20261112T100000Z-abcd")
        #expect(link.url.absoluteString == "anamnesis://session?id=20261112T100000Z-abcd")
        #expect(try #require(SessionLink(url: link.url)) == link)
    }

    @Test("rejects other hosts, missing ids and ids that could leave the spool folder",
          arguments: ["anamnesis://capture?id=x", "https://session?id=x", "anamnesis://session",
                      "anamnesis://session?id=", "anamnesis://session?id=..", "anamnesis://session?id=a/b",
                      "anamnesis://session?id=a%2Fb"])
    func rejects(_ string: String) {
        #expect(SessionLink(url: URL(string: string)!) == nil)
    }
}
