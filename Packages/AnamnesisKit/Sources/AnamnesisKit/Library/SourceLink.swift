import Foundation

/// The link in a poem's source (spec 016 R4). Users paste a reel's share link; opening it hands the URL to the
/// system, which opens the app that owns it (universal links) or the browser. The app itself makes no request.
public enum SourceLink {
    /// The first web link in `note`, if any. Only `http`/`https`: a pasted `tel:`, `sms:` or custom-scheme string is
    /// never offered as something to open. A bare `instagram.com/reel/…` is read as `http://…`, as Safari would.
    public static func url(in note: String?) -> URL? {
        guard let note, !note.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(note.startIndex..., in: note)
        for match in detector.matches(in: note, range: range) {
            guard let url = match.url, let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", url.host() != nil else { continue }
            return url
        }
        return nil
    }

    /// "Instagram", "TikTok", … for known short-video hosts; otherwise the host without `www.`.
    public static func name(of url: URL) -> String {
        let host = (url.host() ?? "").lowercased()
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        for (domain, name) in knownHosts where bare == domain || bare.hasSuffix("." + domain) {
            return name
        }
        return bare
    }

    private static let knownHosts: [(String, String)] = [
        ("instagram.com", "Instagram"), ("tiktok.com", "TikTok"), ("youtube.com", "YouTube"),
        ("youtu.be", "YouTube"), ("facebook.com", "Facebook"), ("fb.watch", "Facebook"),
        ("x.com", "X"), ("twitter.com", "X"), ("threads.net", "Threads"), ("threads.com", "Threads")
    ]
}
