//
//  SelectionToolbar.swift
//  AndroidFileSync
//
//  Toolbar for batch operations on selected files
//

import SwiftUI

struct SelectionToolbar: View {
    let selectedCount: Int
    let onClearSelection: () -> Void
    let onDeleteAll: () -> Void
    let onDownloadAll: () -> Void
    
    @State private var showingBatchDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 16) {
                // Selection count
                Label("\(selectedCount) selected", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                
                Spacer()
                
                // Clear selection
                Button {
                    onClearSelection()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                
                Divider()
                    .frame(height: 20)
                
                // Download all
                Button {
                    onDownloadAll()
                } label: {
                    Label("Download All", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                
                // Delete all
                Button {
                    showingBatchDeleteConfirmation = true
                } label: {
                    Label("Delete All", systemImage: "trash.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.95))
        }
        .alert("Delete \(selectedCount) item(s)?", isPresented: $showingBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                onDeleteAll()
            }
        } message: {
            Text("This action cannot be undone. All \(selectedCount) selected items will be permanently deleted.")
        }
    }
}

#Preview {
    VStack {
        Spacer()
        SelectionToolbar(
            selectedCount: 5,
            onClearSelection: {},
            onDeleteAll: {},
            onDownloadAll: {}
        )
    }
}
