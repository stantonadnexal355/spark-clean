//
//  SparkCleanTests.swift
//  SparkCleanTests
//
//  Created by George Khananaev on 3/6/26.
//

import Testing
import Foundation
import SwiftUI
@testable import SparkClean

// MARK: - Format Tests

struct FormatTests {

    @Test func formatBytesZero() {
        let result = CleanupManager.formatBytes(0)
        #expect(!result.isEmpty)
    }

    @Test func formatBytesKB() {
        let result = CleanupManager.formatBytes(1024)
        let containsKB = result.contains("KB") || result.contains("kB")
        #expect(containsKB)
    }

    @Test func formatBytesMB() {
        let result = CleanupManager.formatBytes(1_048_576)
        #expect(result.contains("1") && result.contains("MB"))
    }

    @Test func formatBytesGB() {
        let result = CleanupManager.formatBytes(1_073_741_824)
        #expect(result.contains("1") && result.contains("GB"))
    }

    @Test func formatBytesNegative() {
        let result = CleanupManager.formatBytes(-1)
        #expect(!result.isEmpty)
    }
}

// MARK: - Safety Level Tests

struct SafetyLevelTests {

    @Test func safetyLevelLabels() {
        #expect(SafetyLevel.safe.label == "Safe to delete")
        #expect(SafetyLevel.review.label == "Review before deleting")
        #expect(SafetyLevel.caution.label == "Use caution")
    }

    @Test func safetyLevelIcons() {
        #expect(!SafetyLevel.safe.icon.isEmpty)
        #expect(!SafetyLevel.review.icon.isEmpty)
        #expect(!SafetyLevel.caution.icon.isEmpty)
    }

    @Test func safetyLevelRawValues() {
        #expect(SafetyLevel.safe.rawValue == "Safe")
        #expect(SafetyLevel.review.rawValue == "Review")
        #expect(SafetyLevel.caution.rawValue == "Caution")
    }
}

// MARK: - Category Group Tests

struct CategoryGroupTests {

    @Test func allCasesExist() {
        #expect(CategoryGroup.allCases.count == 6)
    }

    @Test func groupIcons() {
        for group in CategoryGroup.allCases {
            #expect(!group.icon.isEmpty)
        }
    }

    @Test func groupIdentifiers() {
        for group in CategoryGroup.allCases {
            #expect(group.id == group.rawValue)
        }
    }
}

// MARK: - CleanupManager Logic Tests

@MainActor
struct CleanupManagerLogicTests {

    @Test func initialState() {
        let manager = CleanupManager()
        #expect(manager.categories.isEmpty)
        #expect(!manager.isScanning)
        #expect(!manager.scanComplete)
        #expect(!manager.isCleaning)
        #expect(!manager.cleanComplete)
        #expect(manager.totalSize == 0)
        #expect(manager.totalFiles == 0)
        #expect(manager.overallSize == 0)
        #expect(manager.selectedCategoryCount == 0)
    }

    @Test func selectAllDeselectAll() {
        let manager = CleanupManager()
        manager.categories = [
            makeCategory(name: "A", selected: false),
            makeCategory(name: "B", selected: false),
        ]
        manager.selectAll()
        let allSelected = manager.categories.allSatisfy(\.isSelected)
        #expect(allSelected)

        manager.deselectAll()
        let noneSelected = manager.categories.allSatisfy { !$0.isSelected }
        #expect(noneSelected)
    }

    @Test func selectSafeOnly() {
        let manager = CleanupManager()
        manager.categories = [
            makeCategory(name: "Safe", safetyLevel: .safe, selected: false),
            makeCategory(name: "Review", safetyLevel: .review, selected: true),
            makeCategory(name: "Caution", safetyLevel: .caution, selected: true),
        ]
        manager.selectSafeOnly()
        #expect(manager.categories[0].isSelected == true)
        #expect(manager.categories[1].isSelected == false)
        #expect(manager.categories[2].isSelected == false)
    }

    @Test func selectAllInGroup() {
        let manager = CleanupManager()
        manager.categories = [
            makeCategory(name: "A", group: .system, selected: false),
            makeCategory(name: "B", group: .browsers, selected: false),
        ]
        manager.selectAll(in: .system)
        #expect(manager.categories[0].isSelected == true)
        #expect(manager.categories[1].isSelected == false)
    }

    @Test func deselectAllInGroup() {
        let manager = CleanupManager()
        manager.categories = [
            makeCategory(name: "A", group: .system, selected: true),
            makeCategory(name: "B", group: .browsers, selected: true),
        ]
        manager.deselectAll(in: .system)
        #expect(manager.categories[0].isSelected == false)
        #expect(manager.categories[1].isSelected == true)
    }

    @Test func totalSizeCalculation() {
        let manager = CleanupManager()
        manager.categories = [
            makeCategory(name: "A", size: 1000, selected: true),
            makeCategory(name: "B", size: 2000, selected: true),
            makeCategory(name: "C", size: 3000, selected: false),
        ]
        #expect(manager.totalSize == 3000)
        #expect(manager.overallSize == 6000)
        #expect(manager.selectedCategoryCount == 2)
    }

