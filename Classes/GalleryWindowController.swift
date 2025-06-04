import Cocoa
import MP42Foundation

final class GalleryWindowController: NSWindowController {
    
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
        
        // Right side - Details view
        let detailsItem = NSSplitViewItem(viewController: detailsViewController)
        detailsItem.minimumThickness = 400
        splitViewController.addSplitViewItem(detailsItem)
        
        return splitViewController
    }()
    
    private lazy var galleryViewController: GalleryViewController = {
        return GalleryViewController(delegate: self)
    }()
    
    private lazy var detailsViewController: DetailsViewController = {
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
            //detailsViewController.document = document
        } else {
            //detailsViewController.document = nil
        }
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
        // Handle file import
    }
    
    func galleryViewController(_ controller: GalleryViewController, didRequestRemove documents: [Document]) {
        // Handle document removal
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
        openPanel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        
        openPanel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK else { return }
            // Handle file import
        }
    }
    
    @objc private func removeFiles(_ sender: Any?) {
        // Handle file removal
    }
    
    @objc private func toggleQueue(_ sender: Any?) {
        // Handle queue start/stop
    }
} 