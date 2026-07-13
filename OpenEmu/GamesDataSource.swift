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

/// Data source for the games grid: a single flat section of `OEDBGame`s scoped
/// by the sidebar selection (console, collection, …) via
/// `GameCollectionViewItemProtocol.fetchPredicate`.
final class GamesDataSource: ImageDataSourceDelegate {

    var searchPredicate = NSPredicate(value: true)
    let entityName = OEDBGame.entityName

    /// The sidebar selection that scopes which games are fetched.
    var collectionItem: GameCollectionViewItemProtocol?

    private var items: [OEDBGame] = []
    private var indexPathByItems: [URL: IndexPath] = [:]
    private var tasks: [IndexPath: Task<Void, Never>] = [:]

    var isEmpty: Bool = true

    var numberOfSections: Int { 1 }

    func numberOfItems(in section: Int) -> Int { items.count }

    func loadItemView(_ view: ImageCollectionViewItem, at indexPath: IndexPath) {
        guard let game = item(at: indexPath) as OEDBGame? else { return }
        view.representedObject = game

        if let url = game.boxImage?.imageURL?.absoluteURL {
            view.imageURL = url
            let task = Task(priority: .userInitiated) { [weak self] in
                let img = await ImageCacheService.shared.fetchImage(url)

                guard !Task.isCancelled else { return }

                Task { @MainActor in
                    self?.tasks.removeValue(forKey: indexPath)
                    view.imageView?.image = img
                    view.view.needsLayout = true
                }
            }
            tasks[indexPath] = task
        } else {
            view.imageURL = nil
            view.imageView?.image = NSImage(named: "missing_artwork")
            view.view.needsLayout = true
        }

        view.textField?.stringValue = game.displayName
        view.subtitleField?.stringValue = ""
    }

    func unloadItemView(at indexPath: IndexPath) {
        tasks.removeValue(forKey: indexPath)?.cancel()
    }

    func loadHeaderView(_ view: ImageCollectionHeaderView, at indexPath: IndexPath) {
        // The games grid has no section headers.
        view.sectionTitle.stringValue = ""
        view.secondaryTitle.stringValue = ""
    }

    func fetchItems() {
        guard let ctx = OELibraryDatabase.default?.mainThreadContext else { return }

        items = []
        indexPathByItems = [:]

        guard let collectionItem else {
            isEmpty = true
            return
        }

        let req = NSFetchRequest<OEDBGame>(entityName: entityName)
        req.entity = NSEntityDescription.entity(forEntityName: entityName, in: ctx)

        let scopePredicate = collectionItem.fetchPredicate
        if collectionItem.fetchLimit > 0 {
            req.fetchLimit = collectionItem.fetchLimit
        }

        // isEmpty reflects the unsearched scope, so an empty search result
        // doesn't flip the view to the blank slate.
        let countRequest = NSFetchRequest<OEDBGame>(entityName: entityName)
        countRequest.predicate = scopePredicate
        let count = (try? ctx.count(for: countRequest)) ?? 0
        isEmpty = count == 0
        if isEmpty { return }

        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [scopePredicate, searchPredicate])

        let sortDescriptors = collectionItem.fetchSortDescriptors
        req.sortDescriptors = sortDescriptors.isEmpty
            ? [NSSortDescriptor(key: "gameTitle", ascending: true),
               NSSortDescriptor(key: "name", ascending: true)]
            : sortDescriptors

        items = (try? ctx.fetch(req)) ?? []
        for (offset, item) in items.enumerated() {
            indexPathByItems[item.permanentIDURI] = IndexPath(item: offset, section: 0)
        }
    }

    func indexPath(forID id: NSManagedObjectID) -> IndexPath? {
        indexPathByItems[id.uriRepresentation()]
    }

    func items(at indexPaths: Set<IndexPath>) -> [OEDBGame] {
        indexPaths.sorted().compactMap { item(at: $0) }
    }

    // MARK: - List view (flat row access)

    var numberOfRows: Int { items.count }

    func game(atRow row: Int) -> OEDBGame? {
        guard row >= 0, row < items.endIndex else { return nil }
        return items[row]
    }

    func games(atRows rows: IndexSet) -> [OEDBGame] {
        rows.compactMap { game(atRow: $0) }
    }

    func row(forID id: NSManagedObjectID) -> Int? {
        indexPathByItems[id.uriRepresentation()]?.item
    }

    /// Re-sorts the already-fetched items in place using the given table sort descriptors,
    /// which key off the computed `listView*` accessors (KVC), and rebuilds the index map.
    func sort(using descriptors: [NSSortDescriptor]) {
        guard !descriptors.isEmpty else { return }
        items = (items as NSArray).sortedArray(using: descriptors) as! [OEDBGame]
        indexPathByItems = [:]
        for (offset, item) in items.enumerated() {
            indexPathByItems[item.permanentIDURI] = IndexPath(item: offset, section: 0)
        }
    }

    func item(at indexPath: IndexPath) -> OEDBGame? {
        guard indexPath.section == 0, indexPath.item < items.endIndex else { return nil }
        return items[indexPath.item]
    }

    func item(at indexPath: IndexPath) -> Any {
        let item: OEDBGame? = item(at: indexPath)
        return item as Any
    }

    func permanentIDURIs(forItemsAt indexPaths: Set<IndexPath>) -> [URL] {
        items(at: indexPaths).map { $0.permanentIDURI }
    }

    func imageURL(forItemAt indexPath: IndexPath) -> URL? {
        item(at: indexPath)?.boxImage?.imageURL?.absoluteURL
    }

    func imageURLs(forItemsAt indexPaths: Set<IndexPath>) -> [URL] {
        items(at: indexPaths).compactMap { $0.boxImage?.imageURL?.absoluteURL }
    }
}
