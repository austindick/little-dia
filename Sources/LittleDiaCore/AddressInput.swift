import Foundation

/// What was typed in the New Little Window box, as a web page to open: a web address (with `https://` added when it's
/// left off) or a Google search. Never anything but `http` or `https`, so the box can't open files or browser pages.
public enum AddressInput {
    public static func url(from text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let scheme = text.split(separator: ":", maxSplits: 1).first?.lowercased(), scheme == "http" || scheme == "https",
           let url = URL(string: text), url.host != nil {
            return url
        }
        if isAddress(text), let url = URL(string: "https://" + text) { return url }
        return search(text)
    }

    /// `example.com/path`, `docs.google.com`, `10.0.0.1:8080`, `localhost:3000`: no spaces, and a host that's
    /// `localhost` or has a dot, with a last part that isn't empty.
    private static func isAddress(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace) else { return false }
        let hostAndPort = text.prefix { !"/?#".contains($0) }
        let parts = hostAndPort.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return false }
        if parts.count == 2, parts[1].isEmpty || !parts[1].allSatisfy(\.isNumber) { return false }
        let host = parts[0].lowercased()
        if host == "localhost" { return true }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard labels.allSatisfy({ $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return false }
        // `1.5` is a number to search for, not a host; an IPv4 address has four numeric parts.
        return labels.last!.contains(where: \.isLetter) || (labels.count == 4 && labels.allSatisfy { $0.allSatisfy(\.isNumber) })
    }

    private static func search(_ text: String) -> URL? {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?+#"))
        guard let query = text.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://www.google.com/search?q=" + query)
    }
}
