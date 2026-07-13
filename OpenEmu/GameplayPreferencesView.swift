// Copyright (c) 2026, OpenEmu Team
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

import SwiftUI
import OpenEmuKit

/// The Gameplay preferences pane, hosted in the AppKit preferences window via
/// `NSHostingView` (see `PrefGameplayController`). Kept to macOS 11.5-safe SwiftUI.
struct GameplayPreferencesView: View {

    @StateObject private var model = GameplayPreferencesModel()

    // Window-management toggles bind straight to the same UserDefaults keys the
    // rest of the app reads; registered defaults live in AppDelegate.
    @AppStorage(OEFullScreenGameWindowKey) private var fullScreen = false
    @AppStorage(OEBackgroundPauseKey) private var backgroundPause = true
    @AppStorage(OEBackgroundControllerPlayKey) private var backgroundControllerPlay = true
    @AppStorage(OEForcePopoutGameWindowKey) private var forcePopout = true
    @AppStorage(OEPopoutGameWindowAlwaysOnTopKey) private var alwaysOnTop = false
    @AppStorage(OEPopoutGameWindowIntegerScalingOnlyKey) private var integerScalingOnly = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Shader:")
                Picker("", selection: shaderSelection) {
                    ForEach(model.systemShaders, id: \.self) { name in
                        Text(name).tag(name)
                    }
                    if !model.customShaders.isEmpty {
                        Divider()
                        ForEach(model.customShaders, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: 260)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Window Management:")
                    .font(.system(size: 13, weight: .bold))
                Toggle("Always launch games fullscreen", isOn: $fullScreen)
                Toggle("Always pause gameplay when in background", isOn: $backgroundPause)
                Toggle("Allow playing with controllers when in background", isOn: $backgroundControllerPlay)
                Toggle("Always use popout gameplay window", isOn: $forcePopout)
                Toggle("Always float popout gameplay window on top", isOn: $alwaysOnTop)
                Toggle("Always snap popout gameplay window to integer scale", isOn: $integerScalingOnly)
            }
        }
        .padding(20)
        .frame(width: 460, alignment: .leading)
    }

    private var shaderSelection: Binding<String> {
        Binding(get: { model.selectedShader },
                set: { model.selectShader($0) })
    }
}

/// Backs the shader picker: mirrors `OEShaderStore`, applies a new global default
/// shader (resetting every system's per-system override, as the old controller did),
/// and reloads when the custom-shader list changes.
final class GameplayPreferencesModel: ObservableObject {

    @Published private(set) var systemShaders: [String] = []
    @Published private(set) var customShaders: [String] = []
    @Published var selectedShader: String = ""

    private var token: NSObjectProtocol?

    init() {
        reload()
        token = NotificationCenter.default.addObserver(forName: .shaderModelCustomShadersDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        if let token = token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func reload() {
        systemShaders = OEShaderStore.shared.sortedSystemShaderNames
        customShaders = OEShaderStore.shared.sortedCustomShaderNames

        let current = OEShaderStore.shared.defaultShaderName
        selectedShader = (systemShaders + customShaders).contains(current) ? current : (systemShaders.first ?? "")
    }

    func selectShader(_ name: String) {
        guard name != OEShaderStore.shared.defaultShaderName,
              let context = OELibraryDatabase.default?.mainThreadContext
        else {
            selectedShader = name
            return
        }

        let allSystemIdentifiers = OEDBSystem.allSystemIdentifiers(in: context)
        allSystemIdentifiers.forEach(OESystemShaderStore.shared.resetShader(forSystem:))
        OEShaderStore.shared.defaultShaderName = name
        selectedShader = name
    }
}
