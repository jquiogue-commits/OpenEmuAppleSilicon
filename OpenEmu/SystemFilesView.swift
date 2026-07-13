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
import UniformTypeIdentifiers

/// The System Files (BIOS) preferences pane, hosted in the AppKit preferences
/// window via `NSHostingView` (see `PrefBiosController`). Lists each core's
/// required BIOS files with an availability indicator; files can be dropped in to
/// import, or deleted from the context menu. Kept to macOS 11.5-safe SwiftUI.
struct SystemFilesView: View {

    @StateObject private var model = SystemFilesModel()
    @State private var isTargeted = false

    private let smallFont = Font.system(size: NSFont.smallSystemFontSize)

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("In order to emulate some systems, BIOS files are needed due to increasing complexity of the hardware and software of modern gaming consoles.")
                        .font(smallFont)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("User guide on BIOS files", destination: .userGuideBIOSFiles)
                        .font(smallFont)
                }
                .padding(.vertical, 4)
            }

            ForEach(model.groups) { group in
                Section(header: Text(group.coreName)) {
                    ForEach(group.files) { file in
                        fileRow(file)
                    }
                }
            }
        }
        .frame(width: 480, height: 480)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .onAppear { model.reload() }
    }

    private func fileRow(_ file: SystemFilesModel.FileItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: file.available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(file.available ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileDescription)
                Text("\(file.name) (\(file.sizeString))")
                    .font(smallFont)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .help("MD5: \(file.md5)")
        .contextMenu {
            Button("Delete") { model.deleteFile(file) }
                .disabled(!file.available)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handledAny = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handledAny = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                if let url = url {
                    DispatchQueue.main.async { model.importFiles([url]) }
                }
            }
        }
        return handledAny
    }
}

/// Backs `SystemFilesView`: builds the per-core list of required BIOS files (with
/// availability), and refreshes when the core list changes or a BIOS file is
/// imported. `NSObject` so it can KVO `OECorePlugin.allPlugins` like the old
/// controller did.
final class SystemFilesModel: NSObject, ObservableObject {

    struct FileItem: Identifiable {
        let id = UUID()
        let fileDescription: String
        let name: String
        let sizeString: String
        let md5: String
        let available: Bool
    }

    struct CoreGroup: Identifiable {
        let id = UUID()
        let coreName: String
        let files: [FileItem]
    }

    @Published private(set) var groups: [CoreGroup] = []

    private var token: NSObjectProtocol?
    private static var coreListContext = 0

    override init() {
        super.init()

        reload()

        token = NotificationCenter.default.addObserver(forName: .didImportBIOSFile, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
        OECorePlugin.addObserver(self, forKeyPath: #keyPath(OECorePlugin.allPlugins), context: &Self.coreListContext)
    }

    deinit {
        if let token = token {
            NotificationCenter.default.removeObserver(token)
        }
        OECorePlugin.removeObserver(self, forKeyPath: #keyPath(OECorePlugin.allPlugins), context: &Self.coreListContext)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if context == &Self.coreListContext {
            DispatchQueue.main.async { [weak self] in self?.reload() }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    func reload() {
        var groups: [CoreGroup] = []

        for core in OECorePlugin.allPlugins {
            guard !core.requiredFiles.isEmpty else { continue }

            let sorted = (core.requiredFiles as NSArray).sortedArray(using: [NSSortDescriptor(key: "Description", ascending: true)])
            guard let dicts = sorted as? [[String: Any]], !dicts.isEmpty else { continue }

            let files = dicts.map { dict -> FileItem in
                let size = (dict["Size"] as? NSNumber)?.int64Value ?? 0
                return FileItem(
                    fileDescription: dict["Description"] as? String ?? "",
                    name: dict["Name"] as? String ?? "",
                    sizeString: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                    md5: dict["MD5"] as? String ?? "",
                    available: BIOSFile.isBIOSFileAvailable(withFileInfo: dict)
                )
            }
            groups.append(CoreGroup(coreName: core.displayName, files: files))
        }

        self.groups = groups
    }

    func deleteFile(_ file: FileItem) {
        if BIOSFile.deleteBIOSFile(withFileName: file.name) {
            reload()
        }
    }

    func importFiles(_ urls: [URL]) {
        var importedSomething = false

        for url in urls {
            if url.isDirectory {
                let fm = FileManager.default
                guard let dirEnum = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let fileURL as URL in dirEnum where !fileURL.isDirectory {
                    importedSomething = BIOSFile.checkIfBIOSFileAndImport(at: fileURL) || importedSomething
                }
            } else {
                importedSomething = BIOSFile.checkIfBIOSFileAndImport(at: url) || importedSomething
            }
        }

        if importedSomething {
            reload()
        }
    }
}
