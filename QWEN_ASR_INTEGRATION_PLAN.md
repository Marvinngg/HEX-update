# Qwen3-ASR 集成实现计划

## 📋 概述

集成阿里云通义千问 Qwen3-ASR 模型到 HEX 应用，提供：
- ✅ 52 种语言支持（包括 22 种中文方言）
- ✅ SOTA 级别准确率
- ✅ 完全本地化推理
- ✅ 支持热词功能
- ✅ 音乐/歌曲识别
- ✅ 自动语言检测

---

## 🎯 技术选型

### 使用 MLX-Audio Swift

- **项目地址**：https://github.com/Blaizzy/mlx-audio-swift
- **优势**：
  - 原生 Swift 实现
  - 基于 Apple MLX 框架（比 CoreML 更现代）
  - 极致性能和低功耗
  - 完全本地化

---

## 📦 第一步：添加依赖

### 1.1 添加 Swift Package

在 Xcode 中：
1. File → Add Package Dependencies...
2. 输入 URL：`https://github.com/Blaizzy/mlx-audio-swift`
3. 选择 `main` 分支
4. 添加 `MLXAudioSTT` 产品

或者手动编辑 `project.pbxproj`（参考 WhisperKit 和 FluidAudio 的配置方式）

### 1.2 安装 MLX 框架

```bash
pip install mlx-audio
```

---

## 🔧 第二步：创建 Qwen3ASRClient

### 文件：`Hex/Clients/Qwen3ASRClient.swift`

```swift
import Foundation
import Dependencies
import DependenciesMacros
import HexCore
// import MLXAudioSTT  // 待添加依赖后取消注释

private let qwenLogger = HexLog.qwen

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
}

extension Qwen3ASRClient: DependencyKey {
  static var liveValue: Self {
    let live = Qwen3ASRClientLive()
    return Self(
      transcribe: { try await live.transcribe(url: $0, modelName: $1, hotwords: $2) },
      downloadModel: { try await live.downloadModel(modelName: $0, progressCallback: $1) },
      deleteModel: { try await live.deleteModel(modelName: $0) },
      isModelDownloaded: { await live.isModelDownloaded($0) }
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
  // private var model: MLXAudioSTTModel?  // 待实现
  private var currentModelName: String?

  private let modelsBaseFolder: URL = {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("com.kitlangton.Hex")
      .appendingPathComponent("models")
      .appendingPathComponent("qwen3-asr")
  }()

  func transcribe(url: URL, modelName: String, hotwords: [String]) async throws -> String {
    qwenLogger.notice("Transcribing with Qwen3-ASR model=\(modelName)")

    // TODO: 实现转录逻辑
    // 1. 加载模型（如果未加载）
    // 2. 加载音频文件
    // 3. 使用热词（如果提供）
    // 4. 执行转录
    // 5. 返回结果

    throw NSError(
      domain: "Qwen3ASRClient",
      code: -1,
      userInfo: [NSLocalizedDescriptionKey: "Qwen3-ASR integration not yet implemented"]
    )
  }

  func downloadModel(modelName: String, progressCallback: @escaping (Progress) -> Void) async throws {
    qwenLogger.notice("Downloading Qwen3-ASR model: \(modelName)")

    // TODO: 实现模型下载
    // 从 Hugging Face mlx-community 下载模型
    // 例如：mlx-community/Qwen3-ASR-0.6B-8bit
  }

  func deleteModel(modelName: String) async throws {
    let modelPath = modelsBaseFolder.appendingPathComponent(modelName)
    try FileManager.default.removeItem(at: modelPath)
    qwenLogger.notice("Deleted Qwen3-ASR model: \(modelName)")
  }

  func isModelDownloaded(_ modelName: String) async -> Bool {
    let modelPath = modelsBaseFolder.appendingPathComponent(modelName)
    return FileManager.default.fileExists(atPath: modelPath.path)
  }
}
```

---

## 🔌 第三步：集成到 TranscriptionClient

### 修改 `Hex/Clients/TranscriptionClient.swift`

#### 3.1 添加 Qwen 检测函数

```swift
private func isQwen(_ name: String) -> Bool {
  name.lowercased().hasPrefix("qwen3-asr")
}
```

#### 3.2 修改 `transcribe` 方法

```swift
func transcribe(
  url: URL,
  model: String,
  options: DecodingOptions,
  hotwords: [String],
  progressCallback: @escaping (Progress) -> Void
) async throws -> String {
  let startAll = Date()

  // 检测是否是 Qwen3-ASR 模型
  if isQwen(model) {
    transcriptionLogger.notice("Using Qwen3-ASR for transcription")
    @Dependency(\.qwen3ASR) var qwen
    let result = try await qwen.transcribe(url, model, hotwords)
    transcriptionLogger.info("Qwen3-ASR transcription completed in \(String(format: "%.2f", Date().timeIntervalSince(startAll)))s")
    return result
  }

  // 检测是否是 Parakeet 模型
  if isParakeet(model) {
    // ... 现有 Parakeet 逻辑 ...
  }

  // WhisperKit 逻辑
  // ... 现有 WhisperKit 逻辑 ...
}
```

