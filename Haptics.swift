import UIKit

/// Qora ekranda hech narsa ko'rinmaydi, shuning uchun har bir amal titrash bilan tasdiqlanadi.
/// Shunday qilib foydalanuvchi rasm olinganini yoki yozish to'xtaganini sezadi.
enum Haptics {

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    /// Rejim tanlanganda
    static func select() {
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
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()

        for index in 0..<max(1, count) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.16) {
                generator.impactOccurred()
            }
        }
    }
}
