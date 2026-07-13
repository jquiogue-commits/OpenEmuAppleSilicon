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

class OESegaCDSystemController: OESystemController {

    override func canHandle(_ file: OEFile) -> OEFileSupport {
        guard file is OECUESheet else { return .no }

        let dataTrackString = file.readASCIIString(in: NSRange(location: 0, length: 16))
        let otherDataTrackString = file.readASCIIString(in: NSRange(location: 0x10, length: 16))

        let dataTrackList = ["SEGADISCSYSTEM  ", "SEGABOOTDISC    ", "SEGADISC        ", "SEGADATADISC    "]
        for d in dataTrackList {
            if dataTrackString == d || otherDataTrackString == d {
                return .yes
            }
        }

        return .no
    }

    override func headerLookup(for file: OEFile) -> String? {
        guard file is OECUESheet else { return nil }

        // Read both offsets because of various dumps.
        let dataTrackString = file.readASCIIString(in: NSRange(location: 0x100, length: 16))
        let otherDataTrackString = file.readASCIIString(in: NSRange(location: 0x110, length: 16))

        var offsetFound = 0
        let dataTrackList = ["SEGA GENESIS    ", "SEGA MEGA DRIVE "]

        // Find which offset contains the 256-byte header.
        for d in dataTrackList {
            if dataTrackString == d {
                offsetFound = 0x0100
                break
            } else if otherDataTrackString == d {
                offsetFound = 0x0110
                break
            }
        }

        let header = file.readData(in: NSRange(location: offsetFound, length: 256))
        return header.hexString
    }
}
