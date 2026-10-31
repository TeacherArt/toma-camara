import Photos
import UIKit

/// Guarda en la app Fotos. Todas las respuestas llegan en el hilo principal.
enum PhotoSaver {
    private static func withAccess(_ done: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .authorized || status == .limited {
            done(true)
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
            done(newStatus == .authorized || newStatus == .limited)
        }
    }

    static func saveImages(_ items: [Data], completion: @escaping (Bool) -> Void) {
        let finish: (Bool) -> Void = { ok in DispatchQueue.main.async { completion(ok) } }
        guard !items.isEmpty else { finish(false); return }
        withAccess { ok in
            guard ok else { finish(false); return }
            PHPhotoLibrary.shared().performChanges({
                for data in items {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }
            }, completionHandler: { success, _ in finish(success) })
        }
    }

    static func saveVideos(_ urls: [URL], completion: @escaping (Bool) -> Void) {
        let finish: (Bool) -> Void = { ok in DispatchQueue.main.async { completion(ok) } }
        guard !urls.isEmpty else { finish(false); return }
        withAccess { ok in
            guard ok else { finish(false); return }
            PHPhotoLibrary.shared().performChanges({
                for url in urls {
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: options)
                }
            }, completionHandler: { success, _ in finish(success) })
        }
    }
}
