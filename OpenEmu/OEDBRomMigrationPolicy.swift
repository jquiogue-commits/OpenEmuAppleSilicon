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
import CoreData
import XADMaster.XADArchive

// Referenced by class name from the .xcmappingmodel files — keep the ObjC name stable.
@objc(OEDBRomMigrationPolicy)
final class OEDBRomMigrationPolicy: NSEntityMigrationPolicy {

    override func createDestinationInstances(forSource oldObject: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        assert(manager.sourceModel.versionIdentifiers.count == 1, "Found a source model with various versionIdentifiers!")

        let version = manager.sourceModel.versionIdentifiers.first as? String

        if version == "1.0 Beta" {
            var stale = false
            if let bookmarkData = oldObject.value(forKey: "bookmarkData") as? Data,
               let url = try? URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                let location = url.absoluteString
                let propertyMapping = mapping.attributeMappings?.first { $0.name == "location" }
                propertyMapping?.valueExpression = NSExpression(forConstantValue: location)
            }
        } else if version == "1.0 Beta 4" {
            // Migrate from single rom archives to multi rom archives
            let coord = oldObject.managedObjectContext?.persistentStoreCoordinator
            let romsFolder = romsFolderURL(withPersistentStoreCoordinator: coord)

            let relativePath = oldObject.value(forKey: "location") as? String ?? ""
            let romURL = URL(string: relativePath, relativeTo: romsFolder)
            // OE_archiveForFileAtPath catches the ObjC exceptions XADArchive can throw.
            let archive = romURL.flatMap { XADArchive.oe_archiveForFile(atPath: $0.path) }

            let propertyMapping = mapping.attributeMappings?.first { $0.name == "archiveFileIndex" }
            if let archive, archive.numberOfEntries() == 1 {
                propertyMapping?.valueExpression = NSExpression(forConstantValue: 0)
            } else {
                propertyMapping?.valueExpression = NSExpression(forConstantValue: nil)
            }
        } else if version == "1.2" {
            let coord = oldObject.managedObjectContext?.persistentStoreCoordinator
            let romsFolderURL = romsFolderURL(withPersistentStoreCoordinator: coord)
            let urlString = oldObject.value(forKey: "location") as? String ?? ""
            let url: URL?
            if !urlString.contains("file://") {
                url = URL(string: urlString, relativeTo: romsFolderURL)
            } else {
                url = URL(string: urlString)
            }

            let relativeURL = romsFolderURL.flatMap { url?.url(relativeTo: $0) }
            if let location = relativeURL?.relativeString {
                let propertyMapping = mapping.attributeMappings?.first { $0.name == "location" }
                propertyMapping?.valueExpression = NSExpression(forConstantValue: location)
            }
        }

        try super.createDestinationInstances(forSource: oldObject, in: mapping, manager: manager)
    }

    private func romsFolderURL(withPersistentStoreCoordinator coord: NSPersistentStoreCoordinator?) -> URL? {
        guard let persistentStore = coord?.persistentStores.last,
              let metadata = coord?.metadata(for: persistentStore)
        else { return nil }

        let databaseFolderURL = persistentStore.url?.deletingLastPathComponent()
        let result: URL?
        if let urlString = metadata[OELibraryDatabase.libraryRomsFolderURLKey] as? String {
            if !urlString.contains("file://") {
                result = URL(string: urlString, relativeTo: databaseFolderURL)
            } else {
                result = URL(string: urlString)
            }
        } else {
            result = databaseFolderURL?.appendingPathComponent("roms", isDirectory: true)
        }

        return result?.standardized
    }
}
