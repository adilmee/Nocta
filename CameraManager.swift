import AVFoundation
import CoreMedia
import UIKit

// MARK: - Capture Mode

enum CaptureMode: String, CaseIterable, Identifiable {
    case video
    case photo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: return "Video"
        case .photo: return "Rasm"
        }
    }

    var icon: String {
        switch self {
        case .video: return "video.fill"
        case .photo: return "camera.fill"
        }
    }

    var hint: String {
        switch self {
        case .video:
            return "Qora ekranga o'tilganda yozish o'zi boshlanadi.\nTo'xtatish uchun ekranga bosing."
        case .photo:
            return "Qora ekranda istalgan joyga bossangiz\nrasm olinadi. Ovozsiz, cheksiz marta."
        }
    }
}

// MARK: - Camera Source

enum CameraSource: String, CaseIterable, Identifiable {
    case back
    case front
    case dual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .back: return "Orqa"
        case .front: return "Old"
        case .dual: return "Ikkisi"
        }
    }

    var icon: String {
        switch self {
        case .back: return "camera.fill"
        case .front: return "person.crop.circle.fill"
        case .dual: return "rectangle.on.rectangle"
        }
    }

    /// Qora ekranda almashtirganda shuncha marta titraydi — qaysi kamera yoqilganini
    /// ekranga qaramay bilish uchun.
    var hapticPulses: Int {
        switch self {
        case .back: return 1
        case .front: return 2
        case .dual: return 3
        }
    }
}

// MARK: - Camera Manager

final class CameraManager: NSObject, ObservableObject {

    // MARK: Published state
    @Published private(set) var mode: CaptureMode = .video
    @Published private(set) var source: CameraSource = .back
    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var isAuthorized = false
    @Published private(set) var isSessionRunning = false
    @Published private(set) var isMultiCamAvailable = false
    @Published private(set) var isBackgroundAudioRecording = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    /// Qaysi manbalarni tanlash mumkin: ko'p kamerali bo'lmagan qurilmada "Ikkisi" yo'q.
    var availableSources: [CameraSource] {
        CameraSource.allCases.filter { $0 != .dual || isMultiCamAvailable }
    }

    // MARK: Dependencies
    private let store: MediaStore

    // MARK: Session
    private var session: AVCaptureSession?
    private let sessionQueue = DispatchQueue(label: "com.nocta.session")
    /// Video va audio kadrlar shu bitta navbatda keladi — shuning uchun
    /// quyidagi `data*` maydonlari uchun qulf kerak emas.
    private let dataQueue = DispatchQueue(label: "com.nocta.data")

    /// Ko'p kamerali rejimda: orqa kamera. Oddiy rejimda: joriy kamera.
    private let primaryOutput = AVCaptureVideoDataOutput()
    /// Faqat ko'p kamerali rejimda ishlatiladi: old kamera.
    private let secondaryOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    private var primaryInput: AVCaptureDeviceInput?
    private var secondaryInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?

    private var primaryConnection: AVCaptureConnection?
    private var secondaryConnection: AVCaptureConnection?
    private var audioConnection: AVCaptureConnection?

    private var usesMultiCam = false
    private var isConfigured = false

    // MARK: Recording
    private var engine: RecordingEngine?
    private var compositor: FrameCompositor?
    private let backgroundAudio = BackgroundAudioRecorder()
    private var outputSize = CGSize(width: 1080, height: 1920)

    private var durationTimer: Timer?
    private var messageClearWork: DispatchWorkItem?

    // MARK: dataQueue'ga tegishli holat
    private var activeSource: CameraSource = .back
    private var latestFrontBuffer: CVPixelBuffer?
    private var wantsPhoto = false

    // MARK: - Lifecycle

    init(store: MediaStore) {
        self.store = store
        super.init()
        isMultiCamAvailable = AVCaptureMultiCamSession.isMultiCamSupported
        addObservers()
    }

