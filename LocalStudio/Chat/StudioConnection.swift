import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

struct StudioModel: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let family: String
    let generation: Bool
    let editing: Bool
    let installed: Bool
    let steps: Int
    let cfg: Double
    let sampler: String
    let scheduler: String
    let negative: String

    /// The published sampling preset, before any changes in Settings.
    var preset: SamplingSettings {
        SamplingSettings(steps: steps, cfg: cfg, sampler: sampler, scheduler: scheduler, negativePrompt: negative)
    }

    var capability: String {
        if id == "qwen-chat" { return "Text chat and prompt enhancement" }
        if family == "chat" { return "Image chat and visual prompts" }
        return generation && editing ? "Generate and edit" : editing ? "Edit images" : "Generate images"
    }
}

/// Per-model sampling choices sent with each image request.
struct SamplingSettings: Codable, Equatable, Sendable {
    var steps: Int
    var cfg: Double
    var sampler: String
    var scheduler: String
    var negativePrompt: String
}

struct GenerationMetadata: Codable, Equatable, Sendable {
    let model: String
    let modelId: String
    var requestSeconds: Double?
    let seed: UInt64
    let prompt: String
    let steps: Int?
    let cfg: Double?
    let sampler: String?
    let scheduler: String?
    let negativePrompt: String?
    let diffusionModel: String?
    let encoder: String?
    let vae: String?
    /// Request settings, so a retry repeats them exactly.
    let width: Int
    let height: Int
    let maxTokens: Int
}

struct StudioResult {
    let text: String
    let images: [StudioImage]
    let metadata: GenerationMetadata
}

struct StudioImage {
    let data: Data
    let filename: String
}

enum StudioEvent {
    case text(String)
    case progress(Int, Int)
    case stage(String)
}

/// The output node's UI result: streamed text, or saved images to download.
private struct StudioOutput: Decodable {
    struct ImageReference: Decodable {
        let filename: String
        let subfolder: String
        let type: String
    }
    let text: [String]?
    let images: [ImageReference]?
}

