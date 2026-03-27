//
//  FilePreviewManager.swift
//  AndroidFileSync
//
//  Pulls files from Android device to temp and opens native macOS preview
//

import Foundation
import AppKit
internal import Combine

// MARK: - Preview Manager

class FilePreviewManager: ObservableObject {
    @Published var isLoading = false
    @Published var loadingFileName = ""
    
    /// Cache of already-pulled files: devicePath → localTempURL
    private var cache: [String: URL] = [:]
    
    /// Temp directory for pulled preview files
    private let tempDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AndroidFileSync_Preview")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    // MARK: - Public API
    
    /// Pull a file from the Android device and open it with the default macOS app
    func previewFile(_ file: UnifiedFile) {
        guard !file.isDirectory else { return }
        
        // Check cache first
        if let cached = cache[file.path], FileManager.default.fileExists(atPath: cached.path) {
            NSWorkspace.shared.open(cached)
            return
        }
        
        // Pull from device
        isLoading = true
        loadingFileName = file.name
        
        Task {
            let localURL = tempDir.appendingPathComponent(file.name)
            
            // Remove existing file if any
            try? FileManager.default.removeItem(at: localURL)
            
            let adbPath = ADBManager.getADBPath()
            guard !adbPath.isEmpty else {
                await MainActor.run {
                    isLoading = false
                }
                return
            }
            
            // Pull file using adb
            let (code, _, error) = await Shell.runAsync(
                adbPath,
                args: ADBManager.deviceArgs(["pull", file.path, localURL.path])
            )
            
            await MainActor.run {
                isLoading = false
                
                if code == 0 && FileManager.default.fileExists(atPath: localURL.path) {
                    cache[file.path] = localURL
                    NSWorkspace.shared.open(localURL)
                } else {
                    print("❌ Preview: Failed to pull file: \(error)")
                }
            }
        }
    }
    
    /// Check if a file type is previewable
    static func isPreviewable(_ file: UnifiedFile) -> Bool {
        guard !file.isDirectory else { return false }
        let ext = (file.name as NSString).pathExtension.lowercased()
        let previewableExtensions = [
            // Images
            "jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff", "svg", "ico",
            // Videos
            "mp4", "mov", "avi", "mkv", "m4v", "webm",
            // Audio
            "mp3", "m4a", "wav", "flac", "aac", "ogg",
            // Documents
            "pdf", "txt", "rtf", "html", "htm", "md", "json", "xml", "csv",
            // Office
            "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            // Code
            "swift", "java", "py", "js", "ts", "c", "cpp", "h", "css"
        ]
        return previewableExtensions.contains(ext)
    }
    
    // MARK: - Cleanup
    
    func clearCache() {
        cache.removeAll()
        try? FileManager.default.removeItem(at: tempDir)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }
}
