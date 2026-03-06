//
//  CategoryGroupDetailView.swift
//  SparkClean
//
//  Created by George Khananaev on 3/6/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CategoryGroupDetailView: View {
    @Bindable var manager: CleanupManager
    let group: CategoryGroup
    @Binding var showCleanAlert: Bool

    private var groupCategories: [CleanupCategory] {
        manager.categoriesForGroup(group)
    }

    private var groupSize: Int64 {
        groupCategories.reduce(0) { $0 + $1.size }
    }

    private var selectedSize: Int64 {
        groupCategories.filter(\.isSelected).reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: group.icon)
                    .font(.title2)
                    .foregroundStyle(group.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.rawValue)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("\(groupCategories.count) categories · \(CleanupManager.formatBytes(groupSize)) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button("Select All") { manager.selectAll(in: group) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                    Button("Deselect All") { manager.deselectAll(in: group) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(groupCategories) { category in
                        CategoryRowView(
                            category: category,
                            isSelected: Binding(
                                get: { manager.categories.first(where: { $0.id == category.id })?.isSelected ?? false },
                                set: { newValue in
                                    if let idx = manager.categories.firstIndex(where: { $0.id == category.id }) {
                                        manager.categories[idx].isSelected = newValue
                                    }
                                }
                            )
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected: \(CleanupManager.formatBytes(selectedSize))")
                        .font(.system(size: 12, weight: .medium))
                    Text("\(groupCategories.filter(\.isSelected).count) of \(groupCategories.count) categories")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showCleanAlert = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Clean Selected")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(manager.isScanning || manager.isCleaning || selectedSize == 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - Category Row

struct CategoryRowView: View {
    let category: CleanupCategory
    @Binding var isSelected: Bool
    @State private var isHovered = false
    @State private var showDetails = false

    var body: some View {
        HStack(spacing: 14) {
            Toggle("", isOn: $isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(category.color.gradient.opacity(0.15))
                    .frame(width: 38, height: 38)

                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(category.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(category.name)
                    .font(.system(size: 13, weight: .medium))

                Text("\(category.description) · \(category.fileCount) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 3) {
                Image(systemName: category.safetyLevel.icon)
                    .font(.system(size: 9))
                Text(category.safetyLevel.rawValue)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(category.safetyLevel.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(category.safetyLevel.color.opacity(0.12))
            )
            .help(category.safetyLevel.label)

            if category.isDockerResource {
                Image(systemName: "cube.box")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Docker resource — cleaned via Docker CLI")
            }

            Button {
                showDetails = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Show detailed breakdown")
            .popover(isPresented: $showDetails) {
                PathBreakdownView(category: category)
                    .frame(width: 540, height: 380)
            }

            SizeLabel(size: category.size, color: category.color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        )
        .onHover { isHovered = $0 }
        .opacity(isSelected ? 1.0 : 0.55)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Path Breakdown

struct PathBreakdownView: View {
    let category: CleanupCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: category.icon)
                    .foregroundStyle(category.color)
                Text(category.name)
                    .font(.headline)
                Spacer()
                Text("\(category.fileCount) files · \(CleanupManager.formatBytes(category.size))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !category.description.isEmpty {
                Text(category.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if category.breakdown.isEmpty {
                VStack {
                    Spacer()
                    Text("No detailed breakdown available")
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(category.breakdown) { stat in
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text((stat.path as NSString).lastPathComponent)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                    Text((stat.path as NSString).deletingLastPathComponent)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(CleanupManager.formatBytes(stat.size))
                                        .font(.system(size: 12, weight: .semibold))
                                    if stat.fileCount > 0 {
                                        Text("\(stat.fileCount) file\(stat.fileCount == 1 ? "" : "s")")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let accessed = stat.lastAccessed {
                                        Text("Last: \(accessed.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Button("Reveal") {
                                    let url = URL(fileURLWithPath: stat.path)
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.primary.opacity(0.03))
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Export Report View

struct ExportReportView: View {
    let report: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Scan Report")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                Text(report)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
            )

            HStack {
                Spacer()
                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
                .buttonStyle(.borderedProminent)

                Button("Save...") {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.plainText]
                    panel.nameFieldStringValue = "MacCleanup_Report_\(Date().formatted(date: .numeric, time: .omitted)).txt"
                    if panel.runModal() == .OK, let url = panel.url {
                        try? report.write(to: url, atomically: true, encoding: .utf8)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(width: 600, height: 500)
    }
}
