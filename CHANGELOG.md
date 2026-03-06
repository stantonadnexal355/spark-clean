# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/), [SemVer](https://semver.org/)

## [Unreleased]

### Added
- **app**: Custom About dialog with system info, build details, and Copy Info button
- **app**: Support menu with Help, Contact Support, Report a Bug, Privacy Policy, What's New
- **app**: Selection menu with Select All, Deselect All, Select Safe Only shortcuts
- **app**: Scan Now (Cmd+R) and Export Report (Cmd+E) keyboard shortcuts
- **ui**: Onboarding flow for first-time users
- **ui**: What's New view with version-based display
- **ui**: Help sheet with usage guide
- **ui**: Privacy Policy view
- **ui**: Clean progress bar in sidebar
- **ui**: Partial scan banner when scan is cancelled
- **ui**: Smart recommendation banner for Quick Clean
- **ui**: Clean complete dialog with Open Trash and Show Errors buttons
- **cleanup**: Error tracking for clean operations with per-category progress
- **cleanup**: Partial scan results preserved on cancel instead of discarding
- **models**: ScanConstants enum with extracted magic numbers
- **models**: ReleaseNote struct for changelog display
- **models**: Stable path-based SwiftUI identifiers replacing random UUIDs
- **project**: Info.plist with privacy usage descriptions for folder access
- **dashboard**: Disk usage bar tooltip and accessibility labels
- **ui**: Safety badge tooltips with detailed explanations
- **ui**: Accessibility labels on category rows, badges, and buttons

### Changed
- **cleanup**: Thread safety with OSAllocatedUnfairLock for scannedPaths and cancelRequested
- **cleanup**: autoreleasepool in cache scanning loops for memory management
- **cleanup**: Replaced try? with do/catch for proper error collection during clean
- **cleanup**: Fixed node_modules depth check (guard depth < maxDepth)
- **settings**: Enhanced About tab with version, system info, and contact links
- **settings**: Version display shows only version number without build number

### Fixed
- **uninstaller**: Fixed inverted trash fallback logic (was != nil, now do/catch)
- **uninstaller**: Added running app termination check before uninstall
- **app**: Fixed Help menu triggering macOS "Help isn't available" system message
- **app**: Fixed version display showing unwanted build number "(1)"

## [1.0.0] - 2026-03-06

### Added
- **app**: Rename project from MacSimpleCleanup to SparkClean
- **cleanup**: Disk cleanup scanning and file management
- **uninstaller**: App uninstaller feature
- **settings**: Settings view for user preferences
- **dashboard**: Dashboard components for stats display
- **models**: Data models for cleanup categories and items
- **assets**: Custom app icon set with all required sizes
- **project**: App entitlements and .gitignore configuration