    deinit {
        durationTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Permissions

    func requestAccess() {
        requestAccess(for: .video) { [weak self] videoGranted in
            guard let self else { return }

            guard videoGranted else {
                self.publish(error: "Kamera ruxsati yo'q. Sozlamalar -> blackC -> Kamera'ni yoqing.")
                return
            }

            // Mikrofon majburiy emas: ruxsat bo'lmasa video ovozsiz yoziladi.
            self.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    self.isAuthorized = true
                    self.configureIfNeeded()
                }
            }
        }
    }

    private func requestAccess(for type: AVMediaType, completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: type) { completion($0) }
        default:
            completion(false)
        }
    }

    // MARK: - Configuration

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        let initialMode = mode

        sessionQueue.async { [weak self] in
            guard let self else { return }

            if AVCaptureMultiCamSession.isMultiCamSupported {
                self.configureMultiCam(mode: initialMode)
            } else {
                self.configureSingleCam(position: .back, mode: initialMode)
            }

            self.engine = RecordingEngine(queue: self.dataQueue)
            self.compositor = FrameCompositor(outputSize: self.outputSize)

            self.startSessionOnQueue()
        }
    }

    // MARK: Multi-camera

    /// Ikkala kamera ham doim sessiyada turadi, almashtirish esa ulanishni yoqib-o'chirish
    /// bilan amalga oshadi. Shuning uchun almashtirish bir zumda bo'ladi va yozish paytida
    /// ham ishlaydi — sessiyani qayta sozlash kerak emas.
    private func configureMultiCam(mode: CaptureMode) {
        let session = AVCaptureMultiCamSession()
        self.session = session
        usesMultiCam = true

        guard let backDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        else {
            publish(error: "Old yoki orqa kamera topilmadi")
            configureSingleCam(position: .back, mode: mode)
            return
        }

        session.beginConfiguration()

        guard let back = attach(device: backDevice, to: primaryOutput, mirrored: false, session: session),
              let front = attach(device: frontDevice, to: secondaryOutput, mirrored: true, session: session)
        else {
            session.commitConfiguration()
            publish(error: "Ikkita kamerani birga ulab bo'lmadi, bitta kamera rejimiga o'tildi")
            tearDownSession()
            configureSingleCam(position: .back, mode: mode)
            return
        }

        primaryInput = back.input
        primaryConnection = back.connection
        secondaryInput = front.input
        secondaryConnection = front.connection

        if mode == .video {
            attachAudio(to: session)
        }

        session.commitConfiguration()

        // Formatni tanlash: eng yuqori sifatdan boshlab, apparat imkoniyatiga sig'adiganini olamiz.
        chooseMultiCamFormats(session: session, back: backDevice, front: frontDevice)

        outputSize = portraitSize(for: backDevice.activeFormat)
        applySourceOnQueue(source)
    }

    private func attach(
        device: AVCaptureDevice,
        to output: AVCaptureVideoDataOutput,
        mirrored: Bool,
        session: AVCaptureMultiCamSession
    ) -> (input: AVCaptureDeviceInput, connection: AVCaptureConnection)? {

        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return nil }
        session.addInputWithNoConnections(input)

        configure(output)
        guard session.canAddOutput(output) else { return nil }
        session.addOutputWithNoConnections(output)

        guard let port = input.ports(
            for: .video,
            sourceDeviceType: device.deviceType,
            sourceDevicePosition: device.position
        ).first else { return nil }

        let connection = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(connection) else { return nil }
        session.addConnection(connection)

        applyPortrait(connection, mirrored: mirrored)
        return (input, connection)
    }

    /// Ikkala kamera birga ishlaganda apparat yuki (`hardwareCost`) 1.0 dan oshmasligi kerak,
    /// aks holda sessiya ishga tushmaydi. Shuning uchun kattadan kichikka qarab sinab ko'ramiz.
    private func chooseMultiCamFormats(
        session: AVCaptureMultiCamSession,
        back: AVCaptureDevice,
        front: AVCaptureDevice
    ) {
        for maxWidth in [Int32(1920), Int32(1280), Int32(960)] {
            session.beginConfiguration()
            applyMultiCamFormat(to: back, maxWidth: maxWidth)
            applyMultiCamFormat(to: front, maxWidth: maxWidth)
            session.commitConfiguration()

            if session.hardwareCost <= 1.0 && session.systemPressureCost <= 1.0 {
                return
            }
        }
    }

    private func applyMultiCamFormat(to device: AVCaptureDevice, maxWidth: Int32) {
        let candidates = device.formats.filter { format in
            guard format.isMultiCamSupported else { return false }
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width <= maxWidth else { return false }
            return format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
        }

        guard let best = candidates.max(by: { lhs, rhs in
            let l = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let r = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            return Int(l.width) * Int(l.height) < Int(r.width) * Int(r.height)
        }) else { return }

        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            device.unlockForConfiguration()
        } catch {
            // Format o'rnatilmasa, tizim tanlagani bilan davom etamiz.
        }
    }

    // MARK: Single camera

    private func configureSingleCam(position: AVCaptureDevice.Position, mode: CaptureMode) {
        let session = AVCaptureSession()
        self.session = session
        usesMultiCam = false

        session.beginConfiguration()

        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else {
            session.sessionPreset = .high
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            session.commitConfiguration()
            publish(error: "Kamerani ulab bo'lmadi")
            return
        }

        session.addInput(input)
        primaryInput = input

        configure(primaryOutput)
        if session.canAddOutput(primaryOutput) {
            session.addOutput(primaryOutput)
        }

        if mode == .video {
            attachAudio(to: session)
        }

        session.commitConfiguration()

        if let connection = primaryOutput.connection(with: .video) {
            applyPortrait(connection, mirrored: position == .front)
            primaryConnection = connection
        }

        outputSize = portraitSize(for: device.activeFormat)
    }

    private func configure(_ output: AVCaptureVideoDataOutput) {
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: dataQueue)
    }

    // MARK: Audio

    private func attachAudio(to session: AVCaptureSession) {
        guard audioDeviceInput == nil,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }

        audioOutput.setSampleBufferDelegate(self, queue: dataQueue)

        if let multi = session as? AVCaptureMultiCamSession {
            guard multi.canAddInput(input), multi.canAddOutput(audioOutput) else { return }
            multi.addInputWithNoConnections(input)
            multi.addOutputWithNoConnections(audioOutput)

            guard let port = input.ports(
                for: .audio,
                sourceDeviceType: device.deviceType,
                sourceDevicePosition: device.position
            ).first else { return }

            let connection = AVCaptureConnection(inputPorts: [port], output: audioOutput)
            guard multi.canAddConnection(connection) else { return }
            multi.addConnection(connection)
            audioConnection = connection
        } else {
            guard session.canAddInput(input), session.canAddOutput(audioOutput) else { return }
            session.addInput(input)
            session.addOutput(audioOutput)
            audioConnection = audioOutput.connection(with: .audio)
        }

        audioDeviceInput = input
    }

    /// Rasm rejimida mikrofonni uzamiz — iOS'ning to'q sariq mikrofon indikatori yonmasin.
    private func detachAudio(from session: AVCaptureSession) {
        if let audioConnection, session.connections.contains(audioConnection) {
            session.removeConnection(audioConnection)
        }
        self.audioConnection = nil

        if session.outputs.contains(audioOutput) {
            session.removeOutput(audioOutput)
        }
        if let audioDeviceInput {
            session.removeInput(audioDeviceInput)
        }
        audioDeviceInput = nil
    }

    // MARK: Helpers

    private func applyPortrait(_ connection: AVCaptureConnection, mirrored: Bool) {
        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }

    private func portraitSize(for format: AVCaptureDevice.Format) -> CGSize {
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let short = CGFloat(min(dims.width, dims.height))
        let long = CGFloat(max(dims.width, dims.height))
        guard short > 0, long > 0 else { return CGSize(width: 1080, height: 1920) }
        return CGSize(width: short, height: long)
    }

    private func tearDownSession() {
        guard let session else { return }
        session.beginConfiguration()
        for connection in session.connections { session.removeConnection(connection) }
        for output in session.outputs { session.removeOutput(output) }
        for input in session.inputs { session.removeInput(input) }
        session.commitConfiguration()

        primaryInput = nil
        secondaryInput = nil
        audioDeviceInput = nil
        primaryConnection = nil
        secondaryConnection = nil
        audioConnection = nil
        self.session = nil
    }

    // MARK: - Mode

    func select(mode newMode: CaptureMode) {
        guard newMode != mode, !isRecording else { return }
        mode = newMode

        sessionQueue.async { [weak self] in
            guard let self, let session = self.session else { return }
            session.beginConfiguration()
            switch newMode {
            case .photo: self.detachAudio(from: session)
            case .video: self.attachAudio(to: session)
            }
            session.commitConfiguration()
        }
    }

    // MARK: - Camera source

    func select(source newSource: CameraSource) {
        guard newSource != source else { return }

        guard newSource != .dual || isMultiCamAvailable else {
            publish(error: "Bu qurilma ikkala kamerani bir vaqtda qo'llab-quvvatlamaydi")
            return
        }

        // Oddiy (bitta kamerali) qurilmada "Ikkisi" yo'q, qolgan ikkitasi esa
        // sessiya kirishini almashtirishni talab qiladi.
        source = newSource
        dataQueue.async { [weak self] in
            self?.activeSource = newSource
            if newSource != .dual { self?.latestFrontBuffer = nil }
        }
        sessionQueue.async { [weak self] in
            self?.applySourceOnQueue(newSource)
        }
    }

    /// Qora ekranda ketma-ket almashtirish uchun.
    func cycleSource() {
        let sources = availableSources
        guard let index = sources.firstIndex(of: source) else { return }
        select(source: sources[(index + 1) % sources.count])
    }

    private func applySourceOnQueue(_ newSource: CameraSource) {
        if usesMultiCam {
            // Bir zumda almashtirish: faqat ulanishlarni yoqamiz/o'chiramiz.
            primaryConnection?.isEnabled = (newSource == .back || newSource == .dual)
            secondaryConnection?.isEnabled = (newSource == .front || newSource == .dual)
        } else {
            swapSingleCamera(to: newSource == .front ? .front : .back)
        }
    }

    /// Ko'p kamerali bo'lmagan qurilmada kamerani almashtirish — kirishni almashtirish kerak.
    /// Yozish davom etaveradi (AssetWriter sessiyadan mustaqil), lekin videoda qisqa uzilish bo'ladi.
    private func swapSingleCamera(to position: AVCaptureDevice.Position) {
        guard let session,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let newInput = try? AVCaptureDeviceInput(device: device)
        else { return }

        let oldInput = primaryInput

        session.beginConfiguration()
        if let oldInput { session.removeInput(oldInput) }

        if session.canAddInput(newInput) {
            session.addInput(newInput)
            primaryInput = newInput
        } else if let oldInput, session.canAddInput(oldInput) {
            session.addInput(oldInput)   // qaytarib qo'yamiz
        }
        session.commitConfiguration()

        if let connection = primaryOutput.connection(with: .video) {
            applyPortrait(connection, mirrored: position == .front)
            primaryConnection = connection
        }
    }

    // MARK: - Session start / stop

    func startSession() {
        sessionQueue.async { [weak self] in
            self?.startSessionOnQueue()
        }
    }

    private func startSessionOnQueue() {
        guard let session, !session.isRunning else { return }
        session.startRunning()
        let running = session.isRunning
        DispatchQueue.main.async { self.isSessionRunning = running }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, let session = self.session, session.isRunning else { return }
            session.stopRunning()
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard mode == .video, !isRecording else { return }

        dataQueue.async { [weak self] in
            guard let self, let engine = self.engine, !engine.isRecording else { return }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("NoctaTmp_\(UUID().uuidString).mov")

            let audioSettings = self.audioDeviceInput == nil
                ? nil
                : self.audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) as? [String: Any]

            do {
                try engine.start(url: url, size: self.outputSize, audioSettings: audioSettings)
                DispatchQueue.main.async {
                    self.isRecording = true
                    self.statusMessage = nil
                    self.errorMessage = nil
                    self.startDurationTimer()
                }
            } catch {
                self.publish(error: "Yozishni boshlab bo'lmadi: \(error.localizedDescription)")
            }
        }
    }

    /// `completion` fayl albomga saqlanib bo'lgandan keyin asosiy oqimda chaqiriladi.
    /// Ilova fonga o'tayotganda shu orqali tizimdan olingan muhlat tugatiladi.
    func stopRecording(completion: (() -> Void)? = nil) {
        dataQueue.async { [weak self] in
            guard let self, let engine = self.engine, engine.isRecording else {
                DispatchQueue.main.async { completion?() }
                return
            }

            engine.finish { [weak self] url, error in
                guard let self else {
                    DispatchQueue.main.async { completion?() }
                    return
                }

                DispatchQueue.main.async {
                    self.isRecording = false
                    self.stopDurationTimer()
                }

                if let url {
                    self.saveVideo(at: url) {
                        DispatchQueue.main.async { completion?() }
                    }
                } else {
                    self.publish(error: "Video saqlanmadi: \(error?.localizedDescription ?? "noma'lum xato")")
                    DispatchQueue.main.async { completion?() }
                }
            }
        }
    }

    // MARK: - Photo

    /// Keyingi kadr rasm sifatida saqlanadi. `AVCapturePhotoOutput` ishlatilmagani uchun
    /// zatvor ovozi chiqmaydi — qora ekran uchun shu muhim.
    func capturePhoto() {
        guard mode == .photo, isAuthorized else { return }
        dataQueue.async { [weak self] in
            self?.wantsPhoto = true
        }
    }

    // MARK: - Duration timer

    private func startDurationTimer() {
        durationTimer?.invalidate()
        recordingDuration = 0

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.recordingDuration += 1
        }
        RunLoop.main.add(timer, forMode: .common)
        durationTimer = timer
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    func formattedDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Saving

    private func saveVideo(at url: URL, completion: (() -> Void)? = nil) {
        store.addVideo(movedFrom: url) { [weak self] error in
            if let error {
                self?.publish(error: "Video albomga qo'shilmadi: \(error.localizedDescription)")
            } else {
                self?.publish(status: "Video albomga qo'shildi")
            }
            completion?()
        }
    }

    private func savePhoto(data: Data) {
        store.addPhoto(data: data) { [weak self] error in
            if let error {
                self?.publish(error: "Rasm albomga qo'shilmadi: \(error.localizedDescription)")
            } else {
                self?.publish(status: "Rasm albomga qo'shildi")
            }
        }
    }

    // MARK: - Background audio

    /// Ilova fonga o'tganda chaqiriladi. iOS fonda kameraga ruxsat bermaydi,
    /// shuning uchun video to'xtaydi, ovoz esa yozilishda davom etadi.
    func startBackgroundAudio() {
        guard !backgroundAudio.isRecording else { return }
        do {
            try backgroundAudio.start()
            DispatchQueue.main.async { self.isBackgroundAudioRecording = true }
        } catch {
            publish(error: "Fonda ovoz yozilmadi: \(error.localizedDescription)")
        }
    }

    /// Ilova qaytib ochilganda chaqiriladi: ovoz faylini albomga qo'shadi.
    func stopBackgroundAudio() {
        guard backgroundAudio.isRecording else { return }
        let url = backgroundAudio.stop()
        DispatchQueue.main.async { self.isBackgroundAudioRecording = false }

        guard let url else { return }
        store.addAudio(movedFrom: url) { [weak self] error in
            if error == nil {
                self?.publish(status: "Fondagi ovoz albomga qo'shildi")
            }
        }
    }

    // MARK: - Messages

    private func publish(status message: String) {
        DispatchQueue.main.async {
            self.errorMessage = nil
            self.statusMessage = message
            self.scheduleMessageClear()
        }
    }

    private func publish(error message: String) {
        DispatchQueue.main.async {
            self.statusMessage = nil
            self.errorMessage = message
            self.scheduleMessageClear(after: 6)
        }
    }

    private func scheduleMessageClear(after seconds: TimeInterval = 3) {
        messageClearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.statusMessage = nil
            self?.errorMessage = nil
        }
        messageClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - Session observers

    private func addObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted,
            object: nil
        )
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        publish(error: "Kamera uzildi, qayta ulanmoqda...")
        startSession()
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
              let reason = AVCaptureSession.InterruptionReason(rawValue: raw)
        else { return }

        switch reason {
        case .videoDeviceNotAvailableInBackground:
            // Ilova fonga o'tdi -- bu kutilgan holat, foydalanuvchiga xato ko'rsatmaymiz.
            break
        case .videoDeviceInUseByAnotherClient:
            publish(error: "Kamerani boshqa ilova band qilib turibdi")
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            publish(error: "Split View rejimida kamera ishlamaydi")
        case .videoDeviceNotAvailableDueToSystemPressure:
            publish(error: "Qurilma qizib ketdi, kamera vaqtincha to'xtatildi")
        case .audioDeviceInUseByAnotherClient:
            publish(error: "Mikrofonni boshqa ilova band qilib turibdi")
        @unknown default:
            break
        }
    }
}

