//
//  CleanupManager.swift
//  SparkClean
//
//  Created by George Khananaev on 3/6/26.
//

import Foundation
import SwiftUI
import AppKit

// MARK: - CleanupManager

@Observable
class CleanupManager {
    var categories: [CleanupCategory] = []
    var isScanning = false
    var scanComplete = false
    var isCleaning = false
    var cleanComplete = false
    var lastCleanedSize: Int64 = 0
    var lastCleanedCount: Int = 0
    var currentScanItem = ""
    var scanProgress: Double = 0
    var diskUsage: DiskUsageInfo?
    var lastScanSummary: ScanSummary?
    var searchQuery = ""
    private var cancelRequested: Bool = false
    private var scanStartTime: Date?
    private var scannedPaths: Set<String> = []

    var totalSize: Int64 {
        filteredCategories.filter(\.isSelected).reduce(0) { $0 + $1.size }
    }

    var totalFiles: Int {
        filteredCategories.filter(\.isSelected).reduce(0) { $0 + $1.fileCount }
    }

    var overallSize: Int64 {
        categories.reduce(0) { $0 + $1.size }
    }

    var selectedCategoryCount: Int {
        filteredCategories.filter(\.isSelected).count
    }

    var filteredCategories: [CleanupCategory] {
        if searchQuery.isEmpty { return categories }
        return categories.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery) ||
            $0.description.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    func categoriesForGroup(_ group: CategoryGroup) -> [CleanupCategory] {
        filteredCategories.filter { $0.group == group }
    }

    func sizeForGroup(_ group: CategoryGroup) -> Int64 {
        categoriesForGroup(group).reduce(0) { $0 + $1.size }
    }

    func selectAll(in group: CategoryGroup) {
        for i in categories.indices where categories[i].group == group {
            categories[i].isSelected = true
        }
    }

    func deselectAll(in group: CategoryGroup) {
        for i in categories.indices where categories[i].group == group {
            categories[i].isSelected = false
        }
    }

    func selectAll() {
        for i in categories.indices { categories[i].isSelected = true }
    }

    func deselectAll() {
        for i in categories.indices { categories[i].isSelected = false }
    }

    /// Select only safe categories
    func selectSafeOnly() {
        for i in categories.indices {
            categories[i].isSelected = categories[i].safetyLevel == .safe
        }
    }

    static let home = NSHomeDirectory()

    // MARK: - Settings

    private var settingScanDocker: Bool {
        UserDefaults.standard.object(forKey: "scanDocker") as? Bool ?? true
    }
    private var settingScanNodeModules: Bool {
        UserDefaults.standard.object(forKey: "scanNodeModules") as? Bool ?? true
    }
    private var settingScanUnusedApps: Bool {
        UserDefaults.standard.object(forKey: "scanUnusedApps") as? Bool ?? true
    }
    private var settingUnusedAppThresholdDays: Int {
        let v = UserDefaults.standard.integer(forKey: "unusedAppThresholdDays")
        return v > 0 ? v : 90
    }
    private var settingLargeFileThresholdMB: Int {
        let v = UserDefaults.standard.integer(forKey: "largeFileThresholdMB")
        return v > 0 ? v : 50
    }
    private var settingOldFileThresholdDays: Int {
        let v = UserDefaults.standard.integer(forKey: "oldFileThresholdDays")
        return v > 0 ? v : 30
    }
    private var settingScreenshotThresholdDays: Int {
        let v = UserDefaults.standard.integer(forKey: "screenshotThresholdDays")
        return v > 0 ? v : 30
    }
    private var settingPreferTrash: Bool {
        UserDefaults.standard.object(forKey: "preferTrash") as? Bool ?? true
    }

    // MARK: - Scan Definitions
    //
    // SAFETY RULES:
    // - .safe = caches, logs, temp files — rebuilt automatically, no data loss
    // - .review = user files (downloads, screenshots) — might be wanted
    // - .caution = app data, backups — could break things
    //
    // Only .safe categories are selected by default.

