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
                BlackScreenView(camera: camera, onExit: exitBlackScreen)
                    .transition(.move(edge: .leading))

            case .home:
                HomeView(
                    camera: camera,
                    store: store,
                    onEnterBlackScreen: enterBlackScreen,
                    onOpenAlbum: openAlbum
                )
                .transition(.opacity)

            case .album:
                AlbumView(store: store, onBack: closeAlbum)
                    .transition(.move(edge: .trailing))
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
            if screen != .album {
                camera.startSession()
            }
            if screen == .black {
                UIScreen.main.brightness = 0.0
                UIApplication.shared.isIdleTimerDisabled = true
            }

        case .inactive, .background:
            // iOS kamerani fonda ishlashga qo'ymaydi, shuning uchun yozishni yopib,
            // videoni saqlab qolamiz.
            if camera.isRecording {
                camera.stopRecording()
            }
            restoreScreen()
            if phase == .background {
                camera.stopSession()
            }

        @unknown default:
            restoreScreen()
        }
    }
}

#Preview {
    ContentView()
}
