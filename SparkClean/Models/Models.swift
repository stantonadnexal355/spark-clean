//
//  Models.swift
//  SparkClean
//
//  Created by George Khananaev on 3/6/26.
//

import Foundation
import SwiftUI

// MARK: - Category Group

enum CategoryGroup: String, CaseIterable, Identifiable, Codable {
    case system = "System"
    case browsers = "Browsers"
    case developer = "Developer Tools"
    case packageManagers = "Package Managers"
    case docker = "Docker"
    case applications = "Applications"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .system: "gearshape.2"
        case .browsers: "globe"
        case .developer: "hammer"
        case .packageManagers: "shippingbox"
        case .docker: "cube.box"
        case .applications: "app.badge.checkmark"
        }
    }

    var color: Color {
        switch self {
        case .system: .blue
        case .browsers: .orange
        case .developer: .pink
        case .packageManagers: .green
        case .docker: .cyan
        case .applications: .purple
        }
    }
}

// MARK: - Safety Level

enum SafetyLevel: String, Codable {
    case safe = "Safe"
    case review = "Review"
    case caution = "Caution"

    var color: Color {
        switch self {
        case .safe: .green
        case .review: .orange
        case .caution: .red
        }
    }

    var icon: String {
        switch self {
        case .safe: "checkmark.shield.fill"
        case .review: "eye.fill"
        case .caution: "exclamationmark.triangle.fill"
        }
    }

    var label: String {
        switch self {
        case .safe: "Safe to delete"
        case .review: "Review before deleting"
        case .caution: "Use caution"
        }
    }
}

// MARK: - Constants

enum ScanConstants {
    static let minCacheSizeBytes: Int64 = 100_000       // 100KB
    static let minSystemCacheSizeBytes: Int64 = 500_000 // 500KB
    static let minNodeModulesSizeBytes: Int64 = 1_000_000 // 1MB
    static let minCacheTotalBytes: Int64 = 500_000      // 500KB
    static let minSystemCacheTotalBytes: Int64 = 1_000_000 // 1MB
    static let installerFileAgeDays = 14
    static let secondsPerDay: Double = 86400
    static let maxBreakdownEntries = 60
    static let maxNodeModulesEntries = 50
}

// MARK: - Data Models

struct PathStat: Identifiable {
    var id: String { path }
    let path: String
    let size: Int64
    let fileCount: Int
    var children: [PathStat] = []
    var lastAccessed: Date? = nil
}

struct CleanupCategory: Identifiable, Equatable {
    static func == (lhs: CleanupCategory, rhs: CleanupCategory) -> Bool {
        lhs.id == rhs.id
    }

    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let description: String
    let group: CategoryGroup
    let safetyLevel: SafetyLevel
    var paths: [String]
    var breakdown: [PathStat] = []
    var deleteChildrenOnly: Bool = true
    var isDockerResource: Bool = false
    var dockerCleanCommand: [String]? = nil
    var size: Int64 = 0
    var fileCount: Int = 0
    var isSelected: Bool = true
    var exists: Bool = true
}

struct ScanDefinition {
    let name: String
    let icon: String
    let color: Color
    let description: String
    let group: CategoryGroup
    let safetyLevel: SafetyLevel
    let pathResolver: () -> [String]
    let defaultSelected: Bool

    init(
        name: String, icon: String, color: Color,
        description: String, group: CategoryGroup,
        safetyLevel: SafetyLevel = .safe,
        defaultSelected: Bool = true,
        pathResolver: @escaping () -> [String]
    ) {
        self.name = name; self.icon = icon; self.color = color
        self.description = description; self.group = group
        self.safetyLevel = safetyLevel
        self.defaultSelected = defaultSelected
        self.pathResolver = pathResolver
    }
}

struct DiskUsageInfo {
    let totalSpace: Int64
    let usedSpace: Int64
    let freeSpace: Int64
    let purgeableSpace: Int64

    var usedPercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace)
    }
}

struct ScanSummary {
    let totalCategories: Int
    let totalSize: Int64
    let totalFiles: Int
    let scanDuration: TimeInterval
    let timestamp: Date
    var wasPartial: Bool = false
}

// MARK: - Sidebar Selection

enum SidebarItem: Hashable {
    case dashboard
    case group(CategoryGroup)
    case uninstaller
}

// MARK: - App Info (Uninstaller)

struct AppInfo: Identifiable, Equatable {
    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.id == rhs.id
    }

    let id = UUID()
    let name: String
    let bundleID: String
    let path: String
    let icon: NSImage?
    var appSize: Int64 = 0
    var relatedPaths: [RelatedPath] = []
    var totalRelatedSize: Int64 = 0

    var totalSize: Int64 {
        appSize + totalRelatedSize
    }
}

struct RelatedPath: Identifiable {
    let id = UUID()
    let path: String
    let category: String
    let size: Int64
    let fileCount: Int
}

enum AppSortOrder: String, CaseIterable {
    case name = "Name"
    case totalSize = "Total Size"
    case appSize = "App Size"
    case relatedSize = "Related Data"
}

// MARK: - Release Notes

struct ReleaseNote: Identifiable {
    let id = UUID()
    let version: String
    let date: String
    let notes: [String]
}
