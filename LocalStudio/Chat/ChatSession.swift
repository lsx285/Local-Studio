import Observation
import SwiftUI

@MainActor @Observable
final class ChatSession {
    var messages: [ChatMessage] = []
    var draft = ""
    var attachments: [PhotoAttachment] = []
    var isTemporary = false
    var isGenerating = false
    var storageError: String?
    var generationStarted = Date.now
    var editingMessageID: UUID?
    private var revision = 0
    private var generationTask: Task<Void, Never>?
    private var restored = false

    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty }

    init() {
        #if DEBUG
        // Deterministic reference scenes exist only in simulator/debug builds.
        guard let scene = ProcessInfo.processInfo.environment["LOCAL_STUDIO_PREVIEW"] else { return }
        let short = "Short text message"
        let long = "Long text message that would change the composer!"
        switch scene {
        case "short": draft = short
        case "long": draft = "Long text that can’t fit in here so it changes the composer and makes it look like this!"
        case "attachments", "attachments-long":
            draft = scene == "attachments" ? short : long
            if let url = Bundle.main.url(forResource: "DemoArtwork", withExtension: "jpg"), let data = try? Data(contentsOf: url) {
                attachments = (0..<4).compactMap { _ in PhotoAttachment(data: data) }
            }
        case "conversation":
            messages = [ChatMessage(role: .user, text: "Hello"), ChatMessage(role: .assistant, text: "Hello! 😊 Lovely to have you here. How’s your day going?")]
        case "generation":
            messages = [ChatMessage(role: .user, text: "Generate an image of a pond with various animals residing in it")]
            generationStarted = .now.addingTimeInterval(-10)
            isGenerating = true
        default: break
        }
        #endif
    }

    func restore() async {
        guard !restored else { return }
        restored = true
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
        let saved = await ConversationArchive.shared.load()
        guard messages.isEmpty, !isTemporary, revision == 0 else { return }
        messages = saved.map {
            ChatMessage(id: $0.id, role: $0.role, text: $0.text,
                        attachments: $0.photos.compactMap { PhotoAttachment(id: $0.id, data: $0.data) }, createdAt: $0.createdAt)
        }
    }

    func newChat() {
        cancelGeneration()
        messages.removeAll()
        attachments.removeAll()
        draft = ""
        editingMessageID = nil
        isTemporary = false
        persist()
    }

    func toggleTemporary() {
        guard messages.isEmpty else { return }
        isTemporary.toggle()
    }

    func edit(_ message: ChatMessage) {
        draft = message.text
        attachments = message.attachments
        editingMessageID = message.id
    }

    func send() {
        guard canSend, !isGenerating else { return }
        if let editingMessageID, let index = messages.firstIndex(where: { $0.id == editingMessageID }) {
            messages.removeSubrange(index...)
        }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let photos = attachments
        withAnimation(.spring(response: 0.44, dampingFraction: 0.86)) {
            messages.append(ChatMessage(role: .user, text: prompt, attachments: photos))
            draft = ""
            attachments = []
            editingMessageID = nil
        }
        persist()
        generationStarted = .now
        isGenerating = true
        let imageRequest = ["image", "draw", "generate", "background", "edit"].contains { prompt.localizedCaseInsensitiveContains($0) }
        generationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(imageRequest ? 22 : 0.8))
                guard let self else { return }
                var resultPhotos: [PhotoAttachment] = []
                let response: String
                if imageRequest {
                    if let url = Bundle.main.url(forResource: "DemoArtwork", withExtension: "jpg"),
                       let data = try? Data(contentsOf: url), let photo = PhotoAttachment(data: data) {
                        resultPhotos = [photo]
                    }
                    response = ""
                } else if prompt.lowercased() == "hello" || prompt.lowercased() == "hi" {
                    response = "Hello! 😊 Lovely to have you here. How’s your day going?"
                } else if !photos.isEmpty {
                    response = "What would you like me to create or change using these \(photos.count == 1 ? "image" : "\(photos.count) images")?"
                } else {
                    response = "Local Studio is ready. Connect your local models in a future update to chat, create images, and make edits."
                }
                withAnimation(.easeOut(duration: 0.35)) {
                    self.isGenerating = false
                    self.messages.append(ChatMessage(role: .assistant, text: response, attachments: resultPhotos))
                }
                self.persist()
            } catch { /* Cancellation is an intentional stop or new conversation. */ }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    private func persist() {
        guard !isTemporary, !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        revision += 1
        let currentRevision = revision
        let snapshot = messages.map {
            ArchivedMessage(id: $0.id, role: $0.role, text: $0.text,
                            photos: $0.attachments.map { .init(id: $0.id, data: $0.data) }, createdAt: $0.createdAt)
        }
        Task {
            do { try await ConversationArchive.shared.save(snapshot, revision: currentRevision) }
            catch { storageError = "Your conversation couldn’t be saved on this iPhone." }
        }
    }
}
