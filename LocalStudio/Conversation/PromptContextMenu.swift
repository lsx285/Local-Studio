import SwiftUI
import UIKit

enum PromptMenuAction: String, CaseIterable, Identifiable {
    case copy = "Copy", edit = "Edit", selectText = "Select text", share = "Share prompt"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .copy: "square.on.square"
        case .edit: "pencil"
        case .selectText: "text.cursor"
        case .share: "square.and.arrow.up"
        }
    }
}

struct PromptContextMenu: View {
    let message: ChatMessage
    let action: (PromptMenuAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Calendar.current.isDateInToday(message.createdAt)
                 ? "Today, \(message.createdAt.formatted(date: .omitted, time: .shortened))"
                 : message.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .padding(.bottom, 12)
            ForEach(PromptMenuAction.allCases) { entry in
                Button { action(entry) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: entry.symbol)
                            .font(.system(size: 19, weight: .regular))
                            .frame(width: 24, height: 24)
                        Text(entry.rawValue).font(.system(size: 17))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 28)
                    .frame(height: 42)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
        .frame(width: 250)
        .foregroundStyle(.white)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

struct PromptShare: Identifiable {
    let id = UUID()
    let text: String
}

struct PromptShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

struct PresentedPromptMenu {
    let message: ChatMessage
    let frame: CGRect
}
