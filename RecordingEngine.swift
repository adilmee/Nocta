import AVFoundation

/// Videoni `AVAssetWriter` orqali yozadi.
///
/// Nega `AVCaptureMovieFileOutput` emas? Chunki u yozish davomida sessiya kirishini
/// almashtirishga yo'l qo'ymaydi — kamera almashtirilsa yozuv uziladi va fayl tugaydi.
/// AssetWriter esa kameradan mustaqil: kadrlar qayerdan kelishidan qat'i nazar,
/// bitta uzluksiz faylga yoziladi.
final class RecordingEngine {

    enum RecordingError: LocalizedError {
        case cannotAddInput
        case cannotStart
        case noFrames
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cannotAddInput: return "Yozuv kanalini qo'shib bo'lmadi"
            case .cannotStart: return "Yozuvchini ishga tushirib bo'lmadi"
            case .noFrames: return "Birorta ham kadr yozilmadi"
            case .failed(let reason): return reason
            }
        }
    }

    private(set) var isRecording = false

    private let queue: DispatchQueue

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?

    private var didStartSession = false
    private var firstPTS: CMTime = .invalid
    private var lastPTS: CMTime = .invalid

    /// Yozilgan materialning haqiqiy uzunligi (kadr vaqtlari bo'yicha).
    var duration: TimeInterval {
        guard firstPTS.isValid, lastPTS.isValid else { return 0 }
        let seconds = CMTimeGetSeconds(CMTimeSubtract(lastPTS, firstPTS))
        return seconds.isFinite ? max(0, seconds) : 0
    }

    /// Barcha chaqiruvlar shu navbatda bo'lishi kerak.
    init(queue: DispatchQueue) {
        self.queue = queue
    }

    // MARK: - Start

    func start(url: URL, size: CGSize, audioSettings: [String: Any]?) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 4,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput) else { throw RecordingError.cannotAddInput }
        writer.add(videoInput)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        var audioWriterInput: AVAssetWriterInput?
        if let audioSettings {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audioWriterInput = input
            }
        }

        guard writer.startWriting() else {
            throw writer.error ?? RecordingError.cannotStart
        }

        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioWriterInput
        self.adaptor = adaptor
        self.outputURL = url
        self.didStartSession = false
        self.firstPTS = .invalid
        self.lastPTS = .invalid
        self.isRecording = true
    }

    // MARK: - Append

    func appendVideo(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard isRecording,
              let writer, writer.status == .writing,
              let videoInput, let adaptor,
              time.isValid
        else { return }

        if !didStartSession {
            writer.startSession(atSourceTime: time)
            didStartSession = true
            firstPTS = time
        }

        // Kamera almashtirilgan lahzada ikkala oqimdan kadr kelib, vaqt teskari ketishi mumkin.
        // AVAssetWriter esa qat'iy o'sib boruvchi vaqt talab qiladi — bunday kadrni tashlaymiz,
        // aks holda yozuvchi butunlay xatoga tushadi va fayl yo'qoladi.
        if lastPTS.isValid, CMTimeCompare(time, lastPTS) <= 0 { return }

        // Kodlovchi ulgurmasa kadrni tashlab yuboramiz — real vaqt yozuvida to'g'ri yo'l.
        guard videoInput.isReadyForMoreMediaData else { return }

        if adaptor.append(pixelBuffer, withPresentationTime: time) {
            lastPTS = time
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              didStartSession,
              let writer, writer.status == .writing,
              let audioInput, audioInput.isReadyForMoreMediaData
        else { return }

        audioInput.append(sampleBuffer)
    }

    // MARK: - Finish

    func finish(completion: @escaping (URL?, Error?) -> Void) {
        guard isRecording, let writer else {
            completion(nil, RecordingError.noFrames)
            return
        }

        isRecording = false
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        let url = outputURL

        guard didStartSession, writer.status == .writing else {
            writer.cancelWriting()
            if let url { try? FileManager.default.removeItem(at: url) }
            reset()
            completion(nil, RecordingError.noFrames)
            return
        }

        writer.finishWriting { [weak self] in
            let failure: Error? = writer.status == .completed
                ? nil
                : (writer.error ?? RecordingError.failed("yozuv tugallanmadi"))

            self?.queue.async {
                self?.reset()
                if let failure {
                    if let url { try? FileManager.default.removeItem(at: url) }
                    completion(nil, failure)
                } else {
                    completion(url, nil)
                }
            }
        }
    }

    private func reset() {
        writer = nil
        videoInput = nil
        audioInput = nil
        adaptor = nil
        outputURL = nil
        didStartSession = false
    }
}
