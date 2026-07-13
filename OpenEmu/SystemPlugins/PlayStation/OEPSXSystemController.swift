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

import Cocoa
import OpenEmuSystem

class OEPSXSystemController: OESystemController {

    override func canHandle(_ file: OEFile) -> OEFileSupport {
        guard file is OEDiscDescriptor else { return .no }

        // TODO: Add frontend method to receive NSError from canHandle(_:) in system plugins; this doesn't belong here.
        // Check for ECM magic header. Fix for https://github.com/OpenEmu/OpenEmu/issues/2588
        let ecmMagic = Data([0x45, 0x43, 0x4D, 0x00])
        let isBinaryECM = file.readData(in: NSRange(location: 0, length: 4)) == ecmMagic

        if isBinaryECM {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("ECM compressed binary detected.", comment: "")
                alert.informativeText = NSLocalizedString("ECM compressed binaries cannot be imported. Please read the disc importing guide.", comment: "")
                alert.alertStyle = .critical
                alert.addButton(withTitle: NSLocalizedString("View Guide in Browser", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("Dismiss", comment: ""))

                if alert.runModal() == .alertFirstButtonReturn,
                   let url = URL(string: "https://github.com/OpenEmu/OpenEmu/wiki/User-guide:-CD-based-games") {
                    NSWorkspace.shared.open(url)
                }
            }
            return .no
        }

        let dataTrackString: String? = file.readASCIIString(in: NSRange(location: 0x24E0, length: 16))
        return dataTrackString == "  Licensed  by  " ? .yes : .no
    }

    override func serialLookup(for file: OEFile) -> String? {
        guard file is OEDiscDescriptor else { return nil }

        let mode1DataString: String? = file.readASCIIString(in: NSRange(location: 0x8001, length: 5))
        let mode2DataString: String? = file.readASCIIString(in: NSRange(location: 0x9319, length: 5))

        // Find which offset contains CD001
        let discSectorSize: Int
        let discSectorHeader: Int
        if mode1DataString == "CD001" {
            // ISO9660/MODE1/2048
            discSectorSize = 2048
            discSectorHeader = 0
        } else if mode2DataString == "CD001" {
            // ISO9660/MODE2/FORM1/2352
            discSectorSize = 2352
            discSectorHeader = 24
        } else {
            // bad dump, not ISO 9660
            return nil
        }
        let discOffset = (discSectorSize * 16) + discSectorHeader

        // Root Directory Record offset
        let rootDirectoryRecordLocationOffset = 0x9E
        let rootDirectoryRecordBuffer = file.readData(in: NSRange(location: discOffset + rootDirectoryRecordLocationOffset, length: 8))
        let rootDirectoryRecordSector = Self.readUInt32LE(rootDirectoryRecordBuffer)
        let rootDirectoryRecordOffset = rootDirectoryRecordSector * discSectorSize

        // Find SYSTEM.CNF
        var foundTitleIDFile = false
        var position = 0
        while position < discSectorSize {
            if file.readASCIIString(in: NSRange(location: rootDirectoryRecordOffset + position, length: 10)) == "SYSTEM.CNF" {
                foundTitleIDFile = true
                break
            }
            position += 1
        }
        if !foundTitleIDFile {
            // bad dump, couldn't find SYSTEM.CNF entry on the specified sector
            return nil
        }

        // SYSTEM.CNF Extent Location (Data location)
        let systemcnfDataOffset = (rootDirectoryRecordOffset + position) - 0x1F
        let systemcnfExtentLocationDataBuffer = file.readData(in: NSRange(location: systemcnfDataOffset, length: 8))
        let sizeExtentOffset = Self.readUInt32LE(systemcnfExtentLocationDataBuffer)
        let systemcnfExtentOffset = sizeExtentOffset * discSectorSize

        // Data length (size)
        let systemcnfDataLengthOffset = (rootDirectoryRecordOffset + position) - 0x17
        let systemcnfDataLengthDataBuffer = file.readData(in: NSRange(location: systemcnfDataLengthOffset, length: 8))
        let systemcnfDataLength = Self.readUInt32LE(systemcnfDataLengthDataBuffer)

        let output = file.readASCIIString(in: NSRange(location: systemcnfExtentOffset + discSectorHeader, length: systemcnfDataLength))

        // RegEx pattern match the disc serial (handles whitespace, hyphen/underscore, extra path, etc.)
        let pattern = "BOOT\\s*=\\s*?cdrom:\\\\?(.+\\\\)?(.+?(?=;|\\s))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: output, options: [], range: NSRange(location: 0, length: (output as NSString).length)) else {
            return "NO MATCH"
        }

        var serial = (output as NSString).substring(with: match.range(at: 2))
        // Keep only alphanumerics
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
