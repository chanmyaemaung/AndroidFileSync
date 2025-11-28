//
//  DownloadManager.swift
//  (CORRECTED - Single Argument Callback)
//
import Foundation
internal import Combine

class DownloadManager: ObservableObject {
    // Store progress for each file being downloaded (Key: devicePath)
    @Published var activeDownloads: [String: DownloadProgress] = [:]
    
    // Thread-safe storage for progress updates from background
    private let progressLock = NSLock()
    private var backgroundProgress: [String: (bytes: UInt64, speed: Double)] = [:]
    
    // Timer for periodic UI updates - only runs when downloads are active
    private var updateTimer: Timer?
    
    struct DownloadProgress: Identifiable {
        let id = UUID()
        let fileName: String
        let devicePath: String
        let localPath: String
        var bytesTransferred: UInt64 = 0
        var totalBytes: UInt64
        var transferSpeed: Double = 0
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
    
    private func startTimerIfNeeded() {
        guard updateTimer == nil else { return }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateUIFromBackground()
        }
    }
    
    private func stopTimerIfNeeded() {
        guard activeDownloads.isEmpty else { return }
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // Public methods to pause/resume during navigation
    func pauseUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    func resumeUpdates() {
        guard !activeDownloads.isEmpty else { return }
        startTimerIfNeeded()
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    private func updateUIFromBackground() {
        progressLock.lock()
        let updates = backgroundProgress
        progressLock.unlock()
        
        for (devicePath, (bytes, speed)) in updates {
            activeDownloads[devicePath]?.bytesTransferred = bytes
            activeDownloads[devicePath]?.transferSpeed = speed
        }
    }
    
    func downloadFile(
        devicePath: String,
        fileName: String,
        fileSize: UInt64,
        to localPath: String
    ) async throws {
        
        // Initialize progress
        let progress = DownloadProgress(
            fileName: fileName,
            devicePath: devicePath,
            localPath: localPath,
            totalBytes: fileSize
        )
        
        // Add to UI on main thread and start timer
        await MainActor.run {
            activeDownloads[devicePath] = progress
            startTimerIfNeeded()
        }
        
        print("📥 Downloading: \(fileName) (\(formatBytes(fileSize)))")
        
        // Run download in background
        try await Task.detached { [weak self] in
            guard let self = self else { return }
            
            let progressStream = ADBManager.pullFileWithProgress(
                devicePath: devicePath,
                localPath: localPath
            )
            
            // Consume stream and update background storage
            for await (bytesTransferred, speed) in progressStream {
                self.progressLock.lock()
                self.backgroundProgress[devicePath] = (bytesTransferred, speed)
                self.progressLock.unlock()
            }
            
            // Clear background progress
            self.progressLock.lock()
            self.backgroundProgress.removeValue(forKey: devicePath)
            self.progressLock.unlock()
            
            // Mark complete on main thread
            await MainActor.run {
                self.activeDownloads[devicePath]?.isComplete = true
                self.activeDownloads[devicePath]?.bytesTransferred = fileSize
                self.activeDownloads[devicePath]?.transferSpeed = 0
            }
            
            print("✅ Download complete: \(fileName)")
            
            // Show 100% briefly
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            await MainActor.run {
                self.activeDownloads.removeValue(forKey: devicePath)
                self.stopTimerIfNeeded()
            }
        }.value
    }
}
