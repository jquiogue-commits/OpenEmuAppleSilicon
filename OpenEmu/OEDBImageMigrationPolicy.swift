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

// Referenced by class name from the .xcmappingmodel files — keep the ObjC name stable.
@objc(OEDBImageMigrationPolicy)
final class OEDBImageMigrationPolicy: NSEntityMigrationPolicy {

    static let migrateImageFormatKey = "OEDBImageMigrateImageFormat"

    override func createDestinationInstances(forSource oldObject: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        assert(manager.sourceModel.versionIdentifiers.count == 1, "Found a source model with various versionIdentifiers!")

        let sourceVersion = manager.sourceModel.versionIdentifiers.first as? String
        let entities = manager.sourceModel.entitiesByName

        // Version 1.1 and 1.0 both share version identifier 1.0 :/
        if sourceVersion == "1.0", entities["ImageThumbnail"] != nil {
            UserDefaults.standard.set(true, forKey: Self.migrateImageFormatKey)

            let versions = oldObject.value(forKey: "versions") as? Set<NSManagedObject> ?? []
            var size: Float = 0
            var originalVersion: NSManagedObject?
            for aVersion in versions {
                let currentSize = (aVersion.value(forKey: "width") as? NSNumber)?.floatValue ?? 0
                if currentSize > size {
                    originalVersion = aVersion
                    size = currentSize
                }
            }

            if let originalVersion {
                let coverFolderURL = coverFolderURL

                let width = originalVersion.value(forKey: "width")
                let height = originalVersion.value(forKey: "height")
                let path = originalVersion.value(forKey: "relativePath") as? String
                let source = oldObject.value(forKey: "sourceURL")
                let format = -1
                for obj in versions {
                    let aPath = obj.value(forKey: "relativePath") as? String
                    if aPath != path, let aPath,
                       let imageURL = URL(string: aPath, relativeTo: coverFolderURL) {
                        try? FileManager.default.removeItem(at: imageURL)
                    }
                }

                let newObject = NSEntityDescription.insertNewObject(forEntityName: "Image", into: manager.destinationContext)

                newObject.setValue(width, forKey: "width")
                newObject.setValue(height, forKey: "height")
                newObject.setValue(path, forKey: "relativePath")
                newObject.setValue(source, forKey: "source")
                newObject.setValue(format, forKey: "format")

                manager.associate(sourceInstance: oldObject, withDestinationInstance: newObject, for: mapping)

                return
            }
        }

        throw NSError(domain: "OEDBImageMigrationPolicy", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Failed to migrate Image entity instance",
        ])
    }

    private var coverFolderURL: URL {
        let libraryFolderPath = (UserDefaults.standard.string(forKey: OELibraryDatabase.databasePathKey)! as NSString).expandingTildeInPath
        let coverFolderPath = (libraryFolderPath as NSString).appendingPathComponent("Artwork/")

        return URL(fileURLWithPath: coverFolderPath, isDirectory: true)
    }
}
