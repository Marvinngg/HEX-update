# LLM 辅助热词提取功能说明

## 功能概述

HEX现在支持使用本地或云端LLM来智能分析文本修改并提取热词，相比传统规则算法更加灵活和准确。

### 三种分析模式

1. **传统算法** (默认)
   - 基于Myers差分算法
   - 完全离线，速度快
   - 适合一般使用场景

2. **LLM分析**
   - 使用AI模型理解语义
   - 更智能的热词提取
   - 需要配置LLM

3. **混合模式**
   - 优先使用LLM
   - LLM失败时自动降级到传统算法
   - 兼顾智能性和可靠性

---

## 支持的LLM提供商

### 1. Ollama (推荐)
**本地运行，完全免费**

```bash
# 安装Ollama
brew install ollama

# 下载推荐模型
ollama pull qwen2.5:7b
```

**配置**：
- API地址：`http://localhost:11434`
- 模型名称：`qwen2.5:7b`
- 无需API密钥

### 2. LM Studio
**本地运行，图形界面**

下载：https://lmstudio.ai

**配置**：
- API地址：`http://localhost:1234`
- 模型名称：在LM Studio中下载的模型名
- 无需API密钥

### 3. OpenAI
**云端服务，需要付费**

**配置**：
- API地址：`https://api.openai.com`
- 模型名称：`gpt-4o-mini` (推荐) 或 `gpt-4o`
- API密钥：从 https://platform.openai.com/api-keys 获取

### 4. Anthropic Claude
**云端服务，需要付费**

**配置**：
- API地址：`https://api.anthropic.com`
- 模型名称：`claude-3-5-haiku-20241022`
- API密钥：从 https://console.anthropic.com/ 获取

### 5. 自定义 (OpenAI兼容)
**任何支持OpenAI格式的API**

可以配置：
- Cloudflare Workers AI
- Together AI
- DeepSeek
- 其他兼容OpenAI API的服务

---

## 使用指南

### 步骤1：配置LLM

1. 打开 HEX 设置
2. 找到 "LLM 辅助分析" section
3. 开启 "启用" 开关
4. 选择分析模式（传统/LLM/混合）
5. 如果选择了LLM模式：
   - 选择提供商
   - 填写API地址
   - 填写模型名称
   - （如需要）填写API密钥
6. 点击 "测试连接" 验证配置

### 步骤2：使用

配置完成后，正常使用即时编辑功能：

1. 录音并转录
2. 在编辑窗口修改错误词汇
3. 勾选 "记住我的修改并学习"
4. 点击 "确认并粘贴"

系统会根据配置的模式自动提取热词。

---

## LLM Prompt 说明

系统发送给LLM的prompt格式：

```
你是一个专业的文本分析助手。用户通过语音识别输入了文本，然后手动修改了一些错误。请分析原文和修改后的文本，提取出：
1. 具体哪些词被修改了（word-level corrections）
2. 应该添加到热词列表的重要词汇

**原文**：
{originalText}

**修改后**：
{editedText}

请以JSON格式返回结果，格式如下：
{
  "corrections": [
    {"original": "错误词", "corrected": "正确词"}
  ],
  "hotwords": ["重要词1", "重要词2"],
  "reasoning": "简要说明为什么这些词重要"
}

**规则**：
1. corrections: 只包含真正被替换的词，不包括新增或删除的词
2. hotwords: 从修改后的词中提取，跳过常见词（的、是、在、the、and等）
3. 中文热词：2-10字的专有名词、术语
4. 英文热词：≥3字母的专业词汇、人名、地名、品牌名
5. 如果原文=修改后，返回空数组

只返回JSON，不要其他解释。
```

---

## 对比效果示例

### 场景：中英混合文本修正

**输入**：
```
原文: "有个软件叫Cloudbot它的名字也可以叫Molatebot"
修改: "有个软件叫clawdbot它的名字也可以叫moltbot"
```

**传统算法结果**：
```
检测到修正:
  - Cloudbot → clawdbot
  - Molatebot → moltbot

添加热词:
  - clawdbot
  - moltbot
```

