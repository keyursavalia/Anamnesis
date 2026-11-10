/// Single source of truth for bundle, App Group, logging and IPC identifiers (D-015).
/// Never spell these strings anywhere else.
public enum AppIdentifiers {
    public static let bundlePrefix = "com.keyurdipakbhaisavalia"
    public static let appBundleID = "\(bundlePrefix).Anamnesis"
    public static let broadcastBundleID = extensionBundleID("broadcast")
    public static let controlsBundleID = extensionBundleID("controls")
    public static let appGroupID = "group.\(appBundleID)"
    public static let logSubsystem = appBundleID

    /// Darwin notification names (CFNotificationCenter Darwin center; no payload).
    public enum DarwinNotification {
        /// Posted by the broadcast extension after it writes `DONE` for a spool session (ARCHITECTURE §4).
        public static let sessionFinished = "\(appBundleID).session.finished"
    }

    /// Extension bundle IDs must be prefixed by the host app's bundle ID.
    public static func extensionBundleID(_ suffix: String) -> String {
        "\(appBundleID).\(suffix)"
    }
}
