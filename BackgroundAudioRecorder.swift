import AVFoundation

/// Ilova fonda turganda ovoz yozadi.
///
/// iOS fonda **kameraga** ruxsat bermaydi -- shuning uchun fonga chiqqanda video to'xtaydi.
/// Lekin **mikrofonga** ruxsat beradi (Info.plist'dagi UIBackgroundModes: audio orqali),
/// shuning uchun telefon qulflangan yoki boshqa ilova ochiq bo'lsa ham ovoz yozilaveradi.
final class BackgroundAudioRecorder {

    private var recorder: AVAudioRecorder?
    private var url: URL?

    var isRecording: Bool { recorder?.isRecording ?? false }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // .record kategoriyasi + fon rejimi: ekran qulflangandan keyin ham yozishni davom ettiradi.
        try session.setCategory(.record, mode: .default, options: [])
        try session.setActive(true, options: [])

        let name = "AUD_\(Self.stamp()).m4a"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        guard recorder.record() else {
            throw NSError(domain: "blackC.audio", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "yozuvni boshlab bo'lmadi"])
        }

        self.recorder = recorder
        self.url = fileURL
    }

    /// Yozuvni tugatadi va fayl manzilini qaytaradi (hech narsa yozilmagan bo'lsa nil).
    @discardableResult
    func stop() -> URL? {
        guard let recorder else { return nil }
        recorder.stop()
        self.recorder = nil

        // Boshqa ilovalar ovozi normal chiqishi uchun audio sessiyani bo'shatamiz.
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

        let result = url
        url = nil
        return result
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}
