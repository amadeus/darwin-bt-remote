import Combine
import Foundation

@MainActor
final class DeviceNameStore: ObservableObject {
    @Published private var names: [String: String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        names = defaults.dictionary(forKey: AppSettings.deviceNamesKey) as? [String: String] ?? [:]
    }

    func name(for id: UUID) -> String? {
        names[id.uuidString]
    }

    /// Seed a missing name without replacing a saved alias or selecting a host.
    func rememberName(_ name: String, for id: UUID) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard self.name(for: id) == nil, !trimmed.isEmpty, trimmed.utf8.count <= 256,
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil else { return }
        setName(trimmed, for: id)
    }

    func setName(_ name: String, for id: UUID) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            names.removeValue(forKey: id.uuidString)
        } else {
            names[id.uuidString] = trimmed
        }
        defaults.set(names, forKey: AppSettings.deviceNamesKey)
    }

    func clear() {
        names = [:]
        defaults.removeObject(forKey: AppSettings.deviceNamesKey)
    }
}
