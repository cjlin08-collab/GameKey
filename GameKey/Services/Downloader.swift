import Foundation

/// Downloads installers with progress reporting. Uses URLSession's delegate API instead of the
/// async/await variant because we want byte-by-byte progress in the UI, which `download(from:)`
/// does not expose.
final class Downloader: NSObject, URLSessionDownloadDelegate {
    typealias Progress = (Double) -> Void
    typealias Completion = (Result<URL, Error>) -> Void

    private var session: URLSession!
    private var progressHandler: Progress?
    private var completionHandler: Completion?
    private var destination: URL?

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 30
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    func download(from url: URL,
                  to destination: URL,
                  onProgress: @escaping Progress,
                  completion: @escaping Completion) {
        self.progressHandler = onProgress
        self.completionHandler = completion
        self.destination = destination
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let task = session.downloadTask(with: url)
        task.resume()
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler?(fraction)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let destination else {
            completionHandler?(.failure(DownloaderError.noDestination))
            return
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            completionHandler?(.success(destination))
        } catch {
            completionHandler?(.failure(error))
        }
        // URLSession retains its delegate. Break the cycle once we're done.
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error {
            completionHandler?(.failure(error))
            session.finishTasksAndInvalidate()
        }
    }

    enum DownloaderError: LocalizedError {
        case noDestination
        var errorDescription: String? {
            switch self {
            case .noDestination: return "Download finished but no destination was set."
            }
        }
    }
}

extension Downloader {
    /// Async/await convenience wrapper that surfaces progress via an AsyncStream.
    func downloadAsync(from url: URL, to destination: URL) -> AsyncThrowingStream<DownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            self.download(from: url, to: destination) { fraction in
                continuation.yield(.progress(fraction))
            } completion: { result in
                switch result {
                case .success(let url):
                    continuation.yield(.completed(url))
                    continuation.finish()
                case .failure(let error):
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    enum DownloadEvent {
        case progress(Double)
        case completed(URL)
    }
}
