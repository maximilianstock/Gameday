import AppKit
import Foundation
import ImageIO

/// Downloads, downsamples and caches small images (team logos, flags).
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()

    private let memory = NSCache<NSURL, NSImage>()
    private let session: URLSession
    private let lock = NSLock()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    /// Longest edge in pixels that images are downsampled to. Logos are shown at 18pt, so 2x that.
    private let maxPixelSize: CGFloat = 64

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 120 * 1024 * 1024)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
        memory.countLimit = 600
    }

    func cachedImage(for url: URL) -> NSImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> NSImage? {
        if let cached = cachedImage(for: url) { return cached }

        let task: Task<NSImage?, Never> = lock.withLock {
            if let existing = inFlight[url] { return existing }
            let task = Task<NSImage?, Never> { [session, maxPixelSize] in
                guard let (data, _) = try? await session.data(from: url) else { return nil }
                return Self.downsample(data, maxPixelSize: maxPixelSize)
            }
            inFlight[url] = task
            return task
        }

        let image = await task.value

        lock.withLock { inFlight[url] = nil }

        if let image { memory.setObject(image, forKey: url as NSURL) }
        return image
    }

    func prefetch(_ urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { _ = await self.image(for: url) }
            }
        }
    }

    private static func downsample(_ data: Data, maxPixelSize: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return NSImage(data: data)
        }
        let size = NSSize(width: CGFloat(cgImage.width) / 2, height: CGFloat(cgImage.height) / 2)
        return NSImage(cgImage: cgImage, size: size)
    }
}
