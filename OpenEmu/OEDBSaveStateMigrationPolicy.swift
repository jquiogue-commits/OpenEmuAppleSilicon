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
@objc(OEDBSaveStateMigrationPolicy)
final class OEDBSaveStateMigrationPolicy: NSEntityMigrationPolicy {

    override func createDestinationInstances(forSource oldObject: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        assert(manager.sourceModel.versionIdentifiers.count == 1, "Found a source model with various versionIdentifiers!")

        let version = manager.sourceModel.versionIdentifiers.first as? String

        if version == "1.0 Beta" {
            if let path = oldObject.value(forKey: "path") as? String,
               let url = URL(string: path) {
                let location = url.absoluteString
                let propertyMapping = mapping.attributeMappings?.first { $0.name == "location" }
                propertyMapping?.valueExpression = NSExpression(forConstantValue: location)
            }
        } else if version == "1.2" {
            let romsFolderURL = stateFolderURL
            let urlString = oldObject.value(forKey: "location") as? String ?? ""
            let url: URL?
            if !urlString.contains("file://") {
                url = URL(string: urlString, relativeTo: romsFolderURL)
            } else {
                url = URL(string: urlString)
            }

            let relativeURL = url?.url(relativeTo: romsFolderURL)
            if var location = relativeURL?.relativeString {
                // make sure we don't save trailing '/' for save state bundles
                if location.hasSuffix("/") {
                    location = String(location.dropLast())
                }

                let propertyMapping = mapping.attributeMappings?.first { $0.name == "location" }
                propertyMapping?.valueExpression = NSExpression(forConstantValue: location)
            }
        }

        try super.createDestinationInstances(forSource: oldObject, in: mapping, manager: manager)
    }

    private var stateFolderURL: URL {
        if UserDefaults.standard.object(forKey: OELibraryDatabase.saveStateFolderURLKey) != nil,
           let url = UserDefaults.standard.url(forKey: OELibraryDatabase.saveStateFolderURLKey) {
            return url
        }

        let saveStateFolderName = "Save States"
        var result = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        result.appendPathComponent("OpenEmu", isDirectory: true)
        result.appendPathComponent(saveStateFolderName, isDirectory: true)

        return result.standardized
    }
}