    private let scanDefinitions: [ScanDefinition] = [

        // ═══════════ SYSTEM (safe caches & logs) ═══════════

        ScanDefinition(name: "Temp Files", icon: "clock.arrow.circlepath", color: .red,
            description: "macOS temporary directory files — rebuilt automatically",
            group: .system, safetyLevel: .safe) {
            // Resolve symlinks to avoid duplicates (/tmp -> /private/tmp)
            var resolved = Set<String>()
            for p in [NSTemporaryDirectory(), "/tmp", "/private/var/tmp", "/private/tmp"] {
                let canonical = (p as NSString).resolvingSymlinksInPath
                resolved.insert(canonical)
            }
            return Array(resolved)
        },

        ScanDefinition(name: "System Logs", icon: "doc.text", color: .green,
            description: "Old log files — safe to remove, new logs will be created",
            group: .system, safetyLevel: .safe) {
            // Exclude DiagnosticReports subdirectory (scanned separately)
            ["\(home)/Library/Logs", "/Library/Logs"]
        },

        ScanDefinition(name: "Crash Reports", icon: "exclamationmark.triangle", color: .orange,
            description: "App crash reports and diagnostics — safe to remove",
            group: .system, safetyLevel: .safe) {
            ["\(home)/Library/Logs/DiagnosticReports", "/Library/Logs/DiagnosticReports"]
        },

        ScanDefinition(name: "Saved App State", icon: "rectangle.stack", color: .indigo,
            description: "Window positions for app resume — apps will just open fresh",
            group: .system, safetyLevel: .safe) {
            ["\(home)/Library/Saved Application State"]
        },

        ScanDefinition(name: "macOS Update Cache", icon: "arrow.down.circle", color: .blue,
            description: "Already-installed macOS update files",
            group: .system, safetyLevel: .safe) {
            ["/Library/Updates", "\(home)/Library/Caches/com.apple.SoftwareUpdate"]
        },

        ScanDefinition(name: "Trash", icon: "trash", color: .gray,
            description: "Items already in your Trash — empty to reclaim space",
            group: .system, safetyLevel: .review, defaultSelected: false) {
            ["\(home)/.Trash"]
        },

        // ═══════════ BROWSERS (safe — caches rebuild) ═══════════

        ScanDefinition(name: "Safari Cache", icon: "safari", color: .cyan,
            description: "Safari browser cache — will be rebuilt as you browse",
            group: .browsers, safetyLevel: .safe) {
            ["\(home)/Library/Caches/com.apple.Safari",
             "\(home)/Library/Caches/com.apple.Safari.SearchHelper",
             "\(home)/Library/Caches/com.apple.WebKit.Networking"]
        },

        ScanDefinition(name: "Chrome Cache", icon: "globe", color: .yellow,
            description: "Chrome cache, GPU cache, service workers — rebuilt automatically",
            group: .browsers, safetyLevel: .safe) {
            ["\(home)/Library/Caches/Google/Chrome",
             "\(home)/Library/Application Support/Google/Chrome/Default/Service Worker",
             "\(home)/Library/Application Support/Google/Chrome/Default/GPUCache",
             "\(home)/Library/Application Support/Google/Chrome/Default/Code Cache",
             "\(home)/Library/Application Support/Google/Chrome/Default/Cache",
             "\(home)/Library/Application Support/Google/Chrome/ShaderCache",
             "\(home)/Library/Application Support/Google/Chrome/GrShaderCache",
             "\(home)/Library/Application Support/Google/Chrome/Profile 1/Cache",
             "\(home)/Library/Application Support/Google/Chrome/Profile 1/Code Cache"]
        },

        ScanDefinition(name: "Firefox Cache", icon: "flame", color: .orange,
            description: "Firefox cache and crash reports",
            group: .browsers, safetyLevel: .safe) {
            ["\(home)/Library/Caches/Firefox",
             "\(home)/Library/Caches/org.mozilla.firefox",
             "\(home)/Library/Application Support/Firefox/Crash Reports"]
        },

        ScanDefinition(name: "Arc Cache", icon: "compass.drawing", color: .blue,
            description: "Arc browser cache",
            group: .browsers, safetyLevel: .safe) {
            ["\(home)/Library/Caches/company.thebrowser.Browser",
             "\(home)/Library/Application Support/Arc/User Data/Default/Service Worker",
             "\(home)/Library/Application Support/Arc/User Data/Default/GPUCache",
             "\(home)/Library/Application Support/Arc/User Data/Default/Code Cache"]
        },

        ScanDefinition(name: "Edge Cache", icon: "globe.americas", color: .cyan,
            description: "Microsoft Edge cache",
            group: .browsers, safetyLevel: .safe) {
            ["\(home)/Library/Caches/com.microsoft.edgemac",
             "\(home)/Library/Application Support/Microsoft Edge/Default/Service Worker",
             "\(home)/Library/Application Support/Microsoft Edge/Default/Code Cache",
             "\(home)/Library/Application Support/Microsoft Edge/Default/GPUCache"]
        },

        ScanDefinition(name: "Brave Cache", icon: "shield", color: .orange,
            description: "Brave browser cache",
            group: .browsers, safetyLevel: .safe) {
            ["\(home)/Library/Caches/BraveSoftware/Brave-Browser",
             "\(home)/Library/Application Support/BraveSoftware/Brave-Browser/Default/Service Worker",
             "\(home)/Library/Application Support/BraveSoftware/Brave-Browser/Default/Code Cache"]
        },

        // ═══════════ DEVELOPER (safe — build artifacts rebuild) ═══════════

        ScanDefinition(name: "Xcode Derived Data", icon: "hammer", color: .pink,
            description: "Xcode build artifacts — rebuilt on next build",
            group: .developer, safetyLevel: .safe) {
            ["\(home)/Library/Developer/Xcode/DerivedData"]
        },

        ScanDefinition(name: "Xcode Caches & Device Support", icon: "xmark.bin", color: .indigo,
            description: "Xcode caches, old device support — re-downloaded as needed",
            group: .developer, safetyLevel: .safe) {
            ["\(home)/Library/Caches/com.apple.dt.Xcode",
             "\(home)/Library/Developer/Xcode/iOS DeviceSupport",
             "\(home)/Library/Developer/Xcode/watchOS DeviceSupport",
             "\(home)/Library/Developer/Xcode/tvOS DeviceSupport",
             "\(home)/Library/Developer/Xcode/macOS DeviceSupport",
             "\(home)/Library/Developer/CoreSimulator/Caches",
             "\(home)/Library/Developer/Xcode/Products"]
        },

        ScanDefinition(name: "Xcode Previews", icon: "rectangle.on.rectangle", color: .pink,
            description: "SwiftUI preview build data — rebuilt automatically",
            group: .developer, safetyLevel: .safe) {
            ["\(home)/Library/Developer/Xcode/UserData/Previews",
             "\(home)/Library/Developer/XCPGDevices"]
        },

        ScanDefinition(name: "Xcode Archives", icon: "archivebox", color: .purple,
            description: "Old build archives — may contain release builds you need",
            group: .developer, safetyLevel: .review, defaultSelected: false) {
            ["\(home)/Library/Developer/Xcode/Archives"]
        },

        ScanDefinition(name: "iOS Simulators", icon: "iphone.gen3", color: .indigo,
            description: "Simulator devices & runtimes — re-downloaded from Xcode",
            group: .developer, safetyLevel: .review, defaultSelected: false) {
            ["\(home)/Library/Developer/CoreSimulator/Devices",
             "/Library/Developer/CoreSimulator/Volumes",
             "/Library/Developer/CoreSimulator/Images"]
        },

        ScanDefinition(name: "Android / Gradle", icon: "cpu", color: .green,
            description: "Android build caches and Gradle — rebuilt on next build",
            group: .developer, safetyLevel: .safe) {
            ["\(home)/.gradle/caches", "\(home)/.gradle/wrapper/dists",
             "\(home)/.gradle/daemon", "\(home)/.android/cache"]
        },

        // ═══════════ PACKAGE MANAGERS (safe — caches re-download) ═══════════

        ScanDefinition(name: "Homebrew Cache", icon: "mug", color: .brown,
            description: "Downloaded packages — re-downloaded on next install",
            group: .packageManagers, safetyLevel: .safe) {
            ["\(home)/Library/Caches/Homebrew", "/opt/homebrew/Caches",
             "\(home)/Library/Logs/Homebrew"]
        },

        ScanDefinition(name: "CocoaPods Cache", icon: "shippingbox", color: .brown,
            description: "Pod cache — re-downloaded on pod install",
            group: .packageManagers, safetyLevel: .safe) {
            ["\(home)/Library/Caches/CocoaPods"]
        },

        ScanDefinition(name: "SPM Cache", icon: "swift", color: .orange,
            description: "Swift Package Manager cache — re-downloaded as needed",
            group: .packageManagers, safetyLevel: .safe) {
            ["\(home)/Library/Caches/org.swift.swiftpm", "\(home)/Library/org.swift.swiftpm"]
        },

        ScanDefinition(name: "npm / Yarn / pnpm / Bun", icon: "shippingbox", color: .red,
            description: "JS package caches — re-downloaded on install",
            group: .packageManagers, safetyLevel: .safe) {
            ["\(home)/.npm", "\(home)/Library/Caches/Yarn", "\(home)/.yarn/cache",
             "\(home)/Library/pnpm/store", "\(home)/.pnpm-store",
             "\(home)/.bun/install/cache"]
        },

        ScanDefinition(name: "pip / Conda", icon: "puzzlepiece", color: .green,
            description: "Python package caches — re-downloaded on install",
            group: .packageManagers, safetyLevel: .safe) {
            ["\(home)/Library/Caches/pip", "\(home)/.cache/pip",
             "\(home)/.conda/pkgs", "\(home)/anaconda3/pkgs", "\(home)/miniconda3/pkgs"]
        },

        ScanDefinition(name: "Ruby Gems", icon: "diamond", color: .red,
            description: "Gem cache — re-downloaded on install",
            group: .packageManagers, safetyLevel: .safe) {
            ["\(home)/.gem", "\(home)/.bundle/cache"]
        },

        ScanDefinition(name: "Go Cache", icon: "server.rack", color: .cyan,
            description: "Go build and module caches",
            group: .packageManagers, safetyLevel: .safe) {
            ["\(home)/Library/Caches/go-build", "\(home)/go/pkg/mod/cache"]
        },

        ScanDefinition(name: "Cargo / Rust", icon: "gearshape.2", color: .orange,
            description: "Cargo registry and build cache",
            group: .packageManagers, safetyLevel: .safe) {
            ["\(home)/.cargo/registry", "\(home)/.cargo/git"]
        },

        ScanDefinition(name: "Maven", icon: "building.columns", color: .indigo,
            description: "Maven local repository cache",
            group: .packageManagers, safetyLevel: .safe) {
            ["\(home)/.m2/repository"]
        },

        ScanDefinition(name: "Composer / NuGet / Dart", icon: "cube", color: .purple,
            description: "PHP, .NET, Dart package caches",
            group: .packageManagers, safetyLevel: .safe) {
            ["\(home)/.composer/cache", "\(home)/.nuget/packages", "\(home)/.pub-cache"]
        },

        // ═══════════ DOCKER ═══════════

        ScanDefinition(name: "Docker Desktop Data", icon: "cube.box", color: .blue,
            description: "Docker VM disk images — contains all images/containers",
            group: .docker, safetyLevel: .caution, defaultSelected: false) {
            ["\(home)/Library/Containers/com.docker.docker/Data", "\(home)/.docker"]
        },

        // ═══════════ APPLICATIONS (safe — app caches rebuild) ═══════════

        ScanDefinition(name: "VS Code / Cursor Cache", icon: "curlybraces", color: .blue,
            description: "IDE caches and logs — rebuilt automatically",
            group: .applications, safetyLevel: .safe) {
            ["\(home)/Library/Caches/com.microsoft.VSCode",
             "\(home)/Library/Application Support/Code/Cache",
             "\(home)/Library/Application Support/Code/CachedData",
             "\(home)/Library/Application Support/Code/CachedExtensionVSIXs",
             "\(home)/Library/Application Support/Code/logs",
             "\(home)/Library/Application Support/Code/Service Worker",
             "\(home)/Library/Application Support/Code/Code Cache",
             "\(home)/Library/Application Support/Cursor/Cache",
             "\(home)/Library/Application Support/Cursor/CachedData",
             "\(home)/Library/Application Support/Cursor/Code Cache",
             "\(home)/Library/Application Support/Cursor/logs",
             "\(home)/Library/Caches/com.todesktop.runtime.Cursor"]
        },

        ScanDefinition(name: "JetBrains IDEs Cache", icon: "chevron.left.forwardslash.chevron.right", color: .orange,
            description: "IntelliJ, WebStorm, PyCharm caches/logs — rebuilt on launch",
            group: .applications, safetyLevel: .safe) {
            ["\(home)/Library/Caches/JetBrains", "\(home)/Library/Logs/JetBrains"]
        },

        ScanDefinition(name: "Adobe Cache", icon: "paintbrush", color: .red,
            description: "Adobe media cache — rebuilt when editing",
            group: .applications, safetyLevel: .safe) {
            ["\(home)/Library/Caches/Adobe",
             "\(home)/Library/Application Support/Adobe/Common/Media Cache Files",
             "\(home)/Library/Application Support/Adobe/Common/Media Cache"]
        },

        ScanDefinition(name: "Spotify Cache", icon: "music.note", color: .green,
            description: "Spotify offline cache — music re-streams on demand",
            group: .applications, safetyLevel: .safe) {
            ["\(home)/Library/Caches/com.spotify.client",
             "\(home)/Library/Application Support/Spotify/PersistentCache"]
        },

        ScanDefinition(name: "Slack Cache", icon: "number", color: .purple,
            description: "Slack cache — rebuilt when you open channels",
            group: .applications, safetyLevel: .safe) {
            ["\(home)/Library/Caches/com.tinyspeck.slackmacgap",
             "\(home)/Library/Application Support/Slack/Cache",
             "\(home)/Library/Application Support/Slack/Service Worker",
             "\(home)/Library/Application Support/Slack/Code Cache"]
        },

        ScanDefinition(name: "Discord Cache", icon: "bubble.left.and.bubble.right", color: .indigo,
            description: "Discord cache — rebuilt automatically",
            group: .applications, safetyLevel: .safe) {
            ["\(home)/Library/Caches/com.hnc.Discord",
             "\(home)/Library/Application Support/discord/Cache",
             "\(home)/Library/Application Support/discord/Code Cache",
             "\(home)/Library/Application Support/discord/GPUCache"]
        },

        ScanDefinition(name: "Teams Cache", icon: "person.3", color: .blue,
            description: "Microsoft Teams cache",
            group: .applications, safetyLevel: .safe) {
            ["\(home)/Library/Caches/com.microsoft.teams2",
             "\(home)/Library/Application Support/Microsoft/Teams/Cache",
             "\(home)/Library/Application Support/Microsoft Teams/Cache"]
        },

        ScanDefinition(name: "Zoom Cache", icon: "video", color: .blue,
            description: "Zoom cache — rebuilt on meetings",
            group: .applications, safetyLevel: .safe) {
            ["\(home)/Library/Caches/us.zoom.xos"]
        },

        ScanDefinition(name: "Telegram Cache", icon: "paperplane", color: .blue,
            description: "Telegram media cache — re-downloaded from cloud",
            group: .applications, safetyLevel: .safe) {
            ["\(home)/Library/Caches/ru.keepcoder.Telegram"]
        },

        ScanDefinition(name: "Microsoft Office Cache", icon: "doc.richtext", color: .blue,
            description: "Office app caches — rebuilt on use",
            group: .applications, safetyLevel: .safe) {
            ["\(home)/Library/Caches/com.microsoft.Word",
             "\(home)/Library/Caches/com.microsoft.Excel",
             "\(home)/Library/Caches/com.microsoft.Powerpoint",
             "\(home)/Library/Caches/com.microsoft.Outlook"]
        },
    ]

