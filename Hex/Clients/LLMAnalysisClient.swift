//
//  LLMAnalysisClient.swift
//  Hex
//
//  LLM-assisted text analysis for hotword extraction and correction detection
//

import ComposableArchitecture
import Foundation
import HexCore
import OSLog

private let llmAnalysisLogger = Logger(subsystem: "com.hex.app", category: "LLMAnalysis")

/// Client for LLM-assisted text analysis
@DependencyClient
struct LLMAnalysisClient: Sendable {
    var analyzeCorrections: @Sendable (LLMAnalysisRequest, LLMConfig) async throws -> LLMAnalysisResponse = { _, _ in
        LLMAnalysisResponse(corrections: [], hotwords: [], reasoning: nil)
    }

    var testConnection: @Sendable (LLMConfig) async throws -> Bool = { _ in false }
}

extension LLMAnalysisClient: TestDependencyKey {
    static let testValue = Self()
}

extension DependencyValues {
    var llmAnalysis: LLMAnalysisClient {
        get { self[LLMAnalysisClient.self] }
        set { self[LLMAnalysisClient.self] = newValue }
    }
}

// MARK: - Live Implementation

extension LLMAnalysisClient: DependencyKey {
    static let liveValue: Self = {
        @Sendable
        func analyzeCorrections(request: LLMAnalysisRequest, config: LLMConfig) async throws -> LLMAnalysisResponse {
            guard config.isValid else {
                throw LLMAnalysisError.invalidConfiguration
            }

            llmAnalysisLogger.info("Analyzing corrections with LLM: \(config.provider.rawValue)")

            let prompt = buildAnalysisPrompt(request: request)

            switch config.provider {
            case .ollama, .lmStudio, .openAI, .custom:
                return try await callOpenAICompatibleAPI(prompt: prompt, config: config)
            case .anthropic:
                return try await callAnthropicAPI(prompt: prompt, config: config)
            }
        }

        @Sendable
        func testConnection(config: LLMConfig) async throws -> Bool {
            guard config.isValid else {
                return false
            }

            let testRequest = LLMAnalysisRequest(
                originalText: "测试",
                editedText: "测试",
                language: "zh"
            )

            do {
                _ = try await analyzeCorrections(request: testRequest, config: config)
                return true
            } catch {
                llmAnalysisLogger.error("Connection test failed: \(error.localizedDescription)")
                return false
            }
        }

        return Self(
            analyzeCorrections: analyzeCorrections,
            testConnection: testConnection
        )
    }()
}

// MARK: - Helper Functions

private func buildAnalysisPrompt(request: LLMAnalysisRequest) -> String {
    return """
    你是一个文本对比分析助手。用户说了一段话，语音识别出了原文，然后用户手动修改了识别错误的部分。

    **原文（语音识别结果）**：
    \(request.originalText)

    **修改后（用户手动修正）**：
    \(request.editedText)

    **你的任务**：
    1. 对比两段文本，找出所有被修改的部分
    2. 从修改中提取值得学习的热词

    **分析原则**：
    - 可以返回单词级别的修改（如: "api" → "API"）
    - 也可以返回短语级别的修改（如: "六次体制" → "热词提示"）
    - 关键是找出**有意义的修正单元**，而不是机械地逐字对比

    **热词筛选规则**：
    - ✅ 技术术语：API、plist、json、React、TypeScript等
    - ✅ 专有名词：公司名、产品名、人名、地名
    - ✅ 中文专业词组：热词提示、词汇映射、语音识别等
    - ✅ 英文专业词：≥3字母
    - ❌ 常见词：的、是、在、这、那、一个、功能、测试等

    **返回JSON格式**：
    {
      "corrections": [
        {"original": "错误内容", "corrected": "正确内容"}
      ],
      "hotwords": ["词1", "词2"],
      "reasoning": "简短说明"
    }

    **示例1（单词级修改）**：
    原文: "我用antropic的api"
    修改: "我用Anthropic的API"

    返回:
    {
      "corrections": [
        {"original": "antropic", "corrected": "Anthropic"},
        {"original": "api", "corrected": "API"}
      ],
      "hotwords": ["Anthropic", "API"],
      "reasoning": "Anthropic是公司名，API是技术术语"
    }

    **示例2（短语级修改）**：
    原文: "测试LLM复制的六次体制功能"
    修改: "测试LLM辅助的热词提示功能"

    返回:
    {
      "corrections": [
        {"original": "复制", "corrected": "辅助"},
        {"original": "六次体制", "corrected": "热词提示"}
      ],
      "hotwords": ["辅助", "热词提示"],
      "reasoning": "辅助和热词提示都是专业术语"
    }

    **示例3（混合修改）**：
    原文: "使用palette工具antigravityanthropic还有EPS服务器"
    修改: "使用plist工具antigravity和anthropic还有vps服务器"

    返回:
    {
      "corrections": [
        {"original": "palette", "corrected": "plist"},
        {"original": "antigravityanthropic", "corrected": "antigravity"},
        {"original": "EPS", "corrected": "vps"}
      ],
      "hotwords": ["plist", "antigravity", "anthropic", "vps"],
      "reasoning": "plist是文件扩展名，antigravity和anthropic是技术词汇，vps是服务器术语"
    }

    **重要提示**：
    - 返回有意义的修正单元，不需要逐字拆分
    - 对于同音词修改的短语（如"六次体制"→"热词提示"），可以作为一个correction
    - hotwords可以包含修改后文本中的专业词汇，即使它们没有被修改

    只返回JSON，不要其他内容。不要使用markdown代码块。
    """
}

