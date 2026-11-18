import AVKit
import SwiftUI

/// Ilova ichidagi albom. Fayllar bu yerda turadi; galereyaga faqat tanlanganlari nusxalanadi.
struct AlbumView: View {

    @ObservedObject var store: MediaStore
    let onBack: () -> Void

    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    @State private var previewItem: MediaItem?
    @State private var showDeleteConfirm = false
    @State private var isExporting = false
    @State private var bannerText: String?
    @State private var bannerIsError = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    private var selectedItems: [MediaItem] {
        store.items.filter { selection.contains($0.id) }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if let bannerText {
                    Text(bannerText)
                        .font(.footnote)
                        .foregroundStyle(bannerIsError ? .orange : .green)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                }

                if store.items.isEmpty {
                    emptyState
                } else {
                    grid
                }

                if isSelecting {
                    actionBar
                }
            }
        }
        .simultaneousGesture(backSwipe)
        .fullScreenCover(item: $previewItem) { item in
            MediaPreviewView(item: item) { previewItem = nil }
        }
        .confirmationDialog(
            "\(selection.count) ta fayl o'chirilsinmi?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("O'chirish", role: .destructive) { deleteSelected() }
            Button("Bekor qilish", role: .cancel) {}
        } message: {
            Text("Bu amalni ortga qaytarib bo'lmaydi.")
        }
        .onAppear { store.reload() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                onBack()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Kamera")
                }
                .font(.body.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text("Albom")
                    .font(.headline)
                    .foregroundStyle(.white)
                if !store.items.isEmpty {
                    Text("\(store.items.count) ta · \(MediaStore.formatSize(store.totalSize))")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSelecting.toggle()
                    if !isSelecting { selection.removeAll() }
                }
            } label: {
                Text(isSelecting ? "Bekor" : "Tanlash")
                    .font(.body.weight(.medium))
                    .foregroundStyle(store.items.isEmpty ? .gray : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(store.items.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(store.items) { item in
                    cell(for: item)
                }
            }
            .padding(.horizontal, 3)
            .padding(.bottom, 16)
        }
    }

    private func cell(for item: MediaItem) -> some View {
        let isSelected = selection.contains(item.id)

        return MediaThumbnailView(item: item, store: store)
            .overlay(alignment: .bottomLeading) { kindBadge(item) }
            .overlay {
                if isSelecting {
                    ZStack(alignment: .topTrailing) {
                        Color.black.opacity(isSelected ? 0.45 : 0.0)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.7))
                            .shadow(radius: 2)
                            .padding(6)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelecting {
                    toggle(item)
                } else {
                    previewItem = item
                }
            }
            .onLongPressGesture {
                if !isSelecting {
                    withAnimation(.easeInOut(duration: 0.2)) { isSelecting = true }
                }
                toggle(item)
            }
    }

    private func kindBadge(_ item: MediaItem) -> some View {
        Group {
            if item.kind == .video {
                Image(systemName: "video.fill")
            } else {
                Image(systemName: "camera.fill")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.white.opacity(0.9))
        .padding(4)
        .background(Color.black.opacity(0.45), in: Capsule())
        .padding(5)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 42))
                .foregroundStyle(.gray.opacity(0.6))
            Text("Albom bo'sh")
                .font(.headline)
                .foregroundStyle(.gray)
            Text("Qora ekranda olingan video va rasmlar\nshu yerda to'planadi")
                .font(.footnote)
                .foregroundStyle(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        VStack(spacing: 10) {
            Button {
                selectAllToggle()
            } label: {
                Text(selection.count == store.items.count ? "Tanlovni bekor qilish" : "Hammasini tanlash")
                    .font(.footnote)
                    .foregroundStyle(.gray)
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Button {
                    exportSelected()
                } label: {
                    HStack(spacing: 8) {
                        if isExporting {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text("Galereyaga saqlash")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(selection.isEmpty || isExporting)
                .opacity(selection.isEmpty || isExporting ? 0.4 : 1)

                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(width: 54)
                        .padding(.vertical, 14)
                        .background(Color.red.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(selection.isEmpty || isExporting)
                .opacity(selection.isEmpty || isExporting ? 0.4 : 1)
            }

            Text("\(selection.count) ta tanlandi")
                .font(.caption2)
                .foregroundStyle(.gray)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func toggle(_ item: MediaItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
        Haptics.select()
    }

    private func selectAllToggle() {
        if selection.count == store.items.count {
            selection.removeAll()
        } else {
            selection = Set(store.items.map(\.id))
        }
    }

    private func exportSelected() {
        let items = selectedItems
        guard !items.isEmpty else { return }

        isExporting = true
        store.export(items) { result in
            isExporting = false

            switch result {
            case .success(let count):
                showBanner("\(count) ta fayl galereyaga saqlandi", isError: false)
                Haptics.start()
                withAnimation(.easeInOut(duration: 0.2)) {
                    selection.removeAll()
                    isSelecting = false
                }
            case .failure(let error):
                showBanner(error.message, isError: true)
                Haptics.stop()
            }
        }
    }

    private func deleteSelected() {
        let items = selectedItems
        guard !items.isEmpty else { return }

        store.delete(items) {
            showBanner("\(items.count) ta fayl o'chirildi", isError: false)
            withAnimation(.easeInOut(duration: 0.2)) {
                selection.removeAll()
                isSelecting = false
            }
        }
    }

    private func showBanner(_ text: String, isError: Bool) {
        bannerIsError = isError
        withAnimation(.easeInOut(duration: 0.2)) { bannerText = text }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if bannerText == text { bannerText = nil }
            }
        }
    }

    // MARK: - Gesture

    /// O'ngga surish -> bosh ekranga qaytish.
    /// Gorizontal harakat vertikaldan sezilarli ustun bo'lgandagina ishlaydi,
    /// aks holda ro'yxatni aylantirishga xalaqit beradi.
    private var backSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard dx > 100, dx > abs(dy) * 2.5 else { return }
                onBack()
            }
    }
}

// MARK: - Thumbnail cell

struct MediaThumbnailView: View {

    let item: MediaItem
    @ObservedObject var store: MediaStore

    @State private var image: UIImage?
    @State private var durationText: String?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.opacity(0.05)

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if let durationText {
                    Text(durationText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.5), in: Capsule())
                        .padding(5)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: item.id) {
            if image == nil {
                image = await store.thumbnail(for: item)
            }
            if item.kind == .video, durationText == nil,
               let seconds = await store.duration(of: item) {
                durationText = MediaStore.formatDuration(seconds)
            }
        }
    }
}

// MARK: - Full screen preview

struct MediaPreviewView: View {

    let item: MediaItem
    let onClose: () -> Void

    @State private var image: UIImage?
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch item.kind {
            case .photo:
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView().tint(.gray)
                }

            case .video:
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .topLeading) {
            Button {
                player?.pause()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .padding(.top, 16)
        }
        .overlay(alignment: .bottom) {
            Text("\(MediaStore.formatDate(item.createdAt)) · \(MediaStore.formatSize(item.fileSize))")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 24)
        }
        .task {
            switch item.kind {
            case .photo:
                let url = item.url
                image = await Task.detached(priority: .userInitiated) {
                    UIImage(contentsOfFile: url.path)
                }.value
            case .video:
                let newPlayer = AVPlayer(url: item.url)
                player = newPlayer
                newPlayer.play()
            }
        }
        .onDisappear { player?.pause() }
    }
}
