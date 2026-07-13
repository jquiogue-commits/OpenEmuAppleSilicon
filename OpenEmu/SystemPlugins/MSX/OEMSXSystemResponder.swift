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
import IOKit.hid
import OpenEmuSystem

class OEMSXSystemResponder: OESystemResponder {

    private static let virtualPhysicalKeyMap: [UInt: OEMSXKey] = [
        UInt(kHIDUsage_KeyboardF1): OEMSXKeyF1,
        UInt(kHIDUsage_KeyboardF2): OEMSXKeyF2,
        UInt(kHIDUsage_KeyboardF3): OEMSXKeyF3,
        UInt(kHIDUsage_KeyboardF4): OEMSXKeyF4,
        UInt(kHIDUsage_KeyboardF5): OEMSXKeyF5,

        UInt(kHIDUsage_KeyboardF10): OEMSXKeyStop,
        UInt(kHIDUsage_KeyboardF11): OEMSXKeyCls,
        UInt(kHIDUsage_KeyboardF12): OEMSXKeySelect,
        UInt(kHIDUsage_KeyboardInsert): OEMSXKeyInsert,
        UInt(kHIDUsage_KeyboardDeleteForward): OEMSXKeyDelete,

        UInt(kHIDUsage_KeyboardEscape): OEMSXKeyEscape,
        UInt(kHIDUsage_Keyboard1): OEMSXKey1,
        UInt(kHIDUsage_Keyboard2): OEMSXKey2,
        UInt(kHIDUsage_Keyboard3): OEMSXKey3,
        UInt(kHIDUsage_Keyboard4): OEMSXKey4,
        UInt(kHIDUsage_Keyboard5): OEMSXKey5,
        UInt(kHIDUsage_Keyboard6): OEMSXKey6,
        UInt(kHIDUsage_Keyboard7): OEMSXKey7,
        UInt(kHIDUsage_Keyboard8): OEMSXKey8,
        UInt(kHIDUsage_Keyboard9): OEMSXKey9,
        UInt(kHIDUsage_Keyboard0): OEMSXKey0,
        UInt(kHIDUsage_KeyboardHyphen): OEMSXKeyMinus,
        UInt(kHIDUsage_KeyboardEqualSign): OEMSXKeyEquals,
        UInt(kHIDUsage_KeyboardBackslash): OEMSXKeyBackslash,
        UInt(kHIDUsage_KeyboardDeleteOrBackspace): OEMSXKeyBackspace,

        UInt(kHIDUsage_KeyboardTab): OEMSXKeyTab,
        UInt(kHIDUsage_KeyboardQ): OEMSXKeyQ,
        UInt(kHIDUsage_KeyboardW): OEMSXKeyW,
        UInt(kHIDUsage_KeyboardE): OEMSXKeyE,
        UInt(kHIDUsage_KeyboardR): OEMSXKeyR,
        UInt(kHIDUsage_KeyboardT): OEMSXKeyT,
        UInt(kHIDUsage_KeyboardY): OEMSXKeyY,
        UInt(kHIDUsage_KeyboardU): OEMSXKeyU,
        UInt(kHIDUsage_KeyboardI): OEMSXKeyI,
        UInt(kHIDUsage_KeyboardO): OEMSXKeyO,
        UInt(kHIDUsage_KeyboardP): OEMSXKeyP,
        UInt(kHIDUsage_KeyboardOpenBracket): OEMSXKeyLeftBracket,
        UInt(kHIDUsage_KeyboardCloseBracket): OEMSXKeyRightBracket,
        UInt(kHIDUsage_KeyboardReturnOrEnter): OEMSXKeyReturn,

        UInt(kHIDUsage_KeyboardLeftControl): OEMSXKeyCtrl,
        UInt(kHIDUsage_KeyboardA): OEMSXKeyA,
        UInt(kHIDUsage_KeyboardS): OEMSXKeyS,
        UInt(kHIDUsage_KeyboardD): OEMSXKeyD,
        UInt(kHIDUsage_KeyboardF): OEMSXKeyF,
        UInt(kHIDUsage_KeyboardG): OEMSXKeyG,
        UInt(kHIDUsage_KeyboardH): OEMSXKeyH,
        UInt(kHIDUsage_KeyboardJ): OEMSXKeyJ,
        UInt(kHIDUsage_KeyboardK): OEMSXKeyK,
        UInt(kHIDUsage_KeyboardL): OEMSXKeyL,
        UInt(kHIDUsage_KeyboardSemicolon): OEMSXKeySemicolon,
        UInt(kHIDUsage_KeyboardQuote): OEMSXKeyQuote,
        UInt(kHIDUsage_KeyboardGraveAccentAndTilde): OEMSXKeyBacktick,

        UInt(kHIDUsage_KeyboardLeftShift): OEMSXKeyLeftShift,
        UInt(kHIDUsage_KeyboardZ): OEMSXKeyZ,
        UInt(kHIDUsage_KeyboardX): OEMSXKeyX,
        UInt(kHIDUsage_KeyboardC): OEMSXKeyC,
        UInt(kHIDUsage_KeyboardV): OEMSXKeyV,
        UInt(kHIDUsage_KeyboardB): OEMSXKeyB,
        UInt(kHIDUsage_KeyboardN): OEMSXKeyN,
        UInt(kHIDUsage_KeyboardM): OEMSXKeyM,
        UInt(kHIDUsage_KeyboardComma): OEMSXKeyComma,
        UInt(kHIDUsage_KeyboardPeriod): OEMSXKeyPeriod,
        UInt(kHIDUsage_KeyboardSlash): OEMSXKeySlash,
        // No mapping for OEMSXKeyUnderscore
        UInt(kHIDUsage_KeyboardRightShift): OEMSXKeyRightShift,

        UInt(kHIDUsage_KeyboardCapsLock): OEMSXKeyCapsLock,
        UInt(kHIDUsage_KeyboardLeftAlt): OEMSXKeyGraph,
        // No mapping for OEMSXKeyTorikeshi
        UInt(kHIDUsage_KeyboardSpacebar): OEMSXKeySpacebar,
        // No mapping for OEMSXKeyJikkou
        UInt(kHIDUsage_KeyboardRightAlt): OEMSXKeyCode,
        UInt(kHIDUsage_KeyboardPause): OEMSXKeyPause,

        UInt(kHIDUsage_KeyboardLeftArrow): OEMSXKeyLeft,
        UInt(kHIDUsage_KeyboardUpArrow): OEMSXKeyUp,
        UInt(kHIDUsage_KeyboardDownArrow): OEMSXKeyDown,
        UInt(kHIDUsage_KeyboardRightArrow): OEMSXKeyRight,

        UInt(kHIDUsage_Keypad7): OEMSXKeyNumpad7,
        UInt(kHIDUsage_Keypad8): OEMSXKeyNumpad8,
        UInt(kHIDUsage_Keypad9): OEMSXKeyNumpad9,
        UInt(kHIDUsage_KeypadSlash): OEMSXKeyNumpadSlash,
        UInt(kHIDUsage_Keypad4): OEMSXKeyNumpad4,
        UInt(kHIDUsage_Keypad5): OEMSXKeyNumpad5,
        UInt(kHIDUsage_Keypad6): OEMSXKeyNumpad6,
        UInt(kHIDUsage_KeypadAsterisk): OEMSXKeyNumpadStar,
        UInt(kHIDUsage_Keypad1): OEMSXKeyNumpad1,
        UInt(kHIDUsage_Keypad2): OEMSXKeyNumpad2,
        UInt(kHIDUsage_Keypad3): OEMSXKeyNumpad3,
        UInt(kHIDUsage_KeypadHyphen): OEMSXKeyNumpadMinus,
        UInt(kHIDUsage_Keypad0): OEMSXKeyNumpad0,
        UInt(kHIDUsage_KeypadPeriod): OEMSXKeyNumpadPoint,
        UInt(kHIDUsage_KeypadComma): OEMSXKeyNumpadComma,
        UInt(kHIDUsage_KeypadPlus): OEMSXKeyNumpadPlus,
    ]

