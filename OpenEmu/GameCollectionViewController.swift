// Copyright (c) 2019, OpenEmu Team
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

/// Which view the games collection is currently showing. Raw values are
/// preserved from the retired `OECollectionViewController` (they are persisted
/// in user defaults and referenced by menu-item tags).
enum OECollectionViewControllerViewTag: Int {
    case blankSlateTag = -1
    case gridViewTag   = 0
    case listViewTag   = 2
}

@objc
class GameCollectionViewController: ImageCollectionViewController {

    private static let lastCollectionViewKey = "OELastCollectionView"

    var dataSource = GamesDataSource()

    private(set) var selectedViewTag: OECollectionViewControllerViewTag = .gridViewTag

    private weak var listView: GameTableView!
    private var listScrollView: NSScrollView?

    override var representedObject: Any? {
        didSet {
            dataSource.collectionItem = representedObject as? GameCollectionViewItemProtocol
            if isViewLoaded {
                reloadData()
            }
        }
    }

    var selectedGames: [OEDBGame] {
        if selectedViewTag == .listViewTag {
            return dataSource.games(atRows: listView?.selectedRowIndexes ?? [])
        }
        return dataSource.items(at: collectionView.selectionIndexPaths)
    }

    override func viewDidLoad() {
        showsSectionHeaders = false
        dataSourceDelegate = dataSource

        super.viewDidLoad()

        setUpListView()

        let last = OECollectionViewControllerViewTag(rawValue: UserDefaults.standard.integer(forKey: Self.lastCollectionViewKey)) ?? .gridViewTag
        selectedViewTag = last == .listViewTag ? .listViewTag : .gridViewTag
    }

    private func setUpListView() {
        var topLevelObjects: NSArray?
        Bundle(for: GameTableView.self).loadNibNamed("GameTableView", owner: self, topLevelObjects: &topLevelObjects)

        guard
            let scrollView = topLevelObjects?.compactMap({ $0 as? NSScrollView }).first,
            let table = scrollView.documentView as? GameTableView
        else {
            assertionFailure("GameTableView.xib did not vend a GameTableView in a scroll view")
            return
        }

        listView = table
        listScrollView = scrollView

        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(listViewDoubleClick(_:))
        table.shouldShowSystemColumn = (representedObject as? GameCollectionViewItemProtocol)?.shouldShowSystemColumnInListView ?? true
    }

    func showGridView() {
        setViewTag(.gridViewTag)
    }

    func showListView() {
        setViewTag(.listViewTag)
    }

    private func setViewTag(_ tag: OECollectionViewControllerViewTag) {
        selectedViewTag = tag
        UserDefaults.standard.set(tag.rawValue, forKey: Self.lastCollectionViewKey)
        updateBlankSlate()
        validateToolbarItems()
    }

    override func updateBlankSlate() {
        if shouldShowBlankSlate {
            blankSlateView.representedObject = representedObject
            showContentView(blankSlateView)
        } else if selectedViewTag == .listViewTag {
            listView?.reloadData()
            showContentView(listScrollView)
            positionListViewBelowToolbar()
        } else {
            collectionView.reloadData()
            showContentView(collectionView.enclosingScrollView)
        }
    }

    /// The library window uses a full-size content rect, so a view whose frame is
    /// the controller's full bounds (as `showContentView(_:)` sets it) renders its
    /// top under the toolbar. The grid's scroll view is inset by its storyboard
    /// constraints and the blank slate by an explicit computation; the list scroll
    /// view is loaded from its own nib and added at runtime, so it needs the same
    /// treatment here.
    private func positionListViewBelowToolbar() {
        guard let listScrollView, let window = view.window else { return }
        listScrollView.autoresizingMask = [.width, .height]
        let viewFrame = view.convert(view.bounds, to: nil)
        let nonOverlappingFrame = NSIntersectionRect(viewFrame, window.contentLayoutRect)
        listScrollView.frame = view.convert(nonOverlappingFrame, from: nil)
    }

    override func reloadData() {
        super.reloadData()
        listView?.reloadData()
    }

