//
//  SidebarManager.swift
//  AndroidFileSync
//
//  Manages sidebar Quick Access items — built-in + user-defined custom items.
//  Custom items and hidden built-ins are persisted to UserDefaults.
//

import Foundation
internal import Combine

class SidebarManager: ObservableObject {

    // MARK: - Published State

    /// Custom items added by the user
    @Published var customItems: [QuickAccessItem] = []

    /// Paths of built-in items the user has hidden
    @Published var hiddenBuiltInPaths: Set<String> = []

    /// Paths confirmed to exist on the connected device
    @Published var existingPaths: Set<String> = []

    /// Paths that have been checked at least once (so we can distinguish "unchecked" from "missing")
    @Published var checkedPaths: Set<String> = []

    // MARK: - Computed

    /// All currently visible sidebar items (built-in – hidden + custom)
    var visibleItems: [QuickAccessItem] {
        let builtIn = QuickAccessItem.commonFolders.filter { !hiddenBuiltInPaths.contains($0.path) }
        return builtIn + customItems
    }

    /// True when at least one built-in item is hidden (so user can restore)
    var hasHiddenBuiltIns: Bool { !hiddenBuiltInPaths.isEmpty }

    // MARK: - Init

    init() { load() }

    // MARK: - Existence Checking

    /// Checks which sidebar paths actually exist on the connected device via ADB.
    /// Updates `existingPaths` and `checkedPaths` on the main actor.
    func checkExistence() async {
        let paths = visibleItems.map(\.path)
        guard !paths.isEmpty else { return }

        // Build a single compound ADB shell command to check all paths at once:
        // For each path: "[ -d '/path' ] && echo 1 || echo 0"
        // We run them in sequence separated by ; so we get one line of output per path.
        let adbPath = ADBManager.getADBPath()
        guard !adbPath.isEmpty else { return }

        var newExisting: Set<String> = []
        var newChecked: Set<String> = []

        // Check in parallel with a task group
        await withTaskGroup(of: (String, Bool).self) { group in
            for path in paths {
                group.addTask {
                    let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
                    let (_, output, _) = await Shell.runAsync(
                        adbPath,
                        args: ADBManager.deviceArgs(["shell", "[ -d '\(escaped)' ] && echo 1 || echo 0"])
                    )
                    let exists = output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                    return (path, exists)
                }
            }

            for await (path, exists) in group {
                newChecked.insert(path)
                if exists { newExisting.insert(path) }
            }
        }

        await MainActor.run {
            self.existingPaths = newExisting
            self.checkedPaths = newChecked
        }
    }

    // MARK: - Mutations

    /// Add the given Android path as a custom sidebar item.
    /// Silently ignores duplicates. Then re-checks existence.
    func addItem(name: String, path: String, icon: String = "folder.fill", color: String = "blue") {
        guard !visibleItems.contains(where: { $0.path == path }) else { return }
        let item = QuickAccessItem(name: name, icon: icon, path: path, color: color, isBuiltIn: false)
        customItems.append(item)
        save()
        // Immediately check existence of the newly added item
        Task { await checkExistence() }
    }

    /// Remove a sidebar item. Built-ins are hidden (restorable); custom items are deleted.
    func removeItem(_ item: QuickAccessItem) {
        if item.isBuiltIn {
            hiddenBuiltInPaths.insert(item.path)
        } else {
            customItems.removeAll { $0.id == item.id }
            existingPaths.remove(item.path)
            checkedPaths.remove(item.path)
        }
        save()
    }

    /// Restore all hidden built-in items
    func restoreBuiltIns() {
        hiddenBuiltInPaths.removeAll()
        save()
        Task { await checkExistence() }
    }

    // MARK: - Persistence

    private let customKey  = "sidebar_customItems_v2"
    private let hiddenKey  = "sidebar_hiddenPaths_v2"

    private func save() {
        if let data = try? JSONEncoder().encode(customItems) {
            UserDefaults.standard.set(data, forKey: customKey)
        }
        UserDefaults.standard.set(Array(hiddenBuiltInPaths), forKey: hiddenKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: customKey),
           let items = try? JSONDecoder().decode([QuickAccessItem].self, from: data) {
            customItems = items
        }
        let hidden = UserDefaults.standard.stringArray(forKey: hiddenKey) ?? []
        hiddenBuiltInPaths = Set(hidden)
    }
}
