import Cocoa
import MP42Foundation

final class GalleryWindowController: NSWindowController, TracksViewControllerDelegate {
    
    static let shared = GalleryWindowController()
    
    private var galleryDocuments: [Document] = []
    private var selectedDocuments: Set<Document> = []
    
    override var windowNibName: NSNib.Name? {
        return "GalleryWindowController"
    }
    
    private init() {
        super.init(window: nil)
        _ = window
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private lazy var splitViewController: NSSplitViewController = {
        let splitViewController = NSSplitViewController()
        splitViewController.view.wantsLayer = true
        splitViewController.splitView.isVertical = true
        splitViewController.splitView.dividerStyle = .thin
        
        // Left side - Gallery view
        let galleryItem = NSSplitViewItem(viewController: galleryViewController)
        galleryItem.minimumThickness = 300
        splitViewController.addSplitViewItem(galleryItem)
        
        // Right side - Tab view with Tracks and Details
        let tabViewController = NSTabViewController()
        tabViewController.tabStyle = .toolbar
        
        // Add Tracks tab
        let tracksItem = NSTabViewItem(viewController: tracksViewController)
        tracksItem.label = NSLocalizedString("Tracks", comment: "Tracks tab label")
        tabViewController.addTabViewItem(tracksItem)
        
        // Add Details tab
        let detailsItem = NSTabViewItem(viewController: detailsViewController)
        detailsItem.label = NSLocalizedString("Details", comment: "Details tab label")
        tabViewController.addTabViewItem(detailsItem)
        
        let detailsSplitItem = NSSplitViewItem(viewController: tabViewController)
        detailsSplitItem.minimumThickness = 400
        splitViewController.addSplitViewItem(detailsSplitItem)
        
        return splitViewController
    }()
    
    private lazy var galleryViewController: GalleryViewController = {
        return GalleryViewController(delegate: self)
    }()
    
    private lazy var _tracksViewController: TracksViewController = {
        // Create a new document with an empty MP42File for initial state
        let emptyDoc = Document(mp4: MP42File())
        let controller = TracksViewController(document: emptyDoc, delegate: self)
        return controller
    }()
    
    private lazy var _detailsViewController: DetailsViewController = {
        return DetailsViewController()
    }()
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        guard let window = window else { return }
        
        // Configure window
        window.title = NSLocalizedString("Subler", comment: "Main window title")
        window.contentViewController = splitViewController
        window.registerForDraggedTypes([.fileURL])
        
        // Set up toolbar
        let toolbar = NSToolbar(identifier: "GalleryToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
        
        // Set initial window size
        window.setContentSize(NSSize(width: 1200, height: 800))
        splitViewController.splitView.setPosition(600, ofDividerAt: 0)
    }
    
    // MARK: - Document Management
    
    func addDocument(_ document: Document) {
        galleryDocuments.append(document)
        galleryViewController.reloadData()
    }
    
    func removeDocument(_ document: Document) {
        if let index = galleryDocuments.firstIndex(where: { $0 === document }) {
            galleryDocuments.remove(at: index)
            selectedDocuments.remove(document)
            galleryViewController.reloadData()
        }
    }
    
    func selectDocument(_ document: Document, extendSelection: Bool = false) {
        if !extendSelection {
            selectedDocuments.removeAll()
        }
        selectedDocuments.insert(document)
        galleryViewController.reloadData()
        updateDetailsView()
    }
    
    private func updateDetailsView() {
        if let document = selectedDocuments.first {
            _tracksViewController.mp4 = document.mp4
            // DetailsViewController doesn't have an mp4 property, so we don't update it
        } else {
            // Reset to empty MP4 when no document is selected
            _tracksViewController.mp4 = MP42File()
            // DetailsViewController doesn't need to be reset
        }
    }
    
    // MARK: - TracksViewControllerDelegate
    
    func didSelect(tracks: [MP42Track]) {
        // Handle track selection if needed
    }
    
    func delete(tracks: [MP42Track]) {
        // Handle track deletion if needed
    }
    
    // Make these accessible to GalleryViewController
    var tracksViewController: TracksViewController {
        return _tracksViewController
    }
    
    var detailsViewController: DetailsViewController {
        return _detailsViewController
    }
}

// MARK: - GalleryViewControllerDelegate

extension GalleryWindowController: GalleryViewControllerDelegate {
    var documents: [Document]? {
        return galleryDocuments
    }
    
