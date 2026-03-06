//
//  ContentView.swift
//  SparkClean
//
//  Created by George Khananaev on 3/6/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Main Content View

struct ContentView: View {
    @State private var manager = CleanupManager()
    @State private var showCleanAlert = false
    @State private var selectedSidebar: SidebarItem = .dashboard
    @State private var showExportSheet = false
    @State private var showCleanComplete = false
    @State private var exportVerbose = false

    var body: some View {
        HSplitView {
            // Sidebar
            VStack(spacing: 0) {
                sidebarContent
            }
            .frame(minWidth: 220, idealWidth: 240, maxWidth: 300)
            .background(Color(nsColor: .windowBackgroundColor))

            // Detail
            Group {
                switch selectedSidebar {
                case .dashboard:
                    DashboardView(
                        manager: manager,
                        showCleanAlert: $showCleanAlert,
                        selectedSidebar: $selectedSidebar,
                        showExportSheet: $showExportSheet,
                        exportVerbose: $exportVerbose
                    )
                case .group(let group):
                    CategoryGroupDetailView(
                        manager: manager,
                        group: group,
                        showCleanAlert: $showCleanAlert
                    )
                case .uninstaller:
                    UninstallerView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Clean Selected Items?", isPresented: $showCleanAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                Task {
                    await manager.clean()
                    showCleanComplete = true
                }
            }
        } message: {
            Text("This will remove \(CleanupManager.formatBytes(manager.totalSize)) across \(manager.selectedCategoryCount) categories (\(manager.totalFiles) items).\n\nFiles will be moved to Trash when possible.")
        }
        .alert("Cleanup Complete", isPresented: $showCleanComplete) {
            Button("OK") {}
        } message: {
            Text("Successfully cleaned \(CleanupManager.formatBytes(manager.lastCleanedSize)) across \(manager.lastCleanedCount) categories.\n\nA fresh scan has been performed to show updated results.")
        }
        .sheet(isPresented: $showExportSheet) {
            ExportReportView(report: manager.exportDetailedReport(verbose: exportVerbose))
        }
        .frame(minWidth: 800, minHeight: 550)
        .onAppear {
            manager.fetchDiskUsage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .startScan)) { _ in
            if !manager.isScanning {
                Task { await manager.scan() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectAll)) { _ in
            manager.selectAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deselectAll)) { _ in
            manager.deselectAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectSafeOnly)) { _ in
            manager.selectSafeOnly()
        }
    }

    // MARK: Sidebar Content

    @ViewBuilder
    private var sidebarContent: some View {
        TextField("Filter...", text: $manager.searchQuery)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)

        List {
            Section {
                SidebarRow(
                    label: "Dashboard",
                    icon: "gauge.with.dots.needle.33percent",
                    iconColor: .accentColor,
                    isSelected: selectedSidebar == .dashboard
                ) {
                    selectedSidebar = .dashboard
                }
            }

            if manager.scanComplete || manager.isScanning {
                Section("Categories") {
                    ForEach(CategoryGroup.allCases) { group in
                        let cats = manager.categoriesForGroup(group)
                        if !cats.isEmpty {
                            SidebarRow(
                                label: group.rawValue,
                                icon: group.icon,
                                iconColor: group.color,
                                trailing: CleanupManager.formatBytes(manager.sizeForGroup(group)),
                                badgeCount: cats.count,
                                isSelected: selectedSidebar == .group(group)
                            ) {
                                selectedSidebar = .group(group)
                            }
                        }
                    }
                }
            }

            Section("Tools") {
                SidebarRow(
                    label: "Uninstaller",
                    icon: "trash.square",
                    iconColor: .red,
                    isSelected: selectedSidebar == .uninstaller
                ) {
                    selectedSidebar = .uninstaller
                }
            }
        }
        .listStyle(.sidebar)

        if manager.isScanning {
            VStack(spacing: 6) {
                ProgressView(value: manager.scanProgress)
                    .progressViewStyle(.linear)
                Text(manager.currentScanItem)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    let manager: CleanupManager
    @Binding var showCleanAlert: Bool
    @Binding var selectedSidebar: SidebarItem
    @Binding var showExportSheet: Bool
    @Binding var exportVerbose: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection

                if manager.scanComplete {
                    if let disk = manager.diskUsage {
                        DiskUsageCardView(disk: disk, reclaimable: manager.overallSize)
                    }
                    summaryStatsGrid
                    topCategoriesSection
                    groupOverviewSection
                } else if manager.isScanning {
                    scanningSection
                } else {
                    welcomeSection
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(spacing: 12) {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)

                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("SparkClean - Mac Cleanup Tool")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Deep scan your Mac to find and remove junk files, caches, Docker resources, and more")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if manager.scanComplete {
                VStack(spacing: 4) {
                    Text(CleanupManager.formatBytes(manager.overallSize))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(sizeGradient)
                    Text("reclaimable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
            }
        }

        HStack(spacing: 10) {
            Spacer()

            if manager.isScanning {
                Button("Cancel") { manager.cancelScan() }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }

            Button {
                Task { await manager.scan() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: manager.isScanning ? "arrow.triangle.2.circlepath" : "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                    Text(manager.isScanning ? "Scanning..." : (manager.scanComplete ? "Rescan" : "Scan"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(manager.isScanning || manager.isCleaning)

            if manager.scanComplete {
                Button {
                    showCleanAlert = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                        Text(manager.isCleaning ? "Cleaning..." : "Clean")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(manager.isScanning || manager.isCleaning || manager.totalSize == 0)

                Menu {
                    Button("Select Safe Only") { manager.selectSafeOnly() }
                    Button("Select All") { manager.selectAll() }
                    Button("Deselect All") { manager.deselectAll() }
                    Divider()
                    Button("Export Summary Report...") {
                        exportVerbose = false
                        showExportSheet = true
                    }
                    Button("Export Detailed Audit Report...") {
                        exportVerbose = true
                        showExportSheet = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
            }
        }
        } // VStack
    }

    private var sizeGradient: LinearGradient {
        if manager.overallSize > 5_000_000_000 {
            return LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
        } else if manager.overallSize > 1_000_000_000 {
            return LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
        }
        return LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: Summary Stats

    private var summaryStatsGrid: some View {
        HStack(spacing: 16) {
            StatCard(
                title: "Categories",
                value: "\(manager.categories.count)",
                icon: "folder",
                color: .blue
            )
            StatCard(
                title: "Selected",
                value: CleanupManager.formatBytes(manager.totalSize),
                icon: "checkmark.circle",
                color: .green
            )
            StatCard(
                title: "Files",
                value: formatNumber(manager.categories.reduce(0) { $0 + $1.fileCount }),
                icon: "doc",
                color: .orange
            )
            if let summary = manager.lastScanSummary {
                StatCard(
                    title: "Scan Time",
                    value: String(format: "%.1fs", summary.scanDuration),
                    icon: "clock",
                    color: .purple
                )
            }
        }
    }

    // MARK: Top Categories

    private var topCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Largest Categories")
                .font(.headline)

            let topCats = manager.categories.sorted { $0.size > $1.size }.prefix(5)
            ForEach(Array(topCats)) { category in
                TopCategoryRow(category: category, maxSize: topCats.first?.size ?? 1)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: Group Overview

    private var groupOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Category")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                ForEach(CategoryGroup.allCases) { group in
                    let cats = manager.categoriesForGroup(group)
                    if !cats.isEmpty {
                        GroupCard(group: group, categories: cats) {
                            selectedSidebar = .group(group)
                        }
                    }
                }
            }
        }
    }

    // MARK: Scanning

    private var scanningSection: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView(value: manager.scanProgress) {
                Text("Scanning your Mac...")
                    .font(.headline)
            } currentValueLabel: {
                Text(manager.currentScanItem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .progressViewStyle(.linear)
            .frame(maxWidth: 400)

            Text("\(Int(manager.scanProgress * 100))%")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            if !manager.categories.isEmpty {
                Text("Found \(manager.categories.count) categories (\(CleanupManager.formatBytes(manager.overallSize)) so far)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Welcome

    private var welcomeSection: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.blue.opacity(0.15), .clear],
                            center: .center,
                            startRadius: 30,
                            endRadius: 120
                        )
                    )
                    .frame(width: 220, height: 220)

                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 10) {
                Text("Ready to Scan")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Click **Scan** to deep-scan your Mac for caches, temp files,\norphaned app data, Docker resources, unused apps, and more.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let disk = manager.diskUsage {
                HStack(spacing: 20) {
                    DiskMiniStat(label: "Total", value: CleanupManager.formatBytes(disk.totalSpace))
                    DiskMiniStat(label: "Used", value: CleanupManager.formatBytes(disk.usedSpace))
                    DiskMiniStat(label: "Free", value: CleanupManager.formatBytes(disk.freeSpace))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 650)
}
