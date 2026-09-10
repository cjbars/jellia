import AppKit
import ImageIO
import SwiftUI

@MainActor
private final class ArtworkImageCache {
    static let shared = ArtworkImageCache()

    private let images = NSCache<NSString, NSImage>()

    private init() {
        images.countLimit = 100
        images.totalCostLimit = 96 * 1_024 * 1_024
    }

    func image(for key: String) -> NSImage? {
        images.object(forKey: key as NSString)
    }

    func insert(_ image: NSImage, for key: String) {
        let pixelsWide = image.representations.map(\.pixelsWide).max() ?? Int(image.size.width)
        let pixelsHigh = image.representations.map(\.pixelsHigh).max() ?? Int(image.size.height)
        images.setObject(
            image,
            forKey: key as NSString,
            cost: max(pixelsWide, 1) * max(pixelsHigh, 1) * 4
        )
    }
}

struct LoadErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: AppIcon.warning)
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Retry", action: retry)
        }
        .padding(AppSpacing.sm)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous).strokeBorder(.quaternary))
    }
}

struct LoadingRowsView: View {
    var body: some View {
        VStack(spacing: AppSpacing.row) {
            ForEach(0..<6, id: \.self) { index in
                HStack(spacing: AppSpacing.sm) {
                    RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 28, height: 18)
                    RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                        .fill(.quaternary)
                        .frame(height: 18)
                    RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: CGFloat(110 + (index % 3) * 24), height: 18)
                }
                .padding(AppSpacing.row)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            }
        }
        .redacted(reason: .placeholder)
    }
}

struct RemoteArtworkView: View {
    let artworkID: String
    let fallbackSymbol: String
    let fallbackGradient: [Color]
    var size: CGFloat = 56
    var maxPixelSize = 1_024
    let urlProvider: () async -> URL?

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: fallbackGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(
                        Image(systemName: fallbackSymbol)
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(.white.opacity(AppOpacity.strong))
                    )
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
        .task(id: cacheKey) {
            if let cachedImage = ArtworkImageCache.shared.image(for: cacheKey) {
                image = cachedImage
                return
            }
            image = nil
            guard let url = await urlProvider(), !Task.isCancelled else { return }
            let loadedImage = await Self.loadImage(from: url)
            guard !Task.isCancelled else { return }
            if let loadedImage {
                ArtworkImageCache.shared.insert(loadedImage, for: cacheKey)
            }
            image = loadedImage
        }
    }

    private var cacheKey: String {
        "\(artworkID)-w\(maxPixelSize)"
    }

    private static func loadImage(from url: URL) async -> NSImage? {
        if url.isFileURL {
            return await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                    return downsampledImage(from: source)
                }
            }.value
        }
        guard let data = try? await JellyfinNetworking.shared.session.data(from: url).0 else {
            return nil
        }
        return await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
                return downsampledImage(from: source)
            }
        }.value
    }

    private nonisolated static func downsampledImage(from source: CGImageSource) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_024,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: image, size: .zero)
    }
}
