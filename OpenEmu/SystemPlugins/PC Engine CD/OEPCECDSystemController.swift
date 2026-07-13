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

class OEPCECDSystemController: OESystemController {

    override var systemIcon: NSImage? {
        let imageName = OELocalizationHelper.shared.isRegionJPN ? "pcenginecd_library" : "tgcd_library"

        var image = NSImage(named: imageName)
        if image == nil {
            let bundle = Bundle(for: Self.self)
            image = bundle.image(forResource: imageName)
            image?.setName(imageName)
        }
        return image
    }

    override func canHandle(_ file: OEFile) -> OEFileSupport {
        guard file is OECloneCD || file is OECUESheet, let descriptor = file as? OEDiscDescriptor else {
            return .no
        }

        let search = Data("PC Engine CD-ROM SYSTEM".utf8)
        let battleHeat = Data("Battle Heat".utf8)

        for dataTrackURL in descriptor.referencedBinaryFileURLs {
            guard let dataTrackBuffer = try? Data(contentsOf: dataTrackURL, options: [.mappedIfSafe, .uncached]) else { continue }
            // This still slows import down but we need to scan the disc as there's no common offset.
            guard let range = dataTrackBuffer.range(of: search) else { continue }

            // "Battle Heat" for PC-FX is falsely identified as PCE CD. This should be the only game that needs this.
            let subRange = (range.lowerBound + 74)..<(range.lowerBound + 74 + 11)
            if subRange.upperBound <= dataTrackBuffer.endIndex, dataTrackBuffer.subdata(in: subRange) == battleHeat {
                return .no
            }

            return .yes
        }

        return .no
    }
}
