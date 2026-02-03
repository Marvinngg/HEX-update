//
//  TranscriptionFeature.swift
//  Hex
//
//  Created by Kit Langton on 1/24/25.
//

import ComposableArchitecture
import CoreGraphics
import Foundation
import HexCore
import Inject
import SwiftUI
import WhisperKit

private let transcriptionFeatureLogger = HexLog.transcription

@Reducer
struct TranscriptionFeature {
  @ObservableState
  struct State {
    var isRecording: Bool = false
    var isTranscribing: Bool = false
    var isPrewarming: Bool = false
    var error: String?
    var recordingStartTime: Date?
    var meter: Meter = .init(averagePower: 0, peakPower: 0)
    var sourceAppBundleID: String?
    var sourceAppName: String?
    @Shared(.hexSettings) var hexSettings: HexSettings
    @Shared(.isRemappingScratchpadFocused) var isRemappingScratchpadFocused: Bool = false
    @Shared(.modelBootstrapState) var modelBootstrapState: ModelBootstrapState
    @Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory
  }

  enum Action {
    case task
    case audioLevelUpdated(Meter)

    // Hotkey actions
    case hotKeyPressed
    case hotKeyReleased

    // Recording flow
    case startRecording
    case stopRecording

    // Cancel/discard flow
    case cancel   // Explicit cancellation with sound
    case discard  // Silent discard (too short/accidental)

    // Transcription result flow
    case transcriptionResult(String, URL)
    case transcriptionError(Error, URL?)
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

    // Model availability
    case modelMissing
  }

  enum CancelID {
    case metering
    case transcription
  }

  @Dependency(\.transcription) var transcription
  @Dependency(\.recording) var recording
  @Dependency(\.pasteboard) var pasteboard
  @Dependency(\.keyEventMonitor) var keyEventMonitor
  @Dependency(\.soundEffects) var soundEffect
  @Dependency(\.sleepManagement) var sleepManagement
  @Dependency(\.date.now) var now
  @Dependency(\.transcriptPersistence) var transcriptPersistence

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      // MARK: - Lifecycle / Setup

      case .task:
        // Starts two concurrent effects:
        // 1) Observing audio meter
        // 2) Monitoring hot key events
        // 3) Priming the recorder for instant startup
        return .merge(
          startMeteringEffect(),
          startHotKeyMonitoringEffect(),
          warmUpRecorderEffect()
        )

      // MARK: - Metering

      case let .audioLevelUpdated(meter):
        state.meter = meter
        return .none

      // MARK: - HotKey Flow

      case .hotKeyPressed:
        // If we're transcribing, send a cancel first. Otherwise start recording immediately.
        // We'll decide later (on release) whether to keep or discard the recording.
        return handleHotKeyPressed(isTranscribing: state.isTranscribing)

      case .hotKeyReleased:
        // If we're currently recording, then stop. Otherwise, just cancel
        // the delayed "startRecording" effect if we never actually started.
        return handleHotKeyReleased(isRecording: state.isRecording)

      // MARK: - Recording Flow

      case .startRecording:
        return handleStartRecording(&state)

      case .stopRecording:
        return handleStopRecording(&state)

      // MARK: - Transcription Results

      case let .transcriptionResult(result, audioURL):
        return handleTranscriptionResult(&state, result: result, audioURL: audioURL)

      case let .transcriptionEdited(originalText, editedText, shouldLearn, corrections, duration, sourceAppBundleID, sourceAppName, audioURL):
        return handleTranscriptionEdited(
          &state,
          originalText: originalText,
          editedText: editedText,
          shouldLearn: shouldLearn,
          corrections: corrections,
          duration: duration,
          sourceAppBundleID: sourceAppBundleID,
          sourceAppName: sourceAppName,
          audioURL: audioURL
        )

      case let .transcriptionError(error, audioURL):
        return handleTranscriptionError(&state, error: error, audioURL: audioURL)

      case .modelMissing:
        return .none

      // MARK: - Cancel/Discard Flow

      case .cancel:
        // Only cancel if we're in the middle of recording, transcribing, or post-processing
        guard state.isRecording || state.isTranscribing else {
          return .none
        }
        return handleCancel(&state)

