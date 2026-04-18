import SwiftUI

struct SidebarView: View {
    @ObservedObject var sidebarManager: SidebarManager
    let currentPath: String
    let onNavigate: (String) -> Void
    var trashCount: Int = 0
    var onOpenTrash: (() -> Void)? = nil
    var activeAppFilter: AppFilter? = nil
    var onSelectAppFilter: ((AppFilter) -> Void)? = nil
    var storageStats: [String: DeviceManager.StorageInfo] = [:]

    @State private var showRestoreAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────────────────
            HStack {
                Text("Quick Access")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()

                // Restore hidden built-ins button (only visible when something is hidden)
                if sidebarManager.hasHiddenBuiltIns {
                    Button {
                        showRestoreAlert = true
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Restore hidden default folders")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)

            Divider()

            // ── Items ────────────────────────────────────────────────────────
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(sidebarManager.visibleItems.filter { item in
                        // Show item if: not yet checked (still loading) OR confirmed to exist
                        !sidebarManager.checkedPaths.contains(item.path)
                            || sidebarManager.existingPaths.contains(item.path)
                    }) { item in
                        QuickAccessRow(
                            item: item,
                            isSelected: currentPath == item.path,
                            isChecking: !sidebarManager.checkedPaths.contains(item.path),
                            storageInfo: storageStats[item.path],
                            onTap: { onNavigate(item.path) },
                            onRemove: { sidebarManager.removeItem(item) }
                        )
                    }

                    Spacer(minLength: 8)
                }
                .padding(.vertical, 6)
            }

            // ── Apps Section ─────────────────────────────────────────────────
            if onSelectAppFilter != nil {
                appsSection
            }

            Spacer()

            // ── Trash Section ────────────────────────────────────────────────
            if let openTrash = onOpenTrash {
                Divider()
                Button(action: openTrash) {
                    HStack(spacing: 10) {
                        Image(systemName: trashCount > 0 ? "trash.fill" : "trash")
                            .foregroundColor(trashCount > 0 ? .red : .secondary)
                            .frame(width: 20)
                        Text("Trash")
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                        Spacer()
                        if trashCount > 0 {
                            Text("\(trashCount)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .cornerRadius(8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 200)
        .background(Color(NSColor.controlBackgroundColor))
        .alert("Restore Default Folders?", isPresented: $showRestoreAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Restore") { sidebarManager.restoreBuiltIns() }
        } message: {
            Text("All hidden default folders will reappear in the sidebar.")
        }
        .onAppear {
            Task { await sidebarManager.checkExistence() }
        }
        .onChange(of: sidebarManager.visibleItems.count) { _ in
            Task { await sidebarManager.checkExistence() }
        }
    }

    // MARK: - Apps Section

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Apps")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)

            Divider()

            // Single "Apps" row — opens User apps by default
            Button {
                onSelectAppFilter?(.user)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 13))
                        .foregroundColor(activeAppFilter != nil ? .white : .secondary)
                        .frame(width: 20)
                    Text("Apps")
                        .font(.system(size: 13))
                        .foregroundColor(activeAppFilter != nil ? .white : .primary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(activeAppFilter != nil ? Color.blue : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
        }
    }
} // end SidebarView

// MARK: - Row

struct QuickAccessRow: View {
    let item: QuickAccessItem
    let isSelected: Bool
    /// True while the ADB existence check is still in flight for this item
    let isChecking: Bool
    var storageInfo: DeviceManager.StorageInfo? = nil
    let onTap: () -> Void
    var onRemove: (() -> Void)? = nil

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Image(systemName: item.icon)
                        .font(.system(size: 13))
                        .foregroundColor(Color(item.color.color))
                        .frame(width: 20)

                    Text(item.name)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    if isChecking {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 14, height: 14)
                    }
                }

                // Storage gauge — only shown when stats are available
                if let storage = storageInfo {
                    VStack(alignment: .leading, spacing: 2) {
                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(height: 3)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(storageBarColor(fraction: storage.usedFraction))
                                    .frame(width: geo.size.width * storage.usedFraction, height: 3)
                            }
                        }
                        .frame(height: 3)
                        .padding(.leading, 30)

                        Text(storage.usedText)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .padding(.leading, 30)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, storageInfo != nil ? 5 : 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.blue.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Open", systemImage: "folder")
            }

            Divider()

            if item.isBuiltIn {
                Button(role: .destructive) {
                    onRemove?()
                } label: {
                    Label("Hide from Sidebar", systemImage: "eye.slash")
                }
            } else {
                Button(role: .destructive) {
                    onRemove?()
                } label: {
                    Label("Remove from Sidebar", systemImage: "minus.circle")
                }
            }
        }
    }

    private func storageBarColor(fraction: Double) -> Color {
        if fraction > 0.9 { return .red }
        if fraction > 0.8 { return .orange }
        return .blue
    }
}
