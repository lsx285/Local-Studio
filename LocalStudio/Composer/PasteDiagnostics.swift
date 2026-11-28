import SwiftUI
import UIKit
import Observation

@MainActor @Observable final class PasteDiagnostics {
    static let shared = PasteDiagnostics()
    private(set) var entries: [String] = []
    func record(_ event: String) {
        entries.append("\(Date.now.formatted(date: .omitted, time: .standard)) · \(event)")
        if entries.count > 500 { entries.removeFirst(entries.count - 500) }
    }
    var report: String { (["Local Studio paste diagnostics", "iOS \(UIDevice.current.systemVersion)", "Metadata only; no clipboard text or image pixels recorded."] + entries).joined(separator: "\n") }
    func clear() { entries.removeAll() }
}

struct PasteDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(PasteDiagnostics.shared.report).font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            .navigationTitle("Paste diagnostics").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: PasteDiagnostics.shared.report) { Text("Share logs") }
                }
                ToolbarItem(placement: .bottomBar) { Button("Clear logs") { PasteDiagnostics.shared.clear() } }
            }
        }
    }
}
