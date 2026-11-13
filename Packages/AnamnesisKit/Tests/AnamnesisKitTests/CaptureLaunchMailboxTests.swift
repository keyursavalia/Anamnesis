import Foundation
import Testing
@testable import AnamnesisKit

@Suite("CaptureLaunchMailbox")
struct CaptureLaunchMailboxTests {
    @Test("holds the latest command until taken once, and announces each post")
    func latestWinsAndTakeEmpties() async {
        let mailbox = CaptureLaunchMailbox()
        let center = NotificationCenter()
        let first = CaptureLaunchLink(rung: .onTap, tappedAt: nil)
        let second = CaptureLaunchLink(rung: .withoutForeground, tappedAt: Date(timeIntervalSince1970: 1))
        nonisolated(unsafe) var posts = 0
        let token = center.addObserver(forName: CaptureLaunchMailbox.didPost, object: nil, queue: nil) { _ in
            posts += 1
        }
        defer { center.removeObserver(token) }

        #expect(mailbox.take() == nil)
        mailbox.post(.start(first), center: center)
        mailbox.post(.start(second), center: center)
        #expect(posts == 2)
        #expect(mailbox.take() == .start(second))
        #expect(mailbox.take() == nil)
    }

    @Test("a stop posted after a start replaces it (control switched off before the app drained)")
    func stopReplacesStart() {
        let mailbox = CaptureLaunchMailbox()
        let center = NotificationCenter()
        mailbox.post(.start(CaptureLaunchLink(rung: .withoutForeground, tappedAt: nil)), center: center)
        mailbox.post(.stop, center: center)
        #expect(mailbox.take() == .stop)
        #expect(mailbox.take() == nil)
    }
}
