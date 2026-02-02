import ComposableArchitecture
import Inject
import SwiftUI

struct CuratedList: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<ModelDownloadFeature>

	private var visibleModels: [CuratedModelInfo] {
		if store.showAllModels {
			return Array(store.curatedModels)
		} else {
			// Show recommended models by default: Whisper Base and Qwen3-ASR 0.6B
			return store.curatedModels.filter { model in
				model.internalName == "openai_whisper-base" ||
				model.internalName == "qwen3-asr-0.6b"
			}
		}
	}

	private var hiddenModels: [CuratedModelInfo] {
		store.curatedModels.filter { model in
			model.internalName != "openai_whisper-base" &&
			model.internalName != "qwen3-asr-0.6b"
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			ForEach(visibleModels) { model in
				CuratedRow(store: store, model: model)
			}

			// Show "Show more"/"Show less" button
			if !hiddenModels.isEmpty {
				Button(action: { store.send(.toggleModelDisplay) }) {
					HStack {
                      Spacer()
						Text(store.showAllModels ? "Show less" : "Show more")
							.font(.subheadline)
						Spacer()
					}
				}
				.buttonStyle(.plain)
				.foregroundStyle(.secondary)
			}
		}
		.enableInjection()
	}
}

