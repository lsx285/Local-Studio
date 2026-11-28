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
    var generationStage = "Queued on your PC…"
    var generationProgress: Double?
    var isImageGeneration = false
    var selectedModel: StudioModel? { connection.models.first { $0.id == selectedModelID } }
    var messages: [ChatMessage] = []
    var draft = ""
    var attachments: [PhotoAttachment] = []
    var isGenerating = false
    private(set) var respondingMessageID: UUID?
    var storageError: String?
    var generationStarted = Date.now
    /// Increments once per finished response; drives completion haptics.
    private(set) var completedResponses = 0
    /// Width ÷ height of the artwork being generated, for the progress artwork's frame.
    private(set) var generationAspectRatio = 1.0
    /// The response being regenerated, restored if the retry is stopped.
    private var retryOriginal: ChatMessage?
    /// The prompt before the last enhancement, and the enhanced text that replaced it.
    private var enhanceOriginal: String?
    private var enhancedDraft: String?
    private var revision = 0
    private var generationTask: Task<Void, Never>?
    private var restored = false

    var hasPrompt: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// How many more photos the selected model accepts.
    var attachmentSlots: Int { max(0, (selectedModel?.maxImages ?? 0) - attachments.count) }
    var canSend: Bool {
        guard connection.isConnected, let model = selectedModel, model.installed, !isEnhancing else { return false }
        if model.family != "chat" && !(attachments.isEmpty ? model.generation : model.editing) { return false }
        if attachments.count > model.maxImages { return false }
        return hasPrompt || !attachments.isEmpty
    }
    /// Offered until the enhanced prompt is edited or sent.
    var canUndoEnhance: Bool { !isEnhancing && enhancedDraft == draft && enhanceOriginal != nil }
    var canEnhance: Bool {
        connection.isConnected && selectedModel?.installed == true && !isGenerating && !isEnhancing && hasPrompt
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
        guard messages.isEmpty, revision == 0 else { return }
        messages = saved.map(ChatMessage.init)
    }

    func newChat() {
        cancelGeneration()
        messages.removeAll()
        attachments.removeAll()
        draft = ""
        persist()
    }

    /// Moves a prompt back into the composer and drops it together with everything after it,
    /// so the conversation continues from the edited prompt.
    func edit(_ message: ChatMessage) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        if isGenerating || isEnhancing { cancelGeneration() }
        withAnimation(.easeOut(duration: 0.25)) {
            messages.removeSubrange(index...)
        }
        draft = message.text
        attachments = message.attachments
        persist()
    }

    func send() {
        guard canSend, !isGenerating else { return }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let photos = attachments
        withAnimation(.spring(response: 0.44, dampingFraction: 0.86)) {
            messages.append(ChatMessage(role: .user, text: prompt, attachments: photos))
            draft = ""
            attachments = []
        }
        persist()
        generate(prompt: prompt, photos: photos, modelID: selectedModelID, width: canvasWidth, height: canvasHeight, maxTokens: maxTokens)
    }

    func retry(_ message: ChatMessage) {
        guard !isGenerating, !isEnhancing, connection.isConnected, message.role == .assistant,
              let index = messages.firstIndex(where: { $0.id == message.id }),
              let prompt = messages[..<index].last(where: { $0.role == .user }),
              let metadata = message.metadata else { return }
        // Repeat the original request's model, canvas and length; only the seed is new, so the retry is a fresh take.
        generate(prompt: prompt.text, photos: prompt.attachments, modelID: metadata.modelId, replacing: message.id,
                 width: metadata.width, height: metadata.height, maxTokens: metadata.maxTokens)
    }

    private func generate(prompt: String, photos: [PhotoAttachment], modelID: String, replacing messageID: UUID? = nil,
                          width: Int, height: Int, maxTokens: Int) {
        let responseID = messageID ?? UUID()
        let historyEnd = messageID.flatMap { id in messages.firstIndex { $0.id == id } } ?? messages.endIndex
        let history = messages[..<historyEnd].filter { $0.role == .user || !$0.text.isEmpty }.map { ["role": $0.role.rawValue, "text": $0.text] }
        isImageGeneration = connection.models.first { $0.id == modelID }?.family != "chat"
        // Reference edits keep the first reference's proportions on the PC.
        if let reference = photos.first?.image.size, reference.width > 0, reference.height > 0 {
            generationAspectRatio = reference.width / reference.height
        } else {
            generationAspectRatio = Double(width) / Double(height)
        }
        generationStarted = .now
        generationStage = "Queued on your PC…"
        generationProgress = nil
        isGenerating = true
        respondingMessageID = responseID
        if messageID == nil {
            messages.append(ChatMessage(id: responseID, role: .assistant, text: ""))
        } else if let index = messages.firstIndex(where: { $0.id == responseID }) {
            // A retry hides the response it replaces at once; the new one streams or appears in its place.
            retryOriginal = messages[index]
            withAnimation(.easeOut(duration: 0.2)) {
                messages[index].text = ""
                messages[index].attachments = []
            }
        }
        let image = isImageGeneration
        generationTask = Task { [weak self] in
            guard let self else { return }
            // Tokens can arrive far faster than the display refreshes. Each `messages` write
            // invalidates the whole conversation, so streamed text is applied at most ~30×/s;
            // the final result always carries the complete text.
            let clock = ContinuousClock()
            var lastTextUpdate = clock.now - .seconds(1)
            do {
                let result = try await connection.run(model: modelID, prompt: prompt, photos: photos.map(\.data), messages: history,
                                                       width: width, height: height, maxTokens: maxTokens) { event in
                    switch event {
                    case .text(let text):
                        let now = clock.now
                        guard now - lastTextUpdate >= .milliseconds(33),
                              let index = self.messages.firstIndex(where: { $0.id == responseID }) else { return }
                        lastTextUpdate = now
                        self.messages[index].text = text
                        if !self.messages[index].attachments.isEmpty { self.messages[index].attachments = [] }
                    case .progress(let value, let total):
                        let stage = image ? "Sampling image…" : "Writing…"
                        if self.generationStage != stage { self.generationStage = stage }
                        // Text generation shows no progress value, so per-token progress stays silent.
                        if image { self.generationProgress = total > 0 ? Double(value) / Double(total) : nil }
                    case .stage(let stage):
                        if self.generationStage != stage { self.generationStage = stage }
                        if !image && self.generationProgress != nil { self.generationProgress = nil }
                    }
                }
                try Task.checkCancellation()
                let response = ChatMessage(id: responseID, role: .assistant, text: result.text,
                                           attachments: result.images.compactMap { PhotoAttachment(data: $0.data, filename: $0.filename) }, metadata: result.metadata)
                if let index = messages.firstIndex(where: { $0.id == responseID }) { messages[index] = response }
                else { messages.append(response) }
                completedResponses += 1
            } catch {
                guard !Task.isCancelled else { return }
                if let original = retryOriginal, let index = messages.firstIndex(where: { $0.id == responseID }) { messages[index] = original }
                messages.removeAll { $0.id == responseID && $0.text.isEmpty && $0.attachments.isEmpty }
                if !(error is CancellationError) { generationError = error.localizedDescription }
            }
            isGenerating = false
            respondingMessageID = nil
            retryOriginal = nil
            generationTask = nil
            persist()
        }
    }

    func enhancePrompt() {
        guard canEnhance else { return }
        let original = draft
        let model = selectedModelID
        // Enhancement runs on the chat model, which may take fewer photos than the selected one.
        let photos = attachments.prefix(connection.models.first { $0.family == "chat" }?.maxImages ?? 0).map(\.data)
        isEnhancing = true
        generationTask = Task { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { isEnhancing = false; generationTask = nil } }
            do {
                var streamedDraft = original
                let clock = ContinuousClock()
                var lastTextUpdate = clock.now - .seconds(1)
                let result = try await connection.run(model: model, prompt: original, photos: photos, messages: [], enhance: true,
                                                       width: canvasWidth, height: canvasHeight, maxTokens: maxTokens) { event in
                    guard case .text(let text) = event else { return }
                    guard self.draft == streamedDraft else { self.cancelGeneration(); return }
                    let now = clock.now
                    guard now - lastTextUpdate >= .milliseconds(33) else { return }
                    lastTextUpdate = now
                    self.draft = text
                    streamedDraft = text
                }
                try Task.checkCancellation()
                if draft == streamedDraft {
                    draft = result.text
                    enhanceOriginal = original
                    enhancedDraft = result.text
                }
            } catch {
                if !Task.isCancelled { generationError = error.localizedDescription }
            }
        }
    }

    func undoEnhance() {
        guard canUndoEnhance, let original = enhanceOriginal else { return }
        draft = original
        enhanceOriginal = nil
        enhancedDraft = nil
    }

    func removeArtwork(_ id: UUID) {
        for index in messages.indices where messages[index].role == .assistant {
            messages[index].attachments.removeAll { $0.id == id }
        }
        messages.removeAll { $0.role == .assistant && $0.text.isEmpty && $0.attachments.isEmpty && $0.id != respondingMessageID }
        persist()
    }

    func cancelGeneration() {
        connection.cancel()
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        respondingMessageID = nil
        isEnhancing = false
        if let original = retryOriginal, let index = messages.firstIndex(where: { $0.id == original.id }) { messages[index] = original }
        retryOriginal = nil
        messages.removeAll { $0.role == .assistant && $0.text.isEmpty && $0.attachments.isEmpty }
        persist()
    }

    private func persist() {
        revision += 1
        let currentRevision = revision
        let snapshot = messages.map(ArchivedMessage.init)
        Task {
            do { try await ConversationArchive.shared.save(snapshot, revision: currentRevision) }
            catch { storageError = "Your conversation couldn’t be saved on this iPhone." }
        }
    }
}
