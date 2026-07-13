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
import CoreData
import Sparkle

final class OEVersionMigrationController: NSObject {

    static let errorDomain = "OEVersionMigrationErrorDomain"
    static let failureErrorsKey = "OEVersionMigrationFailureErrorsKey"

    /// Wraps a target/selector pair whose method has the shape
    /// `- (BOOL)doSomething:(NSError **)err` (i.e. a throwing @objc Swift method).
    private final class Migrator {
        weak var target: AnyObject?
        let action: Selector
        var hasRun = false

        init(target: AnyObject, action: Selector) {
            self.target = target
            self.action = action
        }

        func run() throws {
            if hasRun { return }
            hasRun = true

            guard let target = target as? NSObject else { return }

            typealias MigratorFunction = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>) -> ObjCBool
            let imp = target.method(for: action)
            let function = unsafeBitCast(imp, to: MigratorFunction.self)

            var error: NSError?
            let success = withUnsafeMutablePointer(to: &error) { function(target, action, $0) }
            if !success.boolValue {
                throw error ?? NSError(domain: OEVersionMigrationController.errorDomain, code: 1, userInfo: nil)
            }
        }
    }

    static let `default` = OEVersionMigrationController()

    var versionComparator: any SUVersionComparison = SUStandardVersionComparator.default

    private var lastVersion: String?
    private var migrators: [String: [Migrator]] = [:]
    private var isFirstRun = false
    private var isRunning = false

    private override init() {
        super.init()

        // We'll cheat here and rely on Sparkle's key
        isFirstRun = !UserDefaults.standard.bool(forKey: "SUHasLaunchedBefore")
        lastVersion = UserDefaults.standard.string(forKey: "OEMigrationLastVersion")
    }

    func runMigrationIfNeeded() {
        let currentVersion = Bundle.main.infoDictionary?[kCFBundleVersionKey as String] as? String ?? ""
        let mostRecentVersion = lastVersion
        let userDefaults = UserDefaults.standard

        // Start thread to convert old images to new format
        if userDefaults.bool(forKey: OEDBImageMigrationPolicy.migrateImageFormatKey) {
            runImageMigration()
        }

        if userDefaults.bool(forKey: OEDBScreenshot.importRequiredKey) {
            importScreenshots()
        }

        // We have to work around the fact that older versions of OpenEmu didn't stick a version key in the plist.
        // If the Sparkle key for an existing launch doesn't exist, then this is a new installation, not an upgrade.
        // Thus, we log our current version and prevent the migration. Subsequent migrations will then have the new version.
        if isFirstRun, mostRecentVersion == nil {
            userDefaults.set(currentVersion, forKey: "OEMigrationLastVersion")
            return
        }

        // if it's not the first run, and there's no most recent version, then it's a pre-1.0.0b5 upgrade
        // if the current version has a higher version than the most recent version, then it's an upgrade
        if mostRecentVersion == nil || versionComparator.compareVersion(mostRecentVersion!, toVersion: currentVersion) == .orderedAscending {
            migrate(from: mostRecentVersion, to: currentVersion)
        }
    }

    private func runImageMigration() {
        DispatchQueue.global(qos: .background).async {
            let userDefaults = UserDefaults.standard
            let format = OEDBImage.gameArtworkFormat
            let attributes = OEDBImage.gameArtworkProperties

            guard let database = OELibraryDatabase.default else { return }
            let request = NSFetchRequest<OEDBImage>(entityName: OEDBImage.entityName)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "format = -1")

            let context = database.mainThreadContext
            let images = try? context.fetch(request)
            if let images, images.isEmpty {
                let coverFolderURL = database.coverFolderURL

                let boxSizes = ["original", "75", "150", "300", "450"]
                for boxSize in boxSizes {
                    let url = coverFolderURL.appendingPathComponent(boxSize, isDirectory: true)

                    let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [], options: .skipsHiddenFiles)
                    if contents?.isEmpty ?? true {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
                userDefaults.removeObject(forKey: "BoxSizes")
                userDefaults.removeObject(forKey: OEDBImageMigrationPolicy.migrateImageFormatKey)
            } else {
                request.fetchLimit = 10
                var count = 0
                context.performAndWait {
                    count = (try? context.count(for: request)) ?? 0
                }
                while count != 0 {
                    context.performAndWait {
                        let images = (try? context.fetch(request)) ?? []
                        for image in images {
                            if !image.convert(to: format, withProperties: attributes) {
                                DLog("Failed to migrate image! Delete...")
                                image.managedObjectContext?.delete(image)
                            }
                        }
                        try? context.save()
                    }

                    Thread.sleep(forTimeInterval: 1)

                    context.performAndWait {
                        count = (try? context.count(for: request)) ?? 0
                    }
                }
            }
        }
    }

    private func importScreenshots() {
        guard let database = OELibraryDatabase.default else { return }

        let screenshotFolderURL = database.screenshotFolderURL
        importScreenshots(from: screenshotFolderURL)

        try? database.mainThreadContext.save()

        UserDefaults.standard.removeObject(forKey: OEDBScreenshot.importRequiredKey)
    }

    private func importScreenshots(from directory: URL) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"

        for url in files {
            if url.isDirectory {
                importScreenshots(from: url)
            } else {
                guard let context = OELibraryDatabase.default?.mainThreadContext else { continue }

                let file = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension

                let dateLength = 19
                if file.count <= dateLength + 1 || ext.lowercased() != "png" {
                    continue
                }

                let dateString = String(file.suffix(dateLength))
                let timestamp = formatter.date(from: dateString)
                let gameName = String(file.prefix(file.count - dateLength - 1))

                let request = NSFetchRequest<OEDBRom>(entityName: OEDBRom.entityName)

                let predicates = [NSPredicate(format: "game.name contains[cd] %@", gameName),
                                  NSPredicate(format: "game.gameTitle contains[cd] %@", gameName)]
                request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)

                guard let fetchResult = try? context.fetch(request), let rom = fetchResult.last else { continue }

                let screenshot = OEDBScreenshot.createObject(in: context)
                screenshot.name = "Screenshot"
                screenshot.timestamp = timestamp
                screenshot.location = url.absoluteString
                screenshot.rom = rom
            }
        }
    }

    // MARK: -

    @discardableResult
    private func migrate(from mostRecentVersion: String?, to currentVersion: String) -> [Error] {
        let mostRecentVersion = mostRecentVersion ?? "0.0.1"

        var errors: [Error] = []

        for migratorVersion in allMigrationVersions() {
            // @"1.0.0b4", @"1.0.0b5", @"1.0.0"
            // Don't need to migrate, migrator is too young and has already run
            if versionComparator.compareVersion(mostRecentVersion, toVersion: migratorVersion) != .orderedDescending ||
                versionComparator.compareVersion(currentVersion, toVersion: migratorVersion) != .orderedAscending {
                let allMigrators = migrators[migratorVersion] ?? []
                NSLog("Running migrators from \(mostRecentVersion) to \(migratorVersion)")
                for migrator in allMigrators {
                    do {
                        try migrator.run()
                    } catch {
                        errors.append(error)
                    }
                }
            }
        }

        UserDefaults.standard.set(currentVersion, forKey: "OEMigrationLastVersion")

        isRunning = true

        if !errors.isEmpty {
            NSLog("Error migrating! \(errors)")
        }

        return errors
    }

    func allMigrationVersions() -> [String] {
        migrators.keys.sorted { versionComparator.compareVersion($0, toVersion: $1) == .orderedAscending }
    }

    /// The selector must have the shape of a throwing @objc method taking no arguments:
    /// `- (BOOL)doSomething:(NSError **)err`
    func addMigratorTarget(_ target: AnyObject, selector: Selector, forVersion version: String) {
        migrators[version, default: []].append(Migrator(target: target, action: selector))

        if isRunning {
            runMigrationIfNeeded()
        }
    }
}