**LLM分析结果**（更智能）：
```json
{
  "corrections": [
    {"original": "Cloudbot", "corrected": "clawdbot"},
    {"original": "Molatebot", "corrected": "moltbot"}
  ],
  "hotwords": ["clawdbot", "moltbot"],
  "reasoning": "这两个是软件名称，都是专有名词，应该添加为热词以提高识别准确率"
}
```

**优势**：LLM可以理解语义，识别专有名词，过滤更精准

---

## 性能对比

| 模式 | 速度 | 准确率 | 网络 | 成本 |
|------|------|--------|------|------|
| 传统算法 | 极快 (<1ms) | 高 (90%) | 不需要 | 免费 |
| LLM (Ollama) | 快 (~500ms) | 极高 (95%+) | 不需要 | 免费 |
| LLM (OpenAI) | 中 (~1-2s) | 极高 (98%+) | 需要 | 付费 |
| 混合模式 | 自适应 | 极高 | 可选 | 可选 |

---

## 高级配置

### Temperature (温度)
- 范围：0.0 - 2.0
- 推荐：0.3
- 说明：越低越稳定，越高越创造性

### Max Tokens (最大tokens)
- 推荐：500
- 说明：LLM返回的最大token数量

### Timeout (超时时间)
- 推荐：10秒
- 说明：等待LLM响应的最大时间

---

## 故障排除

### 1. 连接测试失败

**Ollama**：
```bash
# 检查Ollama是否运行
ollama list

# 启动Ollama服务
ollama serve
```

**LM Studio**：
- 确保已启动本地服务器
- 检查端口号是否为1234

**OpenAI/Anthropic**：
- 检查API密钥是否正确
- 检查网络连接

### 2. LLM返回格式错误

可能原因：
- 模型不支持JSON格式
- Temperature设置过高
- Max Tokens设置过低

解决方案：
- 切换到支持JSON的模型（如qwen2.5、gpt-4o-mini）
- 降低Temperature到0.1-0.5
- 增加Max Tokens到500以上

### 3. 速度太慢

解决方案：
- 使用本地模型（Ollama、LM Studio）
- 切换到更小的模型（如qwen2.5:3b）
- 使用混合模式或传统模式

---

## 推荐配置

### 日常使用
```
模式：混合模式
提供商：Ollama
模型：qwen2.5:7b
Temperature：0.3
```

### 追求速度
```
模式：传统算法
```

### 追求准确率（不在意成本）
```
模式：LLM分析
提供商：OpenAI
模型：gpt-4o
Temperature：0.2
```

---

## 技术实现细节

### 文件结构

```
HexCore/Sources/HexCore/Models/
  ├── LLMConfig.swift                 # LLM配置模型

Hex/Clients/
  ├── LLMAnalysisClient.swift         # LLM客户端实现

Hex/Features/Settings/
  ├── LLMConfigSectionView.swift      # LLM配置UI

Hex/Features/Transcription/
  ├── TranscriptionFeature.swift      # 集成LLM热词提取
```

### API支持

**OpenAI Compatible**：
- Ollama：`/v1/chat/completions`
- LM Studio：`/v1/chat/completions`
- OpenAI：`/v1/chat/completions`

**Anthropic**：
- Claude：`/v1/messages`

### 错误处理

LLM模式包含完整的降级机制：
1. LLM调用失败 → 自动切换到传统算法
2. JSON解析失败 → 记录错误，返回空结果
3. 超时 → 取消请求，使用传统算法

---

## 隐私说明

- **本地模型（Ollama/LM Studio）**：所有数据完全在本地处理，不发送到互联网
- **云端模型（OpenAI/Anthropic）**：文本会发送到相应服务商
- **建议**：处理敏感内容时使用本地模型

---

## 贡献

如果您想添加新的LLM提供商支持，请修改：
1. `LLMConfig.swift` - 添加新的provider case
2. `LLMAnalysisClient.swift` - 实现API调用逻辑

欢迎提交 PR！🚀
