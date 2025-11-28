//
//  TransferProgressView.swift
//  AndroidFileSync
//
//  Displays detailed progress for file transfers (upload/download)
//

import SwiftUI

// Simple data structure for transfer items
struct TransferItemData: Identifiable {
    let id = UUID()
    let fileName: String
    let progress: Double
    let percentage: Int
    let speed: String
    let bytesTransferred: UInt64
    let totalBytes: UInt64
    let isComplete: Bool
    let error: String?
    let isUpload: Bool
}

struct TransferProgressView: View {
    let title: String
    let items: [TransferItemData]
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .foregroundColor(.blue)
                    Text(title)
                        .font(.headline)
                    Spacer()
                }
                .padding(.bottom, 4)
                
                // Transfer items
                ForEach(items) { item in
                    TransferItemView(item: item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.95))
        }
    }
}

// MARK: - Individual Transfer Item

struct TransferItemView: View {
    let item: TransferItemData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // File name and status
            HStack {
                Image(systemName: item.isUpload ? "arrow.up.doc" : "arrow.down.doc")
                    .foregroundColor(statusColor)
                    .font(.caption)
                
                Text(item.fileName)
                    .font(.system(.body, design: .default))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                if let error = item.error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                        .help(error)
                } else if item.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            
            // Progress bar
            ProgressView(value: item.progress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(progressTint)
            
            // Stats row
            HStack(spacing: 12) {
                // Percentage
                Text("\(item.percentage)%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 40, alignment: .leading)
                
                // Speed
                if !item.speed.isEmpty && !item.isComplete {
                    HStack(spacing: 2) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 9))
                        Text(item.speed)
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Bytes transferred / total
                Text("\(formatBytes(item.bytesTransferred)) / \(formatBytes(item.totalBytes))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(itemBackground)
        .cornerRadius(8)
    }
    
    private var statusColor: Color {
        if item.error != nil {
            return .red
        } else if item.isComplete {
            return .green
        } else {
            return item.isUpload ? .blue : .purple
        }
    }
    
    private var progressTint: Color {
        if item.error != nil {
            return .red
        } else if item.isComplete {
            return .green
        } else {
            return item.isUpload ? .blue : .purple
        }
    }
    
    private var itemBackground: Color {
        if item.error != nil {
            return Color.red.opacity(0.05)
        } else if item.isComplete {
            return Color.green.opacity(0.05)
        } else {
            return Color(NSColor.controlBackgroundColor)
        }
    }
    
    // Helper function for formatting bytes
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Helper Function

