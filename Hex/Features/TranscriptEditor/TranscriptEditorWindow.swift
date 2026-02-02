import AppKit
import Combine
import ComposableArchitecture
import SwiftUI
import HexCore

/// A window controller that displays the transcript editor as a floating panel
@MainActor
class TranscriptEditorWindowController: NSWindowController {
	convenience init(store: StoreOf<TranscriptEditorFeature>) {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
			styleMask: [.titled, .closable, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)

		window.center()
		window.isReleasedWhenClosed = false
		window.level = .floating
		window.titleVisibility = .hidden
		window.titlebarAppearsTransparent = true
		window.isMovableByWindowBackground = true

		// Set the content view
		let hostingView = NSHostingView(rootView: TranscriptEditorView(store: store))
		window.contentView = hostingView

		self.init(window: window)
	}

	func show() {
		window?.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
	}
}

/// Result from the transcript editor
struct TranscriptEditorResult: Sendable {
	let editedText: String
	let shouldLearn: Bool
	let corrections: [TextCorrection]
}

/// A client for managing transcript editor windows
@DependencyClient
struct TranscriptEditorClient {
	var show: @Sendable (
		_ transcript: String,
		_ duration: TimeInterval,
		_ sourceAppName: String?
	) async -> TranscriptEditorResult?
}

extension TranscriptEditorClient: DependencyKey {
	@MainActor
	static var liveValue: TranscriptEditorClient {
		let manager = TranscriptEditorManager()
		return TranscriptEditorClient(
			show: { transcript, duration, sourceAppName in
				await manager.show(
					transcript: transcript,
					duration: duration,
					sourceAppName: sourceAppName
				)
			}
		)
	}
}

extension DependencyValues {
	var transcriptEditor: TranscriptEditorClient {
		get { self[TranscriptEditorClient.self] }
		set { self[TranscriptEditorClient.self] = newValue }
	}
}

@MainActor
private class TranscriptEditorManager {
	private var windowController: TranscriptEditorWindowController?
	private var previousApp: NSRunningApplication?

	func show(
		transcript: String,
		duration: TimeInterval,
		sourceAppName: String?
	) async -> TranscriptEditorResult? {
		@Shared(.hexSettings) var settings: HexSettings

		// Remember the currently active application
		previousApp = NSWorkspace.shared.frontmostApplication

		return await withCheckedContinuation { continuation in
			// Create store with callbacks in dependencies
			let store = Store(
				initialState: TranscriptEditorFeature.State(
					transcript: transcript,
					duration: duration,
					sourceAppName: sourceAppName,
					autoLearn: settings.autoLearnFromEdits
				),
				reducer: {
					TranscriptEditorFeature()
						.dependency(
							\.transcriptEditorCallbacks,
							 TranscriptEditorCallbacks(
								 onConfirm: { [weak self] text, shouldLearn, corrections in
									 let result = TranscriptEditorResult(
										 editedText: text,
										 shouldLearn: shouldLearn,
										 corrections: corrections
									 )

									 // Close window first
									 self?.windowController?.close()
									 self?.windowController = nil

									 // Restore focus to previous app
									 if let previousApp = self?.previousApp {
										 previousApp.activate(options: [.activateIgnoringOtherApps])
									 }

									 continuation.resume(returning: result)
								 },
								 onCancel: { [weak self] in
									 // Close window first
									 self?.windowController?.close()
									 self?.windowController = nil

									 // Restore focus to previous app
									 if let previousApp = self?.previousApp {
										 previousApp.activate(options: [.activateIgnoringOtherApps])
									 }

									 continuation.resume(returning: nil)
								 }
							 )
						)
				}
			)

			let controller = TranscriptEditorWindowController(store: store)
			self.windowController = controller
			controller.show()
		}
	}
}
