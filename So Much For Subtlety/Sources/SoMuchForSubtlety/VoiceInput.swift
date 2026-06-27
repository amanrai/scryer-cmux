#if os(iOS)
import SwiftUI
import AVFoundation
import CoreML
import WhisperKit
import ScryerCore

/// On-device live dictation backed by WhisperKit's `AudioStreamTranscriber`. Transcribes the
/// mic in real time, surfacing confirmed text plus an in-flux tail, and auto-stops after a
/// short trailing silence. Fully on-device; only needs microphone permission.
///
/// Whisper isn't natively streaming — the transcriber re-runs on a sliding window and
/// "confirms" stable segments — so text lands in chunks with a brief lag, not word-by-word.
@MainActor
@Observable
final class VoiceDictation {
    enum Status: Equatable {
        case idle
        case loadingModel           // first-run download / model load
        case listening              // live streaming
        case denied                 // microphone permission refused
        case unavailable(String)    // model load / streaming failed
    }

    /// Final, editable transcript — set when streaming stops (auto or manual).
    var transcript = ""
    /// Live stream text, split so the UI can dim the still-changing tail.
    private(set) var confirmedText = ""
    private(set) var pendingText = ""
    private(set) var status: Status = .idle
    /// 0…1 while the model downloads/loads (first run only).
    private(set) var modelProgress: Double = 0

    var isListening: Bool { status == .listening }
    var isBusy: Bool { status == .loadingModel }

    /// Auto-stop after this much trailing silence, once something has been said. Generous so
    /// a natural mid-thought pause doesn't cut you off.
    var silenceTimeout: TimeInterval = 6.0

    private var streamer: AudioStreamTranscriber?
    private var streamTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private var lastActivity = Date()

    // The model is expensive to load, so keep one instance for the whole app session.
    private static var shared: WhisperKit?
    private static var loadTask: Task<WhisperKit, Error>?
    /// Turbo variant: near-large-v3 accuracy, fast on M-series; runs on A15 (iPhone 14) too.
    static var modelName = "large-v3-v20240930_turbo"

    /// Warm the model ahead of time (e.g. when the panel opens) so it's ready by record time.
    func preloadModel() { Task { _ = try? await loadModelIfNeeded() } }

    func toggle() {
        switch status {
        case .listening:                     Task { await stopStreaming(finalize: true) }
        case .idle, .denied, .unavailable:   Task { await start() }
        case .loadingModel:                  break
        }
    }

    func start() async {
        guard status != .listening, status != .loadingModel else { return }
        guard await AVAudioApplication.requestRecordPermission() else { status = .denied; return }
        status = (Self.shared == nil) ? .loadingModel : .listening
        do {
            let wk = try await loadModelIfNeeded()
            guard let tokenizer = wk.tokenizer else {
                status = .unavailable("Model tokenizer unavailable."); return
            }
            transcript = ""; confirmedText = ""; pendingText = ""; lastActivity = Date()

            var opts = DecodingOptions()
            opts.language = "en"          // skip language detection; we dictate in English
            opts.skipSpecialTokens = true // don't leak <|...|> control tokens into the text
            opts.withoutTimestamps = true // and no <|0.00|> timestamp tokens
            let streamer = AudioStreamTranscriber(
                audioEncoder: wk.audioEncoder,
                featureExtractor: wk.featureExtractor,
                segmentSeeker: wk.segmentSeeker,
                textDecoder: wk.textDecoder,
                tokenizer: tokenizer,
                audioProcessor: wk.audioProcessor,
                decodingOptions: opts,
                stateChangeCallback: { [weak self] _, newState in
                    Task { @MainActor in self?.apply(newState) }
                }
            )
            self.streamer = streamer
            status = .listening
            streamTask = Task { try? await streamer.startStreamTranscription() }
            startSilenceWatch()
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }

    /// Stop the live stream. `finalize` folds the captured text into `transcript` for review.
    func stopStreaming(finalize: Bool) async {
        silenceTask?.cancel(); silenceTask = nil
        await streamer?.stopStreamTranscription()
        streamTask?.cancel(); streamTask = nil
        streamer = nil
        if finalize {
            transcript = (confirmedText + pendingText).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if status == .listening { status = .idle }
    }

    /// Tear down without finalizing (panel dismissed). Safe to call any time.
    func reset() {
        silenceTask?.cancel(); silenceTask = nil
        streamTask?.cancel(); streamTask = nil
        if let s = streamer { Task { await s.stopStreamTranscription() } }
        streamer = nil
        transcript = ""; confirmedText = ""; pendingText = ""
        if status != .loadingModel { status = .idle }
    }

    // Fold a streaming state update into our confirmed/pending text and mark activity.
    private func apply(_ s: AudioStreamTranscriber.State) {
        let confirmed = Self.clean(s.confirmedSegments.map(\.text).joined())
        let pending = Self.clean(s.unconfirmedSegments.map(\.text).joined())
        if confirmed != confirmedText || pending != pendingText {
            confirmedText = confirmed
            pendingText = pending
            lastActivity = Date()
        }
    }

    // Strip any residual Whisper control tokens like <|startoftranscript|> / <|0.00|>.
    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
    }

    // Auto-stop once there's text and the stream has gone quiet for `silenceTimeout`.
    private func startSilenceWatch() {
        silenceTask?.cancel()
        silenceTask = Task { @MainActor in
            while status == .listening {
                try? await Task.sleep(for: .milliseconds(300))
                let hasText = !(confirmedText + pendingText).isEmpty
                if hasText, Date().timeIntervalSince(lastActivity) > silenceTimeout {
                    await stopStreaming(finalize: true)
                }
            }
        }
    }

    /// Download (first run) + load the model, reporting download progress into `modelProgress`.
    private func loadModelIfNeeded() async throws -> WhisperKit {
        if let wk = Self.shared { return wk }
        if let t = Self.loadTask { return try await t.value }

        let (stream, cont) = AsyncStream<Double>.makeStream()
        let consumer = Task { @MainActor in for await f in stream { self.modelProgress = f } }
        let model = Self.modelName
        let task = Task { () throws -> WhisperKit in
            let folder = try await WhisperKit.download(variant: model, progressCallback: { p in
                cont.yield(p.fractionCompleted)
            })
            cont.finish()
            // CPU+GPU, not the Neural Engine: the on-device ANE compiler service is flaky.
            let compute = ModelComputeOptions(audioEncoderCompute: .cpuAndGPU, textDecoderCompute: .cpuAndGPU)
            return try await WhisperKit(WhisperKitConfig(
                model: model, modelFolder: folder.path, computeOptions: compute, download: false))
        }
        Self.loadTask = task
        do {
            let wk = try await task.value
            Self.shared = wk
            consumer.cancel()
            return wk
        } catch {
            cont.finish(); consumer.cancel(); Self.loadTask = nil
            throw error
        }
    }
}

/// Dictation panel: live streaming recorder. Streaming starts when the panel opens; text
/// builds in place (confirmed solid, in-flux tail dimmed) and auto-stops after a brief
/// silence. The big button toggles stop/record; Send hands the final text to the host.
struct DictationView: View {
    @Environment(\.dismiss) private var dismiss
    /// Trailing-silence (seconds) before auto-stop — from Settings → Audio.
    let silenceTimeout: Double
    /// Called with the final transcript when the user taps Send. The host decides whether
    /// to append a newline (submit) — keeps this view ignorant of terminal semantics.
    let onSend: (String) -> Void

