//
//  TransferProgressContainer.swift
//  AndroidFileSync
//
//  Isolates transfer progress updates from the main ContentView
//

import SwiftUI

struct TransferProgressContainer: View {
    @ObservedObject var downloadManager: DownloadManager
    @ObservedObject var uploadManager: UploadManager
    
    var body: some View {
        if !downloadManager.activeDownloads.isEmpty || !uploadManager.activeUploads.isEmpty {
            TransferProgressView(
                title: "Active Transfers",
                items: getTransferItems()
            )
        }
    }
    
    private func getTransferItems() -> [TransferItemData] {
        var items: [TransferItemData] = []
        
        // Add downloads (use devicePath as stable ID)
        for download in downloadManager.activeDownloads.values {
            items.append(TransferItemData(
                id: "download_\(download.devicePath)",
                fileName: download.fileName,
                progress: download.progress,
                percentage: download.progressPercentage,
                speed: download.speedText,
                bytesTransferred: download.bytesTransferred,
                totalBytes: download.totalBytes,
                isComplete: download.isComplete,
                error: download.error,
                isUpload: false
            ))
        }
        
        // Add uploads (use localPath as stable ID)
        for upload in uploadManager.activeUploads.values {
            items.append(TransferItemData(
                id: "upload_\(upload.localPath)",
                fileName: upload.fileName,
                progress: upload.progress,
                percentage: upload.progressPercentage,
                speed: upload.speedText,
                bytesTransferred: upload.bytesTransferred,
                totalBytes: upload.totalBytes,
                isComplete: upload.isComplete,
                error: upload.error,
                isUpload: true
            ))
        }
        
        return items
    }
}

