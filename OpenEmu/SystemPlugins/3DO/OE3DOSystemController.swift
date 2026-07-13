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
import OpenEmuSystem

class OE3DOSystemController: OESystemController {

    // Bytes found at offset 0x0 in some dumps.
    private static let leadInBytes = Data([0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                                           0xff, 0xff, 0xff, 0x00, 0x00, 0x02, 0x00, 0x01])

    override func canHandle(_ file: OEFile) -> OEFileSupport {
        guard file is OECUESheet else { return .no }

        let leadIn = file.readData(in: NSRange(location: 0, length: 16))
        let bytesFound = leadIn == Self.leadInBytes

        let trackBuffer = file.readData(in: NSRange(location: bytesFound ? 0x10 : 0x0, length: 8))
        let comparison = Data([0x01, 0x5a, 0x5a, 0x5a, 0x5a, 0x5a, 0x01, 0x00])

        if trackBuffer != comparison {
            return .no
        }

        let dataTrack = file.readASCIIString(in: NSRange(location: bytesFound ? 0x38 : 0x28, length: 6))
        if dataTrack.caseInsensitiveCompare("CD-ROM") == .orderedSame {
            return .yes
        }
        if dataTrack.contains("TECD") {
            return .yes
        }

        return .no
    }

    override func headerLookup(for file: OEFile) -> String? {
        guard file is OECUESheet else { return nil }

        let leadIn = file.readData(in: NSRange(location: 0, length: 16))
        let bytesFound = leadIn == Self.leadInBytes

        // Read disc header; these 16 bytes seem to be unique for each game.
        let header = file.readData(in: NSRange(location: bytesFound ? 0x60 : 0x50, length: 16))
        return header.hexString
    }
}
