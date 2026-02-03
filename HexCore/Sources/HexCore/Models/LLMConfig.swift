//
//  LLMConfig.swift
//  HexCore
//
//  Configuration for LLM-assisted text analysis
//

import Foundation

/// LLM provider type
public enum LLMProvider: String, Codable, CaseIterable, Sendable {
    case ollama = "Ollama"
    case lmStudio = "LM Studio"
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case custom = "Custom"

    public var displayName: String { rawValue }

    public var defaultBaseURL: String {
        switch self {
        case .ollama:
            return "http://localhost:11434"
        case .lmStudio:
            return "http://localhost:1234"
        case .openAI:
            return "https://api.openai.com"
        case .anthropic:
            return "https://api.anthropic.com"
        case .custom:
            return ""
        }
    }

    public var defaultModel: String {
        switch self {
        case .ollama:
            return "qwen2.5:7b"
        case .lmStudio:
            return "local-model"
        case .openAI:
            return "gpt-4o-mini"
        case .anthropic:
            return "claude-3-5-haiku-20241022"
        case .custom:
            return ""
        }
    }

    public var requiresAPIKey: Bool {
        switch self {
        case .ollama, .lmStudio:
            return false
        case .openAI, .anthropic, .custom:
            return true
        }
    }
}

/// LLM configuration
public struct LLMConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var provider: LLMProvider
    public var baseURL: String
    public var model: String
    public var apiKey: String
    public var temperature: Double
    public var maxTokens: Int
    public var timeout: TimeInterval

    public init(
        enabled: Bool = true,
        provider: LLMProvider = .ollama,
        baseURL: String = "",
        model: String = "",
        apiKey: String = "",
        temperature: Double = 0.1,
        maxTokens: Int = 500,
        timeout: TimeInterval = 10.0
    ) {
        self.enabled = enabled
        self.provider = provider
        self.baseURL = baseURL.isEmpty ? provider.defaultBaseURL : baseURL
        self.model = model.isEmpty ? provider.defaultModel : model
        self.apiKey = apiKey
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.timeout = timeout
    }

    public var isValid: Bool {
        !baseURL.isEmpty && !model.isEmpty && (!provider.requiresAPIKey || !apiKey.isEmpty)
    }
}

/// Analysis mode for text correction detection
public enum CorrectionAnalysisMode: String, Codable, CaseIterable, Sendable {
    case traditional = "Traditional"
    case llm = "LLM"

    public var displayName: String {
        switch self {
        case .traditional:
            return "传统算法"
        case .llm:
            return "LLM分析"
        }
    }

    public var description: String {
        switch self {
        case .traditional:
            return "基于Myers差分算法，快速准确，完全离线"
        case .llm:
            return "使用AI模型智能分析，理解语义，需要LLM支持"
        }
    }
}

/// LLM analysis request
public struct LLMAnalysisRequest: Codable {
    public let originalText: String
    public let editedText: String
    public let language: String?

    public init(originalText: String, editedText: String, language: String? = nil) {
        self.originalText = originalText
        self.editedText = editedText
        self.language = language
    }
}

/// LLM analysis response
public struct LLMAnalysisResponse: Codable {
    public let corrections: [TextCorrection]
    public let hotwords: [String]
    public let reasoning: String?

    public init(corrections: [TextCorrection], hotwords: [String], reasoning: String? = nil) {
        self.corrections = corrections
        self.hotwords = hotwords
        self.reasoning = reasoning
    }
}
