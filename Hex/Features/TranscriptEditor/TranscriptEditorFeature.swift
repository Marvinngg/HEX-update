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
		case delegate(Delegate)

		enum Delegate {
			case confirmed(editedText: String, shouldLearn: Bool, corrections: [TextCorrection])
			case cancelled
		}
	}

	@Dependency(\.transcriptEditorCallbacks) var callbacks

	var body: some ReducerOf<Self> {
		BindingReducer()

		Reduce { state, action in
			switch action {
			case .binding:
				return .none

			case .confirmTapped:
				let corrections = detectCorrections(
					original: state.originalTranscript,
					edited: state.transcript
				)

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

	// 检测修改的词汇
	private func detectCorrections(original: String, edited: String) -> [TextCorrection] {
		guard original != edited else { return [] }

		let originalWords = original.split(separator: " ").map(String.init)
		let editedWords = edited.split(separator: " ").map(String.init)

		var corrections: [TextCorrection] = []

		// 简单的逐词对比（可以后续改进为更智能的 diff 算法）
		let minCount = min(originalWords.count, editedWords.count)
		for i in 0..<minCount {
			let orig = originalWords[i].trimmingCharacters(in: .punctuationCharacters)
			let edit = editedWords[i].trimmingCharacters(in: .punctuationCharacters)

			if orig.lowercased() != edit.lowercased() && !orig.isEmpty && !edit.isEmpty {
				corrections.append(TextCorrection(
					original: orig,
					corrected: edit
				))
			}
		}

		return corrections
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
