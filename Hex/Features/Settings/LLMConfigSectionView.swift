//
//  LLMConfigSectionView.swift
//  Hex
//
//  LLM configuration section in settings
//

import ComposableArchitecture
import HexCore
import SwiftUI

struct LLMConfigSectionView: View {
    @Bindable var store: StoreOf<SettingsFeature>
    @State private var isTestingConnection = false
    @State private var connectionTestResult: String?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Label("LLM 辅助分析", systemImage: "brain")
                        .font(.headline)
                    Spacer()
                    Toggle("启用", isOn: $store.hexSettings.llmConfig.enabled)
                }

                if store.hexSettings.llmConfig.enabled {
                    Divider()

                    // Analysis Mode
                    VStack(alignment: .leading, spacing: 8) {
                        Text("分析模式")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("", selection: $store.hexSettings.correctionAnalysisMode) {
                            ForEach(CorrectionAnalysisMode.allCases, id: \.self) { mode in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.displayName)
                                    Text(mode.description)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .tag(mode)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }

                    if store.hexSettings.correctionAnalysisMode != .traditional {
                        Divider()

                        // Provider Selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("LLM 提供商")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Picker("", selection: $store.hexSettings.llmConfig.provider) {
                                ForEach(LLMProvider.allCases, id: \.self) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: store.hexSettings.llmConfig.provider) { _, newProvider in
                                // Auto-fill default values when provider changes
                                store.hexSettings.llmConfig.baseURL = newProvider.defaultBaseURL
                                store.hexSettings.llmConfig.model = newProvider.defaultModel
                            }
                        }

                        // Configuration fields
                        VStack(alignment: .leading, spacing: 12) {
                            // Base URL
                            VStack(alignment: .leading, spacing: 4) {
                                Text("API 地址")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("http://localhost:11434", text: $store.hexSettings.llmConfig.baseURL)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }

                            // Model
                            VStack(alignment: .leading, spacing: 4) {
                                Text("模型名称")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("qwen2.5:7b", text: $store.hexSettings.llmConfig.model)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }

                            // API Key (if required)
                            if store.hexSettings.llmConfig.provider.requiresAPIKey {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("API 密钥")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    SecureField("sk-...", text: $store.hexSettings.llmConfig.apiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }

                            // Advanced settings (collapsible)
                            DisclosureGroup("高级设置") {
                                VStack(alignment: .leading, spacing: 12) {
                                    // Temperature
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("Temperature")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(String(format: "%.1f", store.hexSettings.llmConfig.temperature))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Slider(
                                            value: $store.hexSettings.llmConfig.temperature,
                                            in: 0.0...2.0,
                                            step: 0.1
                                        )
                                    }

                                    // Max Tokens
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("最大 Tokens")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        TextField("500", value: $store.hexSettings.llmConfig.maxTokens, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                    }

                                    // Timeout
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("超时时间（秒）")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        TextField("10", value: $store.hexSettings.llmConfig.timeout, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }

                        // Test Connection Button
                        HStack {
                            Button {
                                testConnection()
                            } label: {
                                HStack(spacing: 6) {
                                    if isTestingConnection {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .frame(width: 12, height: 12)
                                    } else {
                                        Image(systemName: "network")
                                    }
                                    Text("测试连接")
                                }
                            }
                            .disabled(isTestingConnection || !store.hexSettings.llmConfig.isValid)

                            if let result = connectionTestResult {
                                Text(result)
                                    .font(.caption)
                                    .foregroundStyle(result.contains("✅") ? .green : .red)
                            }
                        }
                        .padding(.top, 8)

                        // Info box
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("LLM 辅助分析可以更智能地提取热词和检测修改")
                                    .font(.caption)
                                Text("支持 Ollama、LM Studio、OpenAI 等标准接口")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            .padding()
        }
    }

    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil

        @Dependency(\.llmAnalysis) var llmAnalysis

        Task {
            do {
                let success = try await llmAnalysis.testConnection(store.hexSettings.llmConfig)
                await MainActor.run {
                    connectionTestResult = success ? "✅ 连接成功" : "❌ 连接失败"
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionTestResult = "❌ \(error.localizedDescription)"
                    isTestingConnection = false
                }
            }
        }
    }
}

#Preview {
    LLMConfigSectionView(
        store: Store(
            initialState: SettingsFeature.State()
        ) {
            SettingsFeature()
        }
    )
    .frame(width: 600)
}