    @objc private func listViewDoubleClick(_ sender: Any?) {
        guard let game = dataSource.game(atRow: listView.clickedRow) else { return }
        NSApp.sendAction(#selector(LibraryController.startSelectedGame(_:)), to: nil, from: game)
    }

    func zoomGridView(withValue value: CGFloat) {
        zoomGridView(zoomValue: value)
    }


    override func validateToolbarItems() {
        guard let toolbar = toolbar else { return }
        
        let isGridView = selectedViewTag == .gridViewTag
        let isBlankSlate = shouldShowBlankSlate
        
        toolbar.viewModeSelector.isEnabled = !isBlankSlate
        toolbar.viewModeSelector.selectedSegment = isGridView ? 0 : 1
        
        toolbar.gridSizeSlider.isEnabled = isGridView && !isBlankSlate
        toolbar.decreaseGridSizeButton.isEnabled = isGridView && !isBlankSlate
        toolbar.increaseGridSizeButton.isEnabled = isGridView && !isBlankSlate
        
        toolbar.searchField.isEnabled = !isBlankSlate
        toolbar.searchField.searchMenuTemplate = nil
        toolbar.searchField.stringValue = currentSearchTerm
        
        toolbar.addButton.isEnabled = true
        
        for item in toolbar.items {
            if item.itemIdentifier == .oeSearch {
                item.isEnabled = !isBlankSlate
            }
        }
    }
}

extension GameCollectionViewController: CollectionViewExtendedDelegate, NSMenuItemValidation {
    
