import AppKit
import ImageIO
import UniformTypeIdentifiers

enum LinkPreviewImageLoader {
    static func load(from provider: NSItemProvider?) async -> Data? {
        guard let provider else { return nil }
        let ids = provider.registeredTypeIdentifiers
        let imageIDs = ids.filter { UTType($0)?.conforms(to: .image) == true }
        let ordered = imageIDs.isEmpty ? ids : imageIDs
        for id in ordered {
            if let data = await loadData(from: provider, typeIdentifier: id),
               let normalized = encodePNG(data: data) {
                return normalized
            }
        }
        if let tiff = await loadNSImageData(from: provider),
           let data = encodePNG(data: tiff) {
            return data
        }
        return nil
    }

    static func encodePNG(data: Data, maxDimension: CGFloat = 800) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    private static func loadData(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                cont.resume(returning: data)
            }
        }
    }

    private static func loadNSImageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage,
                      let tiff = image.tiffRepresentation
                else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: tiff)
            }
        }
    }
}
