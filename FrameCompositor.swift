import CoreImage
import CoreVideo
import Metal
import UIKit

/// Kameradan kelgan kadrlarni bitta doimiy o'lchamdagi kadrga aylantiradi.
///
/// Ikkita vazifasi bor:
///   1. Old va orqa kamera o'lchamlari har xil bo'lishi mumkin. AVAssetWriter esa
///      o'lchami o'zgarib turadigan kadrlarni qabul qilmaydi — shuning uchun hammasini
///      bitta o'lchamga keltiramiz. Shu sabab yozish paytida kamera almashtirilsa ham
///      fayl uzilmaydi.
///   2. "Ikkisi" rejimida orqa kamera to'liq ekran, old kamera burchakdagi kichik
///      oynacha (picture-in-picture) bo'lib qo'shiladi.
final class FrameCompositor {

    let outputSize: CGSize

    private let context: CIContext
    private var pool: CVPixelBufferPool?

    /// PiP oynachasining kenglik ulushi va chetdan masofasi.
    private let insetWidthRatio: CGFloat = 0.30
    private let insetMarginRatio: CGFloat = 0.04
    private let insetCornerRadius: CGFloat = 28

    /// Yumaloq burchak maskasi va ramkasi bir marta chiziladi va qayta ishlatiladi.
    private var cachedMask: CIImage?
    private var cachedBorder: CIImage?

    init(outputSize: CGSize) {
        self.outputSize = outputSize

        let options: [CIContextOption: Any] = [
            .cacheIntermediates: false,
            .workingColorSpace: CGColorSpaceCreateDeviceRGB()
        ]

        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
    }

    // MARK: - Composition

    /// `main` — to'liq ekranli manba, `inset` — burchakdagi kichik oynacha (ixtiyoriy).
    func compose(main: CVPixelBuffer, inset: CVPixelBuffer?) -> CVPixelBuffer? {
        var image = scaleToFill(orientPortrait(CIImage(cvPixelBuffer: main)), to: outputSize)

        if let inset {
            let insetWidth = (outputSize.width * insetWidthRatio).rounded()
            let insetHeight = (insetWidth * 16.0 / 9.0).rounded()
            let insetSize = CGSize(width: insetWidth, height: insetHeight)

            var small = scaleToFill(orientPortrait(CIImage(cvPixelBuffer: inset)), to: insetSize)
            small = roundCorners(small, size: insetSize)

            let margin = (outputSize.width * insetMarginRatio).rounded()
            // CoreImage koordinatasi pastki-chapdan boshlanadi, shuning uchun
            // bu siljish oynachani o'ng YUQORI burchakka olib boradi.
            let dx = outputSize.width - insetWidth - margin
            let dy = outputSize.height - insetHeight - margin

            small = small.transformed(by: CGAffineTransform(translationX: dx, y: dy))
            image = small.composited(over: image)
        }

        guard let buffer = makePixelBuffer() else { return nil }
        context.render(image, to: buffer)
        return buffer
    }

    /// Rasm rejimi uchun: tayyor kadrni JPEG'ga aylantiradi.
    /// `AVCapturePhotoOutput` ishlatilmagani uchun zatvor ovozi chiqmaydi.
    func jpegData(from pixelBuffer: CVPixelBuffer, quality: CGFloat = 0.92) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
    }

    // MARK: - Helpers

    /// Kadr landscape (eni bo'yidan katta) bo'lsa portretga 90 daraja buradi.
    ///
    /// Ko'p kamerali rejimda (ikkala kamera birga) AVCaptureConnection ning
    /// videoRotationAngle sozlamasi ba'zan kadrga qo'llanmaydi va natija yotiq chiqadi.
    /// Shu yerda kafolatlaymiz: agar kadr allaqachon tik bo'lsa (bitta kamera rejimi),
    /// hech narsa o'zgармaydi.
    private func orientPortrait(_ image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.width > extent.height else { return image }

        // 90 daraja soat yo'nalishi bo'yicha
        var rotated = image.transformed(by: CGAffineTransform(rotationAngle: -.pi / 2))
        rotated = rotated.transformed(by: CGAffineTransform(
            translationX: -rotated.extent.minX,
            y: -rotated.extent.minY
        ))
        return rotated
    }

    /// Nisbatni saqlagan holda to'ldiradi va markazidan kesadi (aspect fill).
    private func scaleToFill(_ image: CIImage, to size: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        let scale = max(size.width / extent.width, size.height / extent.height)
        var result = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let dx = (result.extent.width - size.width) / 2
        let dy = (result.extent.height - size.height) / 2

        result = result.transformed(by: CGAffineTransform(
            translationX: -result.extent.origin.x - dx,
            y: -result.extent.origin.y - dy
        ))

        return result.cropped(to: CGRect(origin: .zero, size: size))
    }

    /// PiP oynachasining burchaklarini yumaloqlaydi va ingichka oq ramka qo'shadi.
    ///
    /// Maska `CIFilter` generatori bilan emas, `UIGraphicsImageRenderer` bilan chiziladi:
    /// generator filtrlarining nomi va parametrlari iOS versiyalari bo'ylab farq qiladi,
    /// `setValue` noto'g'ri kalit bilan esa ilovani yiqitadi.
    private func roundCorners(_ image: CIImage, size: CGSize) -> CIImage {
        guard let mask = maskImage(size: size) else { return image }

        var result = image.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: mask
        ])

        if let border = borderImage(size: size) {
            result = border.composited(over: result)
        }

        return result.cropped(to: CGRect(origin: .zero, size: size))
    }

    private func maskImage(size: CGSize) -> CIImage? {
        if let cachedMask, cachedMask.extent.size == size { return cachedMask }

        let renderer = UIGraphicsImageRenderer(size: size)
        let drawn = renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: size),
                cornerRadius: insetCornerRadius
            ).fill()
        }

        guard let cgImage = drawn.cgImage else { return nil }
        let image = CIImage(cgImage: cgImage)
        cachedMask = image
        return image
    }

    private func borderImage(size: CGSize) -> CIImage? {
        if let cachedBorder, cachedBorder.extent.size == size { return cachedBorder }

        let lineWidth: CGFloat = 3

        let renderer = UIGraphicsImageRenderer(size: size)
        let drawn = renderer.image { _ in
            UIColor.white.withAlphaComponent(0.85).setStroke()
            let path = UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
                cornerRadius: insetCornerRadius - lineWidth / 2
            )
            path.lineWidth = lineWidth
            path.stroke()
        }

        guard let cgImage = drawn.cgImage else { return nil }
        let image = CIImage(cgImage: cgImage)
        cachedBorder = image
        return image
    }

    private func makePixelBuffer() -> CVPixelBuffer? {
        if pool == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height),
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
            ]

            var newPool: CVPixelBufferPool?
            let status = CVPixelBufferPoolCreate(
                kCFAllocatorDefault,
                nil,
                attributes as CFDictionary,
                &newPool
            )
            guard status == kCVReturnSuccess else { return nil }
            pool = newPool
        }

        guard let pool else { return nil }

        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess else {
            return nil
        }
        return buffer
    }
}
