# HEX 文档目录

本目录包含 HEX 语音识别应用的技术文档。

## 📂 文档组织

### LLM 功能文档 (`llm-features/`)
AI 智能学习热词相关的功能文档：

- **[LLM_HOTWORD_FEATURE.md](llm-features/LLM_HOTWORD_FEATURE.md)** - LLM 热词功能完整说明
  - 功能介绍
  - 支持的 LLM 提供商
  - 配置指南（Ollama、LM Studio、OpenAI、Anthropic）
  - 使用示例
  - 故障排查

- **[ANALYSIS_MODE_COMPARISON.md](llm-features/ANALYSIS_MODE_COMPARISON.md)** - 分析模式对比
  - 传统算法 vs LLM 分析
  - 实际案例对比
  - 性能和准确率分析
  - 推荐配置

- **[HOTWORD_LEARNING_LOGIC.md](llm-features/HOTWORD_LEARNING_LOGIC.md)** - 热词学习逻辑详解
  - 为什么只从修改中学习
  - 传统模式 vs LLM 模式的区别
  - 词汇映射 vs 热词
  - 常见问题解答

- **[LLM_MODE_CHANGES.md](llm-features/LLM_MODE_CHANGES.md)** - 最新功能修改
  - 删除混合模式
  - 默认启用 LLM
  - 关键代码位置
  - 测试清单

### 开发文档

- **[hotkey-semantics.md](hotkey-semantics.md)** - 快捷键语义说明
- **[parakeet-short-audio-plan.md](parakeet-short-audio-plan.md)** - Parakeet 短音频优化计划
- **[release-pipeline-plan.md](release-pipeline-plan.md)** - 发布流程计划
- **[release-process.md](release-process.md)** - 发布流程说明

### 归档文档 (`archived/`)
历史实现文档，保留作为参考：

- **IMPLEMENTATION_SUMMARY.md** - 早期实现总结
- **QWEN_ASR_INTEGRATION_PLAN.md** - Qwen ASR 集成计划
- **QWEN_INTEGRATION_COMPLETE.md** - Qwen 集成完成报告

## 🚀 快速导航

### 我想...

- **了解 HEX 的所有功能** → 查看根目录 [HEX_EDITING_FEATURES.md](../HEX_EDITING_FEATURES.md)
- **配置 AI 智能学习** → [llm-features/LLM_HOTWORD_FEATURE.md](llm-features/LLM_HOTWORD_FEATURE.md)
- **对比传统和 AI 模式** → [llm-features/ANALYSIS_MODE_COMPARISON.md](llm-features/ANALYSIS_MODE_COMPARISON.md)
- **理解热词学习原理** → [llm-features/HOTWORD_LEARNING_LOGIC.md](llm-features/HOTWORD_LEARNING_LOGIC.md)
- **查看最新改动** → [llm-features/LLM_MODE_CHANGES.md](llm-features/LLM_MODE_CHANGES.md)
- **了解项目变更历史** → 查看根目录 [CHANGELOG.md](../CHANGELOG.md)

## 📝 文档维护

- 主要功能说明放在根目录的 [HEX_EDITING_FEATURES.md](../HEX_EDITING_FEATURES.md)
- 技术细节和专题文档放在 `docs/` 相应子目录
- 过时的实现文档移至 `docs/archived/`
- 更新日志记录在根目录的 [CHANGELOG.md](../CHANGELOG.md)
