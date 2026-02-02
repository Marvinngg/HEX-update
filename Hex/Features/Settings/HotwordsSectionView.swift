import ComposableArchitecture
import HexCore
import SwiftUI

struct HotwordsSectionView: View {
	@Bindable var store: StoreOf<SettingsFeature>
	@State private var newHotword = ""
	@State private var showAddField = false

	var body: some View {
		Section {
			VStack(alignment: .leading, spacing: 12) {
				// Header with description
				VStack(alignment: .leading, spacing: 4) {
					Text("热词列表")
						.font(.headline)
					Text("添加专业词汇、人名等，提高转录准确率。修改转录文本时会自动学习。")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.padding(.bottom, 4)

				// Hotwords list
				if store.hexSettings.hotwords.isEmpty {
					HStack {
						Image(systemName: "text.bubble")
							.foregroundStyle(.secondary)
						Text("暂无热词，点击下方按钮添加")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
					.padding(.vertical, 8)
					.frame(maxWidth: .infinity)
				} else {
					VStack(alignment: .leading, spacing: 6) {
						ForEach(store.hexSettings.hotwords.indices, id: \.self) { index in
							HStack {
								Text(store.hexSettings.hotwords[index])
									.font(.body)

								Spacer()

								// Delete button
								Button {
									store.send(.deleteHotword(at: index))
								} label: {
									Image(systemName: "xmark.circle.fill")
										.foregroundStyle(.secondary)
								}
								.buttonStyle(.plain)
								.help("删除热词")
							}
							.padding(.horizontal, 8)
							.padding(.vertical, 6)
							.background(Color(.controlBackgroundColor))
							.cornerRadius(6)
						}
					}
				}

				Divider()
					.padding(.vertical, 4)

				// Add hotword section
				if showAddField {
					HStack(spacing: 8) {
						TextField("输入热词", text: $newHotword)
							.textFieldStyle(.roundedBorder)
							.onSubmit {
								addHotword()
							}

						Button("添加") {
							addHotword()
						}
						.disabled(newHotword.trimmingCharacters(in: .whitespaces).isEmpty)

						Button("取消") {
							showAddField = false
							newHotword = ""
						}
					}
				} else {
					Button {
						showAddField = true
					} label: {
						HStack {
							Image(systemName: "plus.circle.fill")
							Text("添加热词")
						}
					}
				}

				// Quick actions
				if !store.hexSettings.hotwords.isEmpty {
					Divider()
						.padding(.vertical, 4)

					HStack(spacing: 12) {
						Button {
							store.send(.clearAllHotwords)
						} label: {
							HStack(spacing: 4) {
								Image(systemName: "trash")
								Text("清空全部")
							}
							.font(.caption)
						}
						.buttonStyle(.plain)
						.foregroundStyle(.red)

						Text("•")
							.foregroundStyle(.secondary)

						Text("\(store.hexSettings.hotwords.count) 个热词")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
			}
			.padding(.vertical, 8)
		} header: {
			Label("热词", systemImage: "text.word.spacing")
		}
	}

	private func addHotword() {
		let trimmed = newHotword.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { return }
		guard !store.hexSettings.hotwords.contains(trimmed) else {
			// Already exists, just clear the field
			newHotword = ""
			showAddField = false
			return
		}

		store.send(.addHotword(trimmed))
		newHotword = ""
		showAddField = false
	}
}