      case .discard:
        // Silent discard for quick/accidental recordings
        guard state.isRecording else {
          return .none
        }
        return handleDiscard(&state)
      }
    }
  }
}

// MARK: - Effects: Metering & HotKey

private extension TranscriptionFeature {
  /// Effect to begin observing the audio meter.
  func startMeteringEffect() -> Effect<Action> {
    .run { send in
      for await meter in await recording.observeAudioLevel() {
        await send(.audioLevelUpdated(meter))
      }
    }
    .cancellable(id: CancelID.metering, cancelInFlight: true)
  }

  /// Effect to start monitoring hotkey events through the `keyEventMonitor`.
  func startHotKeyMonitoringEffect() -> Effect<Action> {
    .run { send in
      var hotKeyProcessor: HotKeyProcessor = .init(hotkey: HotKey(key: nil, modifiers: [.option]))
      @Shared(.isSettingHotKey) var isSettingHotKey: Bool
      @Shared(.hexSettings) var hexSettings: HexSettings

      // Handle incoming input events (keyboard and mouse)
      let token = keyEventMonitor.handleInputEvent { inputEvent in
        // Skip if the user is currently setting a hotkey
        if isSettingHotKey {
          return false
        }

        // Always keep hotKeyProcessor in sync with current user hotkey preference
        hotKeyProcessor.hotkey = hexSettings.hotkey
        hotKeyProcessor.useDoubleTapOnly = hexSettings.useDoubleTapOnly
        hotKeyProcessor.minimumKeyTime = hexSettings.minimumKeyTime

        switch inputEvent {
        case .keyboard(let keyEvent):
          // If Escape is pressed with no modifiers while idle, let's treat that as `cancel`.
          if keyEvent.key == .escape, keyEvent.modifiers.isEmpty,
             hotKeyProcessor.state == .idle
          {
            Task { await send(.cancel) }
            return false
          }

          // Process the key event
          switch hotKeyProcessor.process(keyEvent: keyEvent) {
          case .startRecording:
            // If double-tap lock is triggered, we start recording immediately
            if hotKeyProcessor.state == .doubleTapLock {
              Task { await send(.startRecording) }
            } else {
              Task { await send(.hotKeyPressed) }
            }
            // If the hotkey is purely modifiers, return false to keep it from interfering with normal usage
            // But if useDoubleTapOnly is true, always intercept the key
            return hexSettings.useDoubleTapOnly || keyEvent.key != nil

          case .stopRecording:
            Task { await send(.hotKeyReleased) }
            return false // or `true` if you want to intercept

          case .cancel:
            Task { await send(.cancel) }
            return true

          case .discard:
            Task { await send(.discard) }
            return false // Don't intercept - let the key chord reach other apps

          case .none:
            // If we detect repeated same chord, maybe intercept.
            if let pressedKey = keyEvent.key,
               pressedKey == hotKeyProcessor.hotkey.key,
               keyEvent.modifiers == hotKeyProcessor.hotkey.modifiers
            {
              return true
            }
            return false
          }

        case .mouseClick:
          // Process mouse click - for modifier-only hotkeys, this may cancel/discard
          switch hotKeyProcessor.processMouseClick() {
          case .cancel:
            Task { await send(.cancel) }
            return false // Don't intercept the click itself
          case .discard:
            Task { await send(.discard) }
            return false // Don't intercept the click itself
          case .startRecording, .stopRecording, .none:
            return false
          }
        }
      }

      defer { token.cancel() }

      await withTaskCancellationHandler {
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(60))
        }
      } onCancel: {
        token.cancel()
      }
    }
  }

  func warmUpRecorderEffect() -> Effect<Action> {
    .run { _ in
      await recording.warmUpRecorder()
    }
  }
}

// MARK: - HotKey Press/Release Handlers

private extension TranscriptionFeature {
  func handleHotKeyPressed(isTranscribing: Bool) -> Effect<Action> {
    // If already transcribing, cancel first. Otherwise start recording immediately.
    let maybeCancel = isTranscribing ? Effect.send(Action.cancel) : .none
    let startRecording = Effect.send(Action.startRecording)
    return .merge(maybeCancel, startRecording)
  }

