import AppKit

enum SoundEffect: CaseIterable, Hashable {
    case activation
    case success

    var resourceName: String {
        switch self {
        case .activation:
            "activation"
        case .success:
            "success"
        }
    }

    var playbackVolume: Float {
        switch self {
        case .activation:
            0.32
        case .success:
            0.38
        }
    }
}

@MainActor
final class SoundManager {
    static let shared = SoundManager()

    typealias SoundLoader = (SoundEffect) -> NSSound?

    private let loader: SoundLoader
    private var loadedEffects = Set<SoundEffect>()
    private var sounds: [SoundEffect: NSSound] = [:]

    private convenience init() {
        self.init { effect in
            // Los .wav son opcionales (licencia de SND, ver Sounds/NOTICE.txt): sin ellos no suena nada.
            guard let url = Bundle.main.url(
                forResource: effect.resourceName,
                withExtension: "wav",
                subdirectory: "Sounds"
            ) else {
                return nil
            }

            return NSSound(contentsOf: url, byReference: false)
        }
    }

    init(loader: @escaping SoundLoader) {
        self.loader = loader
        prepare()
    }

    func prepare() {
        for effect in SoundEffect.allCases {
            _ = sound(for: effect)
        }
    }

    func play(_ effect: SoundEffect) {
        guard let sound = sound(for: effect) else {
            return
        }

        if sound.isPlaying {
            sound.stop()
        }

        sound.currentTime = 0
        sound.volume = effect.playbackVolume
        sound.play()
    }

    private func sound(for effect: SoundEffect) -> NSSound? {
        if loadedEffects.contains(effect) {
            return sounds[effect]
        }

        loadedEffects.insert(effect)
        guard let sound = loader(effect) else {
            return nil
        }

        sounds[effect] = sound
        return sound
    }
}
