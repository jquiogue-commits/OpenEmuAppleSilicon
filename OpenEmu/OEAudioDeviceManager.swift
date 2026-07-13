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
import CoreAudio

/// Keeps an up-to-date list of all audio devices connected to the machine.
final class OEAudioDeviceManager: NSObject {

    /// Posted whenever an audio device is connected or disconnected.
    /// Corresponds to Core Audio’s `kAudioHardwarePropertyDevices`.
    static let didChangeDeviceListNotification = Notification.Name("OEAudioDeviceManagerDidChangeDeviceListNotification")
    /// Posted when the user changes the default audio input device.
    static let didChangeDefaultInputDeviceNotification = Notification.Name("OEAudioDeviceManagerDidChangeDefaultInputDeviceNotification")
    /// Posted when the user changes the default audio output device.
    static let didChangeDefaultOutputDeviceNotification = Notification.Name("OEAudioDeviceManagerDidChangeDefaultOutputDeviceNotification")
    /// Posted when the user changes the default system audio output device.
    static let didChangeDefaultSystemOutputDeviceNotification = Notification.Name("OEAudioDeviceManagerDidChangeDefaultSystemOutputDeviceNotification")

    static let shared: OEAudioDeviceManager = {
        let manager = OEAudioDeviceManager()
        manager.registerHardwarePropertyListeners()
        return manager
    }()

    private var devices: [OEAudioDevice] = []
    private let devicesLock = NSLock()

    private override init() {
        super.init()
        updateDeviceList()
    }

    var audioDevices: [OEAudioDevice] {
        devicesLock.lock()
        defer { devicesLock.unlock() }
        return devices
    }

    var defaultInputDevice: OEAudioDevice? {
        audioDevice(withPropertySelector: kAudioHardwarePropertyDefaultInputDevice)
    }

    var defaultOutputDevice: OEAudioDevice? {
        audioDevice(withPropertySelector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    var defaultSystemOutputDevice: OEAudioDevice? {
        audioDevice(withPropertySelector: kAudioHardwarePropertyDefaultSystemOutputDevice)
    }

    private func audioDevice(withPropertySelector propertySelector: AudioObjectPropertySelector) -> OEAudioDevice? {
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propAddr = AudioObjectPropertyAddress(mSelector: propertySelector,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMaster)

        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize, &deviceID)
        guard err == noErr else { return nil }

        return OEAudioDevice(id: deviceID)
    }

    // MARK: - Core Audio

    private func registerHardwarePropertyListeners() {
        let propSelectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice,
        ]

        for selector in propSelectors {
            var propAddr = AudioObjectPropertyAddress(mSelector: selector,
                                                      mScope: kAudioObjectPropertyScopeGlobal,
                                                      mElement: kAudioObjectPropertyElementMaster)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &propAddr, nil) { numberAddresses, addresses in
                Self.shared.handleHardwarePropertyChanges(numberAddresses: numberAddresses, addresses: addresses)
            }
        }
    }

    private func handleHardwarePropertyChanges(numberAddresses: UInt32, addresses: UnsafePointer<AudioObjectPropertyAddress>) {
        var notificationNames: Set<Notification.Name> = []

        for i in 0..<Int(numberAddresses) {
            switch addresses[i].mSelector {
            case kAudioHardwarePropertyDefaultInputDevice:
                notificationNames.insert(Self.didChangeDefaultInputDeviceNotification)

            case kAudioHardwarePropertyDefaultOutputDevice:
                notificationNames.insert(Self.didChangeDefaultOutputDeviceNotification)

            case kAudioHardwarePropertyDefaultSystemOutputDevice:
                notificationNames.insert(Self.didChangeDefaultSystemOutputDeviceNotification)

            case kAudioHardwarePropertyDevices:
                notificationNames.insert(Self.didChangeDeviceListNotification)

            default:
                DLog("OEAudioDeviceManager property listener: unknown message")
            }
        }

        let nc = NotificationCenter.default
        for notificationName in notificationNames {
            if notificationName == Self.didChangeDeviceListNotification {
                updateDeviceList()
            }
            nc.post(name: notificationName, object: self)
        }
    }

    private func updateDeviceList() {
        var propAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMaster)

        var dataSize = UInt32(0)
        var err = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize)
        guard err == noErr else { return }

        let numberOfDevices = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        if numberOfDevices == 0 {
            DLog("No audio devices were found")

            devicesLock.lock()
            let previousNumberOfDevices = devices.count
            devices.removeAll()
            devicesLock.unlock()

            if previousNumberOfDevices > 0 {
                NotificationCenter.default.post(name: Self.didChangeDeviceListNotification, object: self)
            }
            return
        }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: numberOfDevices)
        err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &dataSize, &deviceIDs)
        guard err == noErr else {
            DLog("Error retrieving the list of audio devices")
            return
        }

        var aggDevCompositionPropAddr = AudioObjectPropertyAddress(mSelector: kAudioAggregateDevicePropertyComposition,
                                                                   mScope: kAudioObjectPropertyScopeGlobal,
                                                                   mElement: kAudioObjectPropertyElementMaster)

        var devicesToAdd: [OEAudioDevice] = []

        devicesLock.lock()

        for deviceID in deviceIDs {
            // Skip private aggregate devices (e.g. ones created behind the scenes by other apps).
            var composition: Unmanaged<CFDictionary>?
            var compositionSize = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
            AudioObjectGetPropertyData(deviceID, &aggDevCompositionPropAddr, 0, nil, &compositionSize, &composition)
            if let composition = composition?.takeRetainedValue() as? [String: Any] {
                // kAudioAggregateDeviceIsPrivateKey
                if (composition["private"] as? Bool) == true {
                    continue
                }
            }

            if !devices.contains(where: { $0.deviceID == deviceID }) {
                devicesToAdd.append(OEAudioDevice(id: deviceID))
            }
        }

        devices.removeAll { device in
            !deviceIDs.contains(device.deviceID)
        }
        devices.append(contentsOf: devicesToAdd)

        devicesLock.unlock()

        DLog("OEAudioDeviceManager added audio devices \(devicesToAdd)")
    }
}

