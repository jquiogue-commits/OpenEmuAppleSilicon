// Copyright (c) 2022, OpenEmu Team
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

extension OELibraryDatabase {

    func moveGameLibraryToDefaultLocation() {
        let defaultDatabasePath = (UserDefaults.standard.string(forKey: OELibraryDatabase.defaultDatabasePathKey)! as NSString).expandingTildeInPath
        let location = URL(fileURLWithPath: defaultDatabasePath, isDirectory: true).deletingLastPathComponent()

        moveGameLibrary(to: location)
    }

    func moveGameLibrary(to newParentLocation: URL) {
        // Save library just to make sure the changes are on disk
        mainThreadContext.performAndWait {
            try? mainThreadContext.save()
            writerContext.performAndWait {
                try? writerContext.save()
            }
        }

        if !NSDocumentController.shared.documents.isEmpty || importer.status == .running {
            let alert = OEAlert()
            alert.messageText = NSLocalizedString("Please close all games and wait for the importer to finish.", comment: "")
            alert.defaultButtonTitle = NSLocalizedString("OK", comment: "")
            alert.runModal()
            return
        }

        // TODO: stop sync thread!
        // TODO: use migratePersistentStore:toURL:options:withType:error so we don't have to restart the app
        let currentLocation = databaseFolderURL
        let newLocation = newParentLocation.appendingPathComponent(currentLocation.lastPathComponent, isDirectory: true)
        if newLocation == currentLocation {
            return
        }
        if newLocation.isSubpath(of: currentLocation) {
            let alert = OEAlert()
            alert.messageText = NSLocalizedString("You can't move your library into one of its subfolders.", comment: "")
            alert.defaultButtonTitle = NSLocalizedString("OK", comment: "")
            alert.runModal()
            return
        }

        var outerError: Error?
        let fm = OEFileManager()
        var success = false

        let currentFSAttributes = try? fm.attributesOfFileSystem(forPath: currentLocation.path)
        let newFSAttributes = try? fm.attributesOfFileSystem(forPath: newParentLocation.path)

        let sameVolume = (currentFSAttributes?[.systemNumber] as? NSNumber) == (newFSAttributes?[.systemNumber] as? NSNumber)

        // prepare URLs for components to move
        let currentRomsURL = romsFolderURL!
        let newRomsURL = newLocation.appendingPathComponent(currentRomsURL.lastPathComponent, isDirectory: true)

        let artworkURL = currentLocation.appendingPathComponent("Artwork", isDirectory: true)
        let newArtworkURL = newLocation.appendingPathComponent("Artwork", isDirectory: true)

        let currentStoreURL = currentLocation.appendingPathComponent(OELibraryDatabase.databaseFileName)
        let newStoreURL = newLocation.appendingPathComponent(OELibraryDatabase.databaseFileName)

        if sameVolume {
            UserDefaults.standard.set(newLocation.path, forKey: OELibraryDatabase.databasePathKey)
            setRomsFolderURL(newRomsURL)
            writerContext.performAndWait {
                try? writerContext.save()
            }

            do {
                try fm.moveItem(at: currentLocation, to: newLocation)
                success = true
            } catch {
                outerError = error
            }
        } else {
            // create game library directory
            do {
                try fm.createDirectory(at: newLocation, withIntermediateDirectories: true)
                success = true
            } catch {
                outerError = error
                success = false
            }

            if success {
                var alertResult: NSApplication.ModalResponse?

                let alert = OEAlert()
                alert.messageText = NSLocalizedString("Copying Artwork Files…", comment: "Alert Headline: Library migration")
                alert.defaultButtonTitle = NSLocalizedString("Cancel", comment: "")
                alert.showsProgressbar = true
                alert.progress = 0

                DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + 1) { [self] in
                    let context = writerContext

                    // set up progress handler
                    fm.progressHandler = { progress in
                        // update progress
                        alert.performBlockInModalSession {
                            alert.progress = Double(progress)
                        }
                        // continue if alert is still open
                        return alertResult == nil
                    }

                    // set up error handler
                    fm.errorHandler = { src, _, _ in
                        // ignore failing metafiles
                        if src.lastPathComponent.hasPrefix("._") {
                            return true
                        }
                        DLog("OEFM Error handler called on \(src)")
                        return false
                    }

                    // Copy artwork directory if it exists
                    if (try? artworkURL.checkResourceIsReachable()) == true {
                        do {
                            try fm.copyItem(at: artworkURL, to: newArtworkURL)
                        } catch {
                            success = false
                            DLog("Failed to copy artwork")

                            // show error
                            alert.performBlockInModalSession {
                                alert.messageText = NSLocalizedString("Copying artwork failed!", comment: "")
                                alert.defaultButtonTitle = NSLocalizedString("OK", comment: "")
                                alert.showsProgressbar = false
                            }

                            // clean up
                            try? fm.removeItem(at: newArtworkURL)

                            return
                        }
                    }

                    // TODO: migrate store now, remove copy step later

                    // Copy roms directory
                    alert.performBlockInModalSession {
                        alert.messageText = NSLocalizedString("Copying ROM Files…", comment: "Alert Headline: Library migration")
                        alert.progress = 0
                    }

                    // copy only if it exists
                    if (try? currentRomsURL.checkResourceIsReachable()) == true {
                        do {
                            try fm.copyItem(at: currentRomsURL, to: newRomsURL)
                        } catch {
                            success = false
                            DLog("Failed to copy roms")

                            // show error
                            alert.performBlockInModalSession {
                                alert.messageText = NSLocalizedString("Copying ROM files failed!", comment: "")
                                alert.defaultButtonTitle = NSLocalizedString("OK", comment: "")
                                alert.showsProgressbar = false
                            }

                            // clean up
                            try? fm.removeItem(at: newRomsURL)

                            return
                        }
                    }

                    alert.performBlockInModalSession {
                        alert.messageText = NSLocalizedString("Moving Library…", comment: "Alert Headline: Library migration")
                        alert.progress = -1
                    }

                    // copy core data store over
                    guard let coord = context.persistentStoreCoordinator,
                          let currentStore = coord.persistentStore(for: currentStoreURL),
                          let store = try? coord.migratePersistentStore(currentStore, to: newStoreURL, options: nil, withType: NSSQLiteStoreType)
                    else {
                        success = false
                        DLog("failed copy store data")

                        // show error
                        alert.performBlockInModalSession {
                            alert.messageText = NSLocalizedString("Could not move library data!", comment: "")
                            alert.defaultButtonTitle = NSLocalizedString("OK", comment: "")
                            alert.showsProgressbar = false
                        }

                        return
                    }
                    let storeType = store.type
                    let storeURL = store.url
                    try? coord.remove(store)
                    if let storeURL {
                        _ = try? coord.addPersistentStore(ofType: storeType, configurationName: nil, at: storeURL, options: nil)
                    }

                    context.performAndWait {
                        // ensure all copied paths are relative
                        let fetchRequest = NSFetchRequest<OEDBRom>(entityName: OEDBRom.entityName)
                        fetchRequest.predicate = NSPredicate(value: true)

                        // Change absolute paths to relative ones
                        guard let fetchResult = try? context.fetch(fetchRequest) else { return }

                        DLog("Processing \(fetchResult.count) roms")
                        for rom in fetchResult {
                            let oldLocation = rom.location
                            rom.location = rom.url?.url(relativeTo: newRomsURL)?.relativeString
                            DLog("relocated \(rom) from \(oldLocation ?? "nil") to \(rom.location ?? "nil")")
                        }

                        // note new rom folder location in library
                        UserDefaults.standard.set(newLocation.path, forKey: OELibraryDatabase.databasePathKey)
                        setRomsFolderURL(newRomsURL)
                        try? context.save()
                    }

                    // remove original
                    try? fm.removeItem(at: currentStoreURL)

                    // remove artwork directory
                    try? fm.removeItem(at: artworkURL)

                    // remove roms directory
                    try? fm.removeItem(at: currentRomsURL)

                    // remove 'other files'
                    try? fm.removeItem(at: currentLocation.appendingPathComponent(OELibraryDatabase.databaseFileName + "-shm"))
                    try? fm.removeItem(at: currentLocation.appendingPathComponent(OELibraryDatabase.databaseFileName + "-wal"))

                    // TODO: clean up old location by removing empty directories

                    try? context.save()
                    // Make sure to post notification on main thread!
                    DispatchQueue.main.async {
                        self.persistentStoreCoordinator = coord
                        NotificationCenter.default.post(name: Notification.Name(OELibraryDatabase.locationDidChangeNotification as String), object: self)
                    }

                    success = success && alertResult == nil

                    alert.performBlockInModalSession {
                        alert.close(withResult: .alertFirstButtonReturn)
                    }
                }
                alertResult = alert.runModal()
            }
        }

        if success {
            // point openemu to new library location
            UserDefaults.standard.set((newLocation.path as NSString).abbreviatingWithTildeInPath, forKey: OELibraryDatabase.databasePathKey)

            let alert = OEAlert()
            alert.messageText = NSLocalizedString("Your library was moved sucessfully.", comment: "")
            alert.defaultButtonTitle = NSLocalizedString("OK", comment: "")
            alert.runModal()
        } else {
            DLog("restore meta data")
            // restore meta data
            UserDefaults.standard.set(currentLocation.path, forKey: OELibraryDatabase.databasePathKey)
            let url = currentLocation.appendingPathComponent(romsFolderURL!.lastPathComponent, isDirectory: true)
            setRomsFolderURL(url)
            writerContext.performAndWait {
                try? writerContext.save()
            }

            if let outerError {
                NSApp.presentError(outerError)
            }
        }
    }
}