    @Test func filteredCategories() {
        let manager = CleanupManager()
        manager.categories = [
            makeCategory(name: "Safari Cache"),
            makeCategory(name: "Chrome Cache"),
            makeCategory(name: "Xcode Derived Data"),
        ]

        manager.searchQuery = "cache"
        #expect(manager.filteredCategories.count == 2)

        manager.searchQuery = "xcode"
        #expect(manager.filteredCategories.count == 1)

        manager.searchQuery = ""
        #expect(manager.filteredCategories.count == 3)
    }

    @Test func categoriesForGroup() {
        let manager = CleanupManager()
        manager.categories = [
            makeCategory(name: "A", group: .system),
            makeCategory(name: "B", group: .system),
            makeCategory(name: "C", group: .browsers),
        ]
        #expect(manager.categoriesForGroup(.system).count == 2)
        #expect(manager.categoriesForGroup(.browsers).count == 1)
        #expect(manager.categoriesForGroup(.docker).count == 0)
    }

    @Test func sizeForGroup() {
        let manager = CleanupManager()
        manager.categories = [
            makeCategory(name: "A", group: .system, size: 1000),
            makeCategory(name: "B", group: .system, size: 2000),
            makeCategory(name: "C", group: .browsers, size: 500),
        ]
        #expect(manager.sizeForGroup(.system) == 3000)
        #expect(manager.sizeForGroup(.browsers) == 500)
    }

    @Test func diskUsageFetch() {
        let manager = CleanupManager()
        manager.fetchDiskUsage()
        #expect(manager.diskUsage != nil)
        #expect(manager.diskUsage!.totalSpace > 0)
        #expect(manager.diskUsage!.freeSpace > 0)
        #expect(manager.diskUsage!.usedPercentage > 0)
        #expect(manager.diskUsage!.usedPercentage < 1)
    }

    @Test func exportReport() {
        let manager = CleanupManager()
        manager.categories = [
            makeCategory(name: "Test Category", group: .system, size: 1024),
        ]
        let report = manager.exportReport()
        #expect(report.contains("Test Category"))
        #expect(report.contains("System"))
    }

    // MARK: Helpers

    private func makeCategory(
        name: String,
        group: CategoryGroup = .system,
        safetyLevel: SafetyLevel = .safe,
        size: Int64 = 0,
        selected: Bool = true
    ) -> CleanupCategory {
        CleanupCategory(
            name: name, icon: "folder", color: .blue,
            description: "Test", group: group, safetyLevel: safetyLevel,
            paths: [], size: size, isSelected: selected
        )
    }
}

// MARK: - Model Tests

struct ModelTests {

    @Test func pathStatIdentifiable() {
        let stat = PathStat(path: "/test", size: 100, fileCount: 5)
        #expect(!stat.id.uuidString.isEmpty)
        #expect(stat.path == "/test")
        #expect(stat.size == 100)
        #expect(stat.fileCount == 5)
    }

    @Test func diskUsagePercentage() {
        let info = DiskUsageInfo(totalSpace: 1000, usedSpace: 750, freeSpace: 250, purgeableSpace: 0)
        #expect(info.usedPercentage == 0.75)
    }

    @Test func diskUsagePercentageZeroTotal() {
        let info = DiskUsageInfo(totalSpace: 0, usedSpace: 0, freeSpace: 0, purgeableSpace: 0)
        #expect(info.usedPercentage == 0)
    }

    @Test func scanSummary() {
        let summary = ScanSummary(
            totalCategories: 5, totalSize: 1000, totalFiles: 50,
            scanDuration: 2.5, timestamp: Date()
        )
        #expect(summary.totalCategories == 5)
        #expect(summary.totalSize == 1000)
        #expect(summary.scanDuration == 2.5)
    }

    @MainActor @Test func sidebarItemEquality() {
        #expect(SidebarItem.dashboard == SidebarItem.dashboard)
        #expect(SidebarItem.group(.system) == SidebarItem.group(.system))
        #expect(SidebarItem.group(.system) != SidebarItem.group(.browsers))
        #expect(SidebarItem.dashboard != SidebarItem.group(.system))
    }
}

// MARK: - Docker Size Parser Tests

struct DockerSizeParserTests {

    @Test func findDockerPath() {
        _ = CleanupManager.findDocker()
    }

    @Test func parseDockerSizeBytes() {
        #expect(CleanupManager.parseDockerSize("100B") == 100)
    }

    @Test func parseDockerSizeKB() {
        #expect(CleanupManager.parseDockerSize("1.5KB") == 1500)
        #expect(CleanupManager.parseDockerSize("1.5 kB") == 1500)
    }

    @Test func parseDockerSizeMB() {
        #expect(CleanupManager.parseDockerSize("256MB") == 256_000_000)
        #expect(CleanupManager.parseDockerSize("1.2 MB") == 1_200_000)
    }

    @Test func parseDockerSizeGB() {
        #expect(CleanupManager.parseDockerSize("2.5GB") == 2_500_000_000)
    }

    @Test func parseDockerSizeInvalid() {
        #expect(CleanupManager.parseDockerSize("") == 0)
        #expect(CleanupManager.parseDockerSize("invalid") == 0)
    }
}