  func handleHotKeyReleased(isRecording: Bool) -> Effect<Action> {
    // Always stop recording when hotkey is released
    return isRecording ? .send(.stopRecording) : .none
  }
}

// MARK: - Recording Handlers

private extension TranscriptionFeature {
  func handleStartRecording(_ state: inout State) -> Effect<Action> {
    // Note: We don't check isModelReady here because transcription.transcribe()
    // handles model loading automatically. If there's a real model issue, it will
    // throw an error that gets handled by handleTranscriptionError.
    state.isRecording = true
    let startTime = Date()
    state.recordingStartTime = startTime
    
    // Capture the active application
    if let activeApp = NSWorkspace.shared.frontmostApplication {
      state.sourceAppBundleID = activeApp.bundleIdentifier
      state.sourceAppName = activeApp.localizedName
    }
    transcriptionFeatureLogger.notice("Recording started at \(startTime.ISO8601Format())")

    // Prevent system sleep during recording
    return .run { [sleepManagement, preventSleep = state.hexSettings.preventSystemSleep] send in
      // Play sound immediately for instant feedback
      soundEffect.play(.startRecording)

      if preventSleep {
        await sleepManagement.preventSleep(reason: "Hex Voice Recording")
      }
      await recording.startRecording()
    }
  }

  func handleStopRecording(_ state: inout State) -> Effect<Action> {
    state.isRecording = false
    
    let stopTime = now
    let startTime = state.recordingStartTime
    let duration = startTime.map { stopTime.timeIntervalSince($0) } ?? 0

    let decision = RecordingDecisionEngine.decide(
      .init(
        hotkey: state.hexSettings.hotkey,
        minimumKeyTime: state.hexSettings.minimumKeyTime,
        recordingStartTime: state.recordingStartTime,
        currentTime: stopTime
      )
    )

    let startStamp = startTime?.ISO8601Format() ?? "nil"
    let stopStamp = stopTime.ISO8601Format()
    let minimumKeyTime = state.hexSettings.minimumKeyTime
    let hotkeyHasKey = state.hexSettings.hotkey.key != nil
    transcriptionFeatureLogger.notice(
      "Recording stopped duration=\(String(format: "%.3f", duration))s start=\(startStamp) stop=\(stopStamp) decision=\(String(describing: decision)) minimumKeyTime=\(String(format: "%.2f", minimumKeyTime)) hotkeyHasKey=\(hotkeyHasKey)"
    )

    guard decision == .proceedToTranscription else {
      // If the user recorded for less than minimumKeyTime and the hotkey is modifier-only,
      // discard the audio to avoid accidental triggers.
      transcriptionFeatureLogger.notice("Discarding short recording per decision \(String(describing: decision))")
      return .run { _ in
        let url = await recording.stopRecording()
        try? FileManager.default.removeItem(at: url)
      }
    }

    // Otherwise, proceed to transcription
    state.isTranscribing = true
    state.error = nil
    let model = state.hexSettings.selectedModel
    let language = state.hexSettings.outputLanguage

    state.isPrewarming = true

    return .run { [sleepManagement] send in
      // Allow system to sleep again
      await sleepManagement.allowSleep()

      var audioURL: URL?
      do {
        soundEffect.play(.stopRecording)
        let capturedURL = await recording.stopRecording()
        audioURL = capturedURL

        // Create transcription options with the selected language
        // Note: cap concurrency to avoid audio I/O overloads on some Macs
        @Shared(.hexSettings) var settings: HexSettings

        let decodeOptions = DecodingOptions(
          language: language,
          detectLanguage: language == nil, // Only auto-detect if no language specified
          chunkingStrategy: .vad
        )

        // Get hotwords from settings (only used for WhisperKit models)
        let hotwords = settings.hotwords

        let result = try await transcription.transcribe(capturedURL, model, decodeOptions, hotwords) { _ in }
        
        transcriptionFeatureLogger.notice("Transcribed audio from \(capturedURL.lastPathComponent) to text length \(result.count)")
        await send(.transcriptionResult(result, capturedURL))
      } catch {
        transcriptionFeatureLogger.error("Transcription failed: \(error.localizedDescription)")
        await send(.transcriptionError(error, audioURL))
      }
    }
    .cancellable(id: CancelID.transcription)
  }
}

