//
//  ChapterSearchController.swift
//  Subler
//
//  Created by Damiano Galassi on 31/07/2017.
//

import Cocoa
import MP42Foundation

protocol ChapterSearchControllerDelegate : AnyObject {
    func didSelect(chapters: [MP42TextSample])
}

final class ChapterSearchController: ViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {

    @IBOutlet var searchTitle: NSTextField!

    @IBOutlet var resultsTable: NSTableView!
    @IBOutlet var chapterTable: NSTableView!

    @IBOutlet var searchButton: NSButton!
    @IBOutlet var addButton: NSButton!

    @IBOutlet var progress: NSProgressIndicator!
    @IBOutlet var progressText: NSTextField!

    private enum ChapterSearchState {
        case none
        case searching(task: Runnable)
        case completed(results: [ChapterResult], selectedResult: ChapterResult)
    }

    private weak var delegate: ChapterSearchControllerDelegate?
    private let duration: UInt64
    private let searchTerm: String
    private var state: ChapterSearchState
    private var loadedChapters: [UInt64: [Chapter]] = [:] // Track loaded chapters by result ID
    private let scraper = ChapterDBWebScraper() // Keep reference to scraper for lazy loading

    init(delegate: ChapterSearchControllerDelegate, title: String, duration: UInt64) {
        print("ChapterSearchController: init called with title: '\(title)', duration: \(duration)")
        
        let info = title.parsedAsFilename()
        print("ChapterSearchController: parsed filename info: \(info)")

        switch info {

        case .movie(let title):
            searchTerm = title
            print("ChapterSearchController: extracted movie title: '\(title)'")
        case .tvShow, .none:
            searchTerm = title
            print("ChapterSearchController: using original title: '\(title)'")
        }

        self.delegate = delegate
        self.duration = duration
        self.state = .none

        super.init(nibName: nil, bundle: nil)

        self.autosave = "ChapterSearchControllerAutosaveIdentifier"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        resultsTable.delegate = nil
        resultsTable.dataSource = nil
        chapterTable.delegate = nil
        chapterTable.dataSource = nil
    }

    override var nibName: NSNib.Name? {
        return "SBChapterSearch"
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        print("ChapterSearchController: viewDidLoad - setting searchTitle to: '\(searchTerm)'")
        self.searchTitle.stringValue = searchTerm
        self.view.window?.makeFirstResponder(self.searchTitle)

        updateUI()

        if searchTerm.isEmpty == false { searchForResults(self) }
    }

    private func searchDone(results: [ChapterResult]) {
        DispatchQueue.main.async {
            if let first = results.first {
                self.state = .completed(results: results, selectedResult: first)
                
                // Load chapters for the first result immediately
                self.loadChaptersForResult(first)
            }
            else {
                self.state = .none
            }
            self.updateUI()
        }
    }

    @IBAction func searchForResults(_ sender: Any) {
        print("ChapterSearchController: searchForResults called with title: \(searchTitle.stringValue), duration: \(duration)")
        
        switch state {
        case .none, .completed:
            break
        case .searching(let task):
            task.cancel()
        }
        
        let task = ChapterSearch.movieSeach(service: scraper, title: searchTitle.stringValue, duration: duration)
                                .search(completionHandler: searchDone).runAsync()
        print("ChapterSearchController: Created task with service type: \(type(of: scraper))")
        
        // Test the scraper directly
        print("ChapterSearchController: Testing scraper directly...")
        print("ChapterSearchController: scraper type: \(type(of: scraper))")
        let testResults = scraper.search(title: searchTitle.stringValue, duration: duration)
        print("ChapterSearchController: Direct test returned \(testResults.count) results")
        
        state = .searching(task: task)
        updateUI()
    }

    @IBAction func addChapter(_ sender: Any) {
        switch state {
        case .completed(_, let result):
            guard let chapters = loadedChapters[result.id] else {
                print("ChapterSearchController: No chapters loaded for result ID: \(result.id)")
                return
            }
            
            var textChapters: [MP42TextSample] = []
            for chapter in chapters {
                let sample = MP42TextSample()
                sample.timestamp = chapter.timestamp
                sample.title = chapter.name
                textChapters.append(sample)
            }
            delegate?.didSelect(chapters: textChapters)
        default:
            break
        }
        presentingViewController?.dismiss(self)
    }

    @IBAction func closeWindow(_ sender: Any) {
        switch state {
        case .searching(let task):
            task.cancel()
        default:
            break
        }
        presentingViewController?.dismiss(self)
    }

    // MARK - UI state

    private func startProgressReport() {
        progress.startAnimation(self)
        progress.isHidden = false
        progressText.stringValue = NSLocalizedString("Searching for chapter information…", comment: "ChapterDB")
        progressText.isHidden = false
    }

    private func stopProgressReport() {
        progress.stopAnimation(self)
        progress.isHidden = true
        progressText.isHidden = true
    }

    private func reloadTableData() {
        resultsTable.reloadData()
        chapterTable.reloadData()
    }

    private func swithDefaultButton(from oldDefault: NSButton, to newDefault: NSButton, disableOldButton: Bool) {
        oldDefault.keyEquivalent = ""
        oldDefault.isEnabled = !disableOldButton
        newDefault.keyEquivalent = "\r"
        newDefault.isEnabled = true
    }

    private func updateUI() {
        switch state {
        case .none:
            stopProgressReport()
            reloadTableData()
            swithDefaultButton(from: addButton, to: searchButton, disableOldButton: true)
            updateSearchButtonVisibility()
        case .searching:
            startProgressReport()
            reloadTableData()
            swithDefaultButton(from: addButton, to: searchButton, disableOldButton: true)
        case .completed:
            stopProgressReport()
            reloadTableData()
            swithDefaultButton(from: searchButton, to: addButton, disableOldButton: false)
            view.window?.makeFirstResponder(resultsTable)
        }
    }

