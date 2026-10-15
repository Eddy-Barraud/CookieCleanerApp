import SwiftUI

public struct ActionSummarySheet: View {
    let result: CleaningResult
    let isFlush: Bool
    let onDismiss: () -> Void
    
    public init(result: CleaningResult, isFlush: Bool = false, onDismiss: @escaping () -> Void) {
        self.result = result
        self.isFlush = isFlush
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: result.isSuccess ? (isFlush ? "flame.fill" : "sparkles") : "exclamationmark.triangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(result.isSuccess ? (isFlush ? .orange : .green) : .red)
                .padding(.top, 10)
            
            VStack(spacing: 4) {
                Text(result.isSuccess ? (isFlush ? "All Cookies Flushed" : "Cleanup Complete") : "Cleanup Failed")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let error = result.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                } else {
                    Text(isFlush ? "Every stored cookie was completely cleared." : "Cookies and cache were successfully filtered.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow {
                    Text("Cookies Deleted:")
                        .foregroundStyle(.secondary)
                    Text("\(result.cookiesDeleted)")
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                
                if !isFlush {
                    GridRow {
                        Text("Cookies Kept (Whitelisted):")
                            .foregroundStyle(.secondary)
                        Text("\(result.cookiesKept)")
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(.green)
                    }
                }
                
                GridRow {
                    Text("Disk Space Recovered:")
                        .foregroundStyle(.secondary)
                    Text(result.formattedBytesFreed)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                
                GridRow {
                    Text("Cache & Scan Files Removed:")
                        .foregroundStyle(.secondary)
                    Text("\(result.cacheFilesRemoved + result.scanFilesRemoved)")
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                
                if result.profileCachesRemoved > 0 {
                    GridRow {
                        Text("Profile App Data Caches:")
                            .foregroundStyle(.secondary)
                        Text("\(result.profileCachesRemoved) files cleaned")
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(.blue)
                    }
                }
                
                GridRow {
                    Text("Duration:")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2f s", result.duration))
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
            }
            .font(.callout)
            
            Divider()
            
            Button("Done") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 8)
        }
        .padding(24)
        .frame(minWidth: 380)
    }
}
