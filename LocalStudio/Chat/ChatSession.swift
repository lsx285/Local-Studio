import Observation
import SwiftUI

@MainActor @Observable
final class ChatSession {
    let connection = StudioConnection()
    var selectedModelID = "qwen-chat"
    var canvasWidth = 1024
    var canvasHeight = 1024
    var maxTokens = 1024
    var isEnhancing = false
    var generationError: String?
    var generationStage = "Queued on your PC..."
    var generationProgress: Double?
    var isImageGeneration = false
    var selectedModel: StudioModel? { connection.models.first { $0.id == selectedModelID } }
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

    var canSend: Bool {
        guard connection.isConnected, let model = selectedModel, model.installed, !isEnhancing else { return false }
        if model.family != "chat" {
            if attachments.isEmpty && !model.generation { return false }
            if !attachments.isEmpty && !model.editing { return false }
        }
        return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }
    var canEnhance: Bool {
        connection.isConnected && selectedModel?.installed == true && !isGenerating && !isEnhancing &&
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["model": "qwen-chat", "canvasWidth": 1024, "canvasHeight": 1024, "maxTokens": 1024])
        selectedModelID = defaults.string(forKey: "model")!
        canvasWidth = defaults.integer(forKey: "canvasWidth")
        canvasHeight = defaults.integer(forKey: "canvasHeight")
        maxTokens = defaults.integer(forKey: "maxTokens")
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(selectedModelID, forKey: "model")
        defaults.set(canvasWidth, forKey: "canvasWidth")
        defaults.set(canvasHeight, forKey: "canvasHeight")
        defaults.set(maxTokens, forKey: "maxTokens")
    }

    func restore() async {
        guard !restored else { return }
        restored = true
        let saved: [ArchivedMessage]
        do { saved = try await ConversationArchive.shared.load() }
        catch { storageError = "Your saved conversation couldn’t be opened: \(error.localizedDescription)"; return }
        guard messages.isEmpty, !isTemporary, revision == 0 else { return }
        messages = saved.map {
            ChatMessage(id: $0.id, role: $0.role, text: $0.text,
                        attachments: $0.photos.compactMap { PhotoAttachment(id: $0.id, data: $0.data) }, createdAt: $0.createdAt, metadata: $0.metadata)
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
        guard !isGenerating, !isEnhancing, connection.isConnected, message.role == .assistant,
              let index = messages.firstIndex(where: { $0.id == message.id }),
              let prompt = messages[..<index].last(where: { $0.role == .user }) else { return }
        generate(prompt: prompt.text, photos: prompt.attachments, replacing: message.id)
    }

    private func generate(prompt: String, photos: [PhotoAttachment], replacing messageID: UUID? = nil) {
        let modelID = selectedModelID
        let responseID = messageID ?? UUID()
        let previous = messageID.flatMap { id in messages.first { $0.id == id } }
        let historyEnd = messageID.flatMap { id in messages.firstIndex { $0.id == id } } ?? messages.endIndex
        let history = messages[..<historyEnd].filter { !$0.text.isEmpty }.map { ["role": $0.role.rawValue, "text": $0.text] }
        isImageGeneration = selectedModel?.family != "chat"
        generationStarted = .now
        generationStage = "Queued on your PC..."
        generationProgress = nil
        isGenerating = true
        if messageID == nil && !isImageGeneration {
            messages.append(ChatMessage(id: responseID, role: .assistant, text: ""))
        }
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await connection.run(model: modelID, prompt: prompt, photos: photos.map(\.data), messages: history,
                                                       width: canvasWidth, height: canvasHeight, maxTokens: maxTokens) { event in
                    switch event {
                    case .text(let text):
                        if let index = self.messages.firstIndex(where: { $0.id == responseID }) {
                            self.messages[index].text = text
                            self.messages[index].attachments = []
                        }
                    case .progress(let value, let total):
                        self.generationProgress = total > 0 ? Double(value) / Double(total) : nil
                        self.generationStage = self.isImageGeneration ? "Sampling image..." : "Writing..."
                    case .stage(let stage):
                        self.generationStage = stage
                        self.generationProgress = nil
                    }
                }
                try Task.checkCancellation()
                let response = ChatMessage(id: responseID, role: .assistant, text: result.text,
                                           attachments: result.images.compactMap { PhotoAttachment(data: $0) }, metadata: result.metadata)
                if let index = messages.firstIndex(where: { $0.id == responseID }) { messages[index] = response }
                else { messages.append(response) }
                isGenerating = false
                generationTask = nil
                persist()
            } catch {
                guard !Task.isCancelled else { return }
                if let previous, let index = messages.firstIndex(where: { $0.id == responseID }) { messages[index] = previous }
                messages.removeAll { $0.id == responseID && $0.text.isEmpty && $0.attachments.isEmpty }
                isGenerating = false
                generationTask = nil
                if !(error is CancellationError) { generationError = error.localizedDescription }
                persist()
            }
        }
    }

    func enhancePrompt() {
        guard canEnhance else { return }
        let original = draft
        let model = selectedModelID
        let photos = attachments.map(\.data)
        isEnhancing = true
        generationTask = Task { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { isEnhancing = false; generationTask = nil } }
            do {
                let result = try await connection.run(model: model, prompt: original, photos: photos, messages: [], enhance: true,
                                                       width: canvasWidth, height: canvasHeight, maxTokens: maxTokens) { _ in }
                try Task.checkCancellation()
                if draft == original { draft = result.text }
                else { generationError = "Your draft changed during enhancement. The new draft was kept." }
            } catch {
                if !Task.isCancelled { generationError = error.localizedDescription }
            }
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
        connection.cancel()
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        isEnhancing = false
        messages.removeAll { $0.role == .assistant && $0.text.isEmpty && $0.attachments.isEmpty }
        persist()
    }

    private func persist() {
        guard !isTemporary else { return }
        revision += 1
        let currentRevision = revision
        let snapshot = messages.map {
            ArchivedMessage(id: $0.id, role: $0.role, text: $0.text,
                            photos: $0.attachments.map { .init(id: $0.id, data: $0.data) }, createdAt: $0.createdAt, metadata: $0.metadata)
        }
        Task {
            do { try await ConversationArchive.shared.save(snapshot, revision: currentRevision) }
            catch { storageError = "Your conversation couldn’t be saved on this iPhone." }
        }
    }
}
