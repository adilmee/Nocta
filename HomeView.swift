import SwiftUI

/// Bosh ekran: rejim tanlanadi.
///   o'ngga surish -> qora ekran (yozish)
///   chapga surish -> albom (kod so'raladi)
struct HomeView: View {

    @ObservedObject var camera: CameraManager
    @ObservedObject var store: MediaStore

    let onEnterBlackScreen: () -> Void
    let onOpenAlbum: () -> Void
    let onOpenSettings: () -> Void

    /// Surish paytidagi real vaqt siljishi -- harakat sezilib turishi uchun.
    @State private var dragOffset: CGFloat = 0

    private let swipeThreshold: CGFloat = 90

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Sozlamalar tugmasi
                HStack {
                    Spacer()
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(10)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                // Logo va sarlavha biroz pastroqda tursin
                Spacer().frame(height: 46)

                header

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

                bottomBar
            }
            .offset(x: dragOffset * 0.3)
        }
        .contentShape(Rectangle())
        .gesture(swipeGesture)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            // Ilova logosi (ikonkaga mos: oq halqa, ichida teshik)
            LogoMark()
                .frame(width: 80, height: 50)

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
            .padding(.vertical, 26)
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

    // MARK: - Bottom bar

    /// Ikkala o'tish tugmasi pastda yonma-yon, shisha (liquid glass) panelda.
    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                barButton(
                    title: "Kamera",
                    icon: camera.mode.icon,
                    accent: .white,
                    badge: nil,
                    action: onEnterBlackScreen
                )
                .disabled(!camera.isAuthorized)
                .opacity(camera.isAuthorized ? 1 : 0.35)

                barButton(
                    title: "Albom",
                    icon: "lock.fill",
                    accent: .white,
                    badge: store.items.isEmpty ? nil : store.items.count,
                    action: onOpenAlbum
                )
            }
            .padding(7)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))

            Text("o'ngga suring — kamera   ·   chapga — albom")
                .font(.caption2)
                .foregroundStyle(.gray.opacity(0.75))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private func barButton(
        title: String,
        icon: String,
        accent: Color,
        badge: Int?,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            Haptics.select()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))

                Text(title)
                    .font(.subheadline.weight(.semibold))

                if let badge {
                    Text("\(badge)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white, in: Capsule())
                }
            }
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
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

                // O'ngga surish -> qora ekran (kamera), chapga surish -> albom.
                if dx > swipeThreshold {
                    onEnterBlackScreen()
                } else if dx < -swipeThreshold {
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

// MARK: - Liquid glass

extension View {
    /// iOS 26+ da tizimning haqiqiy "Liquid Glass" effekti,
    /// eskiroq versiyalarda esa unga yaqin material + nozik ramka.
    @ViewBuilder
    func liquidGlass(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
    }
}
