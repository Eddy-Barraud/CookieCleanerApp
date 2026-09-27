import Cocoa
import SwiftUI

if CommandLine.arguments.contains("--helper") || CommandLine.arguments.first?.hasSuffix("CookieCleanerHelper") == true {
    MainActor.assumeIsolated {
        CookieCleanerHelperDaemon.main()
    }
} else {
    MyApp.main()
}
