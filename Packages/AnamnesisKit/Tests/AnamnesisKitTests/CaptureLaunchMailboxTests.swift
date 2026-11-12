import Foundation
import Testing
@testable import AnamnesisKit

@Suite("CaptureLaunchMailbox")
struct CaptureLaunchMailboxTests {
    @Test("holds the latest link until taken once, and announces each post")
    func latestWinsAndTakeEmpties() async {
        let mailbox = CaptureLaunchMailbox()
        let center = NotificationCenter()
        let first = CaptureLaunchLink(rung: .onTap, tappedAt: nil)
        let second = CaptureLaunchLink(rung: .onArrival, tappedAt: Date(timeIntervalSince1970: 1))
        nonisolated(unsafe) var posts = 0
        let token = center.addObserver(forName: CaptureLaunchMailbox.didPost, object: nil, queue: nil) { _ in
            posts += 1
        }
        defer { center.removeObserver(token) }

        #expect(mailbox.take() == nil)
        mailbox.post(first, center: center)
        mailbox.post(second, center: center)
        #expect(posts == 2)
        #expect(mailbox.take() == second)
        #expect(mailbox.take() == nil)
    }

    @Test("cannot present in place until the app registers a check (F-031)")
    func inPlaceCheck() async {
        let mailbox = CaptureLaunchMailbox()
        #expect(await mailbox.canPresentInPlace(timeout: .milliseconds(100)) == false)
        mailbox.setInPlaceCheck { true }
        #expect(await mailbox.canPresentInPlace())
        mailbox.setInPlaceCheck { false }
        #expect(await mailbox.canPresentInPlace() == false)
    }

    @Test("waits for a check registered shortly after the call (cold launch)")
    func waitsForLateRegistration() async {
        let mailbox = CaptureLaunchMailbox()
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            mailbox.setInPlaceCheck { true }
        }
        #expect(await mailbox.canPresentInPlace(timeout: .seconds(2)))
    }
}
