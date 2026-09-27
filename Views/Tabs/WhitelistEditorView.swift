import SwiftUI

public struct WhitelistEditorView: View {
    @Environment(WhitelistManager.self) private var whitelistManager
    @Environment(CookieStore.self) private var cookieStore
    
    @State private var editedContent: String = ""
    @State private var testDomain: String = ""
    @State private var saveStatus: SaveStatus = .saved
    @State private var saveTask: Task<Void, Never>?
    @State private var isInitialLoad: Bool = true
    
    private enum SaveStatus {
        case saved
        case saving
    }
    
    public init() {}
    
    private var testResult: Bool? {
        let trimmed = testDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return whitelistManager.isWhitelisted(test: trimmed)
    }
    
    public var body: some View {
        HSplitView {
            // Left pane: Editor
            VStack(alignment: .leading, spacing: 14) {
                // Header bar
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Whitelist Configuration")
                            .font(.headline)
                        Text("Stored in application datastore • Auto-saves after 1 second")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        switch saveStatus {
                        case .saving:
                            ProgressView()
                                .controlSize(.small)
                            Text("Saving...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .saved:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Saved")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                }
                
                Text("Enter one regular expression per line. Lines starting with # are comments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextEditor(text: $editedContent)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .onChange(of: editedContent) { _, newValue in
                        guard !isInitialLoad else { return }
                        scheduleAutoSave(newContent: newValue)
                    }
            }
            .padding(16)
            .frame(minWidth: 400)
            
            // Right pane: Regex Cheatsheet & Live Tester
            VStack(alignment: .leading, spacing: 18) {
                // Live Domain Tester
                VStack(alignment: .leading, spacing: 10) {
                    Label("Live Regex Tester", systemImage: "bolt.shield.fill")
                        .font(.headline)
                    
                    Text("Type a domain to test against active whitelist rules in real time:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                        TextField("e.g. ent.uca.fr", text: $testDomain)
                            .textFieldStyle(.plain)
                        if !testDomain.isEmpty {
                            Button {
                                testDomain = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    
                    if let result = testResult {
                        HStack(spacing: 8) {
                            Image(systemName: result ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(result ? .green : .red)
                            Text(result ? "PROTECTED (Will be preserved)" : "UNMATCHED (Will be deleted on exit)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(result ? .green : .red)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                
                // Cheatsheet & Quick Insert Templates
                VStack(alignment: .leading, spacing: 12) {
                    Label("Regex Guide & Templates", systemImage: "book.fill")
                        .font(.headline)
                    
                    Text("Click any template below to append it to your rules:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        templateRow(
                            title: "Domain & All Subdomains",
                            template: "(^|\\.)domain\\.com$",
                            description: "Matches domain.com, www.domain.com, mail.domain.com"
                        )
                        
                        templateRow(
                            title: "Exact Subdomain Only",
                            template: "^auth\\.domain\\.com$",
                            description: "Matches strictly auth.domain.com"
                        )
                        
                        templateRow(
                            title: "Multiple Country TLDs",
                            template: "(^|\\.)amazon\\.(com|fr|de)$",
                            description: "Matches amazon.com, amazon.fr, amazon.de"
                        )
                        
                        templateRow(
                            title: "Single Exact Domain",
                            template: "^example\\.org$",
                            description: "Excludes subdomains, matches only example.org"
                        )
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                
                Spacer()
            }
            .padding(16)
            .frame(minWidth: 320, maxWidth: 420)
        }
        .onAppear {
            editedContent = whitelistManager.rawContent
            DispatchQueue.main.async {
                isInitialLoad = false
            }
        }
    }
    
    private func scheduleAutoSave(newContent: String) {
        saveTask?.cancel()
        saveStatus = .saving
        
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            
            whitelistManager.updateWhitelist(content: newContent)
            _ = try? cookieStore.loadCookies(whitelist: whitelistManager)
            
            await MainActor.run {
                withAnimation {
                    saveStatus = .saved
                }
            }
        }
    }
    
    @ViewBuilder
    private func templateRow(title: String, template: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    appendTemplate(template)
                } label: {
                    Label("Insert", systemImage: "plus")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Text(template)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.blue)
            
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.textBackgroundColor))
        )
    }
    
    private func appendTemplate(_ template: String) {
        if !editedContent.hasSuffix("\n") && !editedContent.isEmpty {
            editedContent += "\n"
        }
        editedContent += "\(template)\n"
    }
}
