// Copyright (c) 2021, OpenEmu Team
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

extension Notification.Name {
    static let GameInfoHelperWillUpdate = NSNotification.Name("OEGameInfoHelperWillUpdateNotificationName")
    static let GameInfoHelperDidChangeUpdateProgress = NSNotification.Name("OEGameInfoHelperDidChangeUpdateProgressNotificationName")
    static let GameInfoHelperDidUpdate = NSNotification.Name("OEGameInfoHelperDidUpdateNotificationName")
}

final class OpenVGDB: NSObject {
    
    static let versionKey = "OpenVGDBVersion"
    static let updateCheckKey = "OpenVGDBUpdatesChecked"
    static let updateIntervalKey = "OpenVGDBUpdateInterval"
    
    private static let fileName = "openvgdb"
    private static let downloadURL = URL(string: "https://github.com/OpenVGDB/OpenVGDB/releases/download/")!
    private static let updateURL = URL(string: "https://api.github.com/repos/OpenVGDB/OpenVGDB/releases?page=1&per_page=1")!
    
    private static let initializeDefaults: Void = {
        let onceADayInterval = 60 * 60 * 24 * 1
        UserDefaults.standard.register(defaults: [
            OpenVGDB.versionKey : "",
            OpenVGDB.updateCheckKey : Date(timeIntervalSince1970: 0),
            OpenVGDB.updateIntervalKey : onceADayInterval,
        ])
    }()
    
    private(set) var downloadProgress: Double = 0
    private(set) var downloadVersion: String?
    private(set) var isUpdating = false
    
    private var currentDownload: Download?

    private var database: SQLiteDatabase?
    
    var isAvailable: Bool {
        return database != nil
    }
    
    static let shared: OpenVGDB = {
        
        let sharedHelper = OpenVGDB()
        
        let databaseURL = sharedHelper.databaseFileURL
        
        if (try? databaseURL.checkResourceIsReachable()) != true {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: OpenVGDB.updateCheckKey)
            defaults.removeObject(forKey: OpenVGDB.versionKey)

            Task.detached(priority: .utility) {
                await sharedHelper.checkForUpdatesAndInstall()
            }
        }
        else {
            do {
                sharedHelper.database = try SQLiteDatabase(url: databaseURL)
            } catch {
                NSApp.presentError(error)
            }

            // check for updates
            let defaults = UserDefaults.standard
            let lastUpdateCheck = defaults.object(forKey: OpenVGDB.updateCheckKey) as! Date
            let updateInterval = defaults.double(forKey: OpenVGDB.updateIntervalKey)

            if Date().timeIntervalSince(lastUpdateCheck) > updateInterval {
                NSLog("Check for updates (\(Date().timeIntervalSince(lastUpdateCheck)) > \(updateInterval))")

                Task.detached(priority: .utility) {
                    await sharedHelper.checkForUpdatesAndInstall()
                }
            }
        }

        return sharedHelper
    }()

    /// Checks for a newer OpenVGDB release and installs it if one is available.
    private func checkForUpdatesAndInstall() async {
        let (url, version) = await checkForUpdates()
        if let url = url, let version = version {
            await install(with: url, version: version)
        }
    }
    
    override init() {
        super.init()
        Self.initializeDefaults
    }
    
    var databaseFileURL: URL {
        let url = URL.oeApplicationSupportDirectory
            .appendingPathComponent("openvgdb.sqlite", isDirectory: false)
        return url
    }
    
    /// Checks for updates and returns the URL and version of a newer DB release, if any.
    func checkForUpdates() async -> (url: URL?, version: String?) {

        DLog("")

        var request = URLRequest(url: OpenVGDB.updateURL, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: 30)
        request.setValue("OpenEmu", forHTTPHeaderField: "User-Agent")

        let data: Data
        do {
            data = try await withCheckedThrowingContinuation { continuation in
                let task = URLSession.shared.dataTask(with: request) { data, _, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: data ?? Data())
                    }
                }
                task.resume()
            }
        } catch {
            DLog("OpenVGDB update check failed: \(error)")
            return (nil, nil)
        }

        guard let releases = (try? JSONSerialization.jsonObject(with: data, options: .allowFragments)) as? [AnyHashable] else {
            return (nil, nil)
        }

        let defaults = UserDefaults.standard
        let currentVersion = defaults.string(forKey: OpenVGDB.versionKey)!
        var nextVersion = currentVersion

        defaults.set(Date(), forKey: OpenVGDB.updateCheckKey)

        for release in releases {
            if let release = release as? [AnyHashable : Any],
               let tagName = release["tag_name"] as? String,
               tagName.compare(nextVersion) != .orderedSame {
                nextVersion = tagName
            }
        }

        guard nextVersion != currentVersion else {
            DLog("OpenVGDB not updated.")
            return (nil, nil)
        }

        let url = OpenVGDB.downloadURL.appendingPathComponent("\(nextVersion)/\(OpenVGDB.fileName).zip")
        DLog("Updating OpenVGDB version from \(!currentVersion.isEmpty ? currentVersion : "(none)") to \(nextVersion).")
        return (url, nextVersion)
    }

    func cancelUpdate() {
        DLog("Cancelling OpenVGDB download.")

        currentDownload?.cancel()
    }

    @MainActor
    func install(with url: URL, version versionTag: String) async {

        isUpdating = true
        NotificationCenter.default.post(name: .GameInfoHelperWillUpdate, object: self)

        downloadProgress = 0
        downloadVersion = versionTag

        let download = Download(url: url)
        currentDownload = download

        DLog("Starting OpenVGDB download.")

        defer {
            isUpdating = false
            downloadVersion = nil
            currentDownload = nil
            NotificationCenter.default.post(name: .GameInfoHelperDidUpdate, object: self)
        }

        let location: URL
        do {
            location = try await download.download(progressHandler: { [weak self] progress in
                guard let self = self else { return }
                self.downloadProgress = progress
                NotificationCenter.default.post(name: .GameInfoHelperDidChangeUpdateProgress, object: self)
            })
        } catch {
            DLog("OpenVGDB download did complete: \(error.localizedDescription)")
            downloadProgress = 0
            return
        }

        DLog("OpenVGDB download did finish downloading temporary data.")

        let databaseURL = databaseFileURL
        ArchiveHelper.decompressFileInArchive(at: location, toDirectory: databaseURL.deletingLastPathComponent())
        DLog("OpenVGDB extracted to database folder.")

        database = try? SQLiteDatabase(url: databaseURL)
        if database != nil {
            UserDefaults.standard.set(versionTag, forKey: OpenVGDB.versionKey)
        }

        downloadProgress = 1
    }

    func executeQuery(_ sql: String) throws -> [[String : Any]] {
        guard let database = database else { return [] }
        return try database.executeQuery(sql)
    }
}
