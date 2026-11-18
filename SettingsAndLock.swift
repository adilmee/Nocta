import CryptoKit
import SwiftUI

// MARK: - Parol saqlash

/// Albom kodi. Parolning o'zi emas, faqat uning SHA-256 xesh qiymati saqlanadi.
/// Face ID / Touch ID ataylab ishlatilmaydi — faqat raqamli kod.
enum PinStore {

    private static let pinKey = "blackc.album.pin"
    private static let seedKey = "blackc.album.pin.seeded"
    private static let defaultPin = "0216"

    /// Albomga kirishda kod so'ralishi kerakmi?
    static var isEnabled: Bool {
        UserDefaults.standard.string(forKey: pinKey) != nil
    }

    /// Birinchi ishga tushirishda standart kod (0216) o'rnatiladi.
    /// Foydalanuvchi kodni o'chirsa, qayta tiklanmaydi.
    static func seedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seedKey) else { return }
        UserDefaults.standard.set(true, forKey: seedKey)
        set(defaultPin)
    }

    static func set(_ pin: String) {
        UserDefaults.standard.set(hash(pin), forKey: pinKey)
    }

    static func remove() {
        UserDefaults.standard.removeObject(forKey: pinKey)
    }

    static func verify(_ pin: String) -> Bool {
        guard let stored = UserDefaults.standard.string(forKey: pinKey) else { return true }
        return stored == hash(pin)
    }

    private static func hash(_ pin: String) -> String {
        SHA256.hash(data: Data(pin.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

// MARK: - Kod kiritish ekrani

/// Raqamli klaviatura. Uch rejimda ishlaydi: tekshirish, yangi kod, kodni o'zgartirish.
struct PinLockView: View {

    enum Mode {
        /// Albomga kirish uchun kodni tekshirish
        case unlock
        /// Yangi kod o'rnatish (ikki marta kiritiladi)
        case create
    }

    let mode: Mode
    let onSuccess: (String) -> Void
    let onCancel: () -> Void

    @State private var entered = ""
    @State private var firstEntry: String?
    @State private var errorText: String?
    @State private var shake = false

    private let pinLength = 4

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button("Bekor", action: onCancel)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                Image(systemName: "lock.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.85))

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.top, 14)

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.top, 6)
                } else {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.gray)
                        .padding(.top, 6)
                }

                dots
                    .padding(.top, 26)
                    .offset(x: shake ? 10 : 0)
                    .animation(.default, value: shake)

                Spacer()

                keypad
                    .padding(.bottom, 40)
            }
        }
    }

    private var title: String {
        switch mode {
        case .unlock: return "Albom qulflangan"
        case .create: return firstEntry == nil ? "Yangi kod" : "Kodni takrorlang"
        }
    }

    private var subtitle: String {
        switch mode {
        case .unlock: return "4 xonali kodni kiriting"
        case .create: return firstEntry == nil ? "4 ta raqam o'ylab toping" : "Xuddi shu kodni qayta kiriting"
        }
    }

    // MARK: Nuqtalar

    private var dots: some View {
        HStack(spacing: 18) {
            ForEach(0..<pinLength, id: \.self) { index in
                Circle()
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
                    .background(
                        Circle().fill(index < entered.count ? Color.white : Color.clear)
                    )
                    .frame(width: 16, height: 16)
            }
        }
    }

    // MARK: Klaviatura

    private var keypad: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 26) {
                    ForEach(1..<4, id: \.self) { col in
                        let digit = row * 3 + col
                        key("\(digit)")
                    }
                }
            }

            HStack(spacing: 26) {
                // Bo'sh joy — tartib saqlanishi uchun
                Color.clear.frame(width: 72, height: 72)

                key("0")

                Button {
                    if !entered.isEmpty { entered.removeLast() }
                    Haptics.select()
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 72, height: 72)
                }
                .buttonStyle(.plain)
                .opacity(entered.isEmpty ? 0.3 : 1)
            }
        }
    }

    private func key(_ digit: String) -> some View {
        Button {
            append(digit)
        } label: {
            Text(digit)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Mantiq

    private func append(_ digit: String) {
        guard entered.count < pinLength else { return }
        errorText = nil
        entered += digit
        Haptics.select()

        guard entered.count == pinLength else { return }

        let code = entered
        // Oxirgi nuqta chizilishi uchun kichik kechikish
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            submit(code)
        }
    }

    private func submit(_ code: String) {
        switch mode {
        case .unlock:
            if PinStore.verify(code) {
                onSuccess(code)
            } else {
                fail("Kod noto'g'ri")
            }

        case .create:
            if let first = firstEntry {
                if first == code {
                    onSuccess(code)
                } else {
                    firstEntry = nil
                    fail("Kodlar mos kelmadi")
                }
            } else {
                firstEntry = code
                entered = ""
            }
        }
    }

    private func fail(_ message: String) {
        errorText = message
        entered = ""
        Haptics.stop()
        shake = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { shake = false }
    }
}

// MARK: - Sozlamalar

struct SettingsView: View {

    let onClose: () -> Void

    @AppStorage(Haptics.settingsKey) private var hapticsEnabled = true
    @State private var pinEnabled = PinStore.isEnabled
    @State private var showPinCreate = false
    @State private var showPinConfirmRemoval = false
    @State private var note: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Vibratsiya") {
                    Toggle(isOn: $hapticsEnabled) {
                        Label("Titrash bilan javob", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    }
                    Text("Qora ekranda hech narsa ko'rinmaydi, shuning uchun har amal titrash bilan tasdiqlanadi: yozuv boshlandi, rasm olindi, kamera almashdi. O'chirsangiz ilova mutlaqo sezdirmay ishlaydi.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Albom qulfi") {
                    Toggle(isOn: Binding(
                        get: { pinEnabled },
                        set: { newValue in
                            if newValue {
                                showPinCreate = true
                            } else {
                                showPinConfirmRemoval = true
                            }
                        }
                    )) {
                        Label("Kod bilan himoyalash", systemImage: "lock.fill")
                    }

                    if pinEnabled {
                        Button {
                            showPinCreate = true
                        } label: {
                            Label("Kodni o'zgartirish", systemImage: "key.fill")
                        }
                    }

                    Text("Albomga kirishda 4 xonali kod so'raladi. Face ID ishlatilmaydi.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Ilova haqida") {
                    LabeledContent("Nomi", value: "blackC")
                    LabeledContent("Versiya", value: "1.0")
                }
            }
            .navigationTitle("Sozlamalar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Tayyor", action: onClose)
                }
            }
            .overlay(alignment: .bottom) {
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.green)
                        .padding(.bottom, 20)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showPinCreate) {
            PinLockView(mode: .create) { newPin in
                PinStore.set(newPin)
                pinEnabled = true
                showPinCreate = false
                flash("Kod saqlandi")
            } onCancel: {
                showPinCreate = false
                pinEnabled = PinStore.isEnabled
            }
        }
        .alert("Kodni o'chirasizmi?", isPresented: $showPinConfirmRemoval) {
            Button("O'chirish", role: .destructive) {
                PinStore.remove()
                pinEnabled = false
                flash("Kod o'chirildi")
            }
            Button("Bekor", role: .cancel) {
                pinEnabled = PinStore.isEnabled
            }
        } message: {
            Text("Albom hamma uchun ochiq bo'lib qoladi.")
        }
    }

    private func flash(_ text: String) {
        note = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if note == text { note = nil }
        }
    }
}