private struct StudioError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor @Observable
final class StudioConnection: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    var models: [StudioModel] = []
    private(set) var samplers: [String] = []
    private(set) var schedulers: [String] = []
    var status = "Searching for your PC…"
    private(set) var isConnected = false
    private var baseURL: URL?
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var connectedService: NetService?
    private var socket: URLSessionWebSocketTask?
    private var activePromptID: String?
    private var discoveryTask: Task<Void, Never>?

    func discover() {
        guard !isConnected, discoveryTask == nil else { return }
        browse()
        discoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
                guard let self, !isConnected else { return }
                browse()
            }
        }
    }

    private func browse() {
        browser.stop()
        services.forEach { $0.stop() }
        services.removeAll()
        connectedService = nil
        baseURL = nil
        status = "Searching for your PC…"
        browser.delegate = self
        browser.searchForServices(ofType: "_localstudio._tcp.", inDomain: "local.")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard !isConnected else { return }
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 4)
    }

    func netServiceDidResolveAddress(_ service: NetService) {
        guard !isConnected, baseURL == nil, services.contains(service), let resolvedHost = service.hostName else { return }
        let host = resolvedHost.hasSuffix(".") ? String(resolvedHost.dropLast()) : resolvedHost
        guard let url = URL(string: "http://\(host):\(service.port)") else { return }
        connectedService = service
        baseURL = url
        status = "Connecting…"
        Task { await refreshModels() }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 == service }
        if !isConnected && connectedService == service { connectedService = nil; baseURL = nil }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        status = "Allow Local Network access in iPhone Settings."
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        if !isConnected { status = "Searching for your PC…" }
    }

    private func refreshModels() async {
        let candidate = connectedService
        do {
            let data = try await request("local-studio/catalog", timeout: 4)
            struct Catalog: Decodable { let version: Int; let models: [StudioModel]; let samplers: [String]; let schedulers: [String] }
            let catalog = try JSONDecoder().decode(Catalog.self, from: data)
            guard candidate == connectedService else { return }
            guard catalog.version == 3 else { throw StudioError(message: "Update the Local Studio ComfyUI extension.") }
            models = catalog.models
            samplers = catalog.samplers
            schedulers = catalog.schedulers
            isConnected = true
            status = "Connected"
            discoveryTask?.cancel()
            discoveryTask = nil
            browser.stop()
        } catch {
            guard candidate == connectedService else { return }
            status = error.localizedDescription
            baseURL = nil
            connectedService = nil
        }
    }

    private func connectionFailed(_ error: Error) {
        guard !Task.isCancelled, !(error is CancellationError),
              error is URLError || (error as NSError).domain == NSPOSIXErrorDomain else { return }
        isConnected = false
        baseURL = nil
        connectedService = nil
        discover()
    }

    private func request(_ path: String, body: [String: Any]? = nil, timeout: TimeInterval = 60) async throws -> Data {
        guard let baseURL else { throw StudioError(message: "Start ComfyUI on your PC and connect both devices to the same network.") }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.timeoutInterval = timeout
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "ComfyUI request failed."
            throw StudioError(message: String(detail.prefix(1500)))
        }
        return data
    }

    private func upload(_ data: Data) async throws -> String {
        guard let baseURL else { throw StudioError(message: "Your PC is disconnected.") }
        let imageType = CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) }
        guard let type = imageType.flatMap({ UTType($0 as String) }), let fileExtension = type.preferredFilenameExtension,
              let mime = type.preferredMIMEType else { throw StudioError(message: "The attachment’s original image format couldn’t be identified.") }
        let filename = UUID().uuidString + "." + fileExtension
        let boundary = UUID().uuidString
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8)
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: baseURL.appending(path: "upload/image"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 180
        let (result, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw StudioError(message: "ComfyUI couldn’t import the original image.") }
        struct Upload: Decodable { let name: String; let subfolder: String }
        let uploaded = try JSONDecoder().decode(Upload.self, from: result)
        return uploaded.subfolder.isEmpty ? uploaded.name : uploaded.subfolder + "/" + uploaded.name
    }

    func run(model: String, prompt: String, photos: [Data], messages: [[String: String]], enhance: Bool = false,
             width: Int, height: Int, maxTokens: Int, sampling: SamplingSettings, event: (StudioEvent) -> Void) async throws -> StudioResult {
        guard let baseURL else { throw StudioError(message: "No PC found. Start ComfyUI on the same network.") }
        let started = Date.now
        let requestID = UUID().uuidString.lowercased()
        let clientID = UUID().uuidString.lowercased()
        let isImageRequest = !enhance && models.first(where: { $0.id == model })?.family != "chat"
        activePromptID = requestID
        var components = URLComponents(url: baseURL.appending(path: "ws"), resolvingAgainstBaseURL: false)!
        components.scheme = "ws"
        components.queryItems = [URLQueryItem(name: "clientId", value: clientID)]
        let ws = URLSession.shared.webSocketTask(with: components.url!)
        socket = ws
        ws.resume()
        defer {
            ws.cancel(with: .normalClosure, reason: nil)
            socket = nil
            activePromptID = nil
        }
        do {
            return try await withTaskCancellationHandler {
                // Receive the server's status handshake before submitting, so no streamed tokens are lost.
                _ = try await ws.receive()
                var filenames: [String] = []
                for photo in photos {
                    try Task.checkCancellation()
                    event(.stage("Uploading original image…"))
                    filenames.append(try await upload(photo))
                }
                try Task.checkCancellation()
                // One call builds the workflow on the PC and queues it under this request's ID.
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                var metadata = try decoder.decode(GenerationMetadata.self, from: await request("local-studio/run", body: [
                    "model": model, "prompt": prompt, "images": filenames, "messages": messages,
                    "enhance": enhance, "client_id": clientID, "request_id": requestID,
                    "width": width, "height": height, "max_tokens": maxTokens,
                    "steps": sampling.steps, "cfg": sampling.cfg, "sampler": sampling.sampler,
                    "scheduler": sampling.scheduler, "negative_prompt": sampling.negativePrompt
                ]))
                event(.stage("Queued on your PC…"))
                var text = ""
                var output: StudioOutput?
                while true {
                    try Task.checkCancellation()
                    let message = try await ws.receive()
                    // Every event for this request carries its ID; skip parsing everything else
                    // (status broadcasts, other clients, monitoring extensions) on the main actor.
                    guard case .string(let string) = message, string.contains(requestID),
                          let data = string.data(using: .utf8),
                          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = object["type"] as? String, let payload = object["data"] as? [String: Any] else { continue }
                    if type == "local_studio_text", payload["request_id"] as? String == requestID {
                        // The PC streams only new characters; the app always sees the full text so far.
                        text += payload["delta"] as? String ?? ""
                        event(.text(text))
                        continue
                    }
                    guard payload["prompt_id"] as? String == requestID else { continue }
                    switch type {
                    case "executed":
                        // The output node's result arrives here.
                        if payload["node"] as? String == "output", let value = payload["output"] {
                            output = try? JSONDecoder().decode(StudioOutput.self, from: JSONSerialization.data(withJSONObject: value))
                        }
                    case "execution_start": event(.stage("Loading model…"))
                    case "executing":
                        if let node = payload["node"] as? String {
                            event(.stage(node == "decode" ? "Decoding image…" : node == "output" ? "Saving result…" : "Running model…"))
                        } else if payload["node"] is NSNull {
                            metadata.requestSeconds = Date.now.timeIntervalSince(started)
                            return try await result(output: output, metadata: metadata)
                        }
                    case "progress":
                        if isImageRequest && payload["node"] as? String != "sample" { continue }
                        if let value = payload["value"] as? Int, let total = payload["max"] as? Int { event(.progress(value, total)) }
                    case "execution_error": throw StudioError(message: payload["exception_message"] as? String ?? "Model execution failed.")
                    case "execution_interrupted": throw CancellationError()
                    default: break
                    }
                }
            } onCancel: {
                ws.cancel(with: .goingAway, reason: nil)
            }
        } catch {
            connectionFailed(error)
            throw error
        }
    }

    func cancel() {
        guard let id = activePromptID else { return }
        socket?.cancel(with: .goingAway, reason: nil)
        Task {
            do { _ = try await request("api/jobs/\(id)/cancel", body: [:]) }
            catch { connectionFailed(error) }
        }
    }

    private func result(output: StudioOutput?, metadata: GenerationMetadata) async throws -> StudioResult {
        guard let output else { throw StudioError(message: "ComfyUI returned no result.") }
        var images: [StudioImage] = []
        for image in output.images ?? [] {
            guard let baseURL else { throw StudioError(message: "Your PC disconnected before the image downloaded.") }
            var url = URLComponents(url: baseURL.appending(path: "view"), resolvingAgainstBaseURL: false)!
            url.queryItems = [URLQueryItem(name: "filename", value: image.filename),
                              URLQueryItem(name: "subfolder", value: image.subfolder),
                              URLQueryItem(name: "type", value: image.type)]
            let (data, response) = try await URLSession.shared.data(from: url.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw StudioError(message: "Couldn’t download the generated image.") }
            images.append(StudioImage(data: data, filename: image.filename))
        }
        let text = output.text?.joined() ?? ""
        guard !text.isEmpty || !images.isEmpty else { throw StudioError(message: "The model returned an empty result.") }
        return StudioResult(text: text, images: images, metadata: metadata)
    }
}