// MARK: - Transcription Handlers

private extension TranscriptionFeature {
  func handleTranscriptionResult(
    _ state: inout State,
    result: String,
    audioURL: URL
  ) -> Effect<Action> {
    state.isTranscribing = false
    state.isPrewarming = false

    // Check for force quit command (emergency escape hatch)
    if ForceQuitCommandDetector.matches(result) {
      transcriptionFeatureLogger.fault("Force quit voice command recognized; terminating Hex.")
      return .run { _ in
        try? FileManager.default.removeItem(at: audioURL)
        await MainActor.run {
          NSApp.terminate(nil)
        }
      }
    }

    // If empty text, nothing else to do
    guard !result.isEmpty else {
      return .none
    }

    let duration = state.recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0

    transcriptionFeatureLogger.info("Raw transcription: '\(result)'")
    let remappings = state.hexSettings.wordRemappings
    let removalsEnabled = state.hexSettings.wordRemovalsEnabled
    let removals = state.hexSettings.wordRemovals
    let modifiedResult: String
    if state.isRemappingScratchpadFocused {
      modifiedResult = result
      transcriptionFeatureLogger.info("Scratchpad focused; skipping word modifications")
    } else {
      var output = result
      if removalsEnabled {
        let removedResult = WordRemovalApplier.apply(output, removals: removals)
        if removedResult != output {
          let enabledRemovalCount = removals.filter(\.isEnabled).count
          transcriptionFeatureLogger.info("Applied \(enabledRemovalCount) word removal(s)")
        }
        output = removedResult
      }
      let remappedResult = WordRemappingApplier.apply(output, remappings: remappings)
      if remappedResult != output {
        transcriptionFeatureLogger.info("Applied \(remappings.count) word remapping(s)")
      }
      modifiedResult = remappedResult
    }

    guard !modifiedResult.isEmpty else {
      return .none
    }

    let sourceAppBundleID = state.sourceAppBundleID
    let sourceAppName = state.sourceAppName
    let transcriptionHistory = state.$transcriptionHistory
    let enableInstantEdit = state.hexSettings.enableInstantEdit

    // If instant edit is enabled, show the editor window
    if enableInstantEdit {
      @Dependency(\.transcriptEditor) var transcriptEditor

      return .run { [modifiedResult, duration, sourceAppName, audioURL, sourceAppBundleID] send in
        let result = await transcriptEditor.show(
          transcript: modifiedResult,
          duration: duration,
          sourceAppName: sourceAppName
        )

        if let result = result {
          // User confirmed the edit
          await send(.transcriptionEdited(
            originalText: modifiedResult,
            editedText: result.editedText,
            shouldLearn: result.shouldLearn,
            corrections: result.corrections,
            duration: duration,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName,
            audioURL: audioURL
          ))
        } else {
          // User cancelled - clean up the audio file
          try? FileManager.default.removeItem(at: audioURL)
        }
      }
      .cancellable(id: CancelID.transcription)
    } else {
      // Direct paste without editing
      return .run { send in
        do {
          try await finalizeRecordingAndStoreTranscript(
            result: modifiedResult,
            originalText: nil,
            corrections: [],
            duration: duration,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName,
            audioURL: audioURL,
            transcriptionHistory: transcriptionHistory
          )
        } catch {
          await send(.transcriptionError(error, audioURL))
        }
      }
      .cancellable(id: CancelID.transcription)
    }
  }

