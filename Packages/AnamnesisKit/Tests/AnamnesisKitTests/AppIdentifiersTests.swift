import Testing
@testable import AnamnesisKit

@Suite("AppIdentifiers")
struct AppIdentifiersTests {
    @Test("derives every identifier from the bundle prefix (D-015)")
    func derivedIdentifiers() {
        #expect(AppIdentifiers.appBundleID == "com.keyurdipakbhaisavalia.Anamnesis")
        #expect(AppIdentifiers.appGroupID == "group.com.keyurdipakbhaisavalia.Anamnesis")
        #expect(AppIdentifiers.logSubsystem == AppIdentifiers.appBundleID)
        #expect(AppIdentifiers.broadcastBundleID == "com.keyurdipakbhaisavalia.Anamnesis.broadcast")
        #expect(AppIdentifiers.controlsBundleID == "com.keyurdipakbhaisavalia.Anamnesis.controls")
        #expect(AppIdentifiers.DarwinNotification.sessionFinished
            == "com.keyurdipakbhaisavalia.Anamnesis.session.finished")
    }
}
