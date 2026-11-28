import UIKit

struct ChatMessage: Identifiable, Equatable {
    enum Role: String, Codable { case user, assistant }
    let id: UUID
    let role: Role
    var text: String
    var attachments: [PhotoAttachment]
    let createdAt: Date
    var metadata: GenerationMetadata?

    init(id: UUID = UUID(), role: Role, text: String, attachments: [PhotoAttachment] = [], createdAt: Date = .now, metadata: GenerationMetadata? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.attachments = attachments
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

struct PhotoAttachment: Identifiable, Equatable {
    let id: UUID
    let data: Data
    let filename: String?
    let image: UIImage

    init?(id: UUID = UUID(), data: Data, filename: String? = nil) {
        guard let image = UIImage(data: data) else { return nil }
        self.id = id
        self.data = data
        self.filename = filename
        self.image = image
    }

    /// Attachment contents never change after creation, so identity is equality.
    static func == (lhs: PhotoAttachment, rhs: PhotoAttachment) -> Bool { lhs.id == rhs.id }
}

/// Only these immutable, Sendable values cross the disk boundary.
struct ArchivedMessage: Codable, Sendable {
    struct Photo: Codable, Sendable {
        let id: UUID
        let data: Data
        let filename: String?
    }
    let id: UUID
    let role: ChatMessage.Role
    let text: String
    let photos: [Photo]
    let createdAt: Date
    let metadata: GenerationMetadata?
}

actor ConversationArchive {
    static let shared = ConversationArchive()
    private var revision = 0
    private let url = URL.applicationSupportDirectory.appending(path: "conversation.json")

    func load() throws -> [ArchivedMessage] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ArchivedMessage].self, from: Data(contentsOf: url))
    }

    func save(_ messages: [ArchivedMessage], revision newRevision: Int) throws {
        guard newRevision > revision else { return }
        revision = newRevision
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(messages)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
