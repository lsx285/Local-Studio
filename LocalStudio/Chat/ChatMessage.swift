import UIKit

struct ChatMessage: Identifiable {
    enum Role: String, Codable { case user, assistant }
    let id: UUID
    let role: Role
    var text: String
    var attachments: [PhotoAttachment]
    let createdAt: Date

    init(id: UUID = UUID(), role: Role, text: String, attachments: [PhotoAttachment] = [], createdAt: Date = .now) {
        self.id = id
        self.role = role
        self.text = text
        self.attachments = attachments
        self.createdAt = createdAt
    }
}

struct PhotoAttachment: Identifiable {
    let id: UUID
    let data: Data
    let image: UIImage

    init?(id: UUID = UUID(), data: Data) {
        guard let image = UIImage(data: data) else { return nil }
        self.id = id
        self.data = data
        self.image = image
    }
}

/// Only these immutable, Sendable values cross the disk boundary.
struct ArchivedMessage: Codable, Sendable {
    struct Photo: Codable, Sendable {
        let id: UUID
        let data: Data
    }
    let id: UUID
    let role: ChatMessage.Role
    let text: String
    let photos: [Photo]
    let createdAt: Date
}

actor ConversationArchive {
    static let shared = ConversationArchive()
    private var revision = 0
    private var url: URL {
        URL.applicationSupportDirectory.appending(path: "conversation.json")
    }

    func load() -> [ArchivedMessage] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ArchivedMessage].self, from: data)) ?? []
    }

    func save(_ messages: [ArchivedMessage], revision newRevision: Int) throws {
        guard newRevision > revision else { return }
        revision = newRevision
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(messages)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
