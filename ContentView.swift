import SwiftUI

/// Uchta ekranni ushlab turadigan konteyner:
///
///     [ Albom ]  <--  chapga surish --  [ Bosh ekran ]  -- o'ngga surish -->  [ Qora ekran ]
///
/// Qora ekranda yozish/rasm olish ketadi, olingan fayllar albomga tushadi.
struct ContentView: View {

    enum Screen {
        case album
        case home
        case black
    }

    @StateObject private var store: MediaStore
    @StateObject private var camera: CameraManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var screen: Screen = .home
    /// Qora ekranga o'tishdan oldingi yorug'lik. Qaytishda shu qiymat tiklanadi.
    @State private var savedBrightness: CGFloat = UIScreen.main.brightness
    /// URL orqali ochildi, lekin kamera ruxsati hali yo'q edi -> ruxsat berilgach yozamiz.
    @State private var pendingAutoRecord = false

    private let transitionDuration: TimeInterval = 0.3

    init() {
        let store = MediaStore()
        _store = StateObject(wrappedValue: store)
        _camera = StateObject(wrappedValue: CameraManager(store: store))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch screen {
            case .black:
                // Chapga surilganda o'ng chetdan kirib keladi.
                BlackScreenView(camera: camera, onExit: exitBlackScreen)
                    .transition(.move(edge: .trailing))

            case .home:
                HomeView(
                    camera: camera,
                    store: store,
                    onEnterBlackScreen: enterBlackScreen,
                    onOpenAlbum: openAlbum
                )
                .transition(.opacity)

            case .album:
                // O'ngga surilganda chap chetdan kirib keladi.
                AlbumView(store: store, onBack: closeAlbum)
                    .transition(.move(edge: .leading))
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(screen == .black)
        .persistentSystemOverlays(screen == .black ? .hidden : .automatic)
        .onAppear {
            camera.requestAccess()
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
        .onChange(of: camera.isAuthorized) { _, authorized in
            // URL orqali ochilib, ruxsat endigina berilgan bo'lsa, yozuvni boshlaymiz.
            if authorized, pendingAutoRecord {
                startAutoRecord()
            }
        }
        .onOpenURL { url in
            // blackc://record -> ilova ochilishi bilan to'g'ridan-to'g'ri qora ekran + yozuv.
            // iPhone'da Action tugmasi yoki "Orqaga teginish" (Back Tap) bilan Shortcuts orqali
            // ishga tushiriladi.
            guard url.scheme == "blackc" else { return }
            if camera.isAuthorized {
                startAutoRecord()
            } else {
                pendingAutoRecord = true
            }
        }
    }

    /// URL orqali kelgan "darhol yozish" buyrug'ini bajaradi.
    private func startAutoRecord() {
        pendingAutoRecord = false
        if screen == .album { closeAlbum() }
        if screen == .home {
            enterBlackScreen()
        }
    }

    // MARK: - Navigation

    private func enterBlackScreen() {
        guard camera.isAuthorized, screen == .home else { return }

        savedBrightness = UIScreen.main.brightness

        withAnimation(.easeInOut(duration: transitionDuration)) {
            screen = .black
        }

        // Ekran o'chib qolmasligi uchun avtomatik qulflashni to'xtatamiz.
        UIApplication.shared.isIdleTimerDisabled = true

        // Animatsiya tugagach qoraytiramiz, keyin video rejimda yozishni boshlaymiz.
        DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration) {
            // Foydalanuvchi shu oraliqda qaytib ketgan bo'lsa, hech narsa qilmaymiz.
            guard self.screen == .black else { return }
            UIScreen.main.brightness = 0.0

            if self.camera.mode == .video {
                self.camera.startRecording()
            }
            Haptics.enter()
        }
    }

    private func exitBlackScreen() {
        guard screen == .black else { return }

        if camera.isRecording {
            camera.stopRecording()
        }

        restoreScreen()

        withAnimation(.easeInOut(duration: transitionDuration)) {
            screen = .home
        }
        Haptics.exit()
    }

    private func openAlbum() {
        guard screen == .home else { return }
        // Albomda kamera kerak emas -- batareyani tejaymiz.
        camera.stopSession()
        withAnimation(.easeInOut(duration: transitionDuration)) {
            screen = .album
        }
        Haptics.exit()
    }

    private func closeAlbum() {
        guard screen == .album else { return }
        camera.startSession()
        withAnimation(.easeInOut(duration: transitionDuration)) {
            screen = .home
        }
        Haptics.exit()
    }

    private func restoreScreen() {
        UIScreen.main.brightness = savedBrightness
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Scene phase

    /// Muhim: ilova fonga o'tsa yoki yopilsa, yorug'likni albatta tiklaymiz.
    /// Aks holda foydalanuvchining telefoni qop-qorong'i holatda qolib ketadi.
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // Fonda ovoz yozilayotgan bo'lsa, to'xtatib albomga qo'shamiz.
            camera.stopBackgroundAudio()

            if screen != .album {
                camera.startSession()
            }
            if screen == .black {
                UIScreen.main.brightness = 0.0
                UIApplication.shared.isIdleTimerDisabled = true

                // Fonga o'tganda video to'xtagan edi. Qora ekranga qaytdik -- davom etamiz,
                // aks holda foydalanuvchi ekranga qarab yozish to'xtaganini bilmay qoladi.
                if camera.mode == .video, !camera.isRecording {
                    camera.startRecording()
                    Haptics.start()
                }
            }

        case .inactive:
            // Bildirishnoma, Boshqaruv markazi va ilovalar ro'yxati ham shu holatni beradi.
            // Yozishni to'xtatmaymiz -- aks holda har bir bildirishnoma yozuvni uzib qo'yardi.
            // Lekin ilova shu yerdan yopilishi mumkin, shuning uchun yorug'likni tiklaymiz.
            UIScreen.main.brightness = savedBrightness

        case .background:
            // iOS kamerani fonda ishlashga qo'ymaydi. Video yozilayotgan bo'lsa, uni yopib
            // faylni saqlaymiz, so'ng mikrofon orqali ovozni yozishda davom etamiz.
            let wasRecordingVideo = camera.isRecording
            finishRecordingInBackground()
            restoreScreen()
            camera.stopSession()

            // Qora ekranda video yozilayotgan edi -> fonda ovozni davom ettiramiz.
            // Telefon qulflansa yoki boshqa ilova ochilsa ham ovoz yozilaveradi.
            if wasRecordingVideo, screen == .black {
                camera.startBackgroundAudio()
            }

        @unknown default:
            restoreScreen()
        }
    }

    /// Fonga o'tishda yozuvni tugatish uchun tizimdan vaqt so'raydi.
    private func finishRecordingInBackground() {
        guard camera.isRecording else { return }

        var taskID = UIBackgroundTaskIdentifier.invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "NoctaFinishRecording") {
            guard taskID != .invalid else { return }
            UIApplication.shared.endBackgroundTask(taskID)
            taskID = .invalid
        }

        camera.stopRecording {
            guard taskID != .invalid else { return }
            UIApplication.shared.endBackgroundTask(taskID)
            taskID = .invalid
        }
    }
}

#Preview {
    ContentView()
}
