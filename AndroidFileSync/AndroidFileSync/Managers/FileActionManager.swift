//
//  FileActionManager.swift
//  AndroidFileSync
//
//  Manages file operations (delete, rename) with state tracking
//

import Foundation
internal import Combine

class FileActionManager: ObservableObject {
    // Track ongoing operations
    @Published var isPerformingAction: Bool = false
    @Published var currentAction: String = ""
    @Published var lastError: String?
    
    // MARK: - Delete Operation
    
    /// Deletes a file or folder from the Android device
    /// - Parameter file: The file to delete
    func deleteFile(_ file: UnifiedFile) async throws {
        await MainActor.run {
            isPerformingAction = true
            currentAction = "Deleting \(file.name)..."
            lastError = nil
        }
        
        do {
            try await ADBManager.deleteFile(devicePath: file.path)
            
            await MainActor.run {
                isPerformingAction = false
                currentAction = ""
            }
            
            print("✅ File deleted successfully: \(file.name)")
        } catch {
            await MainActor.run {
                isPerformingAction = false
                currentAction = ""
                lastError = error.localizedDescription
            }
            throw error
        }
    }
    
    // MARK: - Rename Operation
    
    /// Renames a file or folder on the Android device
    /// - Parameters:
    ///   - file: The file to rename
    ///   - newName: The new name for the file
    func renameFile(_ file: UnifiedFile, to newName: String) async throws {
        await MainActor.run {
            isPerformingAction = true
            currentAction = "Renaming \(file.name)..."
            lastError = nil
        }
        
        do {
            // Construct the new path by replacing the filename
            let parentPath = (file.path as NSString).deletingLastPathComponent
            let newPath = parentPath + "/" + newName
            
            try await ADBManager.renameFile(oldPath: file.path, newPath: newPath)
            
            await MainActor.run {
                isPerformingAction = false
                currentAction = ""
            }
            
            print("✅ File renamed successfully: \(file.name) → \(newName)")
        } catch {
            await MainActor.run {
                isPerformingAction = false
                currentAction = ""
                lastError = error.localizedDescription
            }
            throw error
        }
    }
    
    // MARK: - Error Handling
    
    /// Clears the last error
    func clearError() {
        lastError = nil
    }
}