    // MARK: - Validation
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)),
             #selector(delete(_:)),
             #selector(showInFinder(_:)):
            return !selectedGames.isEmpty
        default:
            return true
        }
    }
    
    // MARK: - Context Menus
    
    func collectionView(_ collectionView: CollectionView, menuForItemsAt indexPaths: Set<IndexPath>) -> NSMenu? {
        let menu = NSMenu()
        var item: NSMenuItem
        let games = selectedGames
        let hasLocalFiles = games.first(where: { $0.defaultROM?.filesAvailable == true }) != nil
        
        if games.count == 1 {
            let game = games.first!
            
            menu.addItem(withTitle: NSLocalizedString("Play Game", comment: ""),
                         action: #selector(LibraryController.startSelectedGame(_:)),
                         keyEquivalent: "")
            
            item = NSMenuItem()
            item.title = NSLocalizedString("Play Save State", comment: "")
            item.submenu = saveStateMenu(for: game)
            menu.addItem(item)
            
            item = NSMenuItem()
            item.title = NSLocalizedString("Delete Save State", comment: "")
            item.isAlternate = true
            item.keyEquivalentModifierMask = .option
            item.submenu = saveStateMenu(for: game)
            menu.addItem(item)
            
            menu.addItem(.separator())
            
            item = NSMenuItem()
            item.title = NSLocalizedString("Rating", comment: "")
            item.submenu = ratingMenu(for: games)
            menu.addItem(item)
            
            if hasLocalFiles {
                menu.addItem(withTitle: NSLocalizedString("Show in Finder", comment: ""),
                             action: #selector(showInFinder(_:)),
                             keyEquivalent: "")
            }
            
            menu.addItem(.separator())
            
            if game.status == .ok {
                menu.addItem(withTitle: NSLocalizedString("Download Cover Art", comment: ""),
                             action: #selector(downloadCoverArt(_:)),
                             keyEquivalent: "")
            }
            if game.status == .processing {
                menu.addItem(withTitle: NSLocalizedString("Cancel Cover Art Download", comment: ""),
                             action: #selector(cancelCoverArtDownload(_:)),
                             keyEquivalent: "")
            }
            menu.addItem(withTitle: NSLocalizedString("Add Cover Art from File…", comment: ""),
                         action: #selector(addCoverArtFromFile(_:)),
                         keyEquivalent: "")
            if hasLocalFiles {
                menu.addItem(withTitle: NSLocalizedString("Consolidate Files…", comment: ""),
                             action: #selector(consolidateFiles(_:)),
                             keyEquivalent: "")
            }
            
            menu.addItem(.separator())
            
            item = NSMenuItem(title: NSLocalizedString("Add to Collection", comment: ""),
                              action: nil,
                              keyEquivalent: "")
            item.submenu = collectionsMenu(for: games)
            menu.addItem(item)
            
            menu.addItem(.separator())
            
            menu.addItem(withTitle: NSLocalizedString("Rename Game", comment: ""),
                         action: #selector(CollectionView.beginEditingWithSelectedItem(_:)),
                         keyEquivalent: "")
            var title: String
            if type(of: representedObject as AnyObject) === OEDBCollection.self {
                title = NSLocalizedString("Remove Game", comment: "")
            } else {
                title = NSLocalizedString("Delete Game", comment: "")
            }
            menu.addItem(withTitle: title,
                         action: #selector(deleteSelectedItems(_:)),
                         keyEquivalent: "")
        }
        else {
            // FIXME: starting multiple games only starts the first of the selected games
            /*if UserDefaults.standard.bool(forKey: OEForcePopoutGameWindowKey) {
                menu.addItem(withTitle: NSLocalizedString("Play Games (Caution)", comment: ""),
                             action: #selector(LibraryController.startSelectedGame(_:)),
                             keyEquivalent: "")
            }*/
            
            item = NSMenuItem()
            item.title = NSLocalizedString("Rating", comment: "")
            item.submenu = ratingMenu(for: games)
            menu.addItem(item)
            
            if hasLocalFiles {
                menu.addItem(withTitle: NSLocalizedString("Show in Finder", comment: ""),
                             action: #selector(showInFinder(_:)),
                             keyEquivalent: "")
            }
            
            menu.addItem(.separator())
            
            menu.addItem(withTitle: NSLocalizedString("Download Cover Art", comment: ""),
                         action: #selector(downloadCoverArt(_:)),
                         keyEquivalent: "")
            menu.addItem(withTitle: NSLocalizedString("Add Cover Art from File…", comment: ""),
                         action: #selector(addCoverArtFromFile(_:)),
                         keyEquivalent: "")
            menu.addItem(withTitle: NSLocalizedString("Consolidate Files…", comment: ""),
                         action: #selector(consolidateFiles(_:)),
                         keyEquivalent: "")
            
            menu.addItem(.separator())
            
            item = NSMenuItem(title: NSLocalizedString("Add to Collection", comment: ""),
                              action: nil,
                              keyEquivalent: "")
            item.submenu = collectionsMenu(for: games)
            menu.addItem(item)
            
            menu.addItem(.separator())
            
            var title: String
            if type(of: representedObject as AnyObject) === OEDBCollection.self {
                title = NSLocalizedString("Remove Games", comment: "")
            } else {
                title = NSLocalizedString("Delete Games", comment: "")
            }
            menu.addItem(withTitle: title,
                         action: #selector(deleteSelectedItems(_:)),
                         keyEquivalent: "")
        }
        
        return menu
    }
    
    private func saveStateMenu(for game: OEDBGame) -> NSMenu {
        let menu = NSMenu()
        
        game.roms.forEach { rom in
            
            rom.removeMissingStates()
            
            let saveStates = rom.normalSaveStatesByTimestamp(ascending: false)
            saveStates.forEach { saveState in
                
                let title = saveState.name
                
                let item = NSMenuItem()
                item.title = title
                item.action = #selector(LibraryController.startSelectedGame(saveState:))
                item.representedObject = saveState
                menu.addItem(item)
                
                let alternateItem = NSMenuItem()
                alternateItem.title = title
                alternateItem.action = #selector(deleteSaveState(_:))
                alternateItem.isAlternate = true
                alternateItem.keyEquivalentModifierMask = .option
                alternateItem.representedObject = saveState
                menu.addItem(alternateItem)
            }
        }
        
        if menu.items.isEmpty {
            menu.addItem(withTitle: NSLocalizedString("No Save States available", comment: ""),
                         action: nil,
                         keyEquivalent: "")
        }
        
        return menu
    }
    
    private func ratingMenu(for games: [OEDBGame]) -> NSMenu {
        let menu = NSMenu()
        let ratingLabel = "★★★★★"
        
        for i in 0...5 {
            let item = NSMenuItem()
            item.title = i == 0 ? NSLocalizedString("None", comment: "")
                                      : "\(ratingLabel.prefix(i))"
            item.action = #selector(setRatingForSelectedGames(_:))
            item.representedObject = i
            menu.addItem(item)
        }
        
        var valuesDiffer = false
        for i in 0..<games.count {
            let gameRating = games[i].rating
            let itemIndex = gameRating?.intValue ?? 0
            let item = menu.item(at: itemIndex)
            
            if i == 0 {
                item?.state = .on
            } else if item?.state != .on {
                valuesDiffer = true
                item?.state = .mixed
            }
        }
        
        if valuesDiffer {
            let gameRating = games.first?.rating
            let item = menu.item(at: gameRating?.intValue ?? 0)
            item?.state = .mixed
        }
        
        return menu
    }
    
    private func collectionsMenu(for games: [OEDBGame]) -> NSMenu {
        let menu = NSMenu()
        let collections = database!.collections
        
        var item = NSMenuItem()
        item.title = NSLocalizedString("New Collection from Selection", comment: "")
        item.action = #selector(LibraryGamesViewController.makeNewCollectionWithSelectedGames(_:))
        menu.addItem(item)
        
        collections.forEach { collection in
            if type(of: collection) === OEDBCollection.self,
               !collection.isEqual(representedObject) {
                item = NSMenuItem()
                item.title = (collection as! OEDBCollection).name
                item.action = #selector(addSelectedGamesToCollection(_:))
                item.representedObject = collection
                menu.addItem(item)
            }
        }
        
        if menu.items.count != 1 {
            menu.insertItem(.separator(), at: 1)
        }
        
        return menu
    }
    
    // MARK: - Actions
    
    @objc func showInFinder(_ sender: Any?) {
        let urls = selectedGames.compactMap { $0.defaultROM?.url?.absoluteURL }
        
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
    
    @IBAction func copy(_ sender: Any?) {
        copySelectedItems(sender)
    }
    
    @objc func copySelectedItems(_ sender: Any?) {
        let fileURLs = selectedGames.compactMap { $0.defaultROM?.url?.absoluteURL as NSURL? }
        
        let pboard = NSPasteboard.general
        pboard.clearContents()
        pboard.declareTypes([.fileURL], owner: nil)
        pboard.writeObjects(fileURLs)
    }
    
    @IBAction override func delete(_ sender: Any?) {
        deleteSelectedItems(sender)
    }
    
    @objc func deleteSelectedItems(_ sender: Any?) {
        assert(Thread.isMainThread, "Only call on main thread!")
        let multipleGames = selectedGames.count > 1
        
        // deleting from 'All Games', smart collections and consoles removes games from the library
        if representedObject is OEDBSystem ||
           representedObject is OEDBSmartCollection ||
           representedObject is OEDBAllGamesCollection {
            // delete games from library if user allows it
            if OEAlert.removeGamesFromLibrary(multipleGames: multipleGames).runModal() == .alertFirstButtonReturn {
                selectedGames.forEach { $0.delete(moveToTrash: true, keepSaveStates: false) }
                
                let context = selectedGames.last?.managedObjectContext
                try? context?.save()
                
                reloadData()
            }
        }
        // deleting from regular collections removes games from that collection
        else if let collection = representedObject as? OEDBCollection {
            // remove games from collection if user allows it
            if OEAlert.removeGamesFromCollection(multipleGames: multipleGames).runModal() == .alertFirstButtonReturn {
                collection.games.subtract(selectedGames)
                collection.save()
            }
            reloadData()
        }
    }
    
    @objc func deleteSaveState(_ sender: NSMenuItem) {
        guard let state = sender.representedObject as? OEDBSaveState else { return }
        
        let stateName = state.name
        let alert = OEAlert.deleteSaveState(name: stateName)
        
        if alert.runModal() == .alertFirstButtonReturn {
            state.deleteAndRemoveFiles()
        }
    }
    
    @objc func addSelectedGamesToCollection(_ sender: NSMenuItem) {
        assert(Thread.isMainThread, "Only call on main thread!")
        guard let collection = sender.representedObject as? OEDBCollection else { return }
        
        collection.games.formUnion(selectedGames)
        collection.save()
        
        reloadData()
    }
    
    @objc func downloadCoverArt(_ sender: Any?) {
        selectedGames.forEach { $0.requestCoverDownload() }
        selectedGames.last?.save()
        
        reloadData()
    }
    
    @objc func cancelCoverArtDownload(_ sender: Any?) {
        selectedGames.forEach { $0.cancelCoverDownload() }
        selectedGames.last?.save()
        
        reloadData()
    }
    
    @objc func addCoverArtFromFile(_ sender: Any?) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedFileTypes = NSImage.imageTypes
        
        openPanel.begin { result in
            guard result == .OK, let url = openPanel.url else { return }
            
            self.selectedGames.forEach { $0.setBoxImage(url: url) }
            let context = self.selectedGames.last?.managedObjectContext
            try? context?.save()
            
            self.reloadData()
        }
    }
    
    @objc func setRatingForSelectedGames(_ sender: NSMenuItem) {
        selectedGames.forEach { $0.rating = sender.representedObject as? NSNumber }
        
        reloadData()
    }
    
    @IBAction func setRatingForGame(_ sender: NSLevelIndicator) {
        guard let game = sender.cell?.representedObject as? OEDBGame else { return }
        game.rating = sender.intValue as NSNumber
        
        reloadData()
    }
    
    // untested
    @objc func consolidateFiles(_ sender: Any?) {
        DispatchQueue.main.async {
            let games = self.selectedGames
            if games.isEmpty {
                return
            }
            
            var alert = OEAlert()
            alert.messageText = NSLocalizedString("Consolidating will copy all of the selected games into the OpenEmu Library folder.", comment: "")
            alert.informativeText = NSLocalizedString("This cannot be undone.", comment: "")
            alert.defaultButtonTitle = NSLocalizedString("Consolidate", comment: "")
            alert.alternateButtonTitle = NSLocalizedString("Cancel", comment: "")
            if alert.runModal() != .alertFirstButtonReturn {
                return
            }
            
            alert = OEAlert()
            alert.messageText = NSLocalizedString("Copying Game Files…", comment: "")
            alert.showsProgressbar = true
            alert.progress = 0
            
            var alertResult = -1
            let context = OELibraryDatabase.default!.makeWriterChildContext()
            let gameIDs = games.map { $0.permanentID }
            
            DispatchQueue.global(qos: .default).asyncAfter(deadline: DispatchTime.now() + .seconds(1)) {
                context.performAndWait {
                    var err: Error?
                    for i in 0..<gameIDs.count {
                        if alertResult != -1 {
                            break
                        }
                        
                        let gameID = gameIDs[i]
                        let game = OEDBGame.object(with: gameID, in: context)
                        for rom in game?.roms ?? [] {
                            if alertResult != -1 {
                                break
                            }
                            do {
                                try rom.consolidateFiles()
                                break
                            } catch {
                                err = error
                            }
                        }
                        
                        alert.performBlockInModalSession {
                            alert.progress = Double(i + 1) / Double(games.count)
                        }
                        
                        if err != nil {
                            break
                        }
                    }
                    
                    if let error = err {
                        let originalCompletionHandler = alert.callbackHandler
                        alert.callbackHandler = { alert, result in
                            let errorAlert = OEAlert()
                            errorAlert.messageText = NSLocalizedString("Consolidating files failed.", comment: "")
                            errorAlert.informativeText = error.localizedDescription
                            errorAlert.defaultButtonTitle = NSLocalizedString("OK", comment: "")
                            errorAlert.runModal()
                            
                            if let originalCompletionHandler = originalCompletionHandler {
                                originalCompletionHandler(alert, result)
                            }
                        }
                    }
                    
                    try? context.save()
                    let writerContext = context.parent
                    writerContext?.perform {
                        writerContext?.userInfo[OELibraryDatabase.managedObjectContextHasDirectChangesUserInfoKey] = true as NSNumber
                        try? writerContext?.save()
                    }
                    
                    alert.close(withResult: .alertFirstButtonReturn)
                }
            }
            
            alert.defaultButtonTitle = NSLocalizedString("Stop", comment: "")
            alertResult = alert.runModal().rawValue
        }
    }
    
    func collectionView(_ collectionView: CollectionView, doubleClickForItemAt indexPath: IndexPath) {
        guard let item: OEDBGame = dataSource.item(at: indexPath) else { return }
        NSApp.sendAction(#selector(LibraryController.startSelectedGame(_:)), to: nil, from: item)
    }
}

