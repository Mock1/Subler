import Cocoa
import MP42Foundation

protocol GalleryViewControllerDelegate: AnyObject {
    func galleryViewController(_ controller: GalleryViewController, didSelect document: Document, extendSelection: Bool)
    func galleryViewController(_ controller: GalleryViewController, didDeselect document: Document)
    func galleryViewController(_ controller: GalleryViewController, didRequestAddFiles urls: [URL])
    func galleryViewController(_ controller: GalleryViewController, didRequestRemove documents: [Document])
}

final class GalleryViewController: NSViewController {
    
    weak var delegate: GalleryViewControllerDelegate?
    private var documents: [Document] = []
    private var selectedDocuments: Set<Document> = []
    
    private lazy var scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = collectionView
        return scrollView
    }()
    
    private lazy var collectionView: NSCollectionView = {
        let layout = NSCollectionViewGridLayout()
        layout.minimumItemSize = NSSize(width: 200, height: 300)
        layout.maximumItemSize = NSSize(width: 200, height: 300)
        layout.minimumInteritemSpacing = 20
        layout.minimumLineSpacing = 20
        layout.sectionInset = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        
        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.allowsMultipleSelection = true
        collectionView.isSelectable = true
        collectionView.register(GalleryItemView.self, forItemWithIdentifier: .galleryItem)
        
        return collectionView
    }()
    
    private lazy var addButton: NSButton = {
        let button = NSButton(title: NSLocalizedString("Add Files", comment: "Gallery"),
                            target: self,
                            action: #selector(addFiles(_:)))
        button.bezelStyle = .texturedRounded
        return button
    }()
    
    private lazy var removeButton: NSButton = {
        let button = NSButton(title: NSLocalizedString("Remove", comment: "Gallery"),
                            target: self,
                            action: #selector(removeFiles(_:)))
        button.bezelStyle = .texturedRounded
        button.isEnabled = false
        return button
    }()
    
    private lazy var queueButton: NSButton = {
        let button = NSButton(title: NSLocalizedString("Start Queue", comment: "Gallery"),
                            target: self,
                            action: #selector(toggleQueue(_:)))
        button.bezelStyle = .texturedRounded
        button.isEnabled = false
        return button
    }()
    
    private lazy var buttonStack: NSStackView = {
        let stack = NSStackView(views: [addButton, removeButton, queueButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return stack
    }()
    
    init(delegate: GalleryViewControllerDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        
        // Add subviews
        view.addSubview(scrollView)
        view.addSubview(buttonStack)
        
        // Set up constraints
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor),
            
            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Public Methods
    
    func reloadData() {
        collectionView.reloadData()
        updateButtonStates()
    }
    
    // MARK: - Private Methods
    
    private func updateButtonStates() {
        removeButton.isEnabled = !selectedDocuments.isEmpty
        queueButton.isEnabled = !documents.isEmpty
    }
    
    // MARK: - Actions
    
    @objc private func addFiles(_ sender: Any?) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = [.movie, .mpeg4Movie, .mpeg2Movie, .quickTimeMovie]
        
        openPanel.beginSheetModal(for: view.window!) { [weak self] response in
            guard response == .OK else { return }
            self?.delegate?.galleryViewController(self!, didRequestAddFiles: openPanel.urls)
        }
    }
    
    @objc private func removeFiles(_ sender: Any?) {
        delegate?.galleryViewController(self, didRequestRemove: Array(selectedDocuments))
    }
    
    @objc private func toggleQueue(_ sender: Any?) {
        // Handle queue start/stop
    }
}

// MARK: - NSCollectionViewDataSource

extension GalleryViewController: NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return documents.count
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .galleryItem, for: indexPath) as! GalleryItemView
        let document = documents[indexPath.item]
        item.configure(with: document)
        item.isSelected = selectedDocuments.contains(document)
        return item
    }
}

// MARK: - NSCollectionViewDelegate

extension GalleryViewController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        for indexPath in indexPaths {
            let document = documents[indexPath.item]
            let extendSelection = NSEvent.modifierFlags.contains(.shift)
            delegate?.galleryViewController(self, didSelect: document, extendSelection: extendSelection)
        }
        updateButtonStates()
    }
    
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        for indexPath in indexPaths {
            let document = documents[indexPath.item]
            delegate?.galleryViewController(self, didDeselect: document)
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
    
    private lazy var imageView: NSImageView = {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.masksToBounds = true
        return imageView
    }()
    
    private lazy var titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        return label
    }()
    
    private lazy var subtitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    
    private lazy var stackView: NSStackView = {
        let stack = NSStackView(views: [imageView, titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return stack
    }()
    
    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        
        // Add subviews
        view.addSubview(stackView)
        
        // Set up constraints
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 1.5)
        ])
    }
    
    override var isSelected: Bool {
        didSet {
            view.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.cgColor : nil
        }
    }
    
    func configure(with document: Document) {
        // Configure the item view with document metadata
        if let metadata = document.metadata {
            titleLabel.stringValue = metadata.title ?? ""
            
            if let year = metadata.releaseDate?.year {
                subtitleLabel.stringValue = "\(year)"
            } else if let showName = metadata.tvShowName,
                      let season = metadata.tvSeason,
                      let episode = metadata.tvEpisode {
                subtitleLabel.stringValue = "\(showName) S\(String(format: "%02d", season))E\(String(format: "%02d", episode))"
            } else {
                subtitleLabel.stringValue = ""
            }
            
            // Load artwork
            if let artwork = metadata.artwork {
                imageView.image = NSImage(data: artwork)
            } else {
                imageView.image = NSImage(named: "NSDefaultApplicationIcon")
            }
        }
    }
} 