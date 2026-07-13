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

class OEPSPSystemController: OESystemController {

    // Read header to detect PSP ISO & CSO.
    override func canHandle(_ file: OEFile) -> OEFileSupport {
        // Handle cso file and return early.
        if file.fileExtension == "cso" {
            return .yes
        }

        if file.readASCIIString(in: NSRange(location: 0x8008, length: 8)) == "PSP GAME" {
            return .yes
        }

        return .no
    }

    override func serialLookup(for file: OEFile) -> String? {
        // Check if it's a CSO file.
        if file.readASCIIString(in: NSRange(location: 0, length: 4)) == "CISO" {
            return serialLookupForCSOFile(file)
        }

        // ISO 9660 CD001, check for MODE1 or MODE2.
        let mode1DataString = file.readASCIIString(in: NSRange(location: 0x8001, length: 5))
        let mode2DataString = file.readASCIIString(in: NSRange(location: 0x9319, length: 5))

        let discSectorSize: Int
        let discSectorHeader: Int
        if mode1DataString == "CD001" {
            discSectorSize = 2048
            discSectorHeader = 0
        } else if mode2DataString == "CD001" {
            discSectorSize = 2352
            discSectorHeader = 24
        } else {
            // bad dump, not ISO 9660
            return nil
        }
        let discOffset = (discSectorSize * 16) + discSectorHeader

        // Root Directory Record offset
        let rootDirectoryRecordBuffer = file.readData(in: NSRange(location: discOffset + 0x9E, length: 8))
        let rootDirectoryRecordOffset = Self.readUInt32LE(rootDirectoryRecordBuffer) * discSectorSize

        // Find PSP_GAME
        var foundPSPGameDir = false
        var position = 0
        while position < discSectorSize {
            if file.readASCIIString(in: NSRange(location: rootDirectoryRecordOffset + position, length: 8)) == "PSP_GAME" {
                foundPSPGameDir = true
                break
            }
            position += 1
        }
        if !foundPSPGameDir {
            return nil
        }

        // PSP_GAME Extent Location (data location)
        let pspgameDataOffset = (rootDirectoryRecordOffset + position) - 0x1F
        let pspgameExtentLocationDataBuffer = file.readData(in: NSRange(location: pspgameDataOffset, length: 8))
        let pramsfoOffset = Self.readUInt32LE(pspgameExtentLocationDataBuffer) * discSectorSize

        // Find PARAM.SFO
        var foundTitleIDFile = false
        position = 0
        while position < discSectorSize {
            if file.readASCIIString(in: NSRange(location: pramsfoOffset + position, length: 9)) == "PARAM.SFO" {
                foundTitleIDFile = true
                break
            }
            position += 1
        }
        if !foundTitleIDFile {
            return nil
        }

        // PARAM.SFO Extent Location (data location)
        let pramsfoDataOffset = (pramsfoOffset + position) - 0x1F
        let pramsfoExtentLocationDataBuffer = file.readData(in: NSRange(location: pramsfoDataOffset, length: 8))
        let pramsfoExtentOffset = Self.readUInt32LE(pramsfoExtentLocationDataBuffer) * discSectorSize

        // Data length (size)
        let pramsfoDataLengthOffset = (pramsfoOffset + position) - 0x17
        let pramsfoDataLengthDataBuffer = file.readData(in: NSRange(location: pramsfoDataLengthOffset, length: 8))
        let pramsfoDataLength = Self.readUInt32LE(pramsfoDataLengthDataBuffer)

        let unformattedOutput = file.readASCIIString(in: NSRange(location: pramsfoExtentOffset + discSectorHeader, length: pramsfoDataLength))
        // Replace null chars.
        let output = unformattedOutput.replacingOccurrences(of: "\0", with: " ")

        // Scan for UG and end of serial, format string and return.
        let scanner = Scanner(string: output)
        _ = scanner.scanUpToString("UG")
        _ = scanner.scanUpToString("  ")
        guard let serial = scanner.scanUpToString(" ") else {
            // UMD Game ISO is incomplete, no DISC_ID.
            return nil
        }

        var formattedSerial = serial
        formattedSerial.insert("-", at: formattedSerial.index(formattedSerial.startIndex, offsetBy: 4))
        return formattedSerial
    }

    // MARK: - CSO (compressed ISO)