private func callOpenAICompatibleAPI(prompt: String, config: LLMConfig) async throws -> LLMAnalysisResponse {
    var baseURL = config.baseURL
    if !baseURL.hasSuffix("/") {
        baseURL += "/"
    }

    // Construct API endpoint
    let endpoint: String
    switch config.provider {
    case .ollama:
        endpoint = "\(baseURL)v1/chat/completions"
    case .lmStudio:
        endpoint = "\(baseURL)v1/chat/completions"
    case .openAI:
        endpoint = "\(baseURL)v1/chat/completions"
    case .custom:
        endpoint = "\(baseURL)v1/chat/completions"
    case .anthropic:
        fatalError("Use callAnthropicAPI for Anthropic provider")
    }

    guard let url = URL(string: endpoint) else {
        throw LLMAnalysisError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = config.timeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    if config.provider.requiresAPIKey {
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
    }

    let requestBody: [String: Any] = [
        "model": config.model,
        "messages": [
            ["role": "user", "content": prompt]
        ],
        "temperature": config.temperature,
        "max_tokens": config.maxTokens,
        "response_format": ["type": "json_object"]
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

    llmAnalysisLogger.debug("Calling OpenAI-compatible API: \(endpoint)")

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw LLMAnalysisError.invalidResponse
    }

    guard (200...299).contains(httpResponse.statusCode) else {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        llmAnalysisLogger.error("API error (\(httpResponse.statusCode)): \(errorMessage)")
        throw LLMAnalysisError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
    }

    let apiResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)

    guard let content = apiResponse.choices.first?.message.content else {
        throw LLMAnalysisError.emptyResponse
    }

    llmAnalysisLogger.debug("LLM response: \(content)")

    return try parseAnalysisResponse(content)
}

private func callAnthropicAPI(prompt: String, config: LLMConfig) async throws -> LLMAnalysisResponse {
    var baseURL = config.baseURL
    if !baseURL.hasSuffix("/") {
        baseURL += "/"
    }

    let endpoint = "\(baseURL)v1/messages"

    guard let url = URL(string: endpoint) else {
        throw LLMAnalysisError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = config.timeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

    let requestBody: [String: Any] = [
        "model": config.model,
        "messages": [
            ["role": "user", "content": prompt]
        ],
        "temperature": config.temperature,
        "max_tokens": config.maxTokens
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

    llmAnalysisLogger.debug("Calling Anthropic API")

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw LLMAnalysisError.invalidResponse
    }

    guard (200...299).contains(httpResponse.statusCode) else {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        llmAnalysisLogger.error("Anthropic API error (\(httpResponse.statusCode)): \(errorMessage)")
        throw LLMAnalysisError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
    }

    let apiResponse = try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)

    guard let content = apiResponse.content.first?.text else {
        throw LLMAnalysisError.emptyResponse
    }

    llmAnalysisLogger.debug("Anthropic response: \(content)")

    return try parseAnalysisResponse(content)
}

private func parseAnalysisResponse(_ jsonString: String) throws -> LLMAnalysisResponse {
    // Try to extract JSON from markdown code blocks if present
    let cleanedJSON: String
    if jsonString.contains("```json") {
        let pattern = #"```json\s*(.*?)\s*```"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: jsonString, range: NSRange(jsonString.startIndex..., in: jsonString)),
           let range = Range(match.range(at: 1), in: jsonString) {
            cleanedJSON = String(jsonString[range])
        } else {
            cleanedJSON = jsonString
        }
    } else if jsonString.contains("```") {
        let pattern = #"```\s*(.*?)\s*```"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: jsonString, range: NSRange(jsonString.startIndex..., in: jsonString)),
           let range = Range(match.range(at: 1), in: jsonString) {
            cleanedJSON = String(jsonString[range])
        } else {
            cleanedJSON = jsonString
        }
    } else {
        cleanedJSON = jsonString
    }

    guard let data = cleanedJSON.data(using: .utf8) else {
        llmAnalysisLogger.error("Failed to convert JSON string to data")
        throw LLMAnalysisError.invalidJSON
    }

    let decoder = JSONDecoder()
    do {
        let response = try decoder.decode(LLMAnalysisResponse.self, from: data)
        llmAnalysisLogger.info("Successfully parsed LLM response: \(response.corrections.count) corrections, \(response.hotwords.count) hotwords")
        return response
    } catch {
        llmAnalysisLogger.error("JSON decode failed: \(error.localizedDescription)")
        llmAnalysisLogger.error("JSON content: \(cleanedJSON)")
        throw LLMAnalysisError.invalidJSON
    }
}

// MARK: - API Response Models

private struct OpenAIChatResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let message: Message
    }

    struct Message: Codable {
        let content: String
    }
}

private struct AnthropicMessageResponse: Codable {
    let content: [Content]

    struct Content: Codable {
        let text: String?
    }
}

// MARK: - Errors

enum LLMAnalysisError: LocalizedError {
    case invalidConfiguration
    case invalidURL
    case invalidResponse
    case emptyResponse
    case invalidJSON
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "LLM配置无效，请检查API地址、模型名称和密钥"
        case .invalidURL:
            return "API地址格式错误"
        case .invalidResponse:
            return "API响应格式错误"
        case .emptyResponse:
            return "API返回空内容"
        case .invalidJSON:
            return "无法解析LLM返回的JSON"
        case .apiError(let statusCode, let message):
            return "API错误 (\(statusCode)): \(message)"
        }
    }
}
