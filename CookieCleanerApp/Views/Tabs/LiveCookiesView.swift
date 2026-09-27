import SwiftUI

public struct LiveCookiesView: View {
    @Environment(CookieStore.self) private var cookieStore
    @Environment(WhitelistManager.self) private var whitelistManager
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            // Top row: Quick summary cards + Top Domains chart
            HStack(alignment: .top, spacing: 16) {
                // Left: Count cards
                VStack(spacing: 12) {
                    let total = cookieStore.loadedCookies.count
                    let kept = cookieStore.loadedCookies.filter { $0.isWhitelisted }.count
                    let toDelete = cookieStore.loadedCookies.filter { !$0.isWhitelisted }.count
                    
                    StatCardView(
                        title: "Total Cookies",
                        value: "\(total)",
                        subtitle: "\(cookieStore.discoveredProfiles.count) profile(s)",
                        icon: "circle.grid.3x3.fill",
                        color: .blue
                    )
                    
                    StatCardView(
                        title: "Protected (Whitelisted)",
                        value: "\(kept)",
                        subtitle: "Will be preserved",
                        icon: "shield.checkmark.fill",
                        color: .green
                    )
                    
                    StatCardView(
                        title: "To Be Cleaned",
                        value: "\(toDelete)",
                        subtitle: "Will be deleted on exit",
                        icon: "trash.fill",
                        color: .red
                    )
                }
                .frame(width: 220)
                
                // Right: Top Domains Gauge
                TopDomainsView(cookies: cookieStore.loadedCookies)
            }
            .frame(maxHeight: 220)
            
            // Interactive Table
            CookieTableView(
                cookies: cookieStore.loadedCookies,
                profiles: cookieStore.discoveredProfiles
            )
        }
        .padding(16)
        .onAppear {
            _ = try? cookieStore.loadCookies(whitelist: whitelistManager)
        }
    }
}
