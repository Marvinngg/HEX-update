# HEX 即时编辑和热词功能实现总结

## 🎯 实现的功能

### 1. **即时编辑功能**
转录完成后立即弹出编辑窗口，用户可以修改文本后再粘贴。

### 2. **热词功能**
在转录时使用热词列表，提高专业词汇的识别准确率。

### 3. **自动学习机制**
记录用户的修改，自动添加到字词替换规则和热词列表。

---

## 📁 修改的文件

### **核心数据模型**

#### 1. `HexCore/Sources/HexCore/Models/TranscriptionHistory.swift`
- ✅ 添加了 `TextCorrection` 结构体（记录修改）
- ✅ 扩展了 `Transcript` 模型：
  - `originalText: String?` - 原始转录文本
  - `corrections: [TextCorrection]` - 修改记录
  - `wasEdited: Bool` - 是否被编辑过

#### 2. `HexCore/Sources/HexCore/Settings/HexSettings.swift`
- ✅ 添加了新的设置项：
  - `hotwords: [String]` - 热词列表
  - `enableInstantEdit: Bool` - 是否启用即时编辑（默认 `true`）
  - `autoLearnFromEdits: Bool` - 是否自动学习（默认 `true`）

---

### **UI 组件（全新创建）**

#### 3. `Hex/Features/TranscriptEditor/TranscriptEditorFeature.swift`
全新的 TCA Feature，包含：
- **State**: 转录文本、原始文本、时长、来源应用、自动学习开关
- **Action**: `confirmTapped`, `cancelTapped`, `delegate`
- **View**: 编辑窗口 UI
  - 多行文本编辑框
  - 显示录音信息
  - "记住修改"复选框
  - 确认/取消按钮
  - 支持快捷键（Enter = 确认，Esc = 取消）

#### 4. `Hex/Features/TranscriptEditor/TranscriptEditorWindow.swift`
窗口管理和依赖注入：
- `TranscriptEditorWindowController` - 窗口控制器
- `TranscriptEditorClient` - 依赖客户端
- `TranscriptEditorActor` - Actor 管理窗口生命周期

---

### **转录流程集成**

#### 5. `Hex/Features/Transcription/TranscriptionFeature.swift`
**修改内容：**

##### a) 添加热词支持（第 362-370 行）
```swift
let hotwordsPrompt = settings.hotwords.isEmpty ? nil : settings.hotwords.joined(separator: ", ")

let decodeOptions = DecodingOptions(
  language: language,
  detectLanguage: language == nil,
  chunkingStrategy: .vad,
  prompt: hotwordsPrompt  // ← 新增热词参数
)
```

##### b) 添加新的 Action（第 55-63 行）
```swift
case transcriptionEdited(
  originalText: String,
  editedText: String,
  shouldLearn: Bool,
  corrections: [TextCorrection],
  duration: TimeInterval,
  sourceAppBundleID: String?,
  sourceAppName: String?,
  audioURL: URL
)
```

##### c) 修改转录结果处理流程（第 465-522 行）
```swift
if enableInstantEdit {
  // 显示编辑窗口
  await transcriptEditor.show(...)
} else {
  // 直接粘贴
  try await finalizeRecordingAndStoreTranscript(...)
}
```

##### d) 新增 `handleTranscriptionEdited` 方法（第 525-590 行）
处理用户编辑后的逻辑：
- 自动学习：添加修改到 `wordRemappings`
- 自动添加修正词到 `hotwords`
- 保存带有修改记录的转录历史

##### e) 更新 `finalizeRecordingAndStoreTranscript` 方法
添加参数：
- `originalText: String?` - 原始文本
- `corrections: [TextCorrection]` - 修改记录

---

## 🔄 完整工作流程

```
1. 用户按住热键录音
   ↓
2. 停止录音，开始转录
   ├─ 使用热词列表（hotwords）提示转录模型
   ↓
3. 转录完成，应用字词删除和替换
   ↓
4. 如果启用即时编辑（enableInstantEdit = true）
   ├─ 弹出编辑窗口
   ├─ 显示转录文本
   ├─ 用户可以修改
   ├─ 点击"确认并粘贴"
   ↓
5. 如果用户修改了文本且启用自动学习
   ├─ 检测修改的词汇（original → corrected）
   ├─ 自动添加到字词替换规则（wordRemappings）
   ├─ 自动添加修正词到热词列表（hotwords）
   ├─ 记录修改历史
   ↓
6. 粘贴到目标应用
   ↓
7. 保存转录历史
   ├─ 包含原始文本（originalText）
   ├─ 包含修改记录（corrections）
```

---

