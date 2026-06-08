import Foundation

struct PreferencesRepository: Sendable {
    private let favouritesKey = "ai.purple.ddev-menubar.favourites"

    func loadFavourites() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: favouritesKey) ?? []
        return Set(array)
    }

    func saveFavourites(_ names: Set<String>) {
        UserDefaults.standard.set(Array(names).sorted(), forKey: favouritesKey)
    }
}
