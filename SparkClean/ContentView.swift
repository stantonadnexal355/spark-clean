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
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @State private var showWhatsNew = false
    @State private var showHelpSheet = false
    @State private var showPrivacyPolicy = false
    @State private var showCleanErrors = false

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
        // Clean confirmation with safety breakdown
        .alert("Clean Selected Items?", isPresented: $showCleanAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                Task {
                    await manager.clean()
                    showCleanComplete = true
                }
            }
        } message: {
            let safeCount = manager.categories.filter { $0.isSelected && $0.safetyLevel == .safe }.count
            let reviewCount = manager.categories.filter { $0.isSelected && $0.safetyLevel == .review }.count
            let cautionCount = manager.categories.filter { $0.isSelected && $0.safetyLevel == .caution }.count
            Text("This will remove \(CleanupManager.formatBytes(manager.totalSize)) across \(manager.selectedCategoryCount) categories (\(manager.totalFiles) items).\n\nSafe: \(safeCount) · Review: \(reviewCount) · Caution: \(cautionCount)\n\nFiles will be moved to Trash when possible.")
        }
        // Clean complete
        .alert("Cleanup Complete", isPresented: $showCleanComplete) {
            if !manager.cleanErrors.isEmpty {
                Button("Show Errors") { showCleanErrors = true }
            }
            Button("Open Trash") {
                NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"))
            }
            Button("OK") {}
        } message: {
            let errorNote = manager.cleanErrors.isEmpty ? "" : "\n\n\(manager.cleanErrors.count) items could not be removed."
            Text("Cleaned \(CleanupManager.formatBytes(manager.lastCleanedSize)) across \(manager.lastCleanedCount) categories (\(manager.cleanSuccessCount) succeeded, \(manager.cleanFailCount) had errors).\(errorNote)\n\nA fresh scan has been performed.")
        }
        // Clean errors detail
        .alert("Clean Errors", isPresented: $showCleanErrors) {
            Button("OK") {}
        } message: {
            Text(manager.cleanErrors.prefix(10).joined(separator: "\n") + (manager.cleanErrors.count > 10 ? "\n...and \(manager.cleanErrors.count - 10) more" : ""))
        }
        .sheet(isPresented: $showExportSheet) {
            ExportReportView(report: manager.exportDetailedReport(verbose: exportVerbose))
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                showOnboarding = false
            }
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView()
        }
        .sheet(isPresented: $showHelpSheet) {
            HelpView()
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .frame(minWidth: 800, minHeight: 550)
        .onAppear {
            manager.fetchDiskUsage()
            checkWhatsNew()
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
        .onReceive(NotificationCenter.default.publisher(for: .exportReport)) { _ in
            if manager.scanComplete {
                exportVerbose = false
                showExportSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in
            showHelpSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showPrivacyPolicy)) { _ in
            showPrivacyPolicy = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWhatsNew)) { _ in
            showWhatsNew = true
        }
    }

    private func checkWhatsNew() {
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let lastSeen = UserDefaults.standard.string(forKey: "lastSeenVersion") ?? ""
        if lastSeen != currentVersion && !showOnboarding {
            showWhatsNew = true
            UserDefaults.standard.set(currentVersion, forKey: "lastSeenVersion")
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

        // Scan progress
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

        // Clean progress
        if manager.isCleaning {
            VStack(spacing: 6) {
                ProgressView(value: manager.cleanProgress)
                    .progressViewStyle(.linear)
                    .tint(.red)
                Text("Cleaning...")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }

        // Partial scan banner
        if let summary = manager.lastScanSummary, summary.wasPartial {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Partial scan")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
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

                    // Smart recommendation
                    if manager.categories.contains(where: { $0.safetyLevel == .safe && $0.isSelected }) {
                        smartRecommendation
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

    // MARK: Smart Recommendation

    private var smartRecommendation: some View {
        let safeCats = manager.categories.filter { $0.safetyLevel == .safe && $0.isSelected }
        let safeSize = safeCats.reduce(0 as Int64) { $0 + $1.size }
        return HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Quick Clean Available")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(safeCats.count) safe categories can free \(CleanupManager.formatBytes(safeSize)) with no risk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Select Safe Only") {
                manager.selectSafeOnly()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.yellow.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
                )
        )
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
                .help("Total reclaimable space found across all categories")
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
            .accessibilityLabel("Scan your Mac for reclaimable space")

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
                .accessibilityLabel("Clean selected categories")

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
                .accessibilityLabel("More options")
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
                    title: summary.wasPartial ? "Partial Scan" : "Scan Time",
                    value: String(format: "%.1fs", summary.scanDuration),
                    icon: summary.wasPartial ? "exclamationmark.clock" : "clock",
                    color: summary.wasPartial ? .orange : .purple
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

// MARK: - Onboarding View

struct OnboardingView: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            Text("Welcome to SparkClean")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 16) {
                featureRow(icon: "magnifyingglass", color: .blue,
                    title: "Deep Scan",
                    desc: "Finds caches, temp files, build artifacts, browser data, and more.")

                featureRow(icon: "checkmark.shield.fill", color: .green,
                    title: "Safety Levels",
                    desc: "Every item is labeled Safe, Review, or Caution so you know what's risk-free.")

                featureRow(icon: "trash", color: .orange,
                    title: "Trash First",
                    desc: "Files are moved to Trash by default — you can always recover them.")

                featureRow(icon: "app.badge.checkmark", color: .purple,
                    title: "App Uninstaller",
                    desc: "Completely remove apps and all their hidden data with one click.")
            }
            .padding(.horizontal, 20)

            Button("Get Started") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(width: 480, height: 480)
    }

    private func featureRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - What's New View

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    private let releases: [ReleaseNote] = [
        ReleaseNote(version: "1.0.0", date: "March 2026", notes: [
            "Deep scan for caches, temp files, logs, and crash reports",
            "Browser cache cleanup (Safari, Chrome, Firefox, Arc, Edge, Brave)",
            "Developer tools cleanup (Xcode, Android, Gradle)",
            "Package manager cache cleanup (npm, pip, Homebrew, CocoaPods, and more)",
            "Docker resource scanning and cleanup",
            "App Uninstaller with related data detection",
            "Safety levels (Safe, Review, Caution) for every category",
            "Detailed export reports",
            "Configurable scan thresholds",
        ]),
    ]

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("What's New")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(releases) { release in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("v\(release.version)")
                                    .font(.headline)
                                Text(release.date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(release.notes, id: \.self) { note in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    Text(note)
                                        .font(.body)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 480, height: 420)
    }
}

// MARK: - Help View

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("SparkClean Help")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    helpSection("Getting Started",
                        "Click **Scan** to analyze your Mac. SparkClean will find caches, temporary files, build artifacts, and other reclaimable space.")

                    helpSection("Safety Levels",
                        "**Safe** (green): Caches and temp files that rebuild automatically. No risk.\n**Review** (orange): User files like old downloads. Check before deleting.\n**Caution** (red): App data or Docker resources. Could affect running apps.")

                    helpSection("Cleaning",
                        "Select categories you want to clean, then click **Clean**. Files are moved to Trash by default so you can recover them if needed.")

                    helpSection("App Uninstaller",
                        "The Uninstaller finds all installed apps and their hidden data (caches, preferences, containers). Remove everything with one click.")

                    helpSection("Keyboard Shortcuts",
                        "**Cmd+R** — Scan\n**Cmd+E** — Export Report\n**Cmd+Shift+A** — Select All\n**Cmd+Shift+D** — Deselect All\n**Cmd+Shift+S** — Select Safe Only")

                    helpSection("Contact",
                        "Email: george@khananaev.com")
                }
            }
        }
        .padding(24)
        .frame(width: 500, height: 480)
    }

    private func helpSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(.init(body))
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Privacy Policy View

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Privacy Policy")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Last updated: March 2026")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    policySection("Data Collection",
                        "SparkClean does NOT collect, transmit, or store any personal data. All scanning and cleanup operations happen entirely on your device.")

                    policySection("Network Access",
                        "SparkClean makes NO network requests. The app works completely offline. No analytics, no telemetry, no tracking.")

                    policySection("File Access",
                        "SparkClean reads file metadata (sizes, dates) to identify reclaimable space. It only deletes files you explicitly select and confirm. Files are moved to Trash by default.")

                    policySection("Third-Party Services",
                        "SparkClean does not integrate with any third-party services, advertising networks, or analytics platforms.")

                    policySection("Contact",
                        "For questions about this privacy policy, contact george@khananaev.com")
                }
            }
        }
        .padding(24)
        .frame(width: 500, height: 440)
    }

    private func policySection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 650)
}