    /// Decompresses the first blocks of a CSO file (just enough to reach the serial) and reads it.
    private func serialLookupForCSOFile(_ file: OEFile) -> String? {
        guard let handle = FileHandle(forReadingAtPath: file.dataTrackFileURL.path) else { return nil }
        defer { try? handle.close() }

        // Read and validate the CISO header (24 bytes).
        guard let headerData = try? handle.read(upToCount: 24), headerData.count == 24 else { return nil }
        let headerBytes = [UInt8](headerData)
        guard headerBytes[0] == UInt8(ascii: "C"), headerBytes[1] == UInt8(ascii: "I"),
              headerBytes[2] == UInt8(ascii: "S"), headerBytes[3] == UInt8(ascii: "O") else { return nil }

        let totalBytes = Self.readUInt64LE(headerData.subdata(in: 0x08..<0x10))
        let blockSize = Self.readUInt32LE(headerData.subdata(in: 0x10..<0x14))
        let align = UInt(headerBytes[0x15])
        guard blockSize != 0, totalBytes != 0 else { return nil }

        let totalBlock = Int(totalBytes / UInt64(blockSize))

        // 16 blocks (and the following index entry) are enough to reach the serial.
        let indexEntryCount = min(totalBlock + 1, 17) + 1
        guard let indexData = try? handle.read(upToCount: indexEntryCount * 4),
              indexData.count == indexEntryCount * 4 else { return nil }
        let indexBytes = [UInt8](indexData)
        func indexEntry(_ i: Int) -> UInt32 {
            let o = i * 4
            return UInt32(indexBytes[o]) | UInt32(indexBytes[o + 1]) << 8 | UInt32(indexBytes[o + 2]) << 16 | UInt32(indexBytes[o + 3]) << 24
        }

        var header = Data()

        for block in 0...16 {
            guard block + 1 < indexEntryCount else { return nil }

            var index = indexEntry(block)
            let plain = (index & 0x80000000) != 0
            index &= 0x7fffffff
            let readPos = UInt64(index) << UInt64(align)

            let readSize: Int
            if plain {
                readSize = Int(blockSize)
            } else {
                let index2 = indexEntry(block + 1) & 0x7fffffff
                readSize = Int(index2 - index) << Int(align)
            }

            // Ensure the read size will not overflow the working buffer (block_size * 2 in the original).
            guard readSize > 0, readSize <= Int(blockSize) * 2 else { return nil }

            guard (try? handle.seek(toOffset: readPos)) != nil,
                  let chunk = try? handle.read(upToCount: readSize), chunk.count == readSize else { return nil }

            if plain {
                header.append(chunk)
            } else {
                guard let inflated = Self.inflateRawDeflate(chunk, expectedSize: Int(blockSize)) else { return nil }
                header.append(inflated)
            }
        }

        // Get the serial (10 ASCII bytes at 0x8373).
        guard header.count >= 0x8373 + 10 else { return nil }
        return String(data: header.subdata(in: 0x8373..<(0x8373 + 10)), encoding: .ascii)
    }

    /// Inflates a single raw-DEFLATE block (windowBits -15) to exactly `expectedSize` bytes using zlib.
    private static func inflateRawDeflate(_ input: Data, expectedSize: Int) -> Data? {
        var stream = z_stream()
        guard inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var output = Data(count: expectedSize)
        var input = input

        let status: Int32 = input.withUnsafeMutableBytes { inPtr in
            output.withUnsafeMutableBytes { outPtr in
                stream.next_in = inPtr.baseAddress?.assumingMemoryBound(to: Bytef.self)
                stream.avail_in = uInt(inPtr.count)
                stream.next_out = outPtr.baseAddress?.assumingMemoryBound(to: Bytef.self)
                stream.avail_out = uInt(outPtr.count)
                return inflate(&stream, Z_FULL_FLUSH)
            }
        }

        guard status == Z_STREAM_END else { return nil }
        // The block must decompress to exactly block_size bytes.
        guard expectedSize - Int(stream.avail_out) == expectedSize else { return nil }
        return output
    }

    // MARK: - Little-endian readers

    private static func readUInt32LE(_ data: Data) -> Int {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return 0 }
        return Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24
    }

    private static func readUInt64LE(_ data: Data) -> UInt64 {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { return 0 }
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(bytes[i]) << (8 * i)
        }
        return value
    }
}