    // MARK: - Disk Usage

    func fetchDiskUsage() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfFileSystem(forPath: NSHomeDirectory()) else { return }
        let total = (attrs[.systemSize] as? Int64) ?? 0
        let free = (attrs[.systemFreeSize] as? Int64) ?? 0
        let used = total - free
        let url = URL(fileURLWithPath: "/")
        let purgeableBytes: Int64
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let available = values.volumeAvailableCapacityForImportantUsage {
            purgeableBytes = available - free
        } else {
            purgeableBytes = 0
        }
        diskUsage = DiskUsageInfo(totalSpace: total, usedSpace: used, freeSpace: free, purgeableSpace: max(0, purgeableBytes))
    }

    // MARK: - Main Scan

    func scan() async {
        await MainActor.run {
            isScanning = true
            scanComplete = false
            cleanComplete = false
            categories = []
            currentScanItem = ""
            scanProgress = 0
            cancelRequested = false
            scanStartTime = Date()
        }
        scannedPaths = []

        fetchDiskUsage()

        let scanDocker = settingScanDocker
        let scanNodeModules = settingScanNodeModules
        let scanUnusedApps = settingScanUnusedApps

        // Phase 1: Specific known-safe targets
        // First pass: collect all paths so we can detect parent-child overlaps
        let totalDefs = scanDefinitions.count
        var allResolvedPaths: [[String]] = []
        for definition in scanDefinitions {
            let resolved = definition.pathResolver().map { ($0 as NSString).resolvingSymlinksInPath }
            allResolvedPaths.append(resolved)
        }

        for (index, definition) in scanDefinitions.enumerated() {
            if cancelRequested { break }

            await MainActor.run { currentScanItem = definition.name }

            let resolvedPaths = allResolvedPaths[index]
            let fm = FileManager.default
            let existingPaths = resolvedPaths.filter { fm.fileExists(atPath: $0) }

            if !existingPaths.isEmpty {
                var breakdown: [PathStat] = []
                var combinedSize: Int64 = 0
                var combinedCount: Int = 0

                for path in existingPaths {
                    if cancelRequested { break }
                    // Check if this path is a parent of another scan's path — if so,
                    // exclude the child from this scan's size calculation
                    var childPaths: [String] = []
                    for (otherIdx, otherPaths) in allResolvedPaths.enumerated() where otherIdx != index {
                        for otherPath in otherPaths where otherPath.hasPrefix(path + "/") {
                            childPaths.append(otherPath)
                        }
                    }

                    let (size, count): (Int64, Int)
                    if childPaths.isEmpty {
                        (size, count) = await directorySize(path)
                    } else {
                        (size, count) = await directorySizeExcluding(path, excludedPaths: childPaths)
                    }

                    if size > 0 {
                        breakdown.append(PathStat(path: path, size: size, fileCount: count))
                        combinedSize += size
                        combinedCount += count
                        scannedPaths.insert(path)
                    }
                }

                if combinedSize > 0 {
                    let category = CleanupCategory(
                        name: definition.name, icon: definition.icon,
                        color: definition.color, description: definition.description,
                        group: definition.group, safetyLevel: definition.safetyLevel,
                        paths: existingPaths, breakdown: breakdown,
                        deleteChildrenOnly: true,
                        size: combinedSize, fileCount: combinedCount,
                        isSelected: definition.defaultSelected
                    )
                    await MainActor.run { categories.append(category) }
                }
            }

            await MainActor.run {
                scanProgress = Double(index + 1) / Double(totalDefs + 12)
            }
        }

        // Phase 2: Comprehensive walkers + smart scans
        var smartScans: [(String, () async -> CleanupCategory?)] = [
            // SAFE: Cache directory walkers (caches always rebuild)
            ("Scanning all app caches...",       { await self.scanAllCaches() }),
            ("Scanning system caches...",        { await self.scanSystemCaches() }),
            // REVIEW: User file scanners (need user decision)
            ("Scanning old screenshots...",      { await self.scanOldScreenshots() }),
            ("Scanning installer files...",      { await self.scanInstallerFiles() }),
            ("Scanning old downloads...",        { await self.scanOldDownloads() }),
        ]

        if scanDocker {
            smartScans.append(("Scanning Docker images...",      { await self.scanDockerImages() }))
            smartScans.append(("Scanning Docker containers...",  { await self.scanDockerStoppedContainers() }))
            smartScans.append(("Scanning Docker build cache...", { await self.scanDockerBuildCache() }))
        }
        if scanUnusedApps {
            smartScans.append(("Scanning unused apps...",        { await self.scanUnusedApplications() }))
        }
        if scanNodeModules {
            smartScans.append(("Scanning node_modules...",       { await self.scanNodeModules() }))
        }

        // Always scan these
        smartScans.append(("Scanning mail attachments...",   { await self.scanMailAttachments() }))
        smartScans.append(("Scanning app leftovers...",      { await self.scanOrphanedAppData() }))

        let totalSmartScans = smartScans.count
        for (index, (name, scanner)) in smartScans.enumerated() {
            if cancelRequested { break }
            await MainActor.run { currentScanItem = name }

            if let category = await scanner() {
                await MainActor.run { categories.append(category) }
            }

            await MainActor.run {
                scanProgress = Double(totalDefs + index + 1) / Double(totalDefs + totalSmartScans)
            }
        }

        if cancelRequested {
            await MainActor.run {
                isScanning = false; scanComplete = false
                currentScanItem = ""; scanProgress = 0
            }
            return
        }

        let scanDuration = Date().timeIntervalSince(scanStartTime ?? Date())
        await MainActor.run {
            categories.sort { $0.size > $1.size }
            isScanning = false; scanComplete = true
            currentScanItem = ""; scanProgress = 1.0
            lastScanSummary = ScanSummary(
                totalCategories: categories.count, totalSize: overallSize,
                totalFiles: categories.reduce(0) { $0 + $1.fileCount },
                scanDuration: scanDuration, timestamp: Date()
            )
        }
    }

    func cancelScan() { cancelRequested = true }

    // MARK: - Clean

    func clean() async {
        let cleanedSize = totalSize
        let cleanedCount = selectedCategoryCount
        await MainActor.run { isCleaning = true }

        let selectedCategories = categories.filter(\.isSelected)
        let useTrash = settingPreferTrash

        for category in selectedCategories {
            if category.isDockerResource, let command = category.dockerCleanCommand {
                await runDockerClean(command: command)
                continue
            }

            let paths = category.paths
            let deleteChildrenOnly = category.deleteChildrenOnly

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let fm = FileManager.default
                    if deleteChildrenOnly {
                        for path in paths {
                            guard let contents = try? fm.contentsOfDirectory(atPath: path) else { continue }
                            for item in contents {
                                let fullPath = (path as NSString).appendingPathComponent(item)
                                let url = URL(fileURLWithPath: fullPath)
                                if useTrash {
                                    if (try? fm.trashItem(at: url, resultingItemURL: nil)) == nil {
                                        try? fm.removeItem(at: url)
                                    }
                                } else {
                                    try? fm.removeItem(at: url)
                                }
                            }
                        }
                    } else {
                        for path in paths {
                            let url = URL(fileURLWithPath: path)
                            if useTrash {
                                if (try? fm.trashItem(at: url, resultingItemURL: nil)) == nil {
                                    try? fm.removeItem(at: url)
                                }
                            } else {
                                try? fm.removeItem(at: url)
                            }
                        }
                    }
                    continuation.resume()
                }
            }
        }

        await MainActor.run {
            isCleaning = false
            cleanComplete = true
            lastCleanedSize = cleanedSize
            lastCleanedCount = cleanedCount
        }
        await scan()
    }

    // MARK: - Size Calculation

    private func directorySize(_ path: String) async -> (Int64, Int) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.directorySizeSync(path))
            }
        }
    }

    private func directorySizeExcluding(_ path: String, excludedPaths: [String]) async -> (Int64, Int) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.directorySizeSyncExcluding(path, excludedPaths: excludedPaths))
            }
        }
    }

    private static func directorySizeSync(_ path: String) -> (Int64, Int) {
        let fm = FileManager.default
        var totalSize: Int64 = 0
        var count = 0

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey],
            options: [],
            errorHandler: nil
        ) else {
            return (0, 0)
        }

        for case let fileURL as URL in enumerator {
            guard let rv = try? fileURL.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
            ) else { continue }
            if rv.isRegularFile == true {
                totalSize += Int64(rv.totalFileAllocatedSize ?? rv.fileSize ?? 0)
                count += 1
            }
        }

        return (totalSize, count)
    }

    private static func directorySizeSyncExcluding(_ path: String, excludedPaths: [String]) -> (Int64, Int) {
        let fm = FileManager.default
        var totalSize: Int64 = 0
        var count = 0

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey],
            options: [],
            errorHandler: nil
        ) else {
            return (0, 0)
        }

        for case let fileURL as URL in enumerator {
            let filePath = fileURL.path
            // Skip files inside excluded subdirectories
            if excludedPaths.contains(where: { filePath.hasPrefix($0 + "/") || filePath == $0 }) {
                continue
            }
            guard let rv = try? fileURL.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
            ) else { continue }
            if rv.isRegularFile == true {
                totalSize += Int64(rv.totalFileAllocatedSize ?? rv.fileSize ?? 0)
                count += 1
            }
        }

        return (totalSize, count)
    }

    // MARK: - Comprehensive Cache Walkers (SAFE — caches always rebuild)

    /// Walks ~/Library/Caches — finds ALL app caches not already covered by specific scans
    private func scanAllCaches() async -> CleanupCategory? {
        let fm = FileManager.default
        let dir = "\(Self.home)/Library/Caches"
        guard fm.fileExists(atPath: dir) else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [scannedPaths] in
                guard let entries = try? fm.contentsOfDirectory(atPath: dir) else {
                    continuation.resume(returning: nil)
                    return
                }

                var paths: [String] = []
                var breakdown: [PathStat] = []
                var totalSize: Int64 = 0
                var totalCount: Int = 0

                for entry in entries {
                    let fullPath = (dir as NSString).appendingPathComponent(entry)
                    // Skip entries already covered by specific scans
                    if scannedPaths.contains(fullPath) { continue }
                    if scannedPaths.contains(where: { $0.hasPrefix(fullPath + "/") || fullPath.hasPrefix($0 + "/") }) { continue }

                    let (sz, ct) = Self.directorySizeSync(fullPath)
                    if sz > 100_000 { // >100KB
                        paths.append(fullPath)
                        breakdown.append(PathStat(path: fullPath, size: sz, fileCount: ct))
                        totalSize += sz
                        totalCount += ct
                    }
                }

                guard totalSize > 500_000, !paths.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                var sorted = breakdown
                sorted.sort { $0.size > $1.size }

                continuation.resume(returning: CleanupCategory(
                    name: "Other App Caches", icon: "archivebox", color: .blue,
                    description: "\(paths.count) app caches — safe to remove, rebuilt automatically",
                    group: .system, safetyLevel: .safe,
                    paths: paths, breakdown: Array(sorted.prefix(60)),
                    deleteChildrenOnly: false,
                    size: totalSize, fileCount: totalCount,
                    isSelected: true
                ))
            }
        }
    }

    /// Walks /Library/Caches — system-level caches
    private func scanSystemCaches() async -> CleanupCategory? {
        let fm = FileManager.default
        let dir = "/Library/Caches"
        guard fm.fileExists(atPath: dir) else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [scannedPaths] in
                guard let entries = try? fm.contentsOfDirectory(atPath: dir) else {
                    continuation.resume(returning: nil)
                    return
                }

                var paths: [String] = []
                var breakdown: [PathStat] = []
                var totalSize: Int64 = 0
                var totalCount: Int = 0

                for entry in entries {
                    let fullPath = (dir as NSString).appendingPathComponent(entry)
                    if scannedPaths.contains(fullPath) { continue }

                    let (sz, ct) = Self.directorySizeSync(fullPath)
                    if sz > 500_000 { // >500KB
                        paths.append(fullPath)
                        breakdown.append(PathStat(path: fullPath, size: sz, fileCount: ct))
                        totalSize += sz
                        totalCount += ct
                    }
                }

                guard totalSize > 1_000_000, !paths.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                var sorted = breakdown
                sorted.sort { $0.size > $1.size }

                continuation.resume(returning: CleanupCategory(
                    name: "System Caches", icon: "internaldrive.fill", color: .blue,
                    description: "\(paths.count) system-level caches — safe to remove",
                    group: .system, safetyLevel: .safe,
                    paths: paths, breakdown: Array(sorted.prefix(60)),
                    deleteChildrenOnly: false,
                    size: totalSize, fileCount: totalCount,
                    isSelected: true
                ))
            }
        }
    }

    // MARK: - User File Scanners (REVIEW — user should check before deleting)

    /// Old files in Downloads (>30 days old)
    private func scanOldDownloads() async -> CleanupCategory? {
        let olderThanDays = settingOldFileThresholdDays
        let threshold = Date().addingTimeInterval(-Double(olderThanDays) * 86400)

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                let downloads = "\(Self.home)/Downloads"
                guard fm.fileExists(atPath: downloads) else {
                    continuation.resume(returning: nil)
                    return
                }

                var filePaths: [String] = []
                var breakdown: [PathStat] = []
                var totalSize: Int64 = 0

                guard let contents = try? fm.contentsOfDirectory(
                    at: URL(fileURLWithPath: downloads),
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continuation.resume(returning: nil)
                    return
                }

                for url in contents {
                    guard let rv = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]) else { continue }
                    let modDate = rv.contentModificationDate ?? Date.distantPast
                    guard modDate < threshold else { continue }

                    if rv.isRegularFile == true {
                        let size = Int64(rv.totalFileAllocatedSize ?? rv.fileSize ?? 0)
                        if size > 0 {
                            filePaths.append(url.path)
                            breakdown.append(PathStat(path: url.path, size: size, fileCount: 1))
                            totalSize += size
                        }
                    } else if rv.isDirectory == true {
                        let (size, count) = Self.directorySizeSync(url.path)
                        if size > 0 {
                            filePaths.append(url.path)
                            breakdown.append(PathStat(path: url.path, size: size, fileCount: count))
                            totalSize += size
                        }
                    }
                }

                guard !filePaths.isEmpty, totalSize > 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                var sorted = breakdown
                sorted.sort { $0.size > $1.size }

                continuation.resume(returning: CleanupCategory(
                    name: "Old Downloads (>\(olderThanDays)d)", icon: "arrow.down.circle.fill", color: .blue,
                    description: "\(filePaths.count) old items in Downloads — review before deleting",
                    group: .system, safetyLevel: .review,
                    paths: filePaths, breakdown: Array(sorted.prefix(60)),
                    deleteChildrenOnly: false,
                    size: totalSize, fileCount: filePaths.count,
                    isSelected: false
                ))
            }
        }
    }

    /// Old screenshots
    private func scanOldScreenshots() async -> CleanupCategory? {
        let olderThanDays = settingScreenshotThresholdDays
        let threshold = Date().addingTimeInterval(-Double(olderThanDays) * 86400)
        let dirs = ["\(Self.home)/Desktop", "\(Self.home)/Downloads", "\(Self.home)/Documents"]

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                var filePaths: [String] = []
                var breakdown: [PathStat] = []
                var totalSize: Int64 = 0

                for dir in dirs where fm.fileExists(atPath: dir) {
                    guard let contents = try? fm.contentsOfDirectory(
                        at: URL(fileURLWithPath: dir),
                        includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .totalFileAllocatedSizeKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }

                    for url in contents {
                        let name = url.lastPathComponent.lowercased()
                        guard name.hasPrefix("screenshot") || name.hasPrefix("screen shot") ||
                              name.hasPrefix("screen recording") || name.hasPrefix("cleanshot")
                        else { continue }
                        guard let rv = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .totalFileAllocatedSizeKey]),
                              rv.isRegularFile == true,
                              let modDate = rv.contentModificationDate, modDate < threshold else { continue }
                        let size = Int64(rv.totalFileAllocatedSize ?? rv.fileSize ?? 0)
                        guard size > 0 else { continue }

                        filePaths.append(url.path)
                        breakdown.append(PathStat(path: url.path, size: size, fileCount: 1))
                        totalSize += size
                    }
                }

                guard !filePaths.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                breakdown.sort { $0.size > $1.size }

                continuation.resume(returning: CleanupCategory(
                    name: "Old Screenshots (>\(olderThanDays)d)", icon: "camera.viewfinder", color: .teal,
                    description: "\(filePaths.count) old screenshots — likely safe to delete",
                    group: .system, safetyLevel: .review,
                    paths: filePaths, breakdown: breakdown,
                    deleteChildrenOnly: false,
                    size: totalSize, fileCount: filePaths.count,
                    isSelected: false
                ))
            }
        }
    }

    /// Old installer files in Downloads
    private func scanInstallerFiles() async -> CleanupCategory? {
        let olderThanDays = 14
        let threshold = Date().addingTimeInterval(-Double(olderThanDays) * 86400)
        let extensions: Set<String> = ["dmg", "pkg", "iso"]

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                let downloads = "\(Self.home)/Downloads"
                guard fm.fileExists(atPath: downloads) else {
                    continuation.resume(returning: nil)
                    return
                }

                var filePaths: [String] = []
                var breakdown: [PathStat] = []
                var totalSize: Int64 = 0

                guard let enumerator = fm.enumerator(
                    at: URL(fileURLWithPath: downloads),
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .totalFileAllocatedSizeKey],
                    options: [.skipsSubdirectoryDescendants],
                    errorHandler: nil
                ) else {
                    continuation.resume(returning: nil)
                    return
                }

                for case let url as URL in enumerator {
                    guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                    guard let rv = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .totalFileAllocatedSizeKey]),
                          rv.isRegularFile == true else { continue }
                    let size = Int64(rv.totalFileAllocatedSize ?? rv.fileSize ?? 0)
                    let modDate = rv.contentModificationDate ?? Date.distantPast
                    if modDate < threshold && size > 0 {
                        filePaths.append(url.path)
                        breakdown.append(PathStat(path: url.path, size: size, fileCount: 1))
                        totalSize += size
                    }
                }

                guard !filePaths.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                breakdown.sort { $0.size > $1.size }

                continuation.resume(returning: CleanupCategory(
                    name: "Old Installers (>\(olderThanDays)d)", icon: "doc.zipper", color: .brown,
                    description: "\(filePaths.count) old DMG/PKG files — already installed, safe to remove",
                    group: .system, safetyLevel: .review,
                    paths: filePaths, breakdown: breakdown,
                    deleteChildrenOnly: false,
                    size: totalSize, fileCount: filePaths.count,
                    isSelected: false
                ))
            }
        }
    }

    // MARK: - Unused Applications

    private func scanUnusedApplications() async -> CleanupCategory? {
        let thresholdDays = settingUnusedAppThresholdDays
        let threshold = Date().addingTimeInterval(-Double(thresholdDays) * 86400)

        let candidates: [(path: String, lastUsed: Date, displayName: String)] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                let appDirs = ["/Applications", "\(Self.home)/Applications"]
                var results: [(path: String, lastUsed: Date, displayName: String)] = []

                let systemApps: Set<String> = [
                    "Safari", "Mail", "Messages", "FaceTime", "Maps", "Photos",
                    "Music", "TV", "News", "Stocks", "Podcasts", "Books",
                    "App Store", "System Preferences", "System Settings",
                    "Preview", "TextEdit", "Calculator", "Dictionary",
                    "Font Book", "Keychain Access", "Terminal", "Activity Monitor",
                    "Console", "Disk Utility", "Migration Assistant", "Automator",
                    "Xcode", "Finder", "Siri", "Clock", "Weather", "Freeform",
                    "Passwords", "iPhone Mirroring", "Instruments", "FileMerge",
                    "Shortcuts", "Notes", "Reminders", "Calendar", "Contacts",
                    "Home", "Voice Memos", "Photo Booth", "Image Capture",
                    "Grapher", "Chess", "Stickies",
                ]

                // Get currently running app bundle IDs to exclude
                let runningBundleIDs = Self.getRunningAppBundleIDs()

                for dir in appDirs where fm.fileExists(atPath: dir) {
                    guard let contents = try? fm.contentsOfDirectory(
                        at: URL(fileURLWithPath: dir),
                        includingPropertiesForKeys: [.isPackageKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }

                    for url in contents where url.pathExtension == "app" {
                        let appName = url.deletingPathExtension().lastPathComponent
                        if systemApps.contains(appName) { continue }

                        // Skip currently running apps
                        if let bundleID = Bundle(url: url)?.bundleIdentifier,
                           runningBundleIDs.contains(bundleID) { continue }

                        // Multi-signal last-used detection
                        let lastUsed = Self.getBestLastUsedDate(for: url.path, appName: appName)

                        if let lastUsed = lastUsed, lastUsed < threshold {
                            results.append((url.path, lastUsed, appName))
                        }
                        // If we have NO signal at all, skip (don't assume unused)
                    }
                }

                continuation.resume(returning: results)
            }
        }

        guard !candidates.isEmpty else { return nil }

        var appPaths: [String] = []
        var breakdown: [PathStat] = []
        var totalSize: Int64 = 0
        var totalCount: Int = 0

        for candidate in candidates {
            if cancelRequested { break }
            let (size, count) = await directorySize(candidate.path)
            if size > 0 {
                appPaths.append(candidate.path)
                breakdown.append(PathStat(
                    path: candidate.path, size: size, fileCount: count,
                    lastAccessed: candidate.lastUsed
                ))
                totalSize += size
                totalCount += count
            }
        }

        guard totalSize > 0, !appPaths.isEmpty else { return nil }
        breakdown.sort { $0.size > $1.size }

        return CleanupCategory(
            name: "Unused Apps (>\(thresholdDays)d)", icon: "app.dashed", color: .gray,
            description: "\(appPaths.count) apps not opened in \(thresholdDays)+ days",
            group: .applications, safetyLevel: .caution,
            paths: appPaths, breakdown: breakdown,
            deleteChildrenOnly: false,
            size: totalSize, fileCount: totalCount,
            isSelected: false
        )
    }

    /// Multi-signal detection for app last-used date. Uses the most recent of:
    /// 1. Spotlight kMDItemLastUsedDate
    /// 2. contentAccessDate on the app bundle
    /// 3. Recent modification of app preferences plist
    /// 4. Recent modification of app support data
    private static func getBestLastUsedDate(for appPath: String, appName: String) -> Date? {
        var dates: [Date] = []

        // Signal 1: Spotlight metadata
        if let spotlightDate = getSpotlightLastUsedDate(for: appPath) {
            dates.append(spotlightDate)
        }

        // Signal 2: contentAccessDate on the app bundle
        let appURL = URL(fileURLWithPath: appPath)
        if let rv = try? appURL.resourceValues(forKeys: [.contentAccessDateKey]),
           let accessDate = rv.contentAccessDate {
            dates.append(accessDate)
        }

        // Signal 3: Check preferences plist modification
        if let bundleID = Bundle(url: appURL)?.bundleIdentifier {
            let prefsPath = "\(home)/Library/Preferences/\(bundleID).plist"
            if let attrs = try? FileManager.default.attributesOfItem(atPath: prefsPath),
               let modDate = attrs[.modificationDate] as? Date {
                dates.append(modDate)
            }

            // Signal 4: Check app support folder modification
            let supportPath = "\(home)/Library/Application Support/\(appName)"
            if let attrs = try? FileManager.default.attributesOfItem(atPath: supportPath),
               let modDate = attrs[.modificationDate] as? Date {
                dates.append(modDate)
            }

            // Also check support folder by bundle ID
            let supportPath2 = "\(home)/Library/Application Support/\(bundleID)"
            if let attrs = try? FileManager.default.attributesOfItem(atPath: supportPath2),
               let modDate = attrs[.modificationDate] as? Date {
                dates.append(modDate)
            }
        }

        // Return the most recent signal (most optimistic — if any signal says "used recently", trust it)
        return dates.max()
    }

    /// Get bundle IDs of all currently running applications
    private static func getRunningAppBundleIDs() -> Set<String> {
        var ids = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            if let bundleID = app.bundleIdentifier {
                ids.insert(bundleID)
            }
        }
        return ids
    }

    private static func getSpotlightLastUsedDate(for path: String) -> Date? {
        guard let output = runCommand("/usr/bin/mdls", arguments: ["-name", "kMDItemLastUsedDate", "-raw", path]) else {
            return nil
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "(null)" || trimmed.isEmpty { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: trimmed)
    }

    // MARK: - Docker CLI

    private func scanDockerImages() async -> CleanupCategory? {
        guard let dockerPath = Self.findDocker() else { return nil }
        guard let output = Self.runCommand(dockerPath, arguments: [
            "images", "--format", "{{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.ID}}\t{{.CreatedSince}}"
        ]) else { return nil }

        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        var breakdown: [PathStat] = []
        var totalSize: Int64 = 0

        for line in lines {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3 else { continue }
            let sizeBytes = Self.parseDockerSize(parts[1])
            totalSize += sizeBytes
            let created = parts.count > 3 ? parts[3] : ""
            breakdown.append(PathStat(
                path: "\(parts[0]) (\(parts[2].prefix(12))) — \(created)",
                size: sizeBytes, fileCount: 1
            ))
        }

        guard totalSize > 0 else { return nil }
        breakdown.sort { $0.size > $1.size }

        return CleanupCategory(
            name: "Docker Images", icon: "shippingbox.circle", color: .blue,
            description: "\(breakdown.count) images — prunes unused images",
            group: .docker, safetyLevel: .review,
            paths: [], breakdown: breakdown,
            deleteChildrenOnly: false, isDockerResource: true,
            dockerCleanCommand: ["image", "prune", "-a", "-f"],
            size: totalSize, fileCount: breakdown.count, isSelected: false
        )
    }

    private func scanDockerStoppedContainers() async -> CleanupCategory? {
        guard let dockerPath = Self.findDocker() else { return nil }
        guard let output = Self.runCommand(dockerPath, arguments: [
            "ps", "-a", "--filter", "status=exited",
            "--format", "{{.Names}}\t{{.Size}}\t{{.ID}}\t{{.Status}}"
        ]) else { return nil }

        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        var breakdown: [PathStat] = []
        var totalSize: Int64 = 0

        for line in lines {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3 else { continue }
            let sizeBytes = Self.parseDockerSize(parts[1])
            totalSize += sizeBytes
            let status = parts.count > 3 ? parts[3] : ""
            breakdown.append(PathStat(
                path: "\(parts[0]) (\(parts[2].prefix(12))) — \(status)",
                size: sizeBytes, fileCount: 1
            ))
        }

        guard !breakdown.isEmpty else { return nil }
        breakdown.sort { $0.size > $1.size }

        return CleanupCategory(
            name: "Docker Stopped Containers", icon: "stop.circle", color: .orange,
            description: "\(breakdown.count) stopped containers",
            group: .docker, safetyLevel: .safe,
            paths: [], breakdown: breakdown,
            deleteChildrenOnly: false, isDockerResource: true,
            dockerCleanCommand: ["container", "prune", "-f"],
            size: totalSize, fileCount: breakdown.count, isSelected: false
        )
    }

    private func scanDockerBuildCache() async -> CleanupCategory? {
        guard let dockerPath = Self.findDocker() else { return nil }
        guard let dfOutput = Self.runCommand(dockerPath, arguments: [
            "system", "df", "--format", "{{.Type}}\t{{.Size}}\t{{.Reclaimable}}"
        ]) else { return nil }

        for line in dfOutput.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 3 && parts[0] == "Build Cache" {
                let totalSize = Self.parseDockerSize(parts[1])
                guard totalSize > 0 else { return nil }
                return CleanupCategory(
                    name: "Docker Build Cache", icon: "hammer.circle", color: .teal,
                    description: "Build cache — \(parts[2]) reclaimable",
                    group: .docker, safetyLevel: .safe,
                    paths: [],
                    breakdown: [PathStat(path: "Build cache (\(parts[2]) reclaimable)", size: totalSize, fileCount: 1)],
                    deleteChildrenOnly: false, isDockerResource: true,
                    dockerCleanCommand: ["builder", "prune", "-f"],
                    size: totalSize, fileCount: 1, isSelected: false
                )
            }
        }
        return nil
    }

    private func runDockerClean(command: [String]) async {
        guard let dockerPath = Self.findDocker() else { return }
        _ = Self.runCommand(dockerPath, arguments: command)
    }

    // MARK: - node_modules

    private func scanNodeModules() async -> CleanupCategory? {
        let fm = FileManager.default
        var searchDirs = [
            "\(Self.home)/Projects", "\(Self.home)/Developer",
            "\(Self.home)/Documents", "\(Self.home)/Desktop",
            "\(Self.home)/GitHub", "\(Self.home)/repos",
            "\(Self.home)/code", "\(Self.home)/src",
            "\(Self.home)/dev", "\(Self.home)/workspace",
            "\(Self.home)/Work", "\(Self.home)/Sites",
        ]

        if let topLevel = try? fm.contentsOfDirectory(atPath: Self.home) {
            for dir in topLevel where !dir.hasPrefix(".") {
                let fullPath = (Self.home as NSString).appendingPathComponent(dir)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue,
                   !["Library", "Applications", "Music", "Movies", "Pictures",
                    "Downloads", "Public"].contains(dir),
                   !searchDirs.contains(fullPath) {
                    searchDirs.append(fullPath)
                }
            }
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                var found: [String] = []
                var breakdown: [PathStat] = []
                var totalSize: Int64 = 0
                var totalCount: Int = 0

                for searchDir in searchDirs where fm.fileExists(atPath: searchDir) {
                    Self.findNodeModulesRecursive(
                        in: searchDir, depth: 0, maxDepth: 6, fm: fm,
                        found: &found, breakdown: &breakdown,
                        totalSize: &totalSize, totalCount: &totalCount
                    )
                }

                guard !found.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                breakdown.sort { $0.size > $1.size }

                continuation.resume(returning: CleanupCategory(
                    name: "node_modules", icon: "shippingbox.fill", color: .green,
                    description: "\(found.count) node_modules — run npm install to restore",
                    group: .packageManagers, safetyLevel: .safe,
                    paths: found, breakdown: Array(breakdown.prefix(50)),
                    deleteChildrenOnly: false,
                    size: totalSize, fileCount: totalCount,
                    isSelected: true
                ))
            }
        }
    }

    private static func findNodeModulesRecursive(
        in dir: String, depth: Int, maxDepth: Int, fm: FileManager,
        found: inout [String], breakdown: inout [PathStat],
        totalSize: inout Int64, totalCount: inout Int
    ) {
        guard depth <= maxDepth else { return }
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }

        for entry in entries {
            let fullPath = (dir as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }

            if entry == "node_modules" {
                let (sz, ct) = directorySizeSync(fullPath)
                if sz > 1_000_000 {
                    found.append(fullPath)
                    breakdown.append(PathStat(path: fullPath, size: sz, fileCount: ct))
                    totalSize += sz
                    totalCount += ct
                }
            } else if !entry.hasPrefix(".") && entry != "Library" {
                findNodeModulesRecursive(
                    in: fullPath, depth: depth + 1, maxDepth: maxDepth, fm: fm,
                    found: &found, breakdown: &breakdown,
                    totalSize: &totalSize, totalCount: &totalCount
                )
            }
        }
    }

    // MARK: - Mail Attachments

    private func scanMailAttachments() async -> CleanupCategory? {
        let mailDir = "\(Self.home)/Library/Mail"
        let fm = FileManager.default
        guard fm.fileExists(atPath: mailDir) else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Mail Downloads contains cached attachments
                let attachmentsDir = "\(Self.home)/Library/Mail Downloads"
                var paths: [String] = []
                var breakdown: [PathStat] = []
                var totalSize: Int64 = 0
                var totalCount: Int = 0

                if fm.fileExists(atPath: attachmentsDir) {
                    let (sz, ct) = Self.directorySizeSync(attachmentsDir)
                    if sz > 100_000 {
                        paths.append(attachmentsDir)
                        breakdown.append(PathStat(path: attachmentsDir, size: sz, fileCount: ct))
                        totalSize += sz
                        totalCount += ct
                    }
                }

                // Also check Containers mail downloads
                let containerMail = "\(Self.home)/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
                if fm.fileExists(atPath: containerMail) {
                    let (sz, ct) = Self.directorySizeSync(containerMail)
                    if sz > 100_000 {
                        paths.append(containerMail)
                        breakdown.append(PathStat(path: containerMail, size: sz, fileCount: ct))
                        totalSize += sz
                        totalCount += ct
                    }
                }

                guard totalSize > 500_000, !paths.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: CleanupCategory(
                    name: "Mail Attachments", icon: "envelope.badge.shield.half.filled", color: .blue,
                    description: "Cached mail attachment downloads — re-downloaded from server",
                    group: .system, safetyLevel: .safe,
                    paths: paths, breakdown: breakdown,
                    deleteChildrenOnly: true,
                    size: totalSize, fileCount: totalCount,
                    isSelected: true
                ))
            }
        }
    }

    // MARK: - Orphaned App Data

    private func scanOrphanedAppData() async -> CleanupCategory? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                // Get list of installed app bundle IDs
                let installedBundleIDs = Self.getInstalledAppBundleIDs()

                var orphanPaths: [String] = []
                var breakdown: [PathStat] = []
                var totalSize: Int64 = 0
                var totalCount: Int = 0

                // Check ~/Library/Application Support for orphaned app data
                let supportDir = "\(Self.home)/Library/Application Support"
                if let entries = try? fm.contentsOfDirectory(atPath: supportDir) {
                    for entry in entries {
                        // Skip system/common directories
                        let skipNames: Set<String> = [
                            "com.apple.TCC", "com.apple.sharedfilelist",
                            "AddressBook", "CloudDocs", "CrashReporter",
                            "FileProvider", "Knowledge", "SyncServices",
                            "CallHistoryDB", "CallHistoryTransactions",
                            "Accounts", "iLifeMediaBrowser",
                        ]
                        if entry.hasPrefix("com.apple.") || skipNames.contains(entry) { continue }
                        // Skip our own app data
                        let ownID = Bundle.main.bundleIdentifier ?? "gk.SparkClean"
                        if entry == ownID || entry == "gk.SparkClean" || entry == "SparkClean" { continue }

                        // Check if this looks like a bundle ID or app name
                        let fullPath = (supportDir as NSString).appendingPathComponent(entry)
                        // If it matches a bundle ID pattern and the app isn't installed
                        if entry.contains(".") && entry.count > 5 {
                            if !installedBundleIDs.contains(entry) &&
                               !Self.hasMatchingApp(name: entry, bundleIDs: installedBundleIDs) {
                                let (sz, ct) = Self.directorySizeSync(fullPath)
                                if sz > 1_000_000 { // >1MB
                                    orphanPaths.append(fullPath)
                                    breakdown.append(PathStat(path: fullPath, size: sz, fileCount: ct))
                                    totalSize += sz
                                    totalCount += ct
                                }
                            }
                        }
                    }
                }

                // Check ~/Library/Preferences for orphaned plists
                let prefsDir = "\(Self.home)/Library/Preferences"
                // System plists that are NOT app leftovers (macOS services, agents, daemons)
                let systemPlistPrefixes: [String] = [
                    "com.apple.", "com.microsoft.", "group.",
                    "NSGlobalDomain", "Apple", "systemgroup.",
                ]
                let systemPlistNames: Set<String> = [
                    ".GlobalPreferences", ".GlobalPreferences_m",
                    "loginwindow", "pbs", "systempreferences",
                    "diagnostics_agent", "sharedfilelistd",
                    "ContextStoreAgent", "ScopedBookmarkAgent",
                    "MobileMeAccounts", "familycircled",
                    "mbuseragent", "icloudmailagent",
                    "knowledge-agent", "remindd",
                    "sharingd", "rapportd", "CloudPhotosConfiguration",
                    "symbolichotkeys", "spaces", "dock",
                    "HIToolbox", "universalaccess",
                    "embeddedBinaryValidationUtility",
                    "APMAnalyticsSuiteName", "APMExperimentSuiteName",
                    "WirelessRadioManagerModule", "CoreBluetooth",
                    "UserEventAgent-Aqua", "UserEventAgent-System",
                    "talagent", "cmfsyncagent",
                ]
                // Exclude our own app's bundle ID
                let ownBundlePrefix = Bundle.main.bundleIdentifier ?? "gk.SparkClean"

                if let entries = try? fm.contentsOfDirectory(atPath: prefsDir) {
                    for entry in entries where entry.hasSuffix(".plist") {
                        let bundleID = String(entry.dropLast(6)) // remove .plist
                        // Skip system prefixes
                        if systemPlistPrefixes.contains(where: { bundleID.hasPrefix($0) }) { continue }
                        // Skip known system plist names
                        if systemPlistNames.contains(bundleID) { continue }
                        // Skip our own app
                        if bundleID.hasPrefix(ownBundlePrefix) || bundleID == "gk.SparkClean" { continue }
                        // Skip plists that don't look like bundle IDs (no dots = likely system)
                        if !bundleID.contains(".") { continue }

                        if !installedBundleIDs.contains(bundleID) &&
                           !Self.hasMatchingApp(name: bundleID, bundleIDs: installedBundleIDs) {
                            let fullPath = (prefsDir as NSString).appendingPathComponent(entry)
                            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                               let sz = attrs[.size] as? Int64, sz > 0 {
                                orphanPaths.append(fullPath)
                                breakdown.append(PathStat(path: fullPath, size: sz, fileCount: 1))
                                totalSize += sz
                                totalCount += 1
                            }
                        }
                    }
                }

                guard totalSize > 1_000_000, !orphanPaths.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                breakdown.sort { $0.size > $1.size }

                continuation.resume(returning: CleanupCategory(
                    name: "App Leftovers", icon: "trash.slash", color: .purple,
                    description: "\(orphanPaths.count) leftover files from uninstalled apps",
                    group: .applications, safetyLevel: .review,
                    paths: orphanPaths, breakdown: Array(breakdown.prefix(60)),
                    deleteChildrenOnly: false,
                    size: totalSize, fileCount: totalCount,
                    isSelected: false
                ))
            }
        }
    }

    private static func getInstalledAppBundleIDs() -> Set<String> {
        let fm = FileManager.default
        var ids = Set<String>()
        for dir in ["/Applications", "\(home)/Applications"] {
            guard let contents = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: dir),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in contents where url.pathExtension == "app" {
                if let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
                    ids.insert(id)
                }
                // Also add the app name as a pseudo-ID
                ids.insert(url.deletingPathExtension().lastPathComponent)
            }
        }
        return ids
    }

    private static func hasMatchingApp(name: String, bundleIDs: Set<String>) -> Bool {
        let nameLower = name.lowercased()
        for bundleID in bundleIDs {
            let idLower = bundleID.lowercased()
            // Check if the name is a substring of a bundle ID or vice versa
            if idLower.contains(nameLower) || nameLower.contains(idLower) { return true }
        }
        // Also check if the name (minus domain prefix) matches an app name in the set
        // e.g. "org.mozilla.firefox" -> check if "firefox" is an app name
        let components = name.components(separatedBy: ".")
        if components.count >= 3, let appName = components.last, appName.count >= 4 {
            if bundleIDs.contains(where: { $0.lowercased() == appName.lowercased() }) { return true }
        }
        return false
    }

    // MARK: - Helpers

    static func findDocker() -> String? {
        for path in ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/usr/bin/docker"] {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    static func runCommand(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    static func parseDockerSize(_ str: String) -> Int64 {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        let pattern = /^([\d.]+)\s*(B|KB|MB|GB|TB|kB)/
        guard let match = trimmed.firstMatch(of: pattern) else { return 0 }
        let value = Double(match.1) ?? 0
        switch String(match.2).uppercased() {
        case "B": return Int64(value)
        case "KB": return Int64(value * 1_000)
        case "MB": return Int64(value * 1_000_000)
        case "GB": return Int64(value * 1_000_000_000)
        case "TB": return Int64(value * 1_000_000_000_000)
        default: return 0
        }
    }

    // MARK: - Export Report

    func exportReport() -> String {
        exportDetailedReport(verbose: false)
    }

    func exportDetailedReport(verbose: Bool) -> String {
        let dateStr = Date().formatted(date: .long, time: .standard)
        var r = """
        ╔═══════════════════════════════════════════════════════════════════╗
        ║  SparkClean - Detailed Scan Audit Report                        ║
        ║  Generated: \(dateStr)\(String(repeating: " ", count: max(0, 40 - dateStr.count)))║
        ╚═══════════════════════════════════════════════════════════════════╝

        """

        // System info
        r += "SYSTEM INFORMATION\n"
        r += String(repeating: "─", count: 60) + "\n"
        r += "  macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        r += "  Machine:       \(Self.runCommand("/usr/sbin/sysctl", arguments: ["-n", "hw.model"]) ?? "Unknown")\n"
        r += "  User:          \(NSUserName())\n"
        r += "  Home:          \(Self.home)\n\n"

        if let disk = diskUsage {
            r += "DISK USAGE\n"
            r += String(repeating: "─", count: 60) + "\n"
            r += "  Total Space:     \(Self.formatBytes(disk.totalSpace))\n"
            r += "  Used Space:      \(Self.formatBytes(disk.usedSpace)) (\(String(format: "%.1f%%", disk.usedPercentage * 100)))\n"
            r += "  Free Space:      \(Self.formatBytes(disk.freeSpace))\n"
            r += "  Purgeable:       \(Self.formatBytes(disk.purgeableSpace))\n"
            r += "  Reclaimable:     \(Self.formatBytes(overallSize))\n"
            r += "  Selected:        \(Self.formatBytes(totalSize))\n\n"
        }

        if let summary = lastScanSummary {
            r += "SCAN SUMMARY\n"
            r += String(repeating: "─", count: 60) + "\n"
            r += "  Categories:      \(summary.totalCategories)\n"
            r += "  Total Files:     \(summary.totalFiles)\n"
            r += "  Total Size:      \(Self.formatBytes(summary.totalSize))\n"
            r += "  Scan Duration:   \(String(format: "%.2f", summary.scanDuration))s\n"
            r += "  Scan Time:       \(summary.timestamp.formatted(date: .abbreviated, time: .standard))\n\n"
        }

        r += "═══════════════════════════════════════════════════════════════════\n"
        r += "DETAILED FINDINGS BY CATEGORY\n"
        r += "═══════════════════════════════════════════════════════════════════\n\n"

        for group in CategoryGroup.allCases {
            let groupCats = categoriesForGroup(group)
            guard !groupCats.isEmpty else { continue }

            r += "┌─── \(group.rawValue.uppercased()) ─── \(Self.formatBytes(sizeForGroup(group))) total\n"
            r += "│\n"

            for (catIdx, cat) in groupCats.enumerated() {
                let isLast = catIdx == groupCats.count - 1
                let prefix = isLast ? "└" : "├"
                let childPrefix = isLast ? "  " : "│ "
                let marker = cat.isSelected ? "✓" : "○"

                r += "\(prefix)── [\(marker)] \(cat.name)\n"
                r += "\(childPrefix)   Safety:      \(cat.safetyLevel.rawValue) — \(cat.safetyLevel.label)\n"
                r += "\(childPrefix)   Description: \(cat.description)\n"
                r += "\(childPrefix)   Total Size:  \(Self.formatBytes(cat.size))\n"
                r += "\(childPrefix)   File Count:  \(cat.fileCount)\n"
                r += "\(childPrefix)   Selected:    \(cat.isSelected ? "Yes" : "No")\n"

                if cat.isDockerResource {
                    r += "\(childPrefix)   Type:        Docker resource (cleaned via Docker CLI)\n"
                    if let cmd = cat.dockerCleanCommand {
                        r += "\(childPrefix)   Command:     docker \(cmd.joined(separator: " "))\n"
                    }
                }

                if !cat.paths.isEmpty {
                    r += "\(childPrefix)   Paths:\n"
                    for path in cat.paths {
                        r += "\(childPrefix)     → \(path)\n"
                    }
                }

                // Detailed breakdown — ALL entries, not just top 5
                if !cat.breakdown.isEmpty {
                    r += "\(childPrefix)   Breakdown (\(cat.breakdown.count) entries):\n"
                    for stat in cat.breakdown {
                        let name = (stat.path as NSString).lastPathComponent
                        let dir = (stat.path as NSString).deletingLastPathComponent
                        r += "\(childPrefix)     ┊ \(Self.formatBytes(stat.size).padding(toLength: 10, withPad: " ", startingAt: 0)) \(name)\n"
                        if verbose {
                            r += "\(childPrefix)     ┊            Path: \(stat.path)\n"
                            r += "\(childPrefix)     ┊            Dir:  \(dir)\n"
                            r += "\(childPrefix)     ┊            Files: \(stat.fileCount)\n"
                            if let accessed = stat.lastAccessed {
                                r += "\(childPrefix)     ┊            Last Accessed: \(accessed.formatted(date: .abbreviated, time: .standard))\n"
                            }
                        }
                    }
                }

                r += "\(childPrefix)\n"
            }
            r += "\n"
        }

        // Safety summary
        r += "═══════════════════════════════════════════════════════════════════\n"
        r += "SAFETY AUDIT SUMMARY\n"
        r += "═══════════════════════════════════════════════════════════════════\n\n"

        let safeCats = categories.filter { $0.safetyLevel == .safe }
        let reviewCats = categories.filter { $0.safetyLevel == .review }
        let cautionCats = categories.filter { $0.safetyLevel == .caution }

        let safeSize = safeCats.reduce(0 as Int64) { $0 + $1.size }
        let reviewSize = reviewCats.reduce(0 as Int64) { $0 + $1.size }
        let cautionSize = cautionCats.reduce(0 as Int64) { $0 + $1.size }

        r += "  ✓ SAFE (\(safeCats.count) categories, \(Self.formatBytes(safeSize))):\n"
        r += "    Caches, temp files, logs — automatically rebuilt. No risk of data loss.\n"
        for cat in safeCats {
            r += "    • \(cat.name): \(Self.formatBytes(cat.size))\n"
        }

        r += "\n  ⚠ REVIEW (\(reviewCats.count) categories, \(Self.formatBytes(reviewSize))):\n"
        r += "    User files that may be wanted — review before deleting.\n"
        for cat in reviewCats {
            r += "    • \(cat.name): \(Self.formatBytes(cat.size))\n"
        }

        r += "\n  ✕ CAUTION (\(cautionCats.count) categories, \(Self.formatBytes(cautionSize))):\n"
        r += "    App data or system files — could cause issues if deleted.\n"
        for cat in cautionCats {
            r += "    • \(cat.name): \(Self.formatBytes(cat.size))\n"
        }

        r += "\n═══════════════════════════════════════════════════════════════════\n"
        r += "END OF REPORT\n"
        r += "═══════════════════════════════════════════════════════════════════\n"

        return r
    }

    // MARK: - Formatting

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
