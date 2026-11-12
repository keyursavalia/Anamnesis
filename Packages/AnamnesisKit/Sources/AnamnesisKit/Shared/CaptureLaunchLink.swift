import Foundation

/// A capture launch request from the Control Center control or a deep link (spec 005 R2).
/// URL form: `anamnesis://capture?rung=<1|2|3>&t=<tap time, Unix seconds>`
public struct CaptureLaunchLink: Sendable, Equatable {
    static let host = "capture"

    /// The spec 005 R2 ladder: when the system picker is presented.
    public enum Rung: Int, Sendable, CaseIterable {
        /// 1: open the capture screen; the user taps to present the picker.
        case onTap = 1
        /// 2: open the capture screen and present the picker on arrival.
        case onArrival = 2
        /// 3: present the picker without bringing the app forward (experiment).
        case withoutForeground = 3
    }

    public var rung: Rung
    /// When the request was made (wall clock), so the app can measure → first buffer without shared storage.
    public var tappedAt: Date?

    public init(rung: Rung, tappedAt: Date?) {
        self.rung = rung
        self.tappedAt = tappedAt
    }

    public init?(url: URL) {
        guard url.scheme == AppIdentifiers.urlScheme, url.host() == Self.host else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        rung = value("rung").flatMap(Int.init).flatMap(Rung.init(rawValue:)) ?? .onTap
        tappedAt = value("t").flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = AppIdentifiers.urlScheme
        components.host = Self.host
        components.queryItems = [URLQueryItem(name: "rung", value: String(rung.rawValue))]
            + (tappedAt.map { [URLQueryItem(name: "t", value: String($0.timeIntervalSince1970))] } ?? [])
        // Built from constant, valid parts, so `url` cannot be nil.
        return components.url!
    }
}
