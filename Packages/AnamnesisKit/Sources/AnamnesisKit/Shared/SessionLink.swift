import Foundation

/// Opens one capture session (spec 008 R9), for the Live Activity (spec 007) and notifications later.
/// URL form: `anamnesis://session?id=<spool session id>`
public struct SessionLink: Sendable, Equatable {
    static let host = "session"

    public var sessionID: String

    public init(sessionID: String) {
        self.sessionID = sessionID
    }

    /// The id names a folder under the spool root, so anything that could leave it is refused.
    public init?(url: URL) {
        guard url.scheme == AppIdentifiers.urlScheme, url.host() == Self.host,
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "id" })?.value,
              !id.isEmpty, !id.contains("/"), !id.contains("\\"), id != ".", id != ".." else { return nil }
        sessionID = id
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = AppIdentifiers.urlScheme
        components.host = Self.host
        components.queryItems = [URLQueryItem(name: "id", value: sessionID)]
        // Built from constant, valid parts, so `url` cannot be nil.
        return components.url!
    }
}
