import Foundation

public struct TextCorrection: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var original: String
    public var corrected: String
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        original: String,
        corrected: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.original = original
        self.corrected = corrected
        self.timestamp = timestamp
    }

    // Custom decoder to handle LLM responses that only have original/corrected fields
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.original = try container.decode(String.self, forKey: .original)
        self.corrected = try container.decode(String.self, forKey: .corrected)
        // Use defaults for id and timestamp if not present in JSON
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.timestamp = (try? container.decode(Date.self, forKey: .timestamp)) ?? Date()
    }

    private enum CodingKeys: String, CodingKey {
        case id, original, corrected, timestamp
    }
}

public struct Transcript: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var text: String
    public var audioPath: URL
    public var duration: TimeInterval
    public var sourceAppBundleID: String?
    public var sourceAppName: String?
    public var originalText: String?
    public var corrections: [TextCorrection]
    public var wasEdited: Bool {
        return originalText != nil && originalText != text
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        text: String,
        audioPath: URL,
        duration: TimeInterval,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        originalText: String? = nil,
        corrections: [TextCorrection] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.audioPath = audioPath
        self.duration = duration
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.originalText = originalText
        self.corrections = corrections
    }
}

public struct TranscriptionHistory: Codable, Equatable, Sendable {
    public var history: [Transcript] = []
    
    public init(history: [Transcript] = []) {
        self.history = history
    }
}
