import ComposableArchitecture
import Dependencies
import Foundation
import HexCore
import SwiftUI

/// Callbacks for transcript editor (defined in TranscriptEditorWindow.swift)
struct TranscriptEditorCallbacks {
	var onConfirm: (String, Bool, [TextCorrection]) -> Void
	var onCancel: () -> Void
}

private enum TranscriptEditorCallbacksKey: DependencyKey {
	static var liveValue: TranscriptEditorCallbacks?
}

extension DependencyValues {
	var transcriptEditorCallbacks: TranscriptEditorCallbacks? {
		get { self[TranscriptEditorCallbacksKey.self] }
		set { self[TranscriptEditorCallbacksKey.self] = newValue }
	}
}

@Reducer
struct TranscriptEditorFeature {
	@ObservableState
	struct State: Equatable {
		var transcript: String
		var originalTranscript: String
		var duration: TimeInterval
		var sourceAppName: String?
		var autoLearn: Bool
		var isProcessing: Bool = false

		var hasChanges: Bool {
			transcript != originalTranscript
		}

		init(
			transcript: String,
			duration: TimeInterval,
			sourceAppName: String?,
			autoLearn: Bool = true
		) {
			self.transcript = transcript
			self.originalTranscript = transcript
			self.duration = duration
			self.sourceAppName = sourceAppName
			self.autoLearn = autoLearn
		}
	}

	enum Action: BindableAction {
		case binding(BindingAction<State>)
		case confirmTapped
		case cancelTapped
		case correctionsDetected([TextCorrection])
		case delegate(Delegate)

		enum Delegate {
			case confirmed(editedText: String, shouldLearn: Bool, corrections: [TextCorrection])
			case cancelled
		}
	}

	@Dependency(\.transcriptEditorCallbacks) var callbacks
	@Dependency(\.llmAnalysis) var llmAnalysis

	var body: some ReducerOf<Self> {
		BindingReducer()

		Reduce { state, action in
			switch action {
			case .binding:
				return .none

			case .confirmTapped:
				state.isProcessing = true

				let originalText = state.originalTranscript
				let editedText = state.transcript

				// Detect corrections asynchronously based on mode
				return .run { send in
					let corrections = await detectCorrections(
						original: originalText,
						edited: editedText
					)
					await send(.correctionsDetected(corrections))
				}

			case .correctionsDetected(let corrections):
				state.isProcessing = false

				// Call the callback directly
				callbacks?.onConfirm(
					state.transcript,
					state.autoLearn && state.hasChanges,
					corrections
				)

				return .send(.delegate(.confirmed(
					editedText: state.transcript,
					shouldLearn: state.autoLearn && state.hasChanges,
					corrections: corrections
				)))

			case .cancelTapped:
				callbacks?.onCancel()
				return .send(.delegate(.cancelled))

			case .delegate:
				return .none
			}
		}
	}

	// 检测修改的词汇 - 根据配置使用传统算法或LLM
	private func detectCorrections(original: String, edited: String) async -> [TextCorrection] {
		@Shared(.hexSettings) var settings: HexSettings

		// Use LLM or traditional based on mode
		switch settings.correctionAnalysisMode {
		case .traditional:
			// Use traditional algorithm
			return TextDiffAlgorithm.detectCorrections(original: original, edited: edited)

		case .llm:
			// Use LLM analysis
			if settings.llmConfig.enabled && settings.llmConfig.isValid {
				do {
					let request = LLMAnalysisRequest(
						originalText: original,
						editedText: edited,
						language: nil
					)
					let response = try await llmAnalysis.analyzeCorrections(request, settings.llmConfig)
					return response.corrections
				} catch {
					// Fallback to traditional on error
					return TextDiffAlgorithm.detectCorrections(original: original, edited: edited)
				}
			} else {
				// LLM not configured, use traditional
				return TextDiffAlgorithm.detectCorrections(original: original, edited: edited)
			}
		}
	}
}

struct TranscriptEditorView: View {
	@Bindable var store: StoreOf<TranscriptEditorFeature>
	@FocusState private var isTextFieldFocused: Bool

	var body: some View {
		VStack(spacing: 0) {
			// Header
			HStack {
				Text("Transcription Result")
					.font(.headline)
				Spacer()
				Button {
					store.send(.cancelTapped)
				} label: {
					Image(systemName: "xmark.circle.fill")
						.foregroundStyle(.secondary)
						.font(.title3)
				}
				.buttonStyle(.plain)
			}
			.padding()

			Divider()

			// Text Editor
			VStack(spacing: 12) {
				TextEditor(text: $store.transcript)
					.font(.body)
					.frame(minHeight: 120, maxHeight: 300)
					.scrollContentBackground(.hidden)
					.background(Color(nsColor: .textBackgroundColor))
					.cornerRadius(8)
					.overlay(
						RoundedRectangle(cornerRadius: 8)
							.stroke(Color.secondary.opacity(0.2), lineWidth: 1)
					)
					.focused($isTextFieldFocused)

				// Info bar
				HStack(spacing: 16) {
					Label(
						String(format: "%.1fs", store.duration),
						systemImage: "clock"
					)
					.font(.caption)
					.foregroundStyle(.secondary)

					if let appName = store.sourceAppName {
						Label(appName, systemImage: "app")
							.font(.caption)
							.foregroundStyle(.secondary)
					}

					if store.hasChanges {
						Label("Edited", systemImage: "pencil")
							.font(.caption)
							.foregroundStyle(.orange)
					}

					Spacer()
				}
			}
			.padding()

			Divider()

			// Auto-learn checkbox
			HStack {
				Toggle(isOn: $store.autoLearn) {
					HStack(spacing: 6) {
						Image(systemName: "brain")
						Text("Remember my corrections and learn")
							.font(.subheadline)
					}
				}
				.toggleStyle(.checkbox)
				.disabled(!store.hasChanges)

				Spacer()
			}
			.padding(.horizontal)
			.padding(.vertical, 12)

			Divider()

			// Action buttons
			HStack {
				Button("Cancel") {
					store.send(.cancelTapped)
				}
				.keyboardShortcut(.cancelAction)

				Spacer()

				Button {
					store.send(.confirmTapped)
				} label: {
					HStack(spacing: 6) {
						if store.isProcessing {
							ProgressView()
								.scaleEffect(0.7)
								.frame(width: 16, height: 16)
						}
						Text("Confirm & Paste")
					}
				}
				.keyboardShortcut(.defaultAction)
				.disabled(store.isProcessing)
			}
			.padding()
		}
		.frame(width: 500)
		.background(Color(nsColor: .windowBackgroundColor))
		.onAppear {
			isTextFieldFocused = true
		}
	}
}

#Preview {
	TranscriptEditorView(
		store: Store(
			initialState: TranscriptEditorFeature.State(
				transcript: "This is a sample transcription text that can be edited by the user.",
				duration: 5.2,
				sourceAppName: "Xcode"
			)
		) {
			TranscriptEditorFeature()
		}
	)
}