    override class func gameSystemResponderClientProtocol() -> Protocol {
        return OEMSXSystemResponderClient.self
    }

    private var typedClient: OEMSXSystemResponderClient? {
        client as? OEMSXSystemResponderClient
    }

    override func pressEmulatorKey(_ aKey: OESystemKey) {
        let button = OEMSXJoystickButton(rawValue: OEMSXJoystickButton.RawValue(aKey.key))
        typedClient?.didPush(button, controller: Int(aKey.player))
    }

    override func releaseEmulatorKey(_ aKey: OESystemKey) {
        let button = OEMSXJoystickButton(rawValue: OEMSXJoystickButton.RawValue(aKey.key))
        typedClient?.didRelease(button, controller: Int(aKey.player))
    }

    override func hidKeyDown(_ anEvent: OEHIDEvent) {
        super.hidKeyDown(anEvent)

        if let virtualCode = Self.virtualPhysicalKeyMap[anEvent.keycode] {
            typedClient?.didPress(virtualCode)
        }
    }

    override func hidKeyUp(_ anEvent: OEHIDEvent) {
        super.hidKeyUp(anEvent)

        if let virtualCode = Self.virtualPhysicalKeyMap[anEvent.keycode] {
            typedClient?.didRelease(virtualCode)
        }
    }
}