## ⚙️ 用户设置

### **新增设置项**

| 设置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `hotwords` | `[String]` | `[]` | 热词列表，转录时提示模型 |
| `enableInstantEdit` | `Bool` | `true` | 转录后是否显示编辑窗口 |
| `autoLearnFromEdits` | `Bool` | `true` | 是否从编辑中自动学习 |

### **设置管理**

用户可以通过以下方式管理：
1. **热词列表**：在设置界面添加/删除热词
2. **即时编辑**：开关是否显示编辑窗口
3. **自动学习**：开关是否自动从修改中学习

---

## 🔧 下一步需要做的事

### **1. 添加热词管理界面到设置**
需要在 `Hex/Features/Settings/` 创建新的设置视图：
- 显示热词列表
- 添加/删除/编辑热词
- 导入预设热词库（技术词汇、人名等）

### **2. 测试功能**
- 测试编辑窗口是否正常显示
- 测试自动学习是否生效
- 测试热词是否提高识别准确率

### **3. 可选增强功能**
- 更智能的词汇对比算法（使用 diff 库）
- 热词优先级排序
- 热词使用频率统计
- 批量导入/导出热词

---

## 📊 数据结构示例

### **修改记录（TextCorrection）**
```swift
TextCorrection(
  id: UUID(),
  original: "cloud",      // 识别错误的词
  corrected: "Claude",    // 用户修正的词
  timestamp: Date()       // 修正时间
)
```

### **带修改记录的转录（Transcript）**
```swift
Transcript(
  id: UUID(),
  timestamp: Date(),
  text: "I'm using Anthropic Claude",  // 最终文本
  originalText: "I'm using anthropic cloud",  // 原始转录
  corrections: [
    TextCorrection(original: "cloud", corrected: "Claude")
  ],
  audioPath: URL(...),
  duration: 5.2,
  sourceAppName: "Xcode"
)
```

---

## 🎨 UI 预览

### **编辑窗口界面**
```
┌─────────────────────────────────────┐
│  Transcription Result         [×]    │
├─────────────────────────────────────┤
│                                      │
│  ┌────────────────────────────────┐ │
│  │ I'm using Anthropic Claude     │ │
│  │ to build amazing apps...       │ │
│  └────────────────────────────────┘ │
│                                      │
│  ⏱ 5.2s    📱 Xcode    ✏️ Edited   │
│                                      │
│  ☑ Remember my corrections and learn│
│                                      │
│     [Cancel]  [Confirm & Paste]     │
└─────────────────────────────────────┘
```

---

## ✅ 实现状态

- [x] 数据模型扩展
- [x] 设置项添加
- [x] 编辑窗口 UI
- [x] 窗口管理器
- [x] 转录流程集成
- [x] 热词支持（WhisperKit）
- [x] 自动学习机制
- [x] 修改记录存储
- [ ] 热词管理界面
- [ ] 完整测试

---

## 🚀 如何使用

### **作为开发者**
1. 在 Xcode 中重新构建项目（Cmd + B）
2. 运行应用（Cmd + R）
3. 录音并测试编辑功能

### **作为用户**
1. 打开 HEX 应用
2. 按住热键录音
3. 转录完成后会弹出编辑窗口
4. 修改文本（如果需要）
5. 勾选"记住我的修改"
6. 点击"确认并粘贴"
7. 文本会被粘贴到目标应用
8. 下次转录时，HEX 会更准确地识别你之前修正的词汇

---

## 📝 注意事项

1. **热词功能仅适用于 WhisperKit 引擎**
   - Parakeet TDT 引擎目前不支持热词参数
   - 如果使用 Parakeet，只能使用字词替换功能

2. **编辑窗口快捷键**
   - `Enter` = 确认并粘贴
   - `Esc` = 取消

3. **自动学习智能化**
   - 只学习被修改的词汇
   - 自动过滤重复的规则
   - 同时更新热词列表和替换规则

4. **性能优化**
   - 编辑窗口使用 Actor 管理，避免并发问题
   - 窗口自动释放，不占用内存

---

## 🐛 已知问题

无（目前所有核心功能已实现）

---

## 📚 相关文件索引

- 数据模型：`HexCore/Sources/HexCore/Models/TranscriptionHistory.swift`
- 设置模型：`HexCore/Sources/HexCore/Settings/HexSettings.swift`
- 编辑器功能：`Hex/Features/TranscriptEditor/TranscriptEditorFeature.swift`
- 窗口管理：`Hex/Features/TranscriptEditor/TranscriptEditorWindow.swift`
- 转录流程：`Hex/Features/Transcription/TranscriptionFeature.swift`