  func handleTranscriptionEdited(
    _ state: inout State,
    originalText: String,
    editedText: String,
    shouldLearn: Bool,
    corrections: [TextCorrection],
    duration: TimeInterval,
    sourceAppBundleID: String?,
    sourceAppName: String?,
    audioURL: URL
  ) -> Effect<Action> {
    state.isTranscribing = false
    state.isPrewarming = false

    let transcriptionHistory = state.$transcriptionHistory

    // Learn from corrections if enabled
    if shouldLearn && !corrections.isEmpty {
      @Shared(.hexSettings) var settings: HexSettings
      @Dependency(\.llmAnalysis) var llmAnalysis

      return .run { _ in
        // Choose analysis mode based on user settings
        let finalCorrections: [TextCorrection]
        let hotwords: [String]

        switch settings.correctionAnalysisMode {
        case .traditional:
          // Use traditional algorithm for everything
          finalCorrections = corrections
          let commonWords = getCommonWords()
          hotwords = TextDiffAlgorithm.extractHotwords(from: corrections, commonWords: commonWords)
          transcriptionFeatureLogger.info("Using traditional algorithm for corrections and hotwords")

        case .llm:
          // Use LLM analysis for everything
          if settings.llmConfig.enabled && settings.llmConfig.isValid {
            do {
              let request = LLMAnalysisRequest(
                originalText: originalText,
                editedText: editedText,
                language: nil
              )
              let response = try await llmAnalysis.analyzeCorrections(request, settings.llmConfig)

              // Use LLM-detected corrections instead of traditional ones
              finalCorrections = response.corrections
              hotwords = response.hotwords

              transcriptionFeatureLogger.info("✅ LLM analysis complete")
              transcriptionFeatureLogger.info("Detected \(finalCorrections.count) corrections: \(finalCorrections.map { "\($0.original)→\($0.corrected)" }.joined(separator: ", "))")
              transcriptionFeatureLogger.info("Extracted \(hotwords.count) hotwords: \(hotwords.joined(separator: ", "))")
              if let reasoning = response.reasoning {
                transcriptionFeatureLogger.debug("LLM reasoning: \(reasoning)")
              }
            } catch {
              transcriptionFeatureLogger.error("LLM analysis failed, falling back to traditional: \(error.localizedDescription)")
              finalCorrections = corrections
              let commonWords = getCommonWords()
              hotwords = TextDiffAlgorithm.extractHotwords(from: corrections, commonWords: commonWords)
            }
          } else {
            transcriptionFeatureLogger.warning("LLM not configured, falling back to traditional")
            finalCorrections = corrections
            let commonWords = getCommonWords()
            hotwords = TextDiffAlgorithm.extractHotwords(from: corrections, commonWords: commonWords)
          }
        }

        // Add corrections to word remappings
        $settings.withLock { settings in
          for correction in finalCorrections {
            let exists = settings.wordRemappings.contains { remapping in
              remapping.match.lowercased() == correction.original.lowercased()
            }

            if !exists {
              let newRemapping = WordRemapping(
                match: correction.original,
                replacement: correction.corrected
              )
              settings.wordRemappings.append(newRemapping)
              transcriptionFeatureLogger.info("Auto-learned word remapping: '\(correction.original)' → '\(correction.corrected)'")
            }
          }
        }

        // Add hotwords to settings
        $settings.withLock { settings in
          for hotword in hotwords {
            let hotwordLower = hotword.lowercased()
            if !settings.hotwords.contains(where: { $0.lowercased() == hotwordLower }) {
              settings.hotwords.append(hotword)
              transcriptionFeatureLogger.info("Auto-learned hotword: '\(hotword)'")
            }
          }
        }

        // Finalize and save
        try await finalizeRecordingAndStoreTranscript(
          result: editedText,
          originalText: originalText,
          corrections: corrections,
          duration: duration,
          sourceAppBundleID: sourceAppBundleID,
          sourceAppName: sourceAppName,
          audioURL: audioURL,
          transcriptionHistory: transcriptionHistory,
          fromInstantEdit: true
        )
      }
    } else {
      // No learning, just save
      return .run { _ in
        try await finalizeRecordingAndStoreTranscript(
          result: editedText,
          originalText: originalText,
          corrections: corrections,
          duration: duration,
          sourceAppBundleID: sourceAppBundleID,
          sourceAppName: sourceAppName,
          audioURL: audioURL,
          transcriptionHistory: transcriptionHistory,
          fromInstantEdit: true
        )
      }
    }
  }