// MARK: - List View (cell-based table)

extension GameCollectionViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        dataSource.numberOfRows
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard let game = dataSource.game(atRow: row), let columnID = tableColumn?.identifier else { return nil }

        switch columnID {
        case .gameTableViewStatusColumn:
            let imageName = game.listViewStatus()!
            let isSelected = tableView.selectedRowIndexes.contains(row)
            let isMissing = imageName == "list_indicator_missing"
            let image = NSImage(named: imageName)
            let tint: NSColor = isMissing ? .systemOrange : .controlAccentColor
            return isSelected ? image : image?.withTintColor(tint)
        default:
            // The remaining columns key off computed listView* accessors via KVC.
            return game.value(forKey: columnID.rawValue)
        }
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard let game = dataSource.game(atRow: row), let columnID = tableColumn?.identifier else { return }

        switch columnID {
        case .gameTableViewRatingColumn:
            game.setListViewRating(object as? NSNumber)
        case .gameTableViewTitleColumn:
            let title = (object as? NSAttributedString)?.string ?? object as? String
            game.setListViewTitle(title)
            // Search results may no longer be valid, reload.
            reloadData()
        default:
            return
        }
        try? game.managedObjectContext?.save()
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        dataSource.sort(using: tableView.sortDescriptors)
        tableView.reloadData()
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        tableColumn?.identifier == .gameTableViewTitleColumn || tableColumn?.identifier == .gameTableViewRatingColumn
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectionDidChange()
    }
}

extension GameCollectionViewController: GameTableViewMenuSource {
    func tableView(_ tableView: GameTableView, menuForItemsAt indexes: IndexSet) -> NSMenu? {
        // `selectedGames` reflects the table selection while in list mode, so reuse the grid menu.
        collectionView(collectionView, menuForItemsAt: [])
    }
}
