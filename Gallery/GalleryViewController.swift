import Cocoa
import MP42Foundation

protocol GalleryViewControllerDelegate: AnyObject {
    func galleryViewController(_ controller: GalleryViewController, didSelect document: Document, extendSelection: Bool)
    func galleryViewController(_ controller: GalleryViewController, didDeselect document: Document)
    func galleryViewController(_ controller: GalleryViewController, didRequestAddFiles urls: [URL])
    func galleryViewController(_ controller: GalleryViewController, didRequestRemove documents: [Document])
    var documents: [Document]? { get }
}

final class GalleryViewController: NSViewController {
    
    weak var delegate: GalleryViewControllerDelegate?
    var selectedDocuments: Set<Document> = []
    
    @IBOutlet private weak var scrollView: NSScrollView!
    @IBOutlet private weak var collectionView: NSCollectionView!
    @IBOutlet private weak var addButton: NSButton!
    @IBOutlet private weak var removeButton: NSButton!
    @IBOutlet private weak var queueButton: NSButton!
    @IBOutlet private weak var buttonStack: NSStackView!
    
    // Add outlets for the detail views
    private weak var tracksViewController: TracksViewController?
    private weak var detailsViewController: DetailsViewController?
    
    init(delegate: GalleryViewControllerDelegate) {
        self.delegate = delegate
        super.init(nibName: "GalleryViewController", bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let collectionView = collectionView else {
            fatalError("Collection view outlet not connected")
        }
        
        // Configure collection view
        collectionView.delegate = self
        collectionView.dataSource = self
        
        // Try to load the XIB
        if let nib = NSNib(nibNamed: NSNib.Name("GalleryItemView"), bundle: Bundle.main) {
            collectionView.register(nib, forItemWithIdentifier: .galleryItem)
        } else {
            fatalError("Failed to load GalleryItemView.xib")
        }
        
        // Find the detail view controllers from the window controller
        if let windowController = view.window?.windowController as? GalleryWindowController {
            tracksViewController = windowController.tracksViewController
            detailsViewController = windowController.detailsViewController
        }
    }
    
    // MARK: - Public Methods
    
    func reloadData() {
        collectionView.reloadData()
        updateButtonStates()
    }
    
    // MARK: - Private Methods
    
    private func updateButtonStates() {
        removeButton.isEnabled = !selectedDocuments.isEmpty
        queueButton.isEnabled = delegate?.documents?.isEmpty == false
    }
    
    // Add a method to sync selection state
    func syncSelectionState() {
        guard let documents = delegate?.documents else { return }
        selectedDocuments.removeAll()
        
        for indexPath in collectionView.selectionIndexPaths {
            if indexPath.item < documents.count {
                selectedDocuments.insert(documents[indexPath.item])
            }
        }
        
        print("GalleryViewController: syncSelectionState - selected count: \(selectedDocuments.count)")
        updateButtonStates()
    }
    
    private func updateDetailsView(selectedDocument: Document?) {
        if let document = selectedDocument {
            tracksViewController?.mp4 = document.mp4
            // If DetailsViewController needs to update, call a method or set a property here if available
            // detailsViewController?.update(with: document)
        } else {
            tracksViewController?.mp4 = MP42File()
            // If DetailsViewController needs to clear, call a method here if available
            // detailsViewController?.clear()
        }
    }
    
    // MARK: - Actions
    
    @IBAction private func addFiles(_ sender: Any?) {
        print("GalleryViewController: Opening file panel")
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        // Allow all common video formats using file extensions
        openPanel.allowedFileTypes = [
            // QuickTime/MP4
            "mp4", "m4v", "mov", "qt",
            // MPEG-2
            "mpg", "mpeg", "m2v", "vob",
            // Matroska/WebM
            "mkv", "webm",
            // AVI
            "avi", "divx",
            // Transport Stream
            "ts", "mts", "m2ts",
            // Windows Media
            "wmv", "asf",
            // Flash Video
            "flv", "f4v",
            // Mobile formats
            "3gp", "3g2"
        ]
        
        guard let window = view.window else {
            return
        }
        
        openPanel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else {
                return
            }
            
            if response == .OK {
                self.delegate?.galleryViewController(self, didRequestAddFiles: openPanel.urls)
            }
        }
    }
    
    @IBAction private func removeFiles(_ sender: Any?) {
        delegate?.galleryViewController(self, didRequestRemove: Array(selectedDocuments))
    }
    
    @IBAction private func toggleQueue(_ sender: Any?) {
        // Handle queue start/stop
    }
}

// MARK: - NSCollectionViewDataSource

