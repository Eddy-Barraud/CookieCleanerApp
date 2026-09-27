```
cookie-cleaner/
├── clean_cookies                    # UNTOUCHED
├── Makefile                         # UNTOUCHED
├── Package.swift                    # UNTOUCHED
├── WHITELIST                        # Shared whitelist file
├── Sources/
│   ├── cookie-cleaner/              # UNTOUCHED CLI
│   ├── BinaryCodable/               # Vendored library
│   └── BinaryCookies/               # Vendored library
│
└── CookieCleanerApp/                # [NEW] Isolated UI App Directory
    ├── Package.swift                # Standalone SPM package for the UI app
    ├── Makefile                     # Build & bundle commands for the app
    └── Sources/
        └── CookieCleanerApp/
            ├── App/
            │   ├── CookieCleanerApp.swift       # @main SwiftUI App entry point
            │   └── AppState.swift               # Observable coordinator
            ├── Models/
            │   ├── CookieItem.swift             # Identifiable model for UI tables
            │   ├── CleaningResult.swift         # Structured result for popups
            │   └── CumulativeStats.swift        # Codable historical metrics model
            ├── Services/
            │   ├── CookieStore.swift            # Cookie parsing, stats, delete logic
            │   ├── CumulativeStatsManager.swift # Run counts, cookies deleted, bytes freed
            │   ├── WhitelistManager.swift       # Editor, regex validation & guide
            │   └── SafariClosureWatcher.swift   # NSWorkspace background watcher
            └── Views/
                ├── MainView.swift               # Main window layout with tab bar
                ├── LiveCookiesView.swift        # Profile stats, top domains, cookie list
                ├── CumulativeStatsView.swift    # Cleaning counter, data freed, reset button
                ├── WhitelistEditorView.swift    # Text editor + regex cheatsheet & tester
                ├── Components/
                │   ├── TopDomainsView.swift     # Visual domain distribution
                │   ├── CookieTableView.swift    # Searchable/filterable cookie table
                │   └── StatCardView.swift       # Modern metric cards
                └── Modals/
                    └── ActionSummaryAlert.swift # Completion popups (Clean & Flush)
```