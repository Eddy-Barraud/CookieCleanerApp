import SwiftUI

public struct CookieTableView: View {
    let cookies: [CookieItem]
    let profiles: [SafariProfile]
    
    @State private var searchText: String = ""
    @State private var selectedStatus: StatusFilter = .all
    @State private var selectedProfile: String = "All"
    
    public enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case whitelisted = "Kept (Whitelisted)"
        case toDelete = "To Delete"
        public var id: String { rawValue }
    }
    
    private var filteredCookies: [CookieItem] {
        cookies.filter { cookie in
            if selectedStatus == .whitelisted && !cookie.isWhitelisted { return false }
            if selectedStatus == .toDelete && cookie.isWhitelisted { return false }
            if selectedProfile != "All" && cookie.profileName != selectedProfile { return false }
            
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                let matchesDomain = cookie.url.lowercased().contains(query)
                let matchesName = cookie.name.lowercased().contains(query)
                let matchesProfile = cookie.profileName.lowercased().contains(query)
                if !matchesDomain && !matchesName && !matchesProfile {
                    return false
                }
            }
            return true
        }
    }
    
    public init(cookies: [CookieItem], profiles: [SafariProfile]) {
        self.cookies = cookies
        self.profiles = profiles
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Filters row
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search domain or name...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                
                Picker("Status", selection: $selectedStatus) {
                    ForEach(StatusFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .frame(width: 170)
                
                Picker("Profile", selection: $selectedProfile) {
                    Text("All Profiles").tag("All")
                    ForEach(profiles) { profile in
                        Text(profile.name).tag(profile.name)
                    }
                }
                .frame(width: 150)
                
                Spacer()
                
                Text("\(filteredCookies.count) of \(cookies.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Table
            Table(filteredCookies) {
                TableColumn("Status") { cookie in
                    HStack(spacing: 6) {
                        Image(systemName: cookie.isWhitelisted ? "shield.checkmark.fill" : "trash.fill")
                            .foregroundStyle(cookie.isWhitelisted ? .green : .red)
                        Text(cookie.isWhitelisted ? "Kept" : "Delete")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(cookie.isWhitelisted ? .green : .red)
                    }
                }
                .width(min: 75, ideal: 85, max: 95)
                
                TableColumn("Domain") { cookie in
                    Text(cookie.cleanDomain)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .width(min: 140, ideal: 200)
                
                TableColumn("Name") { cookie in
                    Text(cookie.name)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                }
                .width(min: 100, ideal: 140)
                
                TableColumn("Profile") { cookie in
                    Text(cookie.profileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 110, max: 130)
                
                TableColumn("Size") { cookie in
                    Text("\(cookie.valueSize) B")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 70, max: 80)
                
                TableColumn("Expires") { cookie in
                    if let exp = cookie.expiration {
                        Text(exp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Session")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 120, ideal: 140)
            }
            .tableStyle(.inset)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
        }
    }
}
