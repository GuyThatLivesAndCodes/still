import Foundation
import AVFoundation
import Speech
import Observation

/// Records a voice entry with Apple's voice processing (noise suppression and echo
/// cancellation) and transcribes it live, on device only. Audio is written to a
/// protected temp file until the entry is sealed, then encrypted into the entry.
@Observable
final class VoiceRecorder {
    enum State: Equatable { case idle, recording, finishing }

    enum RecorderError: LocalizedError {
        case micDenied, engine
        var errorDescription: String? {
            switch self {
            case .micDenied: return "still. needs microphone access to record. You can turn it on in Settings."
            case .engine: return "The microphone couldn't start. Please try again."
            }
        }
    }

    static let maxDuration: TimeInterval = 180

    private(set) var state: State = .idle
    private(set) var transcript = ""
    private(set) var elapsed: TimeInterval = 0
    /// Recent input levels, 0...1, newest last. Drives the live waveform.
    private(set) var levels: [CGFloat] = Array(repeating: 0, count: 22)
    /// False when on-device speech isn't available (permission or language).
    private(set) var transcribing = false

    var isRecording: Bool { state == .recording }

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var file: AVAudioFile?
    @ObservationIgnored private var converter: AVAudioConverter?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var finished: (() -> Void)?

    // MARK: Permissions

    static func requestPermissions() async -> (mic: Bool, speech: Bool) {
        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else { return (false, false) }
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        return (mic, speech)
    }

    // MARK: Recording

    @MainActor
    func start(transcribe: Bool) throws {
        guard state == .idle else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        // Apple's voice processing: isolates speech from background noise and echo.
        try? input.setVoiceProcessingEnabled(true)

        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0,
              let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inFormat.sampleRate,
                                       channels: 1, interleaved: false)
        else { throw RecorderError.engine }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete],
                                               ofItemAtPath: url.path)
        converter = inFormat == mono ? nil : AVAudioConverter(from: inFormat, to: mono)

        transcribing = false
        if transcribe, let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
           recognizer.isAvailable, recognizer.supportsOnDeviceRecognition {
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.requiresOnDeviceRecognition = true   // never leaves the phone
            req.shouldReportPartialResults = true
            req.addsPunctuation = true
            request = req
            transcribing = true
            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self.completeFinish() }
                }
            }
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.handle(buffer, mono: mono)
        }

        self.engine = engine
        self.file = file
        self.fileURL = url
        transcript = ""
        elapsed = 0
        levels = Array(repeating: 0, count: levels.count)

        _ = engine.mainMixerNode   // voice processing needs a complete I/O graph
        engine.prepare()
        do { try engine.start() } catch { teardown(); throw RecorderError.engine }

        startedAt = .now
        state = .recording
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsed = Date.now.timeIntervalSince(self.startedAt)
            if self.elapsed >= Self.maxDuration { self.stop() }
        }
    }

    private func handle(_ buffer: AVAudioPCMBuffer, mono: AVAudioFormat) {
        var out = buffer
        if let converter {
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * mono.sampleRate / buffer.format.sampleRate) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: capacity) else { return }
            var fed = false
            var err: NSError?
            converter.convert(to: converted, error: &err) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            if err != nil { return }
            out = converted
        }
        try? file?.write(from: out)
        request?.append(out)

        guard let samples = out.floatChannelData?[0], out.frameLength > 0 else { return }
        var sum: Float = 0
        for i in 0..<Int(out.frameLength) { sum += samples[i] * samples[i] }
        let rms = sqrt(sum / Float(out.frameLength))
        let level = CGFloat(min(1, max(0, (20 * log10(max(rms, 0.000_01)) + 50) / 45)))
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state == .recording else { return }
            self.levels.removeFirst()
            self.levels.append(level)
        }
    }

    /// Stops recording. `done` runs once the final transcript is in (or after a short wait).
    func stop(_ done: (() -> Void)? = nil) {
        guard state == .recording else { return }
        state = .finishing
        finished = done
        timer?.invalidate(); timer = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        file = nil   // closes and flushes the m4a
        if let request {
            request.endAudio()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.completeFinish() }
        } else {
            completeFinish()
        }
    }

    private func completeFinish() {
        guard state == .finishing else { return }
        task = nil
        request = nil
        teardownEngine()
        state = .idle
        let done = finished
        finished = nil
        done?()
    }

    /// The recorded audio of the last take, if any.
    var recordingURL: URL? { fileURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } }

    /// Removes the last take and its temp file.
    func discard() {
        if state != .idle { cancel() }
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
        transcript = ""
        elapsed = 0
    }

    func cancel() {
        task?.cancel()
        timer?.invalidate(); timer = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        file = nil
        finished = nil
        teardown()
        state = .idle
    }

    private func teardown() {
        task = nil
        request = nil
        teardownEngine()
    }

    private func teardownEngine() {
        engine = nil
        converter = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Small player used for previewing a take and for revealed voice entries.
@Observable
final class VoicePlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private(set) var duration: TimeInterval = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?

    func load(_ url: URL) {
        stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.prepareToPlay()
        duration = player?.duration ?? 0
        progress = 0
    }

    func load(data: Data) {
        stop()
        player = try? AVAudioPlayer(data: data)
        player?.delegate = self
        player?.prepareToPlay()
        duration = player?.duration ?? 0
        progress = 0
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self, let p = self.player, p.duration > 0 else { return }
                self.progress = p.currentTime / p.duration
            }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        timer?.invalidate(); timer = nil
        isPlaying = false
        progress = 0
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.isPlaying = false
            self.progress = 0
            player.currentTime = 0
        }
    }
}
