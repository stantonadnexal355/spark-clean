# SparkClean v1.0.0

A macOS storage and cache cleaner built with SwiftUI.

## Features

- **Deep Scan** - Scans caches, temp files, Docker resources, developer tools, browsers, package managers, and more
- **Category Groups** - Organizes findings into System, Browsers, Developer Tools, Package Managers, Docker, and Applications
- **Safety Levels** - Each category is labeled Safe, Review, or Caution so you know what's safe to delete
- **App Uninstaller** - Find installed apps and all their related data (caches, preferences, containers, logs, etc.) for complete removal
- **Disk Usage Overview** - Visual breakdown of disk space with reclaimable space highlighted
- **Export Reports** - Generate summary or detailed audit reports of scan results
- **Configurable** - Adjustable thresholds for unused apps, large files, old files, and screenshots

## Requirements

- macOS 14.0+
- Xcode 16.0+

## Getting Started

1. Clone the repository
2. Open `SparkClean.xcodeproj` in Xcode
3. Select the **SparkClean** scheme
4. Click **Run** (Cmd+R)

### Command Line Build

```bash
xcodebuild -project SparkClean.xcodeproj -scheme SparkClean -configuration Release build
```

After building, launch the app with:

```bash
open ~/Library/Developer/Xcode/DerivedData/SparkClean-*/Build/Products/Release/SparkClean.app
```

## Author

George Khananaev
