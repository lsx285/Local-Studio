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

    func restore() async {
        guard !restored else { return }
        restored = true
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
        generate(prompt: prompt, photos: photos)
    }

    func retry(_ message: ChatMessage) {
        guard !isGenerating, message.role == .assistant,
              let index = messages.firstIndex(where: { $0.id == message.id }),
              let prompt = messages[..<index].last(where: { $0.role == .user }) else { return }
        generate(prompt: prompt.text, photos: prompt.attachments, replacing: message.id)
    }

    private func generate(prompt: String, photos: [PhotoAttachment], replacing messageID: UUID? = nil) {
        generationStarted = .now
        isGenerating = true
        let imageRequest = ["image", "draw", "generate", "background", "edit"].contains { prompt.localizedCaseInsensitiveContains($0) }
        generationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(imageRequest ? 17.7 : 0.8))
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
                withAnimation(imageRequest ? nil : .easeOut(duration: 0.35)) {
                    self.isGenerating = false
                    if let messageID, let index = self.messages.firstIndex(where: { $0.id == messageID }) {
                        self.messages[index] = ChatMessage(id: messageID, role: .assistant, text: response, attachments: resultPhotos)
                    } else {
                        self.messages.append(ChatMessage(role: .assistant, text: response, attachments: resultPhotos))
                    }
                }
                self.persist()
            } catch { /* Cancellation is an intentional stop or new conversation. */ }
        }
    }

    func removeArtwork(_ id: UUID) {
        for index in messages.indices where messages[index].role == .assistant {
            messages[index].attachments.removeAll { $0.id == id }
        }
        messages.removeAll { $0.role == .assistant && $0.text.isEmpty && $0.attachments.isEmpty }
        persist()
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    private func persist() {
        guard !isTemporary else { return }
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