    private func updateSearchButtonVisibility() {
        searchButton.isEnabled = searchTitle.stringValue.isEmpty ? false : true
    }

    func controlTextDidChange(_ obj: Notification) {
        updateSearchButtonVisibility()
        searchButton.keyEquivalent = "\r"
        addButton.keyEquivalent = ""
    }

    // MARK: - Table View

    func tableViewSelectionDidChange(_ notification: Notification) {
        if notification.object as? NSTableView == resultsTable {
            switch state {
            case .none, .searching:
                break
            case .completed(let results, _):
                let selectedRow = resultsTable.selectedRow
                guard selectedRow >= 0 && selectedRow < results.count else { return }
                
                let selectedResult = results[selectedRow]
                state = .completed(results: results, selectedResult: selectedResult)
                
                // Load chapters for the selected result if not already loaded
                loadChaptersForResult(selectedResult)
                
                chapterTable.reloadData()
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == resultsTable {
            switch state {
            case .completed(let results, _):
                return results.count
            default:
                break
            }
        }
        else if tableView == chapterTable {
            switch state {
            case .completed(_, let result):
                // Check if chapters are loaded for this result
                if let chapters = loadedChapters[result.id] {
                    return chapters.count
                } else {
                    // Chapters not loaded yet, return 0
                    return 0
                }
            default:
                break
            }
        }
        return 0
    }

    private let titleCell = NSUserInterfaceItemIdentifier(rawValue: "titleCell")
    private let chapterCountCell = NSUserInterfaceItemIdentifier(rawValue: "chapterCountCell")
    private let durationCell = NSUserInterfaceItemIdentifier(rawValue: "durationCell")
    private let confirmationsCell = NSUserInterfaceItemIdentifier(rawValue: "confirmationsCell")

    private let timeCell = NSUserInterfaceItemIdentifier(rawValue: "timeCell")
    private let nameCell = NSUserInterfaceItemIdentifier(rawValue: "nameCell")

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == resultsTable {
            switch state {
            case .completed(let results, _):
                let result = results[row]

                if tableColumn?.identifier.rawValue == "title" {
                    let cell = tableView.makeView(withIdentifier: titleCell, owner:self) as? NSTableCellView
                    cell?.textField?.stringValue = result.title
                    return cell
                }
                else if tableColumn?.identifier.rawValue == "chaptercount" {
                    let cell = tableView.makeView(withIdentifier: titleCell, owner:self) as? NSTableCellView
                    cell?.textField?.attributedStringValue = "\(result.chapters.count)".smallMonospacedAttributedString()
                    return cell
                }
                else if tableColumn?.identifier.rawValue == "duration" {
                    let cell = tableView.makeView(withIdentifier: durationCell, owner:self) as? NSTableCellView
                    cell?.textField?.attributedStringValue = StringFromTime(Int64(result.duration), 1000).smallMonospacedAttributedString()
                    return cell
                }
                else if tableColumn?.identifier.rawValue == "confirmations" {
                    let cell = tableView.makeView(withIdentifier: confirmationsCell, owner:self) as? LevelIndicatorTableCellView
                    cell?.indicator.intValue = Int32(result.confimations)
                    return cell
                }
            default:
                break
            }
        }
        else if tableView == chapterTable {
            switch state {
            case .completed(_, let result):
                // Get chapters from loaded dictionary
                guard let chapters = loadedChapters[result.id],
                      row < chapters.count else {
                    return nil
                }
                
                let chapter = chapters[row]
                if tableColumn?.identifier.rawValue == "time" {
                    let cell = tableView.makeView(withIdentifier: timeCell, owner:self) as? NSTableCellView
                    cell?.textField?.attributedStringValue = StringFromTime(Int64(chapter.timestamp), 1000).boldMonospacedAttributedString()
                    return cell
                }
                else if tableColumn?.identifier.rawValue == "name" {
                    let cell = tableView.makeView(withIdentifier: nameCell, owner:self) as? NSTableCellView
                    cell?.textField?.stringValue = chapter.name
                    return cell
                }
            default:
                break
            }
        }
        return nil
    }

    // MARK: - Lazy Loading
    
    private func loadChaptersForResult(_ result: ChapterResult) {
        // Check if chapters are already loaded
        if loadedChapters[result.id] != nil {
            print("ChapterSearchController: Chapters already loaded for result ID: \(result.id)")
            return
        }
        
        print("ChapterSearchController: Loading chapters for result ID: \(result.id)")
        
        // Show loading state
        progressText.stringValue = NSLocalizedString("Loading chapters…", comment: "ChapterDB")
        progressText.isHidden = false
        
        scraper.loadChapters(for: result) { [weak self] chapters in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                print("ChapterSearchController: Loaded \(chapters.count) chapters for result ID: \(result.id)")
                self.loadedChapters[result.id] = chapters
                
                // Update the selected result with loaded chapters
                if case .completed(let results, let selectedResult) = self.state,
                   selectedResult.id == result.id {
                    // Create a new result with loaded chapters
                    let updatedResult = ChapterResult(
                        title: selectedResult.title,
                        duration: selectedResult.duration,
                        id: selectedResult.id,
                        confimations: selectedResult.confimations,
                        chapters: chapters
                    )
                    self.state = .completed(results: results, selectedResult: updatedResult)
                    self.chapterTable.reloadData()
                }
                
                // Hide loading state
                self.progressText.isHidden = true
            }
        }
    }

}

/// A NSTableCellView that contains a single level indicator.
class LevelIndicatorTableCellView: NSTableCellView {
    @IBOutlet var indicator: NSLevelIndicator!
}
