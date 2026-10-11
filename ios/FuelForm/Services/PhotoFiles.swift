import UIKit
import Foundation

enum PhotoFiles {
    static var directory: URL {
        get throws {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = root.appendingPathComponent("Photos", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); return dir
        }
    }
    static func url(_ relative: String) throws -> URL {
        guard relative.hasPrefix("Photos/"), !relative.contains(".."), relative.split(separator: "/").count == 2 else { throw DomainError.invalid("照片路径无效") }
        return try directory.appendingPathComponent(String(relative.dropFirst(7)))
    }
    static func save(_ image: UIImage) throws -> String {
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.white.setFill(); renderer.fill(CGRect(origin: .zero, size: size)); image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = upright.jpegData(compressionQuality: 0.85), data.count <= 8 * 1024 * 1024 else { throw DomainError.invalid("照片过大或无法读取") }
        let path = "Photos/\(UUID().uuidString).jpg"
        try data.write(to: url(path), options: [.atomic, .completeFileProtection]); return path
    }
    static func cleanOrphans(referenced: Set<String>) throws {
        let dir = try directory
        for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            if file.pathExtension == "jpg", !referenced.contains("Photos/" + file.lastPathComponent) { try FileManager.default.removeItem(at: file) }
        }
    }
    static func image(_ path: String) -> UIImage? { guard let url = try? url(path) else { return nil }; return UIImage(contentsOfFile: url.path) }
    static func remove(_ path: String) throws { try FileManager.default.removeItem(at: url(path)) }
}