  func handleTranscriptionError(
    _ state: inout State,
    error: Error,
    audioURL: URL?
  ) -> Effect<Action> {
    state.isTranscribing = false
    state.isPrewarming = false
    state.error = error.localizedDescription
    
    if let audioURL {
      try? FileManager.default.removeItem(at: audioURL)
    }

    return .none
  }

  /// Move file to permanent location, create a transcript record, paste text, and play sound.
  func finalizeRecordingAndStoreTranscript(
    result: String,
    originalText: String?,
    corrections: [TextCorrection],
    duration: TimeInterval,
    sourceAppBundleID: String?,
    sourceAppName: String?,
    audioURL: URL,
    transcriptionHistory: Shared<TranscriptionHistory>,
    fromInstantEdit: Bool = false
  ) async throws {
    @Shared(.hexSettings) var hexSettings: HexSettings

    if hexSettings.saveTranscriptionHistory {
      var transcript = try await transcriptPersistence.save(
        result,
        audioURL,
        duration,
        sourceAppBundleID,
        sourceAppName
      )

      // Add edit information if available
      if let originalText = originalText, originalText != result {
        transcript.originalText = originalText
        transcript.corrections = corrections
      }

      transcriptionHistory.withLock { history in
        history.history.insert(transcript, at: 0)

        if let maxEntries = hexSettings.maxHistoryEntries, maxEntries > 0 {
          while history.history.count > maxEntries {
            if let removedTranscript = history.history.popLast() {
              Task {
                 try? await transcriptPersistence.deleteAudio(removedTranscript)
              }
            }
          }
        }
      }
    } else {
      try? FileManager.default.removeItem(at: audioURL)
    }

    // For instant edit: always copy to clipboard AND try to insert
    if fromInstantEdit {
      // 1. Copy to clipboard as backup
      await pasteboard.copy(result)
      transcriptionFeatureLogger.info("Copied transcription to clipboard")

      // 2. Try to insert into active input field
      let success = await attemptDirectInsert(result)
      if success {
        transcriptionFeatureLogger.info("Successfully inserted transcription")
        soundEffect.play(.pasteTranscript)
      } else {
        transcriptionFeatureLogger.warning("Failed to auto-insert, but text is in clipboard")
        soundEffect.play(.pasteTranscript)
      }
    } else {
      // Normal transcription flow - use user settings
      await pasteboard.paste(result)
      soundEffect.play(.pasteTranscript)
    }
  }

  /// Returns set of common English/Chinese words that shouldn't be added as hotwords
  private func getCommonWords() -> Set<String> {
    return [
      // English common words
      "the", "and", "for", "are", "but", "not", "you", "all", "can", "her", "was", "one",
      "our", "out", "day", "get", "has", "him", "his", "how", "man", "new", "now", "old",
      "see", "two", "way", "who", "boy", "did", "its", "let", "put", "say", "she", "too",
      "use", "that", "this", "with", "have", "from", "they", "will", "what", "when", "make",
      "like", "time", "just", "know", "take", "people", "into", "year", "your", "good",
      "some", "could", "them", "than", "then", "these", "very", "about", "would", "there",
      "their", "which", "also", "been", "were", "said", "each", "should", "other", "only",
      "such", "being", "after", "before", "because", "through", "where", "while", "does",

      // Chinese common single characters
      "的", "是", "在", "了", "和", "有", "我", "他", "她", "它", "这", "那", "你", "吗", "啊", "呢",
      "吧", "啦", "哦", "嗯", "哈", "呀", "嘛", "哟", "喔", "诶",

      // Chinese common 2-character words
      "我们", "他们", "她们", "它们", "什么", "怎么", "为什么", "可以", "不是", "没有", "还是",
      "如果", "因为", "所以", "但是", "而且", "或者", "那么", "这样", "那样", "一个", "一些",
      "很多", "非常", "特别", "已经", "还有", "知道", "觉得", "认为", "应该", "可能", "需要",
      "希望", "想要", "喜欢", "看到", "听到", "说话", "做事", "时候", "地方", "东西", "事情",
      "问题", "方法", "办法", "情况", "状态", "结果", "原因", "开始", "结束", "继续", "停止",

      // Chinese common 3-character words
      "不知道", "不一定", "不一样", "有一点", "有时候", "没关系", "不客气", "对不起", "不好意思",
      "不可能", "很可能", "怎么样", "为什么", "是不是", "好不好", "行不行", "可不可以",

      // Chinese common 4+ character phrases
      "不好意思", "没关系的", "不要紧的", "无所谓的", "没问题的", "可以的话", "如果可以",
      "应该没有", "可能没有", "肯定没有", "一定要的", "必须要的"
    ]
  }

