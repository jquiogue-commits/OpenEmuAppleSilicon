// Copyright (c) 2021, OpenEmu Team
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the OpenEmu Team nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import Foundation

/// Downloads a URL to a unique temporary file using async/await, optionally
/// reporting fractional progress. Cancel by cancelling the awaiting `Task` or by
/// calling `cancel()`.
///
/// The built-in async `URLSession.download(for:delegate:)` is macOS 12+, but the
/// app targets 11.5, so this bridges the delegate-based API to a continuation.
final class Download: NSObject {

    let url: URL

    private var session: URLSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var progressHandler: ((Double) -> Void)?
    private var destination: URL?
    private var progress: Double = 0

    init(url: URL) {
        self.url = url
        super.init()
    }

    /// Downloads `url` to a unique temporary file and returns its location.
    ///
    /// - Parameter progressHandler: invoked on the main queue with fractional
    ///   progress in `0...1` as data arrives.
    /// - Throws: the underlying `URLError` on failure, or `URLError.cancelled`
    ///   if cancelled.
    func download(progressHandler: ((Double) -> Void)? = nil) async throws -> URL {
        self.progressHandler = progressHandler
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                self.continuation = continuation

                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 60)
                let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
                session.sessionDescription = url.absoluteString
                self.session = session

                DLog("Starting download (\(session.sessionDescription ?? ""))")
                session.downloadTask(with: request).resume()
            }
        } onCancel: {
            cancel()
        }
    }

    func cancel() {
        DLog("Cancelling download (\(session?.sessionDescription ?? ""))")
        session?.invalidateAndCancel()
    }

    /// Resumes the pending continuation exactly once and tears down the session.
    private func finish(_ result: Result<URL, Error>) {
        guard let continuation = continuation else { return }
        self.continuation = nil
        session?.finishTasksAndInvalidate()
        session = nil
        continuation.resume(with: result)
    }
}

extension Download: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {

        DLog("Download (\(session.sessionDescription ?? "")) did complete: \(error?.localizedDescription ?? "no errors")")

        if let error = error {
            finish(.failure(error))
        } else if let destination = destination {
            finish(.success(destination))
        } else {
            // Completed without an error but the temporary file was never staged.
            finish(.failure(URLError(.cannotCreateFile)))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {

        guard totalBytesExpectedToWrite > 0 else { return }

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

        // Try reducing the number of callbacks.
        if abs(progress - self.progress) > 0.01 {
            self.progress = progress
            progressHandler?(progress)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {

        DLog("Download (\(session.sessionDescription ?? "")) did finish downloading temporary data.")

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("org.openemu.OpenEmu", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = temporaryDirectory.appendingPathComponent(url.lastPathComponent)

        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: location, to: destination)
            self.destination = destination
        } catch {
            DLog("Failed to stage downloaded file: \(error)")
        }
    }
}
