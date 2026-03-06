//
//  SettingsView.swift
//  SparkClean
//
//  Created by George Khananaev on 3/6/26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("scanNodeModules") private var scanNodeModules = true
    @AppStorage("scanDocker") private var scanDocker = true
    @AppStorage("scanUnusedApps") private var scanUnusedApps = true
    @AppStorage("unusedAppThresholdDays") private var unusedAppThresholdDays = 90
    @AppStorage("largeFileThresholdMB") private var largeFileThresholdMB = 50
    @AppStorage("oldFileThresholdDays") private var oldFileThresholdDays = 30
    @AppStorage("screenshotThresholdDays") private var screenshotThresholdDays = 30
    @AppStorage("preferTrash") private var preferTrash = true

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            scanTab
                .tabItem {
                    Label("Scanning", systemImage: "magnifyingglass")
                }

            cleanupTab
                .tabItem {
                    Label("Cleanup", systemImage: "trash")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 340)
    }

    // MARK: General

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Scan Docker resources", isOn: $scanDocker)
                Toggle("Scan node_modules directories", isOn: $scanNodeModules)
                Toggle("Detect unused applications", isOn: $scanUnusedApps)
            } header: {
                Text("Smart Scans")
            } footer: {
                Text("These scans may take longer but find additional reclaimable space.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: Scanning

    private var scanTab: some View {
        Form {
            Section("Thresholds") {
                HStack {
                    Text("Unused app threshold")
                    Spacer()
                    Picker("", selection: $unusedAppThresholdDays) {
                        Text("30 days").tag(30)
                        Text("60 days").tag(60)
                        Text("90 days").tag(90)
                        Text("180 days").tag(180)
                        Text("365 days").tag(365)
                    }
                    .frame(width: 120)
                }

                HStack {
                    Text("Large file minimum size")
                    Spacer()
                    Picker("", selection: $largeFileThresholdMB) {
                        Text("25 MB").tag(25)
                        Text("50 MB").tag(50)
                        Text("100 MB").tag(100)
                        Text("250 MB").tag(250)
                        Text("500 MB").tag(500)
                    }
                    .frame(width: 120)
                }

                HStack {
                    Text("Old file threshold")
                    Spacer()
                    Picker("", selection: $oldFileThresholdDays) {
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                        Text("60 days").tag(60)
                        Text("90 days").tag(90)
                    }
                    .frame(width: 120)
                }

                HStack {
                    Text("Old screenshot threshold")
                    Spacer()
                    Picker("", selection: $screenshotThresholdDays) {
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                        Text("60 days").tag(60)
                    }
                    .frame(width: 120)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: Cleanup

    private var cleanupTab: some View {
        Form {
            Section {
                Toggle("Move files to Trash instead of deleting permanently", isOn: $preferTrash)
            } header: {
                Text("Deletion Behavior")
            } footer: {
                Text("When enabled, files are moved to Trash first. If that fails, they are deleted permanently.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: About

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("SparkClean")
                .font(.title2)
                .fontWeight(.bold)

            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Mac Storage & Cache Cleaner.\nScans caches, temp files, Docker resources,\ndev tools, browsers, and more.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Text("Created by George Khananaev")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    SettingsView()
}
