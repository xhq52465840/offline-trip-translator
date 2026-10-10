import AVFoundation
import Speech
import TripAppModel

/// 本机听写：iOS 26 优先 SpeechAnalyzer + SpeechTranscriber；否则 SFSpeechRecognizer（requiresOnDeviceRecognition = true）。
/// 任何路径都不走服务器（技术设计 v2 §7）。
final class LiveTranscriber: Transcribing {
    private let engine = AVAudioEngine()
    private var latest = ""
    private var finalText: String?

    // SFSpeechRecognizer 路径
    private var sfRequest: SFSpeechAudioBufferRecognitionRequest?
    private var sfTask: SFSpeechRecognitionTask?

    // SpeechAnalyzer 路径（类型擦除，避免低版本引用）
    private var analyzerBox: AnyObject?
    private var finishAnalyzer: (() async -> Void)?
    private var cancelAnalyzer: (() -> Void)?
    private var resultsTask: Task<Void, Never>?

    enum Failure: Error { case micDenied, speechDenied, notOnDevice }

    func start(locale: String) async throws {
        latest = ""; finalText = nil
        guard await AVAudioApplication.requestRecordPermission() else { throw Failure.micDenied }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true, options: [])

        if #available(iOS 26.0, *), try await startAnalyzer(locale: Locale(identifier: locale)) { return }
        try await startSF(locale: Locale(identifier: locale))
    }

    func finish() async -> String {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        if let f = finishAnalyzer { await f() }
        sfRequest?.endAudio()
        // 等最终结果，最多 1.5 秒
        for _ in 0..<15 where finalText == nil { try? await Task.sleep(nanoseconds: 100_000_000) }
        cleanup()
        return finalText ?? latest
    }

    func cancel() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        cancelAnalyzer?()
        sfTask?.cancel()
        cleanup()
    }

    private func cleanup() {
        resultsTask?.cancel(); resultsTask = nil
        sfTask = nil; sfRequest = nil; analyzerBox = nil; finishAnalyzer = nil; cancelAnalyzer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: SFSpeechRecognizer（本机）

    private func startSF(locale: Locale) async throws {
        let status = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard status == .authorized else { throw Failure.speechDenied }
        guard let rec = SFSpeechRecognizer(locale: locale), rec.supportsOnDeviceRecognition else { throw Failure.notOnDevice }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        sfRequest = req
        sfTask = rec.recognitionTask(with: req) { [weak self] result, _ in
            guard let self, let result else { return }
            self.latest = result.bestTranscription.formattedString
            if result.isFinal { self.finalText = self.latest }
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)          // 用输入节点格式，不写死 16 kHz
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buf, _ in req?.append(buf) }
        engine.prepare()
        try engine.start()
    }

    // MARK: SpeechAnalyzer（iOS 26）

    @available(iOS 26.0, *)
    private func startAnalyzer(locale: Locale) async throws -> Bool {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return false }
        let installed = await SpeechTranscriber.installedLocales
        guard installed.contains(where: { $0.identifier(.bcp47) == supported.identifier(.bcp47) }) else { return false }

        let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { return false }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        let converter = AVAudioConverter(from: inFormat, to: target)
        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { buf, _ in
            guard let converter else { return }
            let ratio = target.sampleRate / inFormat.sampleRate
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(buf.frameLength) * ratio) + 1) else { return }
            var fed = false
            _ = converter.convert(to: out, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return buf
            }
            continuation.yield(AnalyzerInput(buffer: out))
        }

        resultsTask = Task { [weak self] in
            do {
                for try await r in transcriber.results {
                    let s = String(r.text.characters)
                    self?.latest = s
                    if r.isFinal { self?.finalText = s }
                }
            } catch {}
        }
        try await analyzer.start(inputSequence: stream)
        engine.prepare()
        try engine.start()
        analyzerBox = analyzer
        finishAnalyzer = { continuation.finish(); try? await analyzer.finalizeAndFinishThroughEndOfInput() }
        cancelAnalyzer = { continuation.finish(); Task { await analyzer.cancelAndFinishNow() } }
        return true
    }
}