#### 3.3 修改 `downloadModel` 方法

```swift
var downloadModel: @Sendable (String, @escaping (Progress) -> Void) async throws -> Void = { model, progress in
  if self.isQwen(model) {
    @Dependency(\.qwen3ASR) var qwen
    try await qwen.downloadModel(model, progress)
  } else if self.isParakeet(model) {
    // ... Parakeet 逻辑 ...
  } else {
    // ... WhisperKit 逻辑 ...
  }
}
```

---

## 📝 第四步：更新 UI

### 4.1 添加 Qwen 图标或标识

在 `ModelDownloadFeature.swift` 或相关 UI 文件中，为 Qwen 模型添加特殊标识：

```swift
public var badge: String? {
  if internalName.hasPrefix("qwen3-asr") {
    return "BEST FOR CHINESE"
  }
  // ... 其他徽章 ...
}
```

---

## 🧪 第五步：测试

### 5.1 单元测试

创建 `Qwen3ASRClientTests.swift`：
- 测试模型下载
- 测试转录功能
- 测试热词支持
- 测试中文方言识别

### 5.2 集成测试

1. 下载 Qwen3-ASR-0.6B 模型
2. 录制中文音频
3. 验证转录准确率
4. 测试热词功能
5. 测试中文方言（粤语、四川话等）

---

## 📚 参考资料

- [Qwen3-ASR GitHub](https://github.com/QwenLM/Qwen3-ASR)
- [MLX-Audio Swift GitHub](https://github.com/Blaizzy/mlx-audio-swift)
- [MLX-Audio Python](https://github.com/Blaizzy/mlx-audio)
- [Qwen3-ASR 技术报告](https://arxiv.org/html/2601.21337v1)
- [MLX-Community Qwen3-ASR 模型](https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit)

---

## ⚠️ 注意事项

### 模型大小

- **Qwen3-ASR-0.6B**：约 1.2GB（8-bit 量化后）
- **Qwen3-ASR-1.7B**：约 3.4GB（8-bit 量化后）

### 性能要求

- 需要 Apple Silicon (M1 或更新)
- 推荐 16GB+ 内存（用于 1.7B 模型）

### 热词支持

Qwen3-ASR 官方文档未明确说明是否支持 promptTokens 风格的热词，需要测试验证。可能需要使用后处理方式（类似字词替换）。

---

## 🎯 实施优先级

### Phase 1（基础集成）
1. ✅ 添加模型配置到 models.json
2. ⏳ 添加 MLX-Audio Swift 依赖
3. ⏳ 创建 Qwen3ASRClient 基础结构
4. ⏳ 实现模型检测逻辑

### Phase 2（核心功能）
5. ⏳ 实现模型下载功能
6. ⏳ 实现基础转录功能
7. ⏳ 集成到 TranscriptionClient
8. ⏳ 更新 UI 显示

### Phase 3（高级功能）
9. ⏳ 实现热词支持
10. ⏳ 实现语言自动检测
11. ⏳ 实现中文方言识别
12. ⏳ 性能优化

### Phase 4（测试和优化）
13. ⏳ 单元测试
14. ⏳ 集成测试
15. ⏳ 性能测试
16. ⏳ 文档完善

---

## 💡 开发建议

1. **先测试 Python 版本**：使用 `mlx-audio` Python 库验证功能和性能
2. **渐进式集成**：先实现基础转录，再添加高级功能
3. **性能监控**：记录转录时间、内存使用等指标
4. **用户体验**：提供清晰的下载进度、错误提示
5. **降级策略**：如果 Qwen 失败，自动降级到 WhisperKit

---

## 📊 预期效果

### 与 Whisper Medium 对比

| 指标 | Whisper Medium | Qwen3-ASR 0.6B | Qwen3-ASR 1.7B |
|------|---------------|----------------|----------------|
| 大小 | 1.5GB | 1.2GB | 3.4GB |
| 准确率 | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| 速度 | ⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| 中文支持 | ✅ | ✅✅（更好） | ✅✅（最好） |
| 方言支持 | ❌ | ✅ 22种 | ✅ 22种 |
| 音乐识别 | ❌ | ✅ | ✅ |

---

## 🚀 下一步

1. 添加 MLX-Audio Swift 依赖到项目
2. 创建 Qwen3ASRClient.swift 文件
3. 实现基础转录功能
4. 测试并验证效果
5. 根据测试结果优化实现

如有问题，请参考：
- MLX-Audio Swift 示例：https://github.com/Blaizzy/mlx-audio-swift/tree/main/Examples
- Qwen3-ASR 文档：https://github.com/QwenLM/Qwen3-ASR#usage
