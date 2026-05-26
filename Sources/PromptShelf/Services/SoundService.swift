import AVFoundation

final class SoundService: NSObject {

    static let shared = SoundService()

    private var startPlayer: AVAudioPlayer?
    private var stopPlayer: AVAudioPlayer?

    private override init() {
        super.init()
        startPlayer = makePlayer(resource: "trigger_start", ext: "wav")
        stopPlayer  = makePlayer(resource: "trigger_stop",  ext: "wav")
    }

    // MARK: - Public

    func playStart() {
        startPlayer?.currentTime = 0
        startPlayer?.play()
    }

    func playStop() {
        stopPlayer?.currentTime = 0
        stopPlayer?.play()
    }

    // MARK: - Private

    private func makePlayer(resource: String, ext: String) -> AVAudioPlayer? {
        guard let url = Bundle.module.url(forResource: resource, withExtension: ext) else {
            print("⚠️ SoundService: \(resource).\(ext) not found in bundle")
            return nil
        }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.5
        player?.prepareToPlay()
        return player
    }
}