    @State private var voice = VoiceDictation()
    @State private var pulse = false

    // Whatever's captured so far (final transcript if stopped, else the live stream).
    private var sendable: String {
        let live = voice.transcript.isEmpty ? voice.confirmedText + voice.pendingText : voice.transcript
        return live.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSend: Bool { voice.isListening || !sendable.isEmpty }

    var body: some View {
        VStack(spacing: 24) {
            topBar
            recordButton
            transcript
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dismissOnEscape { dismiss() }
        .onAppear { voice.silenceTimeout = silenceTimeout; voice.preloadModel(); Task { await voice.start() } }
        .onDisappear { voice.reset() }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            Spacer()
            if canSend {
                Button(action: send) { Label("Send", systemImage: "arrow.up.circle.fill") }
                    .buttonStyle(.borderedProminent)
            }
        }
        .animation(.easeOut(duration: 0.18), value: canSend)
    }

    // Sending stops the stream first (if live), then hands the final text to the host.
    private func send() {
        Task {
            if voice.isListening { await voice.stopStreaming(finalize: true) }
            let text = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            onSend(text)
            dismiss()
        }
    }

    private var recordButton: some View {
        Button { voice.toggle() } label: {
            ZStack {
                Circle()
                    .fill(voice.isListening ? Color.red : Color.accentColor)
                    .frame(width: 96, height: 96)
                    .shadow(color: (voice.isListening ? Color.red : Color.accentColor).opacity(0.4), radius: 14)
                if voice.isBusy {
                    ProgressView().tint(.white).scaleEffect(1.4)
                } else {
                    Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .scaleEffect(pulse && voice.isListening ? 1.06 : 1)
            .animation(voice.isListening ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default,
                       value: pulse)
        }
        .buttonStyle(.plain)
        .disabled(voice.isBusy)
        .onChange(of: voice.isListening) { _, listening in pulse = listening }
    }

    // Live stream → confirmed solid + dimmed tail (read-only); after stop → editable text.
    @ViewBuilder private var transcript: some View {
        Group {
            if let message = errorMessage {
                Text(message).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.center)
            } else if voice.isListening {
                ScrollView {
                    (Text(voice.confirmedText) + Text(voice.pendingText).foregroundColor(.secondary))
                        .font(.title3).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .overlay {
                    if voice.confirmedText.isEmpty && voice.pendingText.isEmpty {
                        Text("Listening…").font(.title3).foregroundStyle(.tertiary)
                    }
                }
            } else if !voice.transcript.isEmpty {
                editableTranscript
            } else {
                Text(placeholder).font(.title3).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editableTranscript: some View {
        @Bindable var voice = voice
        return TextEditor(text: $voice.transcript)
            .font(.title3)
            .multilineTextAlignment(.center)
            .scrollContentBackground(.hidden)
            .background(.clear)
    }

    private var placeholder: String {
        switch voice.status {
        case .loadingModel:
            return voice.modelProgress < 1
                ? "Downloading model… \(Int(voice.modelProgress * 100))% (first run only)"
                : "Loading model… (first run, then cached)"
        default:
            return "Tap to record"
        }
    }

    private var errorMessage: String? {
        switch voice.status {
        case .denied:               return "Microphone access denied. Enable it in Settings."
        case .unavailable(let why): return why
        default:                    return nil
        }
    }
}
#endif
