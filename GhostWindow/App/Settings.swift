import Foundation

final class Settings: ObservableObject {
    static let opacityOptions: [Float] = [0.25, 0.40, 0.50, 0.60, 0.75]
    static let defaultOpacity: Float = 0.50

    private enum Keys {
        static let ghostOpacity = "ghostOpacity"
    }

    @Published var ghostOpacity: Float {
        didSet {
            UserDefaults.standard.set(Int((ghostOpacity * 100).rounded()), forKey: Keys.ghostOpacity)
        }
    }

    init() {
        let storedPercent = UserDefaults.standard.object(forKey: Keys.ghostOpacity) as? Int
        let percents = Settings.opacityOptions.map { Int(($0 * 100).rounded()) }
        if let storedPercent, percents.contains(storedPercent) {
            ghostOpacity = Float(storedPercent) / 100
        } else {
            ghostOpacity = Settings.defaultOpacity
        }
    }

    var ghostOpacityPercent: Int {
        Int((ghostOpacity * 100).rounded())
    }
}
