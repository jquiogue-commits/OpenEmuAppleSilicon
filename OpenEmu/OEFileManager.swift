// Copyright (c) 2023, OpenEmu Team
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

/// An `NSFileManager` subclass whose `copyItem(at:to:)` reports progress and
/// per-item results through the `progressHandler`, `itemDoneHandler` and
/// `errorHandler` callbacks (backed by copyfile(3)).
final class OEFileManager: FileManager {

    /// Return `false` to cancel the copy.
    var progressHandler: ((_ progress: Float) -> Bool)?
    /// Return `false` to cancel the copy.
    var itemDoneHandler: ((_ src: URL, _ dst: URL, _ result: Error?) -> Bool)?
    /// Return `false` to cancel the copy.
    var errorHandler: ((_ src: URL, _ dst: URL, _ result: Error?) -> Bool)?

    func sizeOfItem(at url: URL) -> UInt {
        var fileSize: UInt = 0

        guard let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory else {
            return 0
        }

        if isDirectory {
            let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
            guard let directoryEnumerator = enumerator(at: url, includingPropertiesForKeys: keys) else {
                return 0
            }
            for case let itemURL as URL in directoryEnumerator {
                if let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
                   values.isDirectory == false,
                   let size = values.fileSize {
                    fileSize += UInt(size)
                }
            }
        } else if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            fileSize = UInt(size)
        }

        return fileSize
    }

    /// Bridges the C status callback back to the Swift per-copy state.
    private final class CopyContext {
        let callback: (copyfile_state_t?, Int32, Int32, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32

        init(_ callback: @escaping (copyfile_state_t?, Int32, Int32, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32) {
            self.callback = callback
        }
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        let src = srcURL.path
        let dst = dstURL.path

        let total = Int64(sizeOfItem(at: srcURL))
        var done: Int64 = 0

        let context = CopyContext { [self] state, what, stage, csrc, cdst in
            var current: off_t = 0
            copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &current)

            let tmpDone = done + Int64(current)
            let progress = total > 0 ? Float(Double(tmpDone) / Double(total)) : 0

            switch stage {
            case COPYFILE_PROGRESS:
                if let progressHandler {
                    return progressHandler(progress) ? COPYFILE_CONTINUE : COPYFILE_QUIT
                }

            case COPYFILE_FINISH:
                done += Int64(current)
                if what == COPYFILE_RECURSE_DIR_CLEANUP || what == COPYFILE_RECURSE_FILE,
                   let itemDoneHandler, let csrc, let cdst {
                    let isDirectory = what != COPYFILE_RECURSE_FILE
                    let srcItemURL = URL(fileURLWithFileSystemRepresentation: csrc, isDirectory: isDirectory, relativeTo: nil)
                    let dstItemURL = URL(fileURLWithFileSystemRepresentation: cdst, isDirectory: isDirectory, relativeTo: nil)
                    return itemDoneHandler(srcItemURL, dstItemURL, nil) ? COPYFILE_CONTINUE : COPYFILE_QUIT
                }

            case COPYFILE_ERR:
                if let errorHandler, let csrc, let cdst {
                    let isDirectory = stage != COPYFILE_RECURSE_FILE
                    let srcItemURL = URL(fileURLWithFileSystemRepresentation: csrc, isDirectory: isDirectory, relativeTo: nil)
                    let dstItemURL = URL(fileURLWithFileSystemRepresentation: cdst, isDirectory: isDirectory, relativeTo: nil)
                    let error = NSError(domain: "OEFileManagerDomain", code: Int(errno), userInfo: nil)
                    return errorHandler(srcItemURL, dstItemURL, error) ? COPYFILE_CONTINUE : COPYFILE_QUIT
                }
                return COPYFILE_QUIT

            default:
                break
            }
            return COPYFILE_CONTINUE
        }

        let state = copyfile_state_alloc()
        defer { copyfile_state_free(state) }

        let statusCallback: copyfile_callback_t = { what, stage, state, src, dst, ctx in
            guard let ctx else { return COPYFILE_CONTINUE }
            let context = Unmanaged<CopyContext>.fromOpaque(ctx).takeUnretainedValue()
            return context.callback(state, what, stage, src, dst)
        }

        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(statusCallback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(context).toOpaque())

        let res = withExtendedLifetime(context) {
            copyfile(src, dst, state, copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_EXCL))
        }

        if res != 0 {
            throw NSError(domain: "OEFileManagerDomain", code: Int(errno), userInfo: nil)
        }
    }
}