    func galleryViewController(_ controller: GalleryViewController, didSelect document: Document, extendSelection: Bool) {
        selectDocument(document, extendSelection: extendSelection)
    }
    
    func galleryViewController(_ controller: GalleryViewController, didDeselect document: Document) {
        selectedDocuments.remove(document)
        updateDetailsView()
    }
    
    func galleryViewController(_ controller: GalleryViewController, didRequestAddFiles urls: [URL]) {
        for url in urls {
            do {
                let mp4 = try MP42File(url: url)
                let document = Document(mp4: mp4)
                addDocument(document)
            } catch {
                // If the file is not a valid MP4, try to import it
                do {
                    let doc = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true) as! Document
                    if let windowController = doc.windowControllers.first as? DocumentWindowController {
                        windowController.showImportSheet(fileURLs: [url])
                    }
                } catch {
                    NSApp.presentError(error)
                }
            }
        }
    }
    
    func galleryViewController(_ controller: GalleryViewController, didRequestRemove documents: [Document]) {
        // Remove each document from the gallery
        for document in documents {
            removeDocument(document)
        }
        
        // Clear selection after removal
        selectedDocuments.removeAll()
        updateDetailsView()
    }
}

// MARK: - NSToolbarDelegate

extension GalleryWindowController: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .addFiles:
            return ButtonToolbarItem(itemIdentifier: itemIdentifier,
                                   label: NSLocalizedString("Add Files", comment: "Toolbar"),
                                   toolTip: NSLocalizedString("Add files to the gallery", comment: "Toolbar"),
                                   image: "NSAddTemplate",
                                   symbolName: "plus",
                                   target: self,
                                   action: #selector(addFiles(_:)))
            
        case .removeFiles:
            return ButtonToolbarItem(itemIdentifier: itemIdentifier,
                                   label: NSLocalizedString("Remove", comment: "Toolbar"),
                                   toolTip: NSLocalizedString("Remove selected files", comment: "Toolbar"),
                                   image: "NSRemoveTemplate",
                                   symbolName: "minus",
                                   target: self,
                                   action: #selector(removeFiles(_:)))
            
        case .startQueue:
            return ButtonToolbarItem(itemIdentifier: itemIdentifier,
                                   label: NSLocalizedString("Start Queue", comment: "Toolbar"),
                                   toolTip: NSLocalizedString("Start processing the queue", comment: "Toolbar"),
                                   image: "NSPlayTemplate",
                                   symbolName: "play.fill",
                                   target: self,
                                   action: #selector(toggleQueue(_:)))
            
        default:
            return nil
        }
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.addFiles, .removeFiles, .flexibleSpace, .startQueue]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.addFiles, .removeFiles, .flexibleSpace, .startQueue]
    }
}

// MARK: - Toolbar Item Identifiers

extension NSToolbarItem.Identifier {
    static let addFiles = NSToolbarItem.Identifier("addFiles")
    static let removeFiles = NSToolbarItem.Identifier("removeFiles")
    static let startQueue = NSToolbarItem.Identifier("startQueue")
}

// MARK: - Actions

extension GalleryWindowController {
    @objc private func addFiles(_ sender: Any?) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        let galleryVC = self.galleryViewController // Capture before closure
        openPanel.beginSheetModal(for: window!) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK else { return }
            self.galleryViewController(galleryVC, didRequestAddFiles: openPanel.urls)
        }
    }
    
    @objc private func removeFiles(_ sender: Any?) {
        let galleryVC = self.galleryViewController // Capture before use
        // Get the selected documents directly from the gallery view controller
        galleryVC.syncSelectionState() // Ensure selection state is up to date
        if let documents = galleryVC.delegate?.documents {
            // Get the selected documents from the gallery view controller's selection state
            let selectedDocuments = documents.filter { document in
                galleryVC.selectedDocuments.contains(document)
            }
            galleryViewController(galleryVC, didRequestRemove: selectedDocuments)
        }
    }
    
    @objc private func toggleQueue(_ sender: Any?) {
        // Handle queue start/stop
    }
} 