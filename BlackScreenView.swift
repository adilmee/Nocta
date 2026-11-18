import SwiftUI

/// Qora ekran. Hech narsa ko'rinmaydi, lekin kamera shu yerda ishlaydi.
///
/// Boshqarish:
///   - bosish            -> rasm olish (Rasm rejimi) / yozishni to'xtatish-boshlash (Video rejimi)
///   - yuqoriga/pastga surish -> kamerani almashtirish (yozish paytida ham ishlaydi)
///   - o'ngga surish      -> bosh ekranga qaytish (yozish to'xtatiladi va saqlanadi)
struct BlackScreenView: View {

    @ObservedObject var camera: CameraManager
    let onExit: () -> Void

    private let exitThreshold: CGFloat = 80
    private let switchThreshold: CGFloat = 70

    var body: some View {
        // Butun ekranni egallaydigan qora sath. contentShape -- bosish butun maydonda ishlashi uchun.
        Color.black
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                handleTap()
            }
            .gesture(dragGesture)
            // Ekran ko'rinmasa ham VoiceOver foydalanuvchisi holatni bilishi uchun.
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Bosish: suratga olish yoki yozishni to'xtatish. Yuqoriga surish: kamerani almashtirish. O'ngga surish: qaytish.")
    }

    private var accessibilityLabel: String {
        let camera = self.camera.source.title
        switch self.camera.mode {
        case .video:
            return self.camera.isRecording
                ? "Yozilmoqda, \(self.camera.formattedDuration(self.camera.recordingDuration)), \(camera) kamera"
                : "Qora ekran, yozish to'xtatilgan, \(camera) kamera"
        case .photo:
            return "Qora ekran, rasm rejimi, \(camera) kamera"
        }
    }

    // MARK: - Actions

    private func handleTap() {
        switch camera.mode {
        case .photo:
            camera.capturePhoto()
            Haptics.capture()

        case .video:
            if camera.isRecording {
                camera.stopRecording()
                Haptics.stop()
            } else {
                camera.startRecording()
                Haptics.start()
            }
        }
    }

    private func switchCamera() {
        camera.cycleSource()
        // Almashtirish sessiya navbatida bajariladi, titrash esa darhol beriladi:
        // foydalanuvchi qora ekranda qaysi kamera yoqilganini shundan biladi.
        Haptics.pulses(camera.source.hapticPulses)
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 25)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height

                if abs(dy) > abs(dx) {
                    // Vertikal surish -> kamerani almashtirish
                    guard abs(dy) > switchThreshold else { return }
                    switchCamera()
                } else {
                    // O'ngga surish -> bosh ekranga qaytish
                    guard dx > exitThreshold, abs(dy) < 140 else { return }
                    onExit()
                }
            }
    }
}
