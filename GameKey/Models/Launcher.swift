import Foundation

/// One of the launchers we know how to install. Adding a new launcher is just a new case here
/// plus a new `InstallRecipe` in `LauncherCatalog`.
enum Launcher: String, CaseIterable, Identifiable, Codable {
    case steam
    case epic
    case gog
    case ubisoft
    case ea
    case rockstar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .steam:    return "Steam"
        case .epic:     return "Epic Games"
        case .gog:      return "GOG Galaxy"
        case .ubisoft:  return "Ubisoft Connect"
        case .ea:       return "EA App"
        case .rockstar: return "Rockstar Games"
        }
    }

    var subtitle: String {
        switch self {
        case .steam:    return "Valve's storefront and library"
        case .epic:     return "Epic Games Store and Unreal Engine titles"
        case .gog:      return "DRM-free games from CD Projekt"
        case .ubisoft:  return "Ubisoft titles and Ubisoft+ subscription"
        case .ea:       return "Electronic Arts titles and EA Play"
        case .rockstar: return "GTA, Red Dead, and other Rockstar titles"
        }
    }

    /// SF Symbol name used until we add proper artwork.
    var iconSymbol: String {
        switch self {
        case .steam:    return "gamecontroller.fill"
        case .epic:     return "bolt.fill"
        case .gog:      return "moon.stars.fill"
        case .ubisoft:  return "shield.fill"
        case .ea:       return "play.rectangle.fill"
        case .rockstar: return "star.fill"
        }
    }

    /// Short hex tint string used by the launcher card. View layer converts to Color.
    var accentHex: String {
        switch self {
        case .steam:    return "1B2838"
        case .epic:     return "2A2A2A"
        case .gog:      return "86328A"
        case .ubisoft:  return "0085E2"
        case .ea:       return "FF4747"
        case .rockstar: return "F7B500"
        }
    }
}
