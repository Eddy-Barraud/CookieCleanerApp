import SwiftUI

public struct CookieTableView: View {
    @Environment(CookieStore.self) private var cookieStore
    @Environment(WhitelistManager.self) private var whitelistManager
    
    let cookies: [CookieItem]
    let profiles: [SafariProfile]
    
    @State private var searchText: String = ""
    @State private var selectedStatus: StatusFilter = .all
    @State private var selectedProfile: String = "All"
    @State private var selectedCookieIds: Set<UUID> = []
    
    @State private var showingDeleteConfirmation: Bool = false
    @State private var itemsToDelete: [CookieItem] = []
    @State private var isDeleting: Bool = false
    
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
            // Filters & Actions row
            HStack(spacing: 12) {
                // Search box
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
                .frame(minWidth: 160)
                
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
                
                // Selection action controls
                if !selectedCookieIds.isEmpty {
                    HStack(spacing: 8) {
                        Text("\(selectedCookieIds.count) selected")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        
                        Button(role: .destructive) {
                            prepareDeleteSelected()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash.fill")
                                Text("Delete (\(selectedCookieIds.count))")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                        
                        Button("Deselect") {
                            selectedCookieIds.removeAll()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.08))
                    )
                } else {
                    Text("\(filteredCookies.count) of \(cookies.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Interactive Table with multi-selection
            Table(filteredCookies, selection: $selectedCookieIds) {
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
                .width(min: 110, ideal: 130)
                
                TableColumn("Action") { cookie in
                    Button {
                        promptDelete(items: [cookie])
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete this cookie now")
                }
                .width(min: 50, ideal: 50, max: 60)
            }
            .tableStyle(.inset)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .contextMenu(forSelectionType: CookieItem.ID.self) { items in
                let selectedItems = filteredCookies.filter { items.contains($0.id) }
                
                Button(role: .destructive) {
                    promptDelete(items: selectedItems)
                } label: {
                    Label(
                        selectedItems.count > 1 ? "Delete \(selectedItems.count) Cookies" : "Delete Cookie",
                        systemImage: "trash"
                    )
                }
                
                if let single = selectedItems.first, selectedItems.count == 1 {
                    Divider()
                    
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(single.cleanDomain, forType: .string)
                    } label: {
                        Label("Copy Domain '\(single.cleanDomain)'", systemImage: "doc.on.doc")
                    }
                    
                    if !single.isWhitelisted {
                        Button {
                            whitelistDomain(single.cleanDomain)
                        } label: {
                            Label("Add '\(single.cleanDomain)' to Whitelist", systemImage: "shield.badge.plus")
                        }
                    }
                }
            } primaryAction: { items in
                let selectedItems = filteredCookies.filter { items.contains($0.id) }
                promptDelete(items: selectedItems)
            }
            .onDeleteCommand {
                prepareDeleteSelected()
            }
        }
        .confirmationDialog(
            "Delete \(itemsToDelete.count) Cookie(s)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Cookie(s)", role: .destructive) {
                executeDeletion()
            }
            Button("Cancel", role: .cancel) {
                itemsToDelete.removeAll()
            }
        } message: {
            if itemsToDelete.count == 1, let item = itemsToDelete.first {
                Text("Are you sure you want to permanently remove cookie '\(item.name)' for '\(item.cleanDomain)' from \(item.profileName)?")
            } else {
                Text("Are you sure you want to permanently remove \(itemsToDelete.count) selected cookies?")
            }
        }
    }
    
    private func prepareDeleteSelected() {
        let targets = filteredCookies.filter { selectedCookieIds.contains($0.id) }
        guard !targets.isEmpty else { return }
        promptDelete(items: targets)
    }
    
    private func promptDelete(items: [CookieItem]) {
        self.itemsToDelete = items
        self.showingDeleteConfirmation = true
    }
    
    private func executeDeletion() {
        let targets = itemsToDelete
        guard !targets.isEmpty else { return }
        
        let targetIds = Set(targets.map(\.id))
        isDeleting = true
        
        Task {
            _ = await cookieStore.deleteCookies(items: targets)
            await MainActor.run {
                selectedCookieIds.subtract(targetIds)
                itemsToDelete.removeAll()
                isDeleting = false
            }
        }
    }
    
    private func whitelistDomain(_ domain: String) {
        let newRule = "(^|\\.)\(NSRegularExpression.escapedPattern(for: domain))$"
        var current = whitelistManager.rawContent
        if !current.hasSuffix("\n") && !current.isEmpty {
            current += "\n"
        }
        current += "\(newRule)\n"
        whitelistManager.updateWhitelist(content: current)
        _ = try? cookieStore.loadCookies(whitelist: whitelistManager)
    }
}
