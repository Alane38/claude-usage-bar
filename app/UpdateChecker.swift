import Foundation

/// Dernière version publiée sur GitHub (`releases/latest`) : seule la logique pure, sans réseau.
struct ReleaseInfo: Equatable {
    let version: String
    let pageURL: URL
}

enum UpdateChecker {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/Alane38/claude-usage-bar/releases/latest")!
    /// Une vérification toutes les 6 h suffit : les versions sortent au plus quelques fois par jour.
    static let interval: TimeInterval = 6 * 3600

    /// Lit `tag_name` (« v1.8.1 ») et `html_url` ; nil si la réponse n'est pas une release (404, brouillon, JSON inattendu).
    static func parse(_ data: Data) -> ReleaseInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let link = json["html_url"] as? String, let url = URL(string: link),
              url.scheme == "https", url.host == "github.com",
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
              components(tag) != nil else { return nil }
        return ReleaseInfo(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, pageURL: url)
    }

    /// « 1.8.1 » > « 1.8.0 », comparaison numérique composante par composante (1.10.0 > 1.9.0).
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let new = components(candidate), let old = components(current) else { return false }
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    static func shouldCheck(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    private static func components(_ version: String) -> [Int]? {
        let bare = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let parts = bare.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }
    }
}
