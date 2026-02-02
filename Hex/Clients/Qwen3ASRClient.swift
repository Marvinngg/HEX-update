//
//  Qwen3ASRClient.swift
//  Hex
//
//  Created for Qwen3-ASR integration
//

import Foundation
import Dependencies
import DependenciesMacros
import HexCore
import MLXAudioSTT
import MLXAudioCore
import MLX
import os.log
import AVFoundation

private let qwenLogger = os.Logger(subsystem: HexLog.subsystem, category: "Qwen3ASR")

@DependencyClient
struct Qwen3ASRClient {
  /// 转录音频文件
  var transcribe: @Sendable (URL, String, [String]) async throws -> String = { _, _, _ in "" }

  /// 下载模型
  var downloadModel: @Sendable (String, @escaping (Progress) -> Void) async throws -> Void

  /// 删除模型
  var deleteModel: @Sendable (String) async throws -> Void

  /// 检查模型是否已下载
  var isModelDownloaded: @Sendable (String) async -> Bool = { _ in false }

  /// 获取可用的 Qwen 模型列表
  var getAvailableModels: @Sendable () async -> [String] = { [] }
}

extension Qwen3ASRClient: DependencyKey {
  static var liveValue: Self {
    let live = Qwen3ASRClientLive()
    return Self(
      transcribe: { try await live.transcribe(url: $0, modelName: $1, hotwords: $2) },
      downloadModel: { try await live.downloadModel(modelName: $0, progressCallback: $1) },
      deleteModel: { try await live.deleteModel(modelName: $0) },
      isModelDownloaded: { await live.isModelDownloaded($0) },
      getAvailableModels: { await live.getAvailableModels() }
    )
  }
}

extension DependencyValues {
  var qwen3ASR: Qwen3ASRClient {
    get { self[Qwen3ASRClient.self] }
    set { self[Qwen3ASRClient.self] = newValue }
  }
}

// MARK: - Live Implementation

