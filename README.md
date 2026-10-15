# CookieCleaner for Safari

[![Build, Sign & Release DMG](https://github.com/Eddy-Barraud/CookieCleanerApp/actions/workflows/release.yml/badge.svg)](https://github.com/Eddy-Barraud/CookieCleanerApp/actions/workflows/release.yml)

**CookieCleaner** is a native, modern macOS utility written in Swift and SwiftUI designed to inspect, manage, and automatically clean Safari cookies, local storage, databases, and website caches while preserving logins for your trusted websites through a customizable whitelist.

---

## 🎯 App Goal

Modern browsers accumulate hundreds of tracking cookies, cache files, and persistent local storage entries during daily browsing. Safari stores cookies in proprietary binary files (`Cookies.binarycookies`) across different profile stores.

CookieCleaner solves this by:
- Giving you complete visibility into all cookies stored across every Safari profile (Default and custom profiles).
- Allowing you to whitelist essential domains (e.g., your email, banks, work tools) using exact matching or regular expressions.
- Automatically wiping tracking cookies, IndexedDB, local storage, and WebKit caches when Safari quits, without logging you out of your whitelisted sites.
- Running seamlessly either as a GUI application or as a low-overhead background launchd agent (`CookieCleanerHelper`).

---

## ✨ Features & Functions

### 1. 🔍 Live Cookie Inspection
- **Multi-Profile Support**: Automatically detects the Default Safari profile as well as Sonoma/Sequoia custom profiles from Safari's `WebsiteDataStore`.
- **Binary Cookie Parsing**: Reads and parses Safari's native binary format directly using high-performance binary decoders.
- **Search & Filtering**: Search by domain or cookie name, filter by status (All, Whitelisted, Marked for Deletion), and view flags (Secure, HTTP-only, expiration dates).
- **Domain Distribution Chart**: Visual top-domains bar and breakdown of cookies to be kept vs. purged.

### 2. 🧹 Targeted Cleaning & Deep Flushing
- **Clean Action**: Retains whitelisted cookies, safely removes non-whitelisted tracking cookies from `Cookies.binarycookies`, and clears general as well as profile-specific temporary caches (`Caches/`, `Application Cache/`, `DOMCache/`, `ServiceWorkers/`, `ResourceLoadStatistics/`, `WebsiteData/`) and non-whitelisted profile web storage (`LocalStorage`, `IndexedDB`, `GeneralStorage`) across all Safari profiles.
- **Combined Profile Cache Wiping**: Can be toggled on/off in the Dashboard (`Clear Profile App Data & Caches`), or run on-demand via **Clear Profile App Data Caches Only**.
- **Deep Flush**: Flushes all cookies and completely purges deep WebKit storage and caches across all profiles:
  - `~/Library/Containers/com.apple.Safari/Data/Library/Caches/...`
  - `~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore/<Profile>/...`
  - `~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData`
  - `~/Library/Safari/LocalStorage` and per-profile `LocalStorage`
  - `~/Library/Safari/Databases/___IndexedDB/v1` and per-profile `IndexedDB`
  - `~/Library/WebKit/MediaKeys`
- **Action Summary**: Detailed summary sheets showing the exact number of cookies removed, profile cache files purged, and disk space freed.

### 3. 🛡️ Whitelist Manager
- Add domains or regex patterns (e.g. `.*apple\.com`, `.*github\.com`).
- Built-in live regex tester to verify matching patterns before applying them.
- Preconfigured cheatsheet with common rules for major web services.

### 4. ⚡ Automatic Clean on Safari Exit
- Monitors Safari process lifecycle via `NSWorkspace` notifications.
- Automatically triggers cleanup when Safari closes (with a short debounce to allow Safari write buffers to flush to disk).
- Can be toggled on/off in the Dashboard.

### 5. 🤖 Optional Background Helper Daemon (`CookieCleanerHelper`)
- Embedded background agent registered via macOS `SMAppService` (`LaunchAgents/com.eddybarraud.CookieCleanerHelper.plist`).
- **User-controlled installation**: Not installed automatically at launch or first launch. Users can install or uninstall the background service at any time directly from the Dashboard.
- When installed, runs in the background via launchd to handle auto-cleaning upon Safari quit even when the main CookieCleaner app is closed.
- Real-time heartbeat tracking, active PID display, and immediate uninstallation / process termination.

### 6. 📊 Cumulative Metrics & Real-time Console
- Tracks historical metrics: total cleans executed, total cookies purged, and total disk space freed.
- In-app Console with searchable, filterable logs (Debug, Info, Warning, Success, Error).

---

## 🔒 Permissions & Security

Because Safari's cookies and caches are protected by macOS privacy controls:
- **Full Disk Access (FDA)** is required to read and modify `~/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies`.
- The application includes built-in permission verification and quick links to open macOS **System Settings > Privacy & Security > Full Disk Access**.

---

## 🏗️ Code Structure

```
CookieCleanerApp/
├── CookieCleanerApp.xcodeproj         # Xcode Project & Build Configurations
├── LaunchAgents/
│   └── com.eddybarraud.CookieCleanerHelper.plist  # SMAppService LaunchAgent definition
├── CookieCleanerApp/
│   ├── main.swift                     # Entry point routing: GUI app vs. daemon mode (--helper)
│   ├── MyApp.swift                    # SwiftUI App entry & Environment dependency injection
│   ├── ContentView.swift              # Main window container, tab switcher & permission banner
│   │
│   ├── Models/
│   │   ├── CookieItem.swift           # Identifiable cookie model with flags & expiration
│   │   ├── SafariProfile.swift        # Safari profile descriptor (default vs. custom profiles)
│   │   └── CleaningResult.swift       # Result metrics for clean/flush operations
│   │
│   ├── Services/
│   │   ├── CookieStore.swift          # Core cookie binary parser, profile scanner & cleaner
│   │   ├── SafariClosureWatcher.swift # NSWorkspace observer for Safari termination events
│   │   ├── BackgroundServiceManager.swift # SMAppService agent registration & heartbeat monitor
│   │   ├── CookieCleanerHelperDaemon.swift # Headless daemon loop for background execution
│   │   ├── WhitelistManager.swift     # Whitelist storage, regex matching & validation
│   │   ├── CumulativeStatsManager.swift # Persistent stats (total cleans, bytes freed)
│   │   └── AppLogger.swift            # Observable in-app logging system
│   │
│   ├── Views/
│   │   ├── Tabs/
│   │   │   ├── CumulativeStatsView.swift  # Dashboard: status cards, helper status, actions
│   │   │   ├── LiveCookiesView.swift      # Searchable cookie browser & profile selector
│   │   │   ├── WhitelistEditorView.swift  # Whitelist editor, tester & cheatsheet
│   │   │   └── ConsoleView.swift          # Real-time activity logs viewer
│   │   ├── Components/
│   │   │   ├── CookieTableView.swift      # Multi-column table of active cookies
│   │   │   ├── StatCardView.swift         # Metric card components
│   │   │   └── TopDomainsView.swift       # Distribution bar chart for top cookie domains
│   │   └── Modals/
│   │       └── ActionSummarySheet.swift   # Operation results sheet
│   │
│   ├── Extensions/
│   │   └── FileManager+Extensions.swift   # Helpers for path expansion & folder size calculations
│   │
│   ├── Vendored/
│   │   ├── BinaryCodable/             # Stream decoder/encoder for binary payloads
│   │   └── BinaryCookies/             # Binary schema for Safari binary cookies
│   │
│   └── Assets.xcassets/               # App icons, colors, and asset catalog
```

---

## 🛠️ Building & Requirements

- **macOS**: macOS 14.0 (Sonoma) or higher
- **Xcode**: Xcode 15.0 or higher
- **Swift**: Swift 5.9+ / Swift 6 approachable concurrency

### Build in Xcode
Open [CookieCleanerApp.xcodeproj](file:///Users/eddybarraud/gitclones/cookie-cleaner/CookieCleanerApp/CookieCleanerApp.xcodeproj), select the `CookieCleanerApp` scheme with the `My Mac` destination, and press **Cmd + B** (or **Cmd + R** to run).


---

## 👏 Credits & Acknowledgements

- Special thanks and credits to **[Jannis Baum](https://github.com/jannis-baum)** for the original [cookie-cleaner](https://github.com/jannis-baum/cookie-cleaner/blob/main/Package.swift) implementation and binary cookie parsing foundation.