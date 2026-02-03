# 三种分析模式对比

## 核心区别

| 模式 | 文本对比 | 热词提取 | 说明 |
|------|---------|---------|------|
| **传统算法** | Myers diff | 规则过滤 | 全部离线，快速准确 |
| **LLM分析** | LLM | LLM | 全部AI，智能理解 |
| **混合模式** | LLM→传统 | LLM→传统 | LLM优先，失败降级 |

---

## 传统算法模式

### 工作流程

```
用户修改文本
    ↓
Myers Diff 检测修改
  (日→热, palist→plist)
    ↓
规则过滤提取热词
  (长度、常见词检查)
    ↓
学习词汇映射 + 热词
```

### 优点
- ✅ 极快（<1ms）
- ✅ 100%离线
- ✅ 可预测
- ✅ 无需配置

### 缺点
- ❌ 规则死板
- ❌ 可能误判
- ❌ 无法理解语义

### 适用场景
- 日常使用
- 网络不稳定
- 追求速度
- 不想配置LLM

---

## LLM分析模式

### 工作流程

```
用户修改文本
    ↓
发送原文和修改后文本给LLM
    ↓
LLM分析:
  1. 对比文本，检测所有修改
  2. 判断每个修改是否值得学习
    ↓
返回: corrections + hotwords
    ↓
学习词汇映射 + 热词
```

### LLM完成的任务

**1. 文本对比检测**
```
输入:
  原文: "我用antropic的api"
  修改: "我用Anthropic的API"

LLM分析:
  - antropic → Anthropic (大小写和拼写修正)
  - api → API (大小写修正)
```

**2. 热词智能筛选**
```
LLM判断:
  - Anthropic: 公司名 ✅ 学习
  - API: 技术术语 ✅ 学习
```

### 优点
- ✅ 智能理解语义
- ✅ 准确识别专业术语
- ✅ 可以处理复杂修改
- ✅ 理解上下文

### 缺点
- ❌ 需要配置
- ❌ 速度较慢（~500ms - 2s）
- ❌ 可能需要网络

### 适用场景
- 专业领域（医疗、法律、技术）
- 追求准确率
- 有本地LLM或云端API

---

## 混合模式

### 工作流程

```
用户修改文本
    ↓
尝试使用LLM分析
    ↓
  成功？
  ↙   ↘
是      否
↓       ↓
使用    降级到
LLM结果  传统算法
    ↓
学习词汇映射 + 热词
```

### 优点
- ✅ 智能优先
- ✅ 可靠降级
- ✅ 兼顾准确性和稳定性

### 缺点
- ❌ 需要配置LLM
- ❌ 速度不确定

### 适用场景
- 网络不稳定
- 希望智能但需要保障
- 生产环境

---

## 实际案例对比

### 案例1：技术术语修正

**用户输入**：
```
原文: "打开info.palist文件用编译器"
修改: "打开info.plist文件用编辑器"
```

#### 传统算法
```
Myers Diff检测:
  palist → plist
  编译器 → 编辑器

规则过滤:
  plist: ≥3字母, 非常见词 ✅
  编辑器: 常见词 ❌

学习:
  词汇映射: palist→plist, 编译器→编辑器
  热词: [plist]
```

#### LLM分析
```
LLM检测:
  palist → plist
  编译器 → 编辑器

LLM判断:
{
  "corrections": [
    {"original": "palist", "corrected": "plist"},
    {"original": "编译器", "corrected": "编辑器"}
  ],
  "hotwords": ["plist"],
  "reasoning": "plist是配置文件扩展名，属于技术术语；编辑器是常见词"
}

学习:
  词汇映射: palist→plist, 编译器→编辑器
  热词: [plist]
```

**结果**：两种方式都正确

---

### 案例2：品牌名+大小写

**用户输入**：
```
原文: "我用antropic的claude模型"
修改: "我用Anthropic的Claude模型"
```

#### 传统算法
```
Myers Diff检测:
  (中文按字符分词，无法检测到英文词的大小写变化)
  antropic → Anthropic (可能检测为整词替换)
  claude → Claude (可能检测为整词替换)

学习:
  词汇映射: antropic→Anthropic, claude→Claude
  热词: [Anthropic, Claude]
```

#### LLM分析
```
LLM检测:
{
  "corrections": [
    {"original": "antropic", "corrected": "Anthropic"},
    {"original": "claude", "corrected": "Claude"}
  ],
  "hotwords": ["Anthropic", "Claude"],
  "reasoning": "Anthropic是AI公司名，Claude是AI模型名，都是品牌专有名词"
}

学习:
  词汇映射: antropic→Anthropic, claude→Claude
  热词: [Anthropic, Claude]
```

**结果**：LLM更准确理解语义

---

### 案例3：复杂修改

**用户输入**：
```
原文: "使用react native开发移动应用"
修改: "使用React Native开发移动端应用"
```

#### 传统算法
```
Myers Diff检测:
  react → React
  native → Native
  移动应用 → 移动端应用 (中文按字分词，检测为多个字符的变化)

学习:
  词汇映射: react→React, native→Native, 移→移, 动→动, 应→端, 用→应
  热词: [React, Native] (移、动、应、用都是常见字，被过滤)
```

#### LLM分析
```
LLM检测:
{
  "corrections": [
    {"original": "react", "corrected": "React"},
    {"original": "native", "corrected": "Native"}
  ],
  "hotwords": ["React", "Native"],
  "reasoning": "React Native是跨平台开发框架名，应该学习；'移动应用'到'移动端应用'只是措辞变化，不需要学习"
}

学习:
  词汇映射: react→React, native→Native
  热词: [React, Native]
```

**结果**：LLM更智能，不会学习无意义的修改

---

## 日志对比

### 传统模式日志
```
Using traditional algorithm for corrections and hotwords
Auto-learned word remapping: 'palist' → 'plist'
Auto-learned word remapping: 'antropic' → 'Anthropic'
Auto-learned hotword: 'plist'
Auto-learned hotword: 'Anthropic'
```

### LLM模式日志
```
Analyzing corrections with LLM: Ollama
Calling OpenAI-compatible API: http://localhost:11434/v1/chat/completions
LLM response: {"corrections": [...], "hotwords": [...], "reasoning": "..."}
✅ LLM analysis complete
Detected 2 corrections: palist→plist, antropic→Anthropic
Extracted 2 hotwords: plist, Anthropic
LLM reasoning: plist是文件扩展名，Anthropic是公司名
Auto-learned word remapping: 'palist' → 'plist'
Auto-learned word remapping: 'antropic' → 'Anthropic'
Auto-learned hotword: 'plist'
Auto-learned hotword: 'Anthropic'
```

---

## 关键设计

### 即时编辑窗口显示

**无论选择哪种模式，编辑窗口都使用传统算法显示修改**

原因：
1. ✅ 即时反馈 - 用户需要立即看到对比
2. ✅ 离线可用 - 不依赖LLM
3. ✅ 速度快 - Myers diff只需1ms

```
即时编辑窗口
  ↓
  显示: 日→热, palist→plist (传统算法检测)
  ↓
用户确认学习
  ↓
根据选择的模式学习:
  - 传统: 使用传统算法提取热词
  - LLM: 重新用LLM分析整个修改
  - 混合: LLM优先，失败用传统
```

### LLM模式的完整分析

当选择LLM模式时：
1. 编辑窗口显示的corrections（传统算法）**只用于显示**
2. 学习时，会**重新用LLM完整分析**原文和修改后文本
3. LLM返回的corrections用于学习词汇映射
4. LLM返回的hotwords用于学习热词

这样设计的好处：
- 用户可以立即看到修改对比（传统算法）
- 实际学习使用更智能的LLM分析
- 两者互不干扰

---

## 推荐配置

### 普通用户
```
模式: 传统算法
原因: 简单、快速、可靠
```

### 技术用户（有Ollama）
```
模式: LLM分析
提供商: Ollama
模型: qwen2.5:7b
原因: 免费、智能、本地运行
```

### 专业用户（追求准确率）
```
模式: LLM分析
提供商: OpenAI
模型: gpt-4o-mini
原因: 最准确的语义理解
```

### 生产环境
```
模式: 混合模式
提供商: Ollama
原因: 智能+可靠，网络问题时自动降级
```

---

## 总结

| 需求 | 推荐模式 |
|------|---------|
| 简单快速 | 传统算法 |
| 智能准确 | LLM分析 |
| 可靠稳定 | 混合模式 |
| 专业领域 | LLM分析 |
| 离线使用 | 传统算法 |

**核心改进**：用户选择LLM模式后，整个流程都使用LLM，而不是只用LLM做热词提取！🎯
