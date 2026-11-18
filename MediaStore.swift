import AVFoundation
import ImageIO
import Photos
import UIKit

// MARK: - Media Item

enum MediaKind: Hashable {
    case photo
    case video
    /// Ilova fonda ishlaganda yozilgan ovoz: iOS fonda kameraga ruxsat bermaydi,
    /// mikrofonga esa beradi.
    case audio
}

struct MediaItem: Identifiable, Hashable {
    let id: String
    let kind: MediaKind
    let url: URL
    let createdAt: Date
    let fileSize: Int64

    init?(url: URL) {
        let kind: MediaKind
        switch url.pathExtension.lowercased() {
        case "mov", "mp4":
            kind = .video
        case "heic", "jpg", "jpeg":
            kind = .photo
        case "m4a":
            kind = .audio
        default:
            return nil
        }

        let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])

        self.id = url.lastPathComponent
        self.kind = kind
        self.url = url
        self.createdAt = values?.creationDate ?? Date.distantPast
        self.fileSize = Int64(values?.fileSize ?? 0)
    }
}

// MARK: - Media Store

/// Olingan video va rasmlar ilova ichidagi papkada saqlanadi, Fotosuratlarga emas.
/// Galereyaga faqat foydalanuvchi albomda tanlagan fayllar nusxalanadi.
final class MediaStore: ObservableObject {

    @Published private(set) var items: [MediaItem] = []

    private let folder: URL
    private let io = DispatchQueue(label: "com.nocta.mediastore", qos: .utility)
    private let thumbnailCache = NSCache<NSString, UIImage>()

    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.fileSize }
    }

    // MARK: Init

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        folder = base.appendingPathComponent("Media", isDirectory: true)

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        thumbnailCache.countLimit = 300
        reload()
    }

    // MARK: Reading

    func reload() {
        io.async { [weak self] in
            guard let self else { return }
            let items = self.scan()
            DispatchQueue.main.async { self.items = items }
        }
    }

    private func scan() -> [MediaItem] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .compactMap(MediaItem.init(url:))
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Writing

    /// Yozib bo'lingan videoni vaqtinchalik papkadan albomga ko'chiradi.
    func addVideo(movedFrom tempURL: URL, completion: @escaping (Error?) -> Void) {
        io.async { [weak self] in
            guard let self else { return }

            let destination = self.folder.appendingPathComponent("VID_\(Self.stamp()).mov")

            do {
                try FileManager.default.moveItem(at: tempURL, to: destination)
                let items = self.scan()
                DispatchQueue.main.async {
                    self.items = items
                    completion(nil)
                }
            } catch {
                // Ko'chirib bo'lmasa, vaqtinchalik fayl joy egallab qolmasin.
                try? FileManager.default.removeItem(at: tempURL)
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    /// Fonda yozilgan ovoz faylini albomga ko'chiradi.
    func addAudio(movedFrom tempURL: URL, completion: @escaping (Error?) -> Void) {
        io.async { [weak self] in
            guard let self else { return }

            let destination = self.folder.appendingPathComponent("AUD_\(Self.stamp()).m4a")

            do {
                try FileManager.default.moveItem(at: tempURL, to: destination)
                let items = self.scan()
                DispatchQueue.main.async {
                    self.items = items
                    completion(nil)
                }
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    func addPhoto(data: Data, completion: @escaping (Error?) -> Void) {
        io.async { [weak self] in
            guard let self else { return }

            let ext = Self.photoExtension(for: data)
            let destination = self.folder.appendingPathComponent("IMG_\(Self.stamp()).\(ext)")

            do {
                try data.write(to: destination, options: .atomic)
                let items = self.scan()
                DispatchQueue.main.async {
                    self.items = items
                    completion(nil)
                }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    // MARK: Deleting

    func delete(_ itemsToDelete: [MediaItem], completion: @escaping () -> Void) {
        io.async { [weak self] in
            guard let self else { return }

            for item in itemsToDelete {
                try? FileManager.default.removeItem(at: item.url)
                self.thumbnailCache.removeObject(forKey: item.id as NSString)
            }

            let items = self.scan()
            DispatchQueue.main.async {
                self.items = items
                completion()
            }
        }
    }

    // MARK: Export to Photos

    /// Tanlangan fayllarni galereyaga **nusxalaydi** -- asl nusxa albomda qoladi.
    func export(_ selected: [MediaItem], completion: @escaping (Result<Int, ExportError>) -> Void) {
        // Fotosuratlar ilovasi ovoz faylini saqlay olmaydi -- ularni chiqarib tashlaymiz.
        let itemsToExport = selected.filter { $0.kind != .audio }

        guard !itemsToExport.isEmpty else {
            completion(.failure(.audioNotSupported))
            return
        }

        requestPhotoAccess { granted in
            guard granted else {
                completion(.failure(.noPermission))
                return
            }

            PHPhotoLibrary.shared().performChanges {
                for item in itemsToExport {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = false
                    request.addResource(
                        with: item.kind == .video ? .video : .photo,
                        fileURL: item.url,
                        options: options
                    )
                }
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        completion(.success(itemsToExport.count))
                    } else {
                        completion(.failure(.failed(error?.localizedDescription ?? "noma'lum xato")))
                    }
                }
            }
        }
    }

    enum ExportError: Error {
        case noPermission
        case audioNotSupported
        case failed(String)

        var message: String {
            switch self {
            case .noPermission:
                return "Galereyaga saqlash uchun ruxsat yo'q. Sozlamalar -> blackC -> Rasmlar."
            case .audioNotSupported:
                return "Ovoz faylini galereyaga saqlab bo'lmaydi. Ulashish tugmasidan foydalaning."
            case .failed(let reason):
                return "Saqlanmadi: \(reason)"
            }
        }
    }

    private func requestPhotoAccess(completion: @escaping (Bool) -> Void) {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                DispatchQueue.main.async {
                    completion(status == .authorized || status == .limited)
                }
            }
        default:
            completion(false)
        }
    }

    // MARK: Thumbnails

    func thumbnail(for item: MediaItem) async -> UIImage? {
        let key = item.id as NSString

        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }

        let image: UIImage?
        switch item.kind {
        case .photo:
            image = await Task.detached(priority: .utility) {
                Self.photoThumbnail(url: item.url)
            }.value
        case .video:
            image = await Self.videoThumbnail(url: item.url)
        }

        if let image {
            thumbnailCache.setObject(image, forKey: key)
        }
        return image
    }

    private static func photoThumbnail(url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 600
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private static func videoThumbnail(url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)

        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let result = try? await generator.image(at: time) else { return nil }
        return UIImage(cgImage: result.image)
    }

    func duration(of item: MediaItem) async -> TimeInterval? {
        guard item.kind == .video || item.kind == .audio else { return nil }
        let asset = AVURLAsset(url: item.url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : nil
    }

    // MARK: Helpers

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return formatter.string(from: Date())
    }

    /// AVCapturePhoto HEIC yoki JPEG qaytarishi mumkin -- baytlardan aniqlaymiz.
    private static func photoExtension(for data: Data) -> String {
        let header = Array(data.prefix(3))
        if header.count >= 3, header[0] == 0xFF, header[1] == 0xD8, header[2] == 0xFF {
            return "jpg"
        }
        return "heic"
    }

    static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "uz_UZ")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter.string(from: date)
    }
}
