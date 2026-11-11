import Cocoa
import SwiftUI

// Inspect CLI arguments to determine operating mode: one-shot clean, helper daemon, or interactive GUI
let args = CommandLine.arguments

// If invoked with a clean flag, execute one-shot headless cleanup and exit
if args.contains("--clean") || args.contains("-c") || args.contains("clean") {
    // Isolate execution to the main actor
    MainActor.assumeIsolated {
        CookieCleanerHelperDaemon.performCleanAndExit()
    }
// If invoked with a help flag, display usage text and exit
} else if args.contains("--help") || args.contains("-h") {
    // Print usage instructions to standard output
    CookieCleanerHelperDaemon.printUsage()
    exit(EXIT_SUCCESS)
// If launched with --helper or as the standalone CookieCleanerHelper binary, run as background daemon
} else if args.contains("--helper") || args.first?.hasSuffix("CookieCleanerHelper") == true {
    // Isolate daemon main loop on the main actor
    MainActor.assumeIsolated {
        CookieCleanerHelperDaemon.main()
    }
// Default to running the full SwiftUI desktop GUI application
} else {
    // Launch interactive macOS SwiftUI application
    MyApp.main()
}
