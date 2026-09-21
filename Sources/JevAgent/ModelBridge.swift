import Foundation
import Darwin
import JevCore

final class ModelBridge {
    private let settings: Settings
    private let ioQueue = DispatchQueue(label: "ai.jev.agent.worker-input")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errors: FileHandle?
    private var buffer = Data()
    private var generation = 0
    private var requestID: String?
    private var deadline: DispatchWorkItem?
    private var restartCount = 0
    private(set) var ready = false
    var onStatus: ((String) -> Void)?
    var onResult: ((String?, String?) -> Void)?

    init(settings: Settings) { self.settings = settings; signal(SIGPIPE, SIG_IGN) }

    func start() {
        stop()
        let token = generation
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent("runtime.json"),
                          Bundle.main.resourceURL?.appendingPathComponent("Resources/runtime.json")]
        guard let runtimeURL = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: runtimeURL),
              let runtime = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
              let python = runtime["python"], let root = runtime["project_root"] else {
            onStatus?("Runtime not configured. Run scripts/bootstrap.sh and scripts/build-app.sh. Manual selection is available.")
            return
        }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: python)
        child.arguments = ["-m", "jev_agent.worker", "--provider", settings.provider]
        child.currentDirectoryURL = URL(fileURLWithPath: root)
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["TYPESAFE_DEFAULT_MODEL"] = settings.model
        if settings.provider == "jev" {
            do {
                if let key = try Keychain.read(), !key.isEmpty { environment["TYPESAFE_API_KEY"] = key }
            } catch {
                onStatus?("Keychain access failed: \(error.localizedDescription). Unlock or update the key in Settings.")
                return
            }
        } else { environment.removeValue(forKey: "TYPESAFE_API_KEY") }
        child.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = stderr
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let incoming = handle.availableData
            guard !incoming.isEmpty else { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.consume(incoming)
            }
        }
        errors = stderr.fileHandleForReading
        errors?.readabilityHandler = { handle in
            let incoming = handle.availableData
            guard !incoming.isEmpty else { handle.readabilityHandler = nil; return }
            FileHandle.standardError.write(incoming)
        }
        child.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.ready = false
                self.cancel(terminatePending: false)
                self.onStatus?("Model process stopped. Manual selection is available.")
                self.recover()
            }
        }
        process = child
        onStatus?("Loading \(settings.title)… You can choose manually.")
        do { try child.run() }
        catch { stop(); onStatus?("Cannot start model: \(error.localizedDescription)") }
    }

    func reconfigure() { restartCount = 0; start() }
    func cancel(terminatePending: Bool = true) {
        let pending = requestID != nil
        requestID = nil
        deadline?.cancel()
        deadline = nil
        if pending && terminatePending {
            stop()
            let token = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.start()
            }
        }
    }
    func stop() {
        generation += 1
        cancel(terminatePending: false)
        ready = false
        output?.readabilityHandler = nil
        output = nil
        errors?.readabilityHandler = nil
        errors = nil
        let previousInput = input
        input = nil
        if let process, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        process = nil
        // Closing a pipe can synchronize with a blocked writer. Keep that off the UI thread.
        ioQueue.async { try? previousInput?.close() }
        buffer = Data()
    }
    private func recover() {
        guard restartCount < 1 else { return }
        restartCount += 1
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.generation == token else { return }
            self.start()
        }
    }
    func decide(context: [String: String], candidates: [ClipboardEntry]) {
        cancel()
        guard ready, !candidates.isEmpty else { return }
        let id = UUID().uuidString
        requestID = id
        let request: [String: Any] = ["version": 1, "type": "decide", "request_id": id,
            "config_version": generation, "provider": settings.provider, "context": context.mapValues { String($0.unicodeScalars.prefix(512)) },
            "candidates": candidates.map { ["id": $0.id, "text": String($0.text.unicodeScalars.prefix(1200))] }]
        do {
            var data = try JSONSerialization.data(withJSONObject: request)
            data.append(10)
            guard data.count <= 200_000, let destination = input else {
                cancel(terminatePending: false)
                onResult?(nil, "Request exceeds the byte budget or the model is disconnected.")
                return
            }
            onStatus?("Finding a match… You can choose manually.")
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.requestID == id else { return }
                self.onResult?(nil, "Recommendation timed out. Choose an item manually.")
                self.stop()
                self.recover()
            }
            deadline = timeout
            let configured = Double(ProcessInfo.processInfo.environment["JEV_AGENT_DECISION_TIMEOUT_MS"] ?? "2000") ?? 2000
            DispatchQueue.main.asyncAfter(deadline: .now() + max(100, min(configured, 2000)) / 1000, execute: timeout)
            let payload = data
            let token = generation
            ioQueue.async { [weak self] in
                do { try destination.write(contentsOf: payload) }
                catch {
                    DispatchQueue.main.async {
                        guard let self, self.generation == token, self.requestID == id else { return }
                        self.cancel()
                        self.onResult?(nil, "Model communication failed: \(error.localizedDescription)")
                    }
                }
            }
        } catch { cancel(); onResult?(nil, "Model communication failed: \(error.localizedDescription)") }
    }
    private func consume(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 2_000_000 else { stop(); onStatus?("Invalid model response: too large."); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  object["version"] as? Int == 1, object["provider"] as? String == settings.provider else { continue }
            if object["type"] as? String == "status" {
                ready = object["status"] as? String == "ready"
                let error = object["error"] as? [String: Any]
                onStatus?(ready ? "Ready. Open the panel to find a match." : error?["message"] as? String ?? "Loading model…")
            } else if object["type"] as? String == "result",
                      object["request_id"] as? String == requestID,
                      object["config_version"] as? Int == generation {
                cancel(terminatePending: false)
                let error = object["error"] as? [String: Any]
                onResult?(object["selected_id"] as? String, error?["message"] as? String)
            }
        }
    }
}
