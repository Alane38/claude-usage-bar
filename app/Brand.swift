import Foundation

/// Nom affiché partout où l'utilisateur lit du texte. Les noms de fichiers, de dossiers et d'archives
/// gardent « ClaudeUsageBar » : changer l'un d'eux casserait les données, les permissions et la mise à jour.
enum Brand {
    static let name = "UsageForecast"
    static let tagline = "Usage de Claude, prévisions et alertes dans la barre de menu"
    static let repository = "https://github.com/Alane38/claude-usage-bar"
}
