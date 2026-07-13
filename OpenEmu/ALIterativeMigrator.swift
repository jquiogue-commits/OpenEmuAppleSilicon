/*
 Copyright (c) 2013, Art & Logic, Inc.
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.

 The views and conclusions contained in the software and documentation are those
 of the authors and should not be interpreted as representing official policies,
 either expressed or implied, of the FreeBSD Project.
*/

import Foundation
import CoreData

/// Iteratively migrates a Core Data persistent store through an ordered list
/// of managed object model versions.
enum ALIterativeMigrator {

    static let errorDomain = "com.artlogic.IterativeMigrator"

    static func iterativeMigrateURL(_ sourceStoreURL: URL, ofType sourceStoreType: String, to finalModel: NSManagedObjectModel, orderedModelNames modelNames: [String]) throws {
        // If the persistent store does not exist at the given URL,
        // assume that it hasn't yet been created and return success immediately.
        guard FileManager.default.fileExists(atPath: sourceStoreURL.path) else {
            return
        }

        // Get the persistent store's metadata. The metadata is used to
        // get information about the store's managed object model.
        let sourceMetadata = try metadataForPersistentStore(ofType: sourceStoreType, at: sourceStoreURL)

        // Check whether the final model is already compatible with the store.
        // If it is, no migration is necessary.
        if finalModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: sourceMetadata) {
            return
        }

        // Find the current model used by the store.
        let sourceModel = try model(forStoreMetadata: sourceMetadata)

        // Get NSManagedObjectModels for each of the model names given.
        let models = try models(named: modelNames)

        // Build an inclusive list of models between the source and final models.
        var relevantModels: [NSManagedObjectModel] = []
        var firstFound = false
        var lastFound = false
        var reverse = false
        for model in models {
            if model == sourceModel || model == finalModel {
                if firstFound {
                    lastFound = true
                    // In case a reverse migration is being performed (descending through the
                    // ordered array of models), check whether the source model is found
                    // after the final model.
                    reverse = model == sourceModel
                } else {
                    firstFound = true
                }
            }

            if firstFound {
                relevantModels.append(model)
            }

            if lastFound {
                break
            }
        }

        // Ensure that the source model is at the start of the list.
        if reverse {
            relevantModels.reverse()
        }

        // Migrate through the list
        for i in 0..<(relevantModels.count - 1) {
            let modelA = relevantModels[i]
            let modelB = relevantModels[i + 1]

            // Check whether a custom mapping model exists.
            // If there is no custom mapping model, try to infer one.
            let mappingModel: NSMappingModel
            if let customModel = NSMappingModel(from: nil, forSourceModel: modelA, destinationModel: modelB) {
                mappingModel = customModel
            } else {
                mappingModel = try NSMappingModel.inferredMappingModel(forSourceModel: modelA, destinationModel: modelB)
            }

            try migrateURL(sourceStoreURL, ofType: sourceStoreType, fromModel: modelA, toModel: modelB, mappingModel: mappingModel)
        }
    }

    static func migrateURL(_ sourceStoreURL: URL, ofType sourceStoreType: String, fromModel sourceModel: NSManagedObjectModel, toModel targetModel: NSManagedObjectModel, mappingModel: NSMappingModel) throws {
        // Build a temporary path to write the migrated store.
        let tempDestinationStoreURL = URL(fileURLWithPath: (sourceStoreURL.path as NSString).appendingPathExtension("tmp")!)

        // Migrate from the source model to the target model using the mapping,
        // and store the resulting data at the temporary path.
        let migrator = NSMigrationManager(sourceModel: sourceModel, destinationModel: targetModel)

        try migrator.migrateStore(from: sourceStoreURL,
                                  sourceType: sourceStoreType,
                                  options: nil,
                                  with: mappingModel,
                                  toDestinationURL: tempDestinationStoreURL,
                                  destinationType: sourceStoreType,
                                  destinationOptions: nil)

        // Move the original source store to a backup location.
        let backupPath = (sourceStoreURL.path as NSString).appendingPathExtension("bak")!
        let fileManager = FileManager.default
        do {
            try fileManager.moveItem(atPath: sourceStoreURL.path, toPath: backupPath)
        } catch {
            // If the move fails, delete the migrated destination store.
            try? fileManager.moveItem(atPath: tempDestinationStoreURL.path, toPath: sourceStoreURL.path)
            throw error
        }

        // Move the destination store to the original source location.
        do {
            try fileManager.moveItem(atPath: tempDestinationStoreURL.path, toPath: sourceStoreURL.path)
            // If the move succeeds, delete the backup of the original store.
            try? fileManager.removeItem(atPath: backupPath)
        } catch {
            // If the move fails, restore the original store to its original location.
            try? fileManager.moveItem(atPath: backupPath, toPath: sourceStoreURL.path)
            throw error
        }
    }

    // MARK: - Private methods

    // Returns an NSError with the given code and localized description,
    // and this type's error domain.
    private static func error(code: Int, description: String) -> Error {
        NSError(domain: errorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: description])
    }

    // Gets the metadata for the given persistent store.
    private static func metadataForPersistentStore(ofType storeType: String, at url: URL) throws -> [String: Any] {
        do {
            return try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: storeType, at: url, options: nil)
        } catch {
            throw self.error(code: 102, description: "Failed to find source metadata for store: \(url)")
        }
    }

    // Finds the source model for the store described by the given metadata.
    private static func model(forStoreMetadata metadata: [String: Any]) throws -> NSManagedObjectModel {
        guard let sourceModel = NSManagedObjectModel.mergedModel(from: nil, forStoreMetadata: metadata) else {
            throw error(code: 100, description: "Failed to find source model for metadata: \(metadata)")
        }
        return sourceModel
    }

    // Returns an array of NSManagedObjectModels loaded from mom files with the given names.
    // Throws if any model files could not be found.
    private static func models(named modelNames: [String]) throws -> [NSManagedObjectModel] {
        var models: [NSManagedObjectModel] = []
        for modelName in modelNames {
            guard let modelUrl = urlForModel(named: modelName, inDirectory: nil),
                  let model = NSManagedObjectModel(contentsOf: modelUrl)
            else {
                throw error(code: 110, description: "No model found for \(modelName)")
            }
            models.append(model)
        }
        return models
    }

    // Returns the URL for a model file with the given name in the given directory.
    // @param directory The name of the bundle directory to search. If nil,
    //    searches default paths.
    private static func urlForModel(named modelName: String, inDirectory directory: String?) -> URL? {
        let bundle = Bundle.main
        if let url = bundle.url(forResource: modelName, withExtension: "cdm", subdirectory: directory) {
            return url
        }

        // Get mom file paths from momd directories.
        var url: URL?
        let momdPaths = bundle.paths(forResourcesOfType: "momd", inDirectory: directory)
        for momdPath in momdPaths {
            url = bundle.url(forResource: modelName, withExtension: "mom", subdirectory: (momdPath as NSString).lastPathComponent)
        }

        return url
    }
}
