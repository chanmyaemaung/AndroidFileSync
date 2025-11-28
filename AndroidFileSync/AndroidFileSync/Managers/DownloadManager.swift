//
//  DownloadManager.swift
//  (CORRECTED - Single Argument Callback)
//
import Foundation
internal import Combine

@MainActor
class DownloadManager: ObservableObject {
    // Store progress for each file being downloaded (Key: devicePath)
    @Published var activeDownloads: [String: DownloadProgress] = [:]
    
    struct DownloadProgress: Identifiable {
        let id = UUID()
        let fileName: String
        let devicePath: String   // Source (on Android)
        let localPath: String    // Destination (on Mac)
        var bytesTransferred: UInt64 = 0
        var totalBytes: UInt64
        var transferSpeed: Double = 0 // MB/s
        var isComplete: Bool = false
        var error: String?
        
        var progress: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(bytesTransferred) / Double(totalBytes)
        }
        
        var progressPercentage: Int {
            Int(progress * 100)
        }
        
        var speedText: String {
            if transferSpeed > 0 {
                return String(format: "%.1f MB/s", transferSpeed)
            }
            return ""
        }
    }
    
    func downloadFile(
        devicePath: String,
        fileName: String,
        fileSize: UInt64,
        to localPath: String
    ) async throws {
        
        // Initialize progress state
        var progress = DownloadProgress(
            fileName: fileName,
            devicePath: devicePath,
            localPath: localPath,
            totalBytes: fileSize
        )
        
        // Add to active list
        activeDownloads[devicePath] = progress
        
        print("📥 Downloading: \(fileName) (\(formatBytes(fileSize)))")
        
        // Get the progress stream
        let progressStream = ADBManager.pullFileWithProgress(
            devicePath: devicePath,
            localPath: localPath
        )
        
        // Iterate over the stream and update UI
        for await (bytesTransferred, speed) in progressStream {
            if var currentProgress = activeDownloads[devicePath] {
                currentProgress.bytesTransferred = bytesTransferred
                currentProgress.transferSpeed = speed
                activeDownloads[devicePath] = currentProgress
                
                // print("🔄 UI Update: \(bytesTransferred) bytes") // Optional logging
            }
        }
        
        // Mark as complete
        if var download = activeDownloads[devicePath] {
            download.isComplete = true
            download.bytesTransferred = fileSize
            download.transferSpeed = 0
            activeDownloads[devicePath] = download
        }
        
        print("✅ Download complete: \(fileName)")
        
        // Briefly show "100%" before removing it
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        activeDownloads.removeValue(forKey: devicePath)
    }
}