extension GalleryViewController: NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return delegate?.documents?.count ?? 0
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .galleryItem, for: indexPath)
        
        guard let galleryItem = item as? GalleryItemView else {
            fatalError("Expected GalleryItemView but got \(type(of: item))")
        }
        
        if let documents = delegate?.documents, indexPath.item < documents.count {
            let document = documents[indexPath.item]
            galleryItem.configure(with: document)
            galleryItem.isSelected = selectedDocuments.contains(document)
        }
        
        return galleryItem
    }
}

// MARK: - NSCollectionViewDelegate

extension GalleryViewController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let documents = delegate?.documents else { return }
        
        // Add newly selected documents
        for indexPath in indexPaths {
            if indexPath.item < documents.count {
                let document = documents[indexPath.item]
                selectedDocuments.insert(document)
                delegate?.galleryViewController(self, didSelect: document, extendSelection: false)
            }
        }
        
        updateButtonStates()
    }
    
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        guard let documents = delegate?.documents else { return }
        
        // Remove deselected documents
        for indexPath in indexPaths {
            if indexPath.item < documents.count {
                let document = documents[indexPath.item]
                selectedDocuments.remove(document)
                delegate?.galleryViewController(self, didDeselect: document)
            }
        }
        
        updateButtonStates()
    }
}

// MARK: - NSCollectionViewItemIdentifier

extension NSUserInterfaceItemIdentifier {
    static let galleryItem = NSUserInterfaceItemIdentifier("GalleryItem")
}

// MARK: - GalleryItemView

final class GalleryItemView: NSCollectionViewItem {
    
    @IBOutlet weak var customImageView: NSImageView!
    @IBOutlet weak var titleLabel: NSTextField!
    @IBOutlet weak var subtitleLabel: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configure view
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
    }
    
    override var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }
    
    private func updateSelectionAppearance() {
        let backgroundColor: NSColor
        if isSelected {
            if #available(macOS 10.14, *) {
                backgroundColor = NSColor(named: "selectedContentBackgroundColor") ?? .alternateSelectedControlColor
            } else {
                backgroundColor = .alternateSelectedControlColor
            }
            view.layer?.backgroundColor = backgroundColor.cgColor
            //titleLabel.textColor = .selectedControlTextColor
            //subtitleLabel.textColor = .selectedControlTextColor
        } else {
            view.layer?.backgroundColor = nil
            //titleLabel.textColor = .labelColor
            //subtitleLabel.textColor = .secondaryLabelColor
        }
    }
    
    func configure(with document: Document) {
        // Configure the item view with document metadata
        let metadata = document.mp4.metadata
        
        // Get title
        if let titleItem = metadata.metadataItemsFiltered(byIdentifier: MP42MetadataKeyName).first {
            titleLabel.stringValue = titleItem.stringValue ?? ""
        } else {
            titleLabel.stringValue = ""
        }
        
        // Get release date or TV show info
        if let releaseDateItem = metadata.metadataItemsFiltered(byIdentifier: MP42MetadataKeyReleaseDate).first,
           let releaseDate = releaseDateItem.stringValue {
            // Try to extract just the year from the date
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"  // Common format for release dates
            
            if let date = dateFormatter.date(from: releaseDate) {
                dateFormatter.dateFormat = "yyyy"
                subtitleLabel.stringValue = dateFormatter.string(from: date)
            } else {
                // If we can't parse the date, try to extract year using regex
                if let year = releaseDate.range(of: "\\d{4}", options: .regularExpression) {
                    subtitleLabel.stringValue = String(releaseDate[year])
                } else {
                    subtitleLabel.stringValue = releaseDate
                }
            }
        } else if let showNameItem = metadata.metadataItemsFiltered(byIdentifier: MP42MetadataKeyTVShow).first,
                  let seasonItem = metadata.metadataItemsFiltered(byIdentifier: MP42MetadataKeyTVSeason).first,
                  let episodeItem = metadata.metadataItemsFiltered(byIdentifier: MP42MetadataKeyTVEpisodeNumber).first,
                  let showName = showNameItem.stringValue,
                  let season = seasonItem.numberValue?.intValue,
                  let episode = episodeItem.numberValue?.intValue {
            subtitleLabel.stringValue = "\(showName) S\(String(format: "%02d", season))E\(String(format: "%02d", episode))"
        } else {
            subtitleLabel.stringValue = ""
        }
        
        // Load artwork
        if let artworkItem = metadata.metadataItemsFiltered(byIdentifier: MP42MetadataKeyCoverArt).first,
           let artworkImage = artworkItem.value as? MP42Image,
           let artworkData = artworkImage.data {
            customImageView.image = NSImage(data: artworkData)
        } else {
            customImageView.image = NSImage(named: "NSDefaultApplicationIcon")
        }
    }
} 