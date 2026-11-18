import SwiftUI

/// Bosh ekran: rejim tanlanadi.
///   o'ngga surish -> qora ekran (yozish shu yerda ketadi)
///   chapga surish -> albom (olingan fayllar)
struct HomeView: View {

    @ObservedObject var camera: CameraManager
    @ObservedObject var store: MediaStore

    let onEnterBlackScreen: () -> Void
    let onOpenAlbum: () -> Void

    /// Surish paytidagi real vaqt siljishi -- harakat sezilib turishi uchun.
    @State private var dragOffset: CGFloat = 0

    private let swipeThreshold: CGFloat = 90

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)

                header
                    .padding(.top, 24)

                Spacer()

                modePicker
                    .padding(.horizontal, 24)

                sourcePicker
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                Text(hintText)
                    .font(.footnote)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
                    .padding(.horizontal, 32)
                    .animation(.easeInOut(duration: 0.2), value: hintText)

                Spacer()

                messages
                    .frame(height: 44)

                swipeArea
                    .padding(.bottom, 32)
            }
            .offset(x: dragOffset * 0.3)
        }
        .contentShape(Rectangle())
        .gesture(swipeGesture)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Spacer()

            // Albom o'ngga surish bilan ochiladi, shuning uchun tugma ham o'ngda
            // va strelka o'ngga qaraydi.
            Button {
                onOpenAlbum()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "photo.stack")
                        .font(.body)
                    Text("Albom")
                        .font(.subheadline.weight(.medium))
                    if !store.items.isEmpty {
                        Text("\(store.items.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white, in: Capsule())
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.vertical, 9)
                .padding(.horizontal, 14)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            // Ilova logosi (ikonkaga mos: oq halqa, ichida teshik)
            LogoMark()
                .frame(width: 76, height: 48)

            Text("blackC")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                Circle()
                    .fill(camera.isSessionRunning ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
        }
    }

    private var statusText: String {
        if !camera.isAuthorized { return "Ruxsat kutilmoqda" }
        return camera.isSessionRunning ? "Kamera tayyor" : "Kamera ishga tushmoqda"
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        HStack(spacing: 14) {
            ForEach(CaptureMode.allCases) { mode in
                modeCard(mode)
            }
        }
    }

    private func modeCard(_ mode: CaptureMode) -> some View {
        let isSelected = camera.mode == mode

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                camera.select(mode: mode)
            }
            Haptics.select()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.system(size: 30))
                Text(mode.title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .foregroundStyle(isSelected ? .white : .gray)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.1),
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!camera.isAuthorized || camera.isRecording)
    }

    // MARK: - Camera source picker

    private var sourcePicker: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(camera.availableSources) { source in
                    sourceChip(source)
                }
            }

            if !camera.isMultiCamAvailable {
                Text("Bu qurilma ikkala kamerani bir vaqtda qo'llab-quvvatlamaydi")
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.7))
            }
        }
    }

    private func sourceChip(_ source: CameraSource) -> some View {
        let isSelected = camera.source == source

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                camera.select(source: source)
            }
            Haptics.select()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: source.icon)
                    .font(.system(size: 13))
                Text(source.title)
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(isSelected ? .black : .gray)
            .background(
                Capsule().fill(isSelected ? Color.white : Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .disabled(!camera.isAuthorized)
    }

    private var hintText: String {
        if camera.source == .dual {
            return "Orqa kamera to'liq ekran, old kamera\no'ng yuqori burchakda kichik oynachada"
        }
        return camera.mode.hint
    }

    // MARK: - Messages

    private var messages: some View {
        VStack(spacing: 6) {
            if let error = camera.errorMessage {
                messageRow(icon: "exclamationmark.triangle.fill", text: error, color: .orange)
            } else if let status = camera.statusMessage {
                messageRow(icon: "checkmark.circle.fill", text: status, color: .green)
            }
        }
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.2), value: camera.errorMessage)
        .animation(.easeInOut(duration: 0.2), value: camera.statusMessage)
    }

    private func messageRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
                .multilineTextAlignment(.leading)
        }
        .font(.footnote)
        .foregroundStyle(color)
    }

    // MARK: - Swipe area

    private var swipeArea: some View {
        VStack(spacing: 14) {
            // Surish uchun ko'rsatma. Tugma sifatida ham ishlaydi -- qo'l bilan surish
            // qiyin bo'lgan holatda (yoki VoiceOver bilan) bosib ham o'tiladi.
            Button {
                onEnterBlackScreen()
            } label: {
                HStack(spacing: 12) {
                    // Qora ekran chapga surish bilan ochiladi -- strelkalar chapga qaraydi.
                    HStack(spacing: -4) {
                        ForEach(Array((0..<3).reversed()), id: \.self) { index in
                            Image(systemName: "chevron.left")
                                .opacity(chevronOpacity(index))
                        }
                    }
                    .font(.headline)

                    Text("Qora ekran")
                        .font(.headline)
                }
                .foregroundStyle(.white.opacity(camera.isAuthorized ? 0.9 : 0.3))
                .padding(.vertical, 16)
                .padding(.horizontal, 28)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!camera.isAuthorized)

            VStack(spacing: 4) {
                Text("chapga suring — qora ekran   ·   o'ngga — albom")
                Text("qora ekranda yuqoriga surish — kamerani almashtiradi")
            }
            .font(.caption2)
            .foregroundStyle(.gray.opacity(0.8))
            .multilineTextAlignment(.center)
        }
    }

    private func chevronOpacity(_ index: Int) -> Double {
        // Qora ekran chapga surish bilan ochiladi, ya'ni dragOffset manfiy bo'ladi.
        let progress = min(1, max(0, -dragOffset / swipeThreshold))
        let step = Double(index + 1) / 3.0
        return progress >= step ? 1.0 : 0.35
    }

    // MARK: - Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard camera.isAuthorized, abs(value.translation.height) < 140 else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let dx = value.translation.width
                let isHorizontal = abs(value.translation.height) < 140

                withAnimation(.easeOut(duration: 0.2)) {
                    dragOffset = 0
                }

                guard camera.isAuthorized, isHorizontal else { return }

                // Chapga surish -> qora ekran (yozish), o'ngga surish -> albom.
                if dx < -swipeThreshold {
                    onEnterBlackScreen()
                } else if dx > swipeThreshold {
                    onOpenAlbum()
                }
            }
    }
}

// MARK: - Logo

/// Ilova ikonkasiga mos belgi: oq "stadion" shakli, ichida qora teshik.
/// SwiftUI bilan chiziladi, alohida rasm fayli kerak emas.
struct LogoMark: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Capsule(style: .continuous)
                    .fill(.white)
                Capsule(style: .continuous)
                    .fill(.black)
                    .frame(width: w * 0.5, height: h * 0.34)
            }
            .frame(width: w, height: h)
        }
    }
}