// MARK: - Sample buffer delegates

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate,
                         AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Hammasi bitta `dataQueue`da keladi, shuning uchun bu yerda qulf kerak emas.

        if output === audioOutput {
            engine?.appendAudio(sampleBuffer)
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if usesMultiCam, output === secondaryOutput {
            switch activeSource {
            case .front:
                process(main: pixelBuffer, inset: nil, at: time)
            case .dual:
                // Old kamera kadri saqlanadi va orqa kadr kelganda ustiga qo'yiladi.
                latestFrontBuffer = pixelBuffer
            case .back:
                break
            }
            return
        }

        // primaryOutput
        switch activeSource {
        case .dual where usesMultiCam:
            process(main: pixelBuffer, inset: latestFrontBuffer, at: time)
        case .front where usesMultiCam:
            break   // old kamera alohida chiqishdan keladi
        default:
            process(main: pixelBuffer, inset: nil, at: time)
        }
    }

    private func process(main: CVPixelBuffer, inset: CVPixelBuffer?, at time: CMTime) {
        let recording = engine?.isRecording ?? false

        // Yozilmayotgan va rasm so'ralmagan paytda hech narsa hisoblamaymiz —
        // batareya va qizish uchun muhim.
        guard recording || wantsPhoto else { return }

        guard let composed = compositor?.compose(main: main, inset: inset) else { return }

        if recording {
            engine?.appendVideo(composed, at: time)
        }

        if wantsPhoto {
            wantsPhoto = false
            if let data = compositor?.jpegData(from: composed) {
                savePhoto(data: data)
            } else {
                publish(error: "Rasmni tayyorlab bo'lmadi")
            }
        }
    }
}