actor Qwen3ASRClientLive {
  private var model: GLMASRModel?
  private var currentModelName: String?

  private let modelsBaseFolder: URL = {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("com.kitlangton.Hex")
      .appendingPathComponent("models")
      .appendingPathComponent("qwen3-asr")
  }()

  // 模型映射：内部名称 -> Hugging Face 模型 ID
  private let modelMapping: [String: String] = [
    "qwen3-asr-0.6b": "mlx-community/Qwen3-ASR-0.6B-8bit",
    "qwen3-asr-1.7b": "mlx-community/Qwen3-ASR-1.7B-8bit",
  ]

  init() {
    // 确保模型目录存在
    try? FileManager.default.createDirectory(
      at: modelsBaseFolder,
      withIntermediateDirectories: true
    )
  }

  func transcribe(url: URL, modelName: String, hotwords: [String]) async throws -> String {
    let startTime = Date()
    qwenLogger.notice("Transcribing with Qwen3-ASR model=\(modelName) file=\(url.lastPathComponent)")

    // 加载模型（如果需要）
    try await ensureModelLoaded(modelName)

    guard let model = self.model else {
      throw NSError(
        domain: "Qwen3ASRClient",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to load Qwen3-ASR model: \(modelName)"]
      )
    }

    // 加载音频
    qwenLogger.debug("Loading audio file: \(url.path)")
    let (sampleRate, audioData) = try loadAudioArray(from: url)
    qwenLogger.debug("Audio loaded: sampleRate=\(sampleRate), samples=\(audioData.count)")

    // 执行转录
    qwenLogger.info("Starting transcription...")
    // 将 [Float] 转换为 MLXArray
    let audioMLXArray = MLXArray(audioData)
    let output = try await model.generate(audio: audioMLXArray)

    let elapsed = Date().timeIntervalSince(startTime)
    qwenLogger.notice("Qwen3-ASR transcription completed in \(String(format: "%.2f", elapsed))s, text length=\(output.text.count)")

    // 应用热词后处理（如果需要）
    if !hotwords.isEmpty {
      qwenLogger.debug("Hotwords provided: \(hotwords.joined(separator: ", "))")
      // TODO: 实现热词后处理逻辑
      // Qwen3-ASR 支持 context biasing，可以在模型推理时传入
    }

    return output.text
  }

  func downloadModel(modelName: String, progressCallback: @escaping (Progress) -> Void) async throws {
    guard let huggingFaceID = modelMapping[modelName] else {
      throw NSError(
        domain: "Qwen3ASRClient",
        code: -2,
        userInfo: [NSLocalizedDescriptionKey: "Unknown Qwen3-ASR model: \(modelName)"]
      )
    }

    qwenLogger.notice("Downloading Qwen3-ASR model: \(modelName) from \(huggingFaceID)")

    // 创建进度对象
    let progress = Progress(totalUnitCount: 100)
    progress.completedUnitCount = 0
    progressCallback(progress)

    // 使用 MLXAudioSTT 的模型加载功能
    // 这会自动从 Hugging Face 下载模型到 ~/.cache/huggingface
    do {
      qwenLogger.info("Initiating model download from Hugging Face: \(huggingFaceID)")

      // 显示下载进度
      progress.completedUnitCount = 10
      progressCallback(progress)

      // 加载模型（这会触发下载）
      qwenLogger.debug("Calling GLMASRModel.fromPretrained...")
      let model = try await GLMASRModel.fromPretrained(huggingFaceID)

      progress.completedUnitCount = 90
      progressCallback(progress)

      // 保存模型引用
      self.model = model
      self.currentModelName = modelName

      // 创建标记文件表示已下载
      let modelPath = modelsBaseFolder.appendingPathComponent(modelName)
      try? FileManager.default.createDirectory(at: modelPath, withIntermediateDirectories: true)
      try? "downloaded".write(to: modelPath.appendingPathComponent(".downloaded"), atomically: true, encoding: .utf8)

      progress.completedUnitCount = 100
      progressCallback(progress)

      qwenLogger.notice("Model downloaded and loaded successfully: \(modelName)")
    } catch let error as NSError {
      qwenLogger.error("Failed to download model: \(error.localizedDescription)")
      qwenLogger.error("Error domain: \(error.domain), code: \(error.code)")
      if let userInfo = error.userInfo as? [String: Any] {
        qwenLogger.error("Error details: \(String(describing: userInfo))")
      }

      // 提供更友好的错误信息
      var errorMessage = "无法下载 Qwen3-ASR 模型"
      if error.localizedDescription.contains("Modelfile") {
        errorMessage = "模型文件结构不完整，请稍后重试"
      } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
        errorMessage = "网络连接失败，请检查网络并重试"
      } else {
        errorMessage = error.localizedDescription
      }

      throw NSError(
        domain: "Qwen3ASRClient",
        code: error.code,
        userInfo: [NSLocalizedDescriptionKey: errorMessage]
      )
    }
  }

  func deleteModel(modelName: String) async throws {
    let modelPath = modelsBaseFolder.appendingPathComponent(modelName)

    if FileManager.default.fileExists(atPath: modelPath.path) {
      try FileManager.default.removeItem(at: modelPath)
      qwenLogger.notice("Deleted Qwen3-ASR model: \(modelName)")
    }

    // 如果删除的是当前加载的模型，清除引用
    if currentModelName == modelName {
      model = nil
      currentModelName = nil
    }
  }

  func isModelDownloaded(_ modelName: String) async -> Bool {
    guard let huggingFaceID = modelMapping[modelName] else {
      return false
    }

    // 检查 Hugging Face 缓存（这是主要的模型存储位置）
    let cacheBase = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".cache")
      .appendingPathComponent("huggingface")
      .appendingPathComponent("hub")

    let modelCachePath = cacheBase.appendingPathComponent("models--\(huggingFaceID.replacingOccurrences(of: "/", with: "--"))")

    // 检查模型目录是否存在
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: modelCachePath.path, isDirectory: &isDirectory)

    if exists && isDirectory.boolValue {
      // 进一步检查关键文件是否存在
      let configPath = modelCachePath.appendingPathComponent("snapshots").path
      let hasSnapshots = FileManager.default.fileExists(atPath: configPath)

      if hasSnapshots {
        qwenLogger.debug("Model found in cache: \(modelCachePath.path)")
        return true
      }
    }

    // 备选：检查我们的标记文件
    let modelPath = modelsBaseFolder.appendingPathComponent(modelName)
    let markerExists = FileManager.default.fileExists(atPath: modelPath.appendingPathComponent(".downloaded").path)

    return markerExists
  }

  func getAvailableModels() async -> [String] {
    return Array(modelMapping.keys)
  }

  // MARK: - Private Helpers

  private func ensureModelLoaded(_ modelName: String) async throws {
    // 如果已经加载了正确的模型，直接返回
    if currentModelName == modelName && model != nil {
      qwenLogger.debug("Model already loaded: \(modelName)")
      return
    }

    guard let huggingFaceID = modelMapping[modelName] else {
      throw NSError(
        domain: "Qwen3ASRClient",
        code: -2,
        userInfo: [NSLocalizedDescriptionKey: "Unknown Qwen3-ASR model: \(modelName)"]
      )
    }

    qwenLogger.info("Loading Qwen3-ASR model: \(modelName) from \(huggingFaceID)")

    do {
      qwenLogger.debug("Calling GLMASRModel.fromPretrained(\(huggingFaceID))")
      let loadedModel = try await GLMASRModel.fromPretrained(huggingFaceID)
      self.model = loadedModel
      self.currentModelName = modelName
      qwenLogger.notice("Model loaded successfully: \(modelName)")
    } catch let error as NSError {
      qwenLogger.error("Failed to load model: \(error.localizedDescription)")
      qwenLogger.error("Error domain: \(error.domain), code: \(error.code)")

      // 提供更详细的错误信息
      var errorMessage = "无法加载 Qwen3-ASR 模型"
      if error.localizedDescription.contains("not found") || error.localizedDescription.contains("does not exist") {
        errorMessage = "模型未下载，请先在设置中下载模型"
      } else if error.localizedDescription.contains("Modelfile") {
        errorMessage = "模型文件不完整，请尝试重新下载"
      } else {
        errorMessage = error.localizedDescription
      }

      throw NSError(
        domain: "Qwen3ASRClient",
        code: error.code,
        userInfo: [NSLocalizedDescriptionKey: errorMessage]
      )
    }
  }

  private func loadAudioArray(from url: URL) throws -> (sampleRate: Float, audio: [Float]) {
    // 使用 AVFoundation 加载音频
    let audioFile = try AVAudioFile(forReading: url)
    let format = audioFile.processingFormat
    let frameCount = UInt32(audioFile.length)

    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
      throw NSError(
        domain: "Qwen3ASRClient",
        code: -3,
        userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer"]
      )
    }

    try audioFile.read(into: buffer)

    // 转换为 Float 数组
    guard let floatChannelData = buffer.floatChannelData else {
      throw NSError(
        domain: "Qwen3ASRClient",
        code: -4,
        userInfo: [NSLocalizedDescriptionKey: "Failed to get float channel data"]
      )
    }

    let channelCount = Int(format.channelCount)
    let frameLength = Int(buffer.frameLength)

    // 如果是立体声，转换为单声道（取平均值）
    var audioData: [Float] = []
    if channelCount == 2 {
      let leftChannel = Array(UnsafeBufferPointer(start: floatChannelData[0], count: frameLength))
      let rightChannel = Array(UnsafeBufferPointer(start: floatChannelData[1], count: frameLength))
      audioData = zip(leftChannel, rightChannel).map { ($0 + $1) / 2.0 }
    } else {
      audioData = Array(UnsafeBufferPointer(start: floatChannelData[0], count: frameLength))
    }

    return (Float(format.sampleRate), audioData)
  }
}
