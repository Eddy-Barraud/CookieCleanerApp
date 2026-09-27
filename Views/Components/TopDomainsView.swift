import SwiftUI

public struct TopDomainsView: View {
    let cookies: [CookieItem]
    
    private struct DomainStat: Identifiable {
        let id: String
        let domain: String
        let count: Int
        let isWhitelisted: Bool
    }
    
    private var topDomains: [DomainStat] {
        var counts: [String: (count: Int, isWhitelisted: Bool)] = [:]
        for c in cookies {
            let d = c.cleanDomain
            let existing = counts[d]?.count ?? 0
            counts[d] = (count: existing + 1, isWhitelisted: c.isWhitelisted)
        }
        
        return counts.map { DomainStat(id: $0.key, domain: $0.key, count: $0.value.count, isWhitelisted: $0.value.isWhitelisted) }
            .sorted { $0.count > $1.count }
            .prefix(10)
            .map { $0 }
    }
    
    private var maxCount: Int {
        topDomains.map(\.count).max() ?? 1
    }
    
    public init(cookies: [CookieItem]) {
        self.cookies = cookies
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Top Cookie Sources", systemImage: "chart.bar.fill")
                    .font(.headline)
                Spacer()
                Text("\(topDomains.count) shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if topDomains.isEmpty {
                Text("No cookies loaded yet. Refresh or visit websites in Safari.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(topDomains) { item in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(item.isWhitelisted ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            
                            Text(item.domain)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .frame(width: 170, alignment: .leading)
                            
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(height: 7)
                                    Capsule()
                                        .fill(item.isWhitelisted ? Color.green.opacity(0.8) : Color.orange.opacity(0.8))
                                        .frame(width: max(8, geo.size.width * CGFloat(item.count) / CGFloat(max(1, maxCount))), height: 7)
                                }
                            }
                            .frame(height: 7)
                            
                            Text("\(item.count)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
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
    }
}
