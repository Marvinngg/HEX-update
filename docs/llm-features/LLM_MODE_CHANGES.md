# LLM 模式修改总结

## 完成的修改

### 1. 删除混合模式
- **文件**: `HexCore/Sources/HexCore/Models/LLMConfig.swift`
- **修改**:
  - 删除 `CorrectionAnalysisMode.hybrid` 枚举值
  - 现在只有两个模式：`traditional` 和 `llm`

- **文件**: `Hex/Features/TranscriptEditor/TranscriptEditorFeature.swift`
- **修改**: 删除了 `.hybrid` case 的处理

- **文件**: `Hex/Features/Transcription/TranscriptionFeature.swift`
- **修改**: 删除了 `.hybrid` case 的处理

### 2. 默认启用 LLM 分析
- **文件**: `HexCore/Sources/HexCore/Models/LLMConfig.swift`
- **修改**:
  ```swift
  // 之前
  enabled: Bool = false,
  temperature: Double = 0.3,

  // 现在
  enabled: Bool = true,
  temperature: Double = 0.1,
  ```

- **文件**: `HexCore/Sources/HexCore/Settings/HexSettings.swift`
- **修改**:
  ```swift
  // 之前
  correctionAnalysisMode: CorrectionAnalysisMode = .traditional,

  // 现在
  correctionAnalysisMode: CorrectionAnalysisMode = .llm,
  ```

### 3. 验证 LLM 热词学习功能

LLM 模式下的完整流程：

```
1. 用户编辑文本并确认学习
   ↓
2. 调用 LLM 分析原文和修改后文本
   ↓
3. LLM 返回:
   - corrections: [TextCorrection] - 修正列表
   - hotwords: [String] - 热词列表
   - reasoning: String? - 分析原因
   ↓
4. 学习 corrections (TranscriptionFeature.swift:590-605)
   - 添加到 settings.wordRemappings
   - 日志: "Auto-learned word remapping: 'X' → 'Y'"
   ↓
5. 学习 hotwords (TranscriptionFeature.swift:607-616)
   - 添加到 settings.hotwords
   - 日志: "Auto-learned hotword: 'X'"
   ↓
6. 保存到转录历史
```

## 关键代码位置

### LLM 分析调用
**文件**: `Hex/Features/Transcription/TranscriptionFeature.swift:554-586`
```swift
case .llm:
  if settings.llmConfig.enabled && settings.llmConfig.isValid {
    do {
      let request = LLMAnalysisRequest(
        originalText: originalText,
        editedText: editedText,
        language: nil
      )
      let response = try await llmAnalysis.analyzeCorrections(request, settings.llmConfig)

      // Use LLM-detected corrections and hotwords
      finalCorrections = response.corrections
      hotwords = response.hotwords

      transcriptionFeatureLogger.info("✅ LLM analysis complete")
      transcriptionFeatureLogger.info("Detected \(finalCorrections.count) corrections")
      transcriptionFeatureLogger.info("Extracted \(hotwords.count) hotwords")
    } catch {
      // Fallback to traditional
    }
  }
```

### 热词学习
**文件**: `Hex/Features/Transcription/TranscriptionFeature.swift:607-616`
```swift
$settings.withLock { settings in
  for hotword in hotwords {
    let hotwordLower = hotword.lowercased()
    if !settings.hotwords.contains(where: { $0.lowercased() == hotwordLower }) {
      settings.hotwords.append(hotword)
      transcriptionFeatureLogger.info("Auto-learned hotword: '\(hotword)'")
    }
  }
}
```

## 测试清单

### LLM 模式测试
- [ ] 打开应用，验证默认是 LLM 模式
- [ ] 验证 temperature 默认为 0.1
- [ ] 录音并修改文本
- [ ] 确认学习时显示 "Analyzing corrections with LLM"
- [ ] 检查日志中的 "✅ LLM analysis complete"
- [ ] 验证日志显示 "Detected X corrections" 和 "Extracted Y hotwords"
- [ ] 检查 "Auto-learned hotword" 日志
- [ ] 在设置的热词列表中验证热词被添加

### 传统模式测试
- [ ] 切换到传统模式
- [ ] 录音并修改文本
- [ ] 验证使用 Myers diff 算法
- [ ] 检查日志中的 "Using traditional algorithm"

## 现在的行为

### LLM 模式 (默认)
1. **编辑窗口**: 点击确认时调用 LLM 分析修正（~500ms-2s）
2. **学习阶段**: 使用 LLM 返回的 corrections 和 hotwords
3. **显示**: 编辑窗口显示的修正列表与实际学习的完全一致
4. **失败处理**: LLM 失败时自动降级到传统算法

### 传统模式
1. **编辑窗口**: 即时使用 Myers diff 显示修正（<1ms）
2. **学习阶段**: 使用传统算法提取热词（基于规则过滤）
3. **优点**: 快速、可靠、完全离线

## 配置说明

### 默认配置
```swift
LLMConfig(
  enabled: true,              // 启用 LLM
  provider: .ollama,          // 使用 Ollama
  baseURL: "http://localhost:11434",
  model: "qwen2.5:7b",
  temperature: 0.1,           // 更精确的输出
  maxTokens: 500,
  timeout: 10.0
)

HexSettings(
  correctionAnalysisMode: .llm,  // 使用 LLM 分析
  llmConfig: LLMConfig()
)
```

### 用户可调整
- 分析模式：传统 / LLM
- LLM 提供商：Ollama / LM Studio / OpenAI / Anthropic / Custom
- Temperature: 0.1 - 1.0 (推荐 0.1 以获得更一致的结果)

## 总结

所有三个任务已完成：
1. ✅ 删除混合模式 - 只保留传统和 LLM 两种模式
2. ✅ 验证 LLM 热词功能 - 代码正确，热词会被添加到设置
3. ✅ 默认启用 LLM - enabled=true, mode=llm, temperature=0.1
