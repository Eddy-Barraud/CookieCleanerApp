import SwiftUI

public struct StatCardView: View {
    let title: String
    let value: String
    let subtitle: String?
    let icon: String
    let color: Color
    
    public init(
        title: String,
        value: String,
        subtitle: String? = nil,
        icon: String,
        color: Color = .blue
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.icon = icon
        self.color = color
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
            }
            
            Text(value)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