  /// Attempts to directly insert text into the focused input field
  private func attemptDirectInsert(_ text: String) async -> Bool {
    // Wait a bit for the window to close and focus to return to the original app
    try? await Task.sleep(for: .milliseconds(200))

    transcriptionFeatureLogger.info("Attempting to insert text via Accessibility API")

    // Try Accessibility API first (most reliable)
    do {
      try PasteboardClientLive.insertTextAtCursor(text)
      transcriptionFeatureLogger.info("✅ Successfully inserted via Accessibility API")
      return true
    } catch {
      transcriptionFeatureLogger.warning("❌ Accessibility API failed: \(error.localizedDescription)")
    }

    // Fallback: try Cmd+V (text is already in clipboard)
    transcriptionFeatureLogger.info("Attempting to insert text via Cmd+V")

    let source = CGEventSource(stateID: .combinedSessionState)
    guard let source = source else {
      transcriptionFeatureLogger.error("Failed to create CGEventSource")
      return false
    }

    let vKey = CGKeyCode(9) // V key
    let cmdKey = CGKeyCode(55) // Cmd key

    let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true)
    let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
    vDown?.flags = .maskCommand
    let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
    vUp?.flags = .maskCommand
    let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)

    cmdDown?.post(tap: .cghidEventTap)
    vDown?.post(tap: .cghidEventTap)
    vUp?.post(tap: .cghidEventTap)
    cmdUp?.post(tap: .cghidEventTap)

    transcriptionFeatureLogger.info("✅ Posted Cmd+V events")
    return true
  }
}

// MARK: - Cancel/Discard Handlers

private extension TranscriptionFeature {
  func handleCancel(_ state: inout State) -> Effect<Action> {
    state.isTranscribing = false
    state.isRecording = false
    state.isPrewarming = false

    return .merge(
      .cancel(id: CancelID.transcription),
      .run { [sleepManagement] _ in
        // Allow system to sleep again
        await sleepManagement.allowSleep()
        // Stop the recording to release microphone access
        let url = await recording.stopRecording()
        try? FileManager.default.removeItem(at: url)
        soundEffect.play(.cancel)
      }
    )
  }

  func handleDiscard(_ state: inout State) -> Effect<Action> {
    state.isRecording = false
    state.isPrewarming = false

    // Silently discard - no sound effect
    return .run { [sleepManagement] _ in
      // Allow system to sleep again
      await sleepManagement.allowSleep()
      let url = await recording.stopRecording()
      try? FileManager.default.removeItem(at: url)
    }
  }
}

// MARK: - View

struct TranscriptionView: View {
  @Bindable var store: StoreOf<TranscriptionFeature>
  @ObserveInjection var inject

  var status: TranscriptionIndicatorView.Status {
    if store.isTranscribing {
      return .transcribing
    } else if store.isRecording {
      return .recording
    } else if store.isPrewarming {
      return .prewarming
    } else {
      return .hidden
    }
  }

  var body: some View {
    TranscriptionIndicatorView(
      status: status,
      meter: store.meter
    )
    .task {
      await store.send(.task).finish()
    }
    .enableInjection()
  }
}

// MARK: - Force Quit Command

private enum ForceQuitCommandDetector {
  static func matches(_ text: String) -> Bool {
    let normalized = normalize(text)
    return normalized == "force quit hex now" || normalized == "force quit hex"
  }

  private static func normalize(_ text: String) -> String {
    text
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}
