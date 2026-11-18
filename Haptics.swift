import UIKit

/// Qora ekranda hech narsa ko'rinmaydi, shuning uchun har bir amal titrash bilan tasdiqlanadi.
/// Shunday qilib foydalanuvchi rasm olinganini yoki yozish to'xtaganini sezadi.
enum Haptics {

    /// Sozlamalar bo'limidagi kalit shu yerdan o'qiladi (SettingsView ham shu kalitni ishlatadi).
    static let settingsKey = "blackc.haptics.enabled"

    /// Foydalanuvchi sozlamalardan o'chirgan bo'lsa, ilova mutlaqo titramaydi.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingsKey) as? Bool ?? true
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    /// Rejim tanlanganda
    static func select() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Qora ekranga kirilganda
    static func enter() {
        impact(.medium)
    }

    /// Bosh ekranga qaytilganda
    static func exit() {
        impact(.light)
    }

    /// Rasm olinganda
    static func capture() {
        impact(.rigid)
    }

    /// Yozish boshlanganda
    static func start() {
        notify(.success)
    }

    /// Yozish to'xtaganda
    static func stop() {
        notify(.warning)
    }

    /// Qora ekranda kamera almashtirilganda: qaysi kamera yoqilganini titrash soni bildiradi
    /// (orqa = 1, old = 2, ikkisi = 3). Ekranga qaramay bilish uchun.
    static func pulses(_ count: Int) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()

        for index in 0..<max(1, count) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.16) {
                generator.impactOccurred()
            }
        }
    }
}
