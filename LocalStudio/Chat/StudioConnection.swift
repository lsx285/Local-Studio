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

    var capability: String {
        if family == "chat" { return "Chat and prompt enhancement" }
        return generation && editing ? "Generate and edit" : editing ? "Edit images" : "Generate images"
    }
}

struct GenerationMetadata: Codable, Sendable {
    let model: String
    let seed: UInt64
    let prompt: String
    let steps: Int?
    let cfg: Double?
    let sampler: String?
    let scheduler: String?
    let negativePrompt: String?
}

struct StudioResult {
    let text: String
    let images: [Data]
    let metadata: GenerationMetadata
}

enum StudioEvent {
    case text(String)
    case progress(Int, Int)
    case stage(String)
}

private struct StudioError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor @Observable
final class StudioConnection: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    var models: [StudioModel] = []
    var status = "Searching for your PC…"
    var serverName: String?
    var isConnected: Bool { baseURL != nil }
    private var baseURL: URL?
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var connectedService: NetService?
    private var socket: URLSessionWebSocketTask?
    private var activePromptID: String?
    private var discoveryTask: Task<Void, Never>?

    func discover() {
        discoveryTask?.cancel()
        browser.stop()
        services.forEach { $0.stop() }
        services.removeAll()
        connectedService = nil
        baseURL = nil
        models = []
        serverName = nil
        status = "Searching for your PC…"
        browser.delegate = self
        browser.searchForServices(ofType: "_localstudio._tcp.", inDomain: "local.")
        discoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) }
                catch { return }
                guard let self else { return }
                if baseURL == nil {
                    for service in services { service.resolve(withTimeout: 5) }
                } else if socket == nil {
                    await refreshModels()
                }
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 10)
    }

    func netServiceDidResolveAddress(_ service: NetService) {
        guard baseURL == nil, let resolvedHost = service.hostName else { return }
        let host = resolvedHost.hasSuffix(".") ? String(resolvedHost.dropLast()) : resolvedHost
        guard let url = URL(string: "http://\(host):\(service.port)") else { return }
        connectedService = service
        baseURL = url
        serverName = service.name
        status = "Connecting…"
        Task { await refreshModels() }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 == service }
        if connectedService == service {
            baseURL = nil
            models = []
            serverName = nil
            status = "PC disconnected. Searching…"
            for candidate in services { candidate.resolve(withTimeout: 10) }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        status = "Discovery unavailable. Allow Local Network access in iPhone Settings."
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        if baseURL == nil { status = "Couldn’t reach your PC. Check that ComfyUI is running on the same network." }
    }

    func refreshModels() async {
        do {
            let data = try await request("local-studio/catalog")
            struct Catalog: Decodable { let version: Int; let models: [StudioModel] }
            let catalog = try JSONDecoder().decode(Catalog.self, from: data)
            guard catalog.version == 1 else { throw StudioError(message: "Update the Local Studio ComfyUI extension.") }
            models = catalog.models
            status = "Connected"
        } catch {
            status = error.localizedDescription
            baseURL = nil
            connectedService = nil
        }
    }

    private func request(_ path: String, body: [String: Any]? = nil) async throws -> Data {
        guard let baseURL else { throw StudioError(message: "Start ComfyUI on your PC and connect both devices to the same network.") }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.timeoutInterval = 60
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
             width: Int, height: Int, maxTokens: Int, event: (StudioEvent) -> Void) async throws -> StudioResult {
        guard let baseURL else { throw StudioError(message: "No PC found. Start ComfyUI on the same network.") }
        let requestID = UUID().uuidString.lowercased()
        let clientID = UUID().uuidString.lowercased()
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
        return try await withTaskCancellationHandler {
            // Receive the server's status handshake before submitting, so no streamed tokens are lost.
            _ = try await ws.receive()
            var filenames: [String] = []
            for photo in photos {
                try Task.checkCancellation()
                event(.stage("Uploading original image…"))
                filenames.append(try await upload(photo))
            }
            let workflowData = try await request("local-studio/workflow", body: [
                "model": model, "prompt": prompt, "images": filenames, "messages": messages,
                "enhance": enhance, "client_id": clientID, "request_id": requestID,
                "width": width, "height": height, "max_tokens": maxTokens
            ])
            let workflow = try JSONSerialization.jsonObject(with: workflowData) as! [String: Any]
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let metadata = try decoder.decode(GenerationMetadata.self, from: JSONSerialization.data(withJSONObject: workflow["metadata"]!))
            try Task.checkCancellation()
            _ = try await request("prompt", body: ["prompt": workflow["prompt"]!, "client_id": clientID, "prompt_id": requestID])
            event(.stage("Queued on your PC…"))
            while true {
                try Task.checkCancellation()
                let message = try await ws.receive()
                guard case .string(let string) = message,
                      let data = string.data(using: .utf8),
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = object["type"] as? String, let payload = object["data"] as? [String: Any] else { continue }
                if type == "local_studio_text", payload["request_id"] as? String == requestID {
                    event(.text(payload["text"] as? String ?? ""))
                    continue
                }
                guard payload["prompt_id"] as? String == requestID else { continue }
                switch type {
                case "execution_start": event(.stage("Loading model…"))
                case "executing":
                    if let node = payload["node"] as? String {
                        event(.stage(node == "decode" ? "Decoding image…" : node == "output" ? "Saving result…" : "Running model…"))
                    } else if payload["node"] is NSNull {
                        return try await result(requestID, metadata: metadata)
                    }
                case "progress":
                    if let value = payload["value"] as? Int, let total = payload["max"] as? Int { event(.progress(value, total)) }
                case "execution_error": throw StudioError(message: payload["exception_message"] as? String ?? "Model execution failed.")
                case "execution_interrupted": throw CancellationError()
                default: break
                }
            }
        } onCancel: {
            ws.cancel(with: .goingAway, reason: nil)
        }
    }

    func cancel() {
        guard let id = activePromptID else { return }
        socket?.cancel(with: .goingAway, reason: nil)
        Task {
            do { _ = try await request("api/jobs/\(id)/cancel", body: [:]) }
            catch { status = "Couldn’t cancel the PC job: \(error.localizedDescription)" }
        }
    }

    private func result(_ id: String, metadata: GenerationMetadata) async throws -> StudioResult {
        let data = try await request("history/\(id)")
        let history = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        guard let entry = history[id] as? [String: Any], let outputs = entry["outputs"] as? [String: Any],
              let output = outputs["output"] as? [String: Any] else { throw StudioError(message: "ComfyUI returned no result.") }
        var images: [Data] = []
        for image in output["images"] as? [[String: String]] ?? [] {
            guard let baseURL else { throw StudioError(message: "Your PC disconnected before the image downloaded.") }
            var url = URLComponents(url: baseURL.appending(path: "view"), resolvingAgainstBaseURL: false)!
            url.queryItems = ["filename", "subfolder", "type"].map { URLQueryItem(name: $0, value: image[$0]) }
            let (data, response) = try await URLSession.shared.data(from: url.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw StudioError(message: "Couldn’t download the generated image.") }
            images.append(data)
        }
        return StudioResult(text: (output["text"] as? [String])?.joined() ?? "", images: images, metadata: metadata)
    }
}
