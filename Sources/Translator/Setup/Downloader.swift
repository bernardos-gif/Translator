import Foundation

/// Downloads a file to disk while reporting progress (0...1, or nil when the size is unknown).
final class Downloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    private var progress: ((Double?, Int64) -> Void)?
    private var destination: URL!
    private var session: URLSession!

    static func download(_ url: URL, to destination: URL,
                         progress: @escaping (Double?, Int64) -> Void) async throws -> URL {
        let downloader = Downloader()
        return try await downloader.start(url, to: destination, progress: progress)
    }

    private func start(_ url: URL, to destination: URL,
                       progress: @escaping (Double?, Int64) -> Void) async throws -> URL {
        self.destination = destination
        self.progress = progress
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                var request = URLRequest(url: url)
                request.setValue("Translator-macOS", forHTTPHeaderField: "User-Agent")
                session.downloadTask(with: request).resume()
            }
        } onCancel: { [weak self] in
            self?.session?.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let fraction = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : nil
        progress?(fraction, totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(SetupError.message("Download failed (HTTP \(http.statusCode)) for \(downloadTask.originalRequest?.url?.lastPathComponent ?? "file").")))
            return
        }
        do {
            let fm = FileManager.default
            try? fm.removeItem(at: destination)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
        session.finishTasksAndInvalidate()
    }
}

enum SetupError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

/// Small helpers for running command-line tools synchronously during setup.
enum Shell {
    struct Result {
        let status: Int32
        let output: String
    }

    @discardableResult
    static func run(_ executable: String, _ args: [String], environment: [String: String]? = nil,
                    cwd: URL? = nil) async -> Result {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            if let environment { process.environment = environment }
            if let cwd { process.currentDirectoryURL = cwd }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let collector = OutputCollector()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil } else { collector.append(data) }
            }
            process.terminationHandler = { proc in
                // Drain anything left in the pipe before reporting.
                pipe.fileHandleForReading.readabilityHandler = nil
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                collector.append(rest)
                continuation.resume(returning: Result(status: proc.terminationStatus, output: collector.text))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: Result(status: -1, output: error.localizedDescription))
            }
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) {
        lock.lock(); data.append(chunk); lock.unlock()
    }
    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
