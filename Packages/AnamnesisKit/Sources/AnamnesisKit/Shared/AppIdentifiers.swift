/// Single source of truth for bundle, App Group, logging and IPC identifiers (D-015).
/// Never spell these strings anywhere else.
public enum AppIdentifiers {
    public static let bundlePrefix = "com.keyurdipakbhaisavalia"
    public static let appBundleID = "\(bundlePrefix).Anamnesis"
    public static let controlsBundleID = extensionBundleID("controls")
    public static let appGroupID = "group.\(appBundleID)"
    public static let logSubsystem = appBundleID
    /// Custom URL scheme registered in the app's Info.plist (`CFBundleURLTypes`).
    public static let urlScheme = "anamnesis"
    /// `ControlWidget` kinds; also used with `ControlCenter.shared.reloadControls(ofKind:)`.
    public enum ControlKind {
        public static let capture = "\(appBundleID).control.capture"
    }

    /// Extension bundle IDs must be prefixed by the host app's bundle ID.
    public static func extensionBundleID(_ suffix: String) -> String {
        "\(appBundleID).\(suffix)"
    }
}
