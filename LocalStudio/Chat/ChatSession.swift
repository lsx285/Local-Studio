import Observation
import SwiftUI

@MainActor @Observable
final class ChatSession {
    let connection = StudioConnection()
    var selectedModelID = "qwen-chat"
    var canvasMegapixels = 1.0
    var canvasAspectRatio = CanvasAspectRatio.square
    private var canvasSize: (width: Int, height: Int) {
        let area = canvasMegapixels * 1_000_000
        let ratio = canvasAspectRatio.ratio
        return (max(16, Int((sqrt(area * ratio) / 16).rounded()) * 16),
                max(16, Int((sqrt(area / ratio) / 16).rounded()) * 16))
    }
    var canvasWidth: Int { canvasSize.width }
    var canvasHeight: Int { canvasSize.height }
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
    private(set) var respondingMessageID: UUID?
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
        defaults.register(defaults: ["model": "qwen-chat", "canvasMegapixels": 1.0, "canvasAspectRatio": "1:1", "maxTokens": 1024])
        selectedModelID = defaults.string(forKey: "model")!
        canvasMegapixels = defaults.double(forKey: "canvasMegapixels")
        canvasAspectRatio = CanvasAspectRatio(rawValue: defaults.string(forKey: "canvasAspectRatio")!)!
        maxTokens = defaults.integer(forKey: "maxTokens")
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(selectedModelID, forKey: "model")
        defaults.set(canvasMegapixels, forKey: "canvasMegapixels")
        defaults.set(canvasAspectRatio.rawValue, forKey: "canvasAspectRatio")
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
                        attachments: $0.photos.compactMap { PhotoAttachment(id: $0.id, data: $0.data, filename: $0.filename) }, createdAt: $0.createdAt, metadata: $0.metadata)
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
        generate(prompt: prompt, photos: photos, modelID: selectedModelID)
    }

    func retry(_ message: ChatMessage) {
        guard !isGenerating, !isEnhancing, connection.isConnected, message.role == .assistant,
              let index = messages.firstIndex(where: { $0.id == message.id }),
              let prompt = messages[..<index].last(where: { $0.role == .user }) else { return }
        let modelID: String?
        if let recorded = message.metadata?.modelId { modelID = recorded }
        else if message.metadata?.model == "Qwen3-VL 4B" { modelID = "qwen-chat" }
        else { modelID = connection.models.first { $0.name == message.metadata?.model }?.id }
        guard let modelID else { generationError = "The original model for this response is unavailable."; return }
        generate(prompt: prompt.text, photos: prompt.attachments, modelID: modelID, replacing: message.id)
    }

    private func generate(prompt: String, photos: [PhotoAttachment], modelID: String, replacing messageID: UUID? = nil) {
        let responseID = messageID ?? UUID()
        let previous = messageID.flatMap { id in messages.first { $0.id == id } }
        let historyEnd = messageID.flatMap { id in messages.firstIndex { $0.id == id } } ?? messages.endIndex
        let history = messages[..<historyEnd].filter { $0.role == .user || !$0.text.isEmpty }.map { ["role": $0.role.rawValue, "text": $0.text] }
        isImageGeneration = connection.models.first { $0.id == modelID }?.family != "chat"
        generationStarted = .now
        generationStage = "Queued on your PC..."
        generationProgress = nil
        isGenerating = true
        respondingMessageID = responseID
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
                        if !self.isImageGeneration { self.generationProgress = nil }
                    }
                }
                try Task.checkCancellation()
                let response = ChatMessage(id: responseID, role: .assistant, text: result.text,
                                           attachments: result.images.compactMap { PhotoAttachment(data: $0.data, filename: $0.filename) }, metadata: result.metadata)
                if let index = messages.firstIndex(where: { $0.id == responseID }) { messages[index] = response }
                else { messages.append(response) }
                isGenerating = false
                respondingMessageID = nil
                generationTask = nil
                persist()
            } catch {
                guard !Task.isCancelled else { return }
                if let previous, let index = messages.firstIndex(where: { $0.id == responseID }) { messages[index] = previous }
                messages.removeAll { $0.id == responseID && $0.text.isEmpty && $0.attachments.isEmpty }
                isGenerating = false
                respondingMessageID = nil
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
                var streamedDraft = original
                let result = try await connection.run(model: model, prompt: original, photos: photos, messages: [], enhance: true,
                                                       width: canvasWidth, height: canvasHeight, maxTokens: maxTokens) { event in
                    guard case .text(let text) = event else { return }
                    guard self.draft == streamedDraft else { self.cancelGeneration(); return }
                    self.draft = text
                    streamedDraft = text
                }
                try Task.checkCancellation()
                if draft == streamedDraft { draft = result.text }
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
        respondingMessageID = nil
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
                            photos: $0.attachments.map { .init(id: $0.id, data: $0.data, filename: $0.filename) }, createdAt: $0.createdAt, metadata: $0.metadata)
        }
        Task {
            do { try await ConversationArchive.shared.save(snapshot, revision: currentRevision) }
            catch { storageError = "Your conversation couldn’t be saved on this iPhone." }
        }
    }
}