// MARK: -

/// Contains information about an audio device.
final class OEAudioDevice: NSObject {

    let deviceID: AudioDeviceID
    private(set) var deviceName: String = ""
    private(set) var numberOfInputChannels: Int = 0
    private(set) var numberOfOutputChannels: Int = 0

    init(id deviceID: AudioDeviceID) {
        self.deviceID = deviceID
        super.init()

        retrieveDeviceName()
        numberOfInputChannels = numberOfChannels(inScope: kAudioObjectPropertyScopeInput)
        numberOfOutputChannels = numberOfChannels(inScope: kAudioObjectPropertyScopeOutput)
    }

    private func retrieveDeviceName() {
        var tempString: Unmanaged<CFString>?
        var ioSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var propAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMaster)

        let err = AudioObjectGetPropertyData(deviceID, &propAddr, 0, nil, &ioSize, &tempString)
        if err == noErr, let name = tempString?.takeRetainedValue() {
            deviceName = name as String
        }
    }

    private func numberOfChannels(inScope propScope: AudioObjectPropertyScope) -> Int {
        var ioSize = UInt32(0)
        var propAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                  mScope: propScope,
                                                  mElement: 0)

        var err = AudioObjectGetPropertyDataSize(deviceID, &propAddr, 0, nil, &ioSize)
        guard err == noErr, ioSize != 0 else { return 0 }

        let bufferListPtr = UnsafeMutableRawPointer.allocate(byteCount: Int(ioSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferListPtr.deallocate() }

        // Get stream configuration
        err = AudioObjectGetPropertyData(deviceID, &propAddr, 0, nil, &ioSize, bufferListPtr)
        guard err == noErr else { return 0 }

        // Count the total number of channels in the stream
        var number = 0
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPtr.assumingMemoryBound(to: AudioBufferList.self))
        for buffer in bufferList {
            number += Int(buffer.mNumberChannels)
        }
        return number
    }

    override func isEqual(_ object: Any?) -> Bool {
        if let other = object as? OEAudioDevice {
            return other === self || other.deviceID == deviceID
        }
        return false
    }

    override var hash: Int {
        Int(deviceID)
    }

    override var description: String {
        "Audio device \(deviceID), name \(deviceName), \(numberOfInputChannels) input channels, \(numberOfOutputChannels) output channels"
    }
}
