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

class OEPS2SystemController: OESystemController {

    private static let serialPattern = "BOOT2\\s*=\\s*?cdrom0:\\\\?(.+\\\\)?(.+?(?=;|\\s))"

    override func canHandle(_ file: OEFile) -> OEFileSupport {
        guard file is OEDiscDescriptor || file.fileExtension.caseInsensitiveCompare("iso") == .orderedSame else {
            return .no
        }

        // ISO 9660 CD001, check for MODE1 or MODE2 by locating "PLAYSTATION".
        let dataTrackString: String? = file.readASCIIString(in: NSRange(location: 0x8008, length: 11))
        let dataTrackString2: String? = file.readASCIIString(in: NSRange(location: 0x9320, length: 11))

        let layout: ISOLayout
        if dataTrackString == "PLAYSTATION" {
            layout = .mode1
        } else if dataTrackString2 == "PLAYSTATION" {
            layout = .mode2
        } else {
            return .no
        }

        let cnf = readSystemCNF(file, layout: layout)
        guard cnf.found else {
            // bad dump, couldn't find SYSTEM.CNF entry on the specified sector
            return .uncertain
        }
        guard let output = cnf.contents, matchesSerial(in: output) else {
            return .no
        }
        return .yes
    }

    override func serialLookup(for file: OEFile) -> String? {
        guard file is OEDiscDescriptor || file.fileExtension.caseInsensitiveCompare("iso") == .orderedSame else {
            return nil
        }

        let mode1DataString: String? = file.readASCIIString(in: NSRange(location: 0x8001, length: 5))
        let mode2DataString: String? = file.readASCIIString(in: NSRange(location: 0x9319, length: 5))

        let layout: ISOLayout
        if mode1DataString == "CD001" {
            layout = .mode1
        } else if mode2DataString == "CD001" {
            layout = .mode2
        } else {
            return nil
        }

        let cnf = readSystemCNF(file, layout: layout)
        guard cnf.found, let output = cnf.contents else {
            return nil
        }
        return formattedSerial(in: output)
    }

    // MARK: - ISO 9660 helpers

    private enum ISOLayout {
        case mode1, mode2

        var sectorSize: Int { self == .mode1 ? 2048 : 2352 }
        var sectorHeader: Int { self == .mode1 ? 0 : 24 }
        var offset: Int { (sectorSize * 16) + sectorHeader }
    }

    /// Walks the ISO 9660 root directory to find SYSTEM.CNF and returns whether it was located
    /// along with its ASCII contents (which may be nil if the contents could not be read).
    private func readSystemCNF(_ file: OEFile, layout: ISOLayout) -> (found: Bool, contents: String?) {
        let discSectorSize = layout.sectorSize

        let rootDirectoryRecordLocationOffset = 0x9E
        let rootDirectoryRecordBuffer = file.readData(in: NSRange(location: layout.offset + rootDirectoryRecordLocationOffset, length: 8))
        let rootDirectoryRecordOffset = Self.readUInt32LE(rootDirectoryRecordBuffer) * discSectorSize

        var position = 0
        var found = false
        while position < discSectorSize {
            if file.readASCIIString(in: NSRange(location: rootDirectoryRecordOffset + position, length: 10)) == "SYSTEM.CNF" {
                found = true
                break
            }
            position += 1
        }
        guard found else { return (false, nil) }

        // SYSTEM.CNF Extent Location (data location)
        let systemcnfDataOffset = (rootDirectoryRecordOffset + position) - 0x1F
        let systemcnfExtentLocationDataBuffer = file.readData(in: NSRange(location: systemcnfDataOffset, length: 8))
        let systemcnfExtentOffset = Self.readUInt32LE(systemcnfExtentLocationDataBuffer) * discSectorSize

        // Data length (size)
        let systemcnfDataLengthOffset = (rootDirectoryRecordOffset + position) - 0x17
        let systemcnfDataLengthDataBuffer = file.readData(in: NSRange(location: systemcnfDataLengthOffset, length: 8))
        let systemcnfDataLength = Self.readUInt32LE(systemcnfDataLengthDataBuffer)

        let contents = file.readASCIIString(in: NSRange(location: systemcnfExtentOffset + layout.sectorHeader, length: systemcnfDataLength))
        return (true, contents)
    }

    private func matchesSerial(in output: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: Self.serialPattern, options: .caseInsensitive) else {
            return false
        }
        return regex.firstMatch(in: output, options: [], range: NSRange(location: 0, length: (output as NSString).length)) != nil
    }

    private func formattedSerial(in output: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: Self.serialPattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: output, options: [], range: NSRange(location: 0, length: (output as NSString).length)) else {
            return "NO MATCH"
        }

        var serial = (output as NSString).substring(with: match.range(at: 2))
        serial = serial.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()

        var formattedSerial = serial.uppercased()
        formattedSerial.insert("-", at: formattedSerial.index(formattedSerial.startIndex, offsetBy: 4))
        return formattedSerial
    }

    /// Reads a little-endian unsigned 32-bit value from the first four bytes of `data`.
    private static func readUInt32LE(_ data: Data) -> Int {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return 0 }
        return Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24
    }
}
