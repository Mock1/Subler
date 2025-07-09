//
//  ChapterDBWebScraper.swift
//  Subler
//
//  Created by Michael Mock on 07/03/2025.
//  New implementation to use web scraping instead of deprecated API
//

import Foundation
import MP42Foundation

extension String {
    func matches(pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: self.utf16.count)
        return regex.firstMatch(in: self, range: range) != nil
    }
}

public struct ChapterDBWebScraper : ChapterService {

    private let baseURL = "https://chapterdb.plex.tv"
    private let searchPath = "/grid"
    
    public init() {
        print("ChapterDBWebScraper: init() called")
        print("ChapterDBWebScraper: baseURL = \(baseURL)")
        print("ChapterDBWebScraper: searchPath = \(searchPath)")
    }

    public func search(title: String, duration: UInt64) -> [ChapterResult] {
        print("ChapterDBWebScraper: search() called with title: '\(title)', duration: \(duration)")
        print("ChapterDBWebScraper: About to start search logic...")
        
        // Create search URL
        let encodedTitle = title.urlEncoded()
        let searchURL = "\(baseURL)\(searchPath)?Title=\(encodedTitle)"
        
        print("ChapterDBWebScraper: Searching for '\(title)' at URL: \(searchURL)")
        
        guard let url = URL(string: searchURL) else {
            print("ChapterDBWebScraper: Invalid URL")
            return []
        }
        
        print("ChapterDBWebScraper: URL is valid, fetching data...")
        
        // First, test with a simple request to httpbin.org to verify network connectivity
        print("ChapterDBWebScraper: Testing network connectivity...")
        if let testURL = URL(string: "https://httpbin.org/get"),
           let testData = fetch(url: testURL) {
            print("ChapterDBWebScraper: Network test successful, got \(testData.count) bytes")
        } else {
            print("ChapterDBWebScraper: Network test failed")
        }
        
        guard let data = fetch(url: url),
              let htmlString = String(data: data, encoding: .utf8) else {
            print("ChapterDBWebScraper: Failed to fetch or decode data from ChapterDB")
            return []
        }
        
        print("ChapterDBWebScraper: Successfully fetched \(data.count) bytes from ChapterDB")
        print("ChapterDBWebScraper: HTML length: \(htmlString.count) characters")
        
        // Parse search results
        let searchResults = parseSearchResults(html: htmlString)
        
        print("ChapterDBWebScraper: Parsed \(searchResults.count) search results")
        
        // Filter by duration if we have a valid duration
        let delta: Int64 = 20000 // 20 seconds tolerance
        let filteredResults = searchResults.filter { result in
            if duration > 0 {
                return result.duration < (Int64(duration) + delta) && result.duration > (Int64(duration) - delta)
            }
            return true
        }
        
        print("ChapterDBWebScraper: After duration filtering: \(filteredResults.count) results")
        
        // If we have duration-filtered results, return those; otherwise return all results
        if duration > 0 && !filteredResults.isEmpty {
            return filteredResults
        } else {
            return searchResults
        }
    }
    
    private func fetch(url: URL) -> Data? {
        let header = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"]
        return URLSession.data(from: url, header: header)
    }
    
    private func parseSearchResults(html: String) -> [ChapterResult] {
        var results: [ChapterResult] = []
        let lines = html.components(separatedBy: .newlines)
        var insideRow = false
        var currentRow: [String] = []
        
        print("ChapterDBWebScraper: parseSearchResults - Processing \(lines.count) lines")
        
        for line in lines {
            if line.contains("<tr>") {
                insideRow = true
                currentRow = []
            } else if line.contains("</tr>") && insideRow {
                insideRow = false
                // Process the collected row
                if let result = parseSearchResultFromManualRow(currentRow) {
                    print("ChapterDBWebScraper: Successfully parsed result: \(result.title)")
                    results.append(result)
                }
            } else if insideRow {
                currentRow.append(line)
            }
        }
        print("ChapterDBWebScraper: Finished parsing, found \(results.count) results")
        return results
    }

    private func parseSearchResultsManually(html: String) -> [ChapterResult] {
        var results: [ChapterResult] = []
        let lines = html.components(separatedBy: .newlines)
        var currentRow: [String] = []
        var insideRow = false

        for line in lines {
            if line.contains("<tr>") {
                insideRow = true
                currentRow = []
            } else if line.contains("</tr>") && insideRow {
                insideRow = false
                // Process the collected row
                if let result = parseSearchResultFromManualRow(currentRow) {
                    print("ChapterDBWebScraper: Successfully parsed result: \(result.title)")
                    results.append(result)
                }
            } else if insideRow {
                currentRow.append(line)
            }
        }
        print("ChapterDBWebScraper: Finished parsing, found \(results.count) results")
        return results
    }

    private func parseSearchResultFromManualRow(_ rowLines: [String]) -> ChapterResult? {
        print("ChapterDBWebScraper: Parsing row with \(rowLines.count) lines")
        print("ChapterDBWebScraper: Row content:")
        for (index, line) in rowLines.enumerated() {
            print("ChapterDBWebScraper:   Line \(index): \(line)")
        }
        
        // Look for the <a href="/browse/ID">Title</a> cell
        guard let browseLine = rowLines.first(where: { $0.contains("/browse/") }),
              let idMatch = browseLine.range(of: "/browse/(\\d+)", options: .regularExpression),
              let idString = browseLine[idMatch].components(separatedBy: "/").last,
              let id = UInt64(idString) else {
            print("ChapterDBWebScraper: Could not extract ID from browse line")
            return nil
        }
        
        // Extract title
        let titleRegex = try! NSRegularExpression(pattern: ">([^<]+)</a>")
        let nsLine = browseLine as NSString
        let titleMatch = titleRegex.firstMatch(in: browseLine, range: NSRange(location: 0, length: nsLine.length))
        let title = titleMatch.map { nsLine.substring(with: $0.range(at: 1)) } ?? "Unknown"
        
        print("ChapterDBWebScraper: Extracted title: \(title), ID: \(id)")
        
        // Extract confirmations (first column - Matches)
        var confirmations: UInt = 1
        print("ChapterDBWebScraper: Looking for confirmations in row lines...")
        for (index, line) in rowLines.enumerated() {
            if line.contains("<span") && line.contains("ui small label") {
                print("ChapterDBWebScraper:   Checking line \(index) for confirmations: \(line)")
                let confirmationsRegex = try! NSRegularExpression(pattern: ">\\s*(\\d+)\\s*<")
                let nsConfirmationsLine = line as NSString
                if let confirmationsMatch = confirmationsRegex.firstMatch(in: line, range: NSRange(location: 0, length: nsConfirmationsLine.length)) {
                    let confirmationsString = nsConfirmationsLine.substring(with: confirmationsMatch.range(at: 1))
                    confirmations = UInt(confirmationsString) ?? 1
                    print("ChapterDBWebScraper: Extracted confirmations: \(confirmations) from line \(index)")
                    break
                }
            }
        }
        
        // Extract duration (fourth column)
        var duration: UInt64 = 0
        var durationFound = false
        print("ChapterDBWebScraper: Looking for duration in row lines...")
        for (index, line) in rowLines.enumerated() {
            if line.contains("<td") && line.contains("</td>") && !line.contains("/browse/") && !durationFound {
                print("ChapterDBWebScraper:   Checking line \(index) for duration: \(line)")
                // Look for duration pattern like "02:03.07" or "02:03:07"
                let durationPattern = "(\\d{1,2}):(\\d{2})\\.(\\d{2})"
                if let regex = try? NSRegularExpression(pattern: durationPattern),
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    let nsString = line as NSString
                    let hours = Int(nsString.substring(with: match.range(at: 1))) ?? 0
                    let minutes = Int(nsString.substring(with: match.range(at: 2))) ?? 0
                    let seconds = Int(nsString.substring(with: match.range(at: 3))) ?? 0
                    
                    duration = UInt64((hours * 3600 + minutes * 60 + seconds) * 1000) // Convert to milliseconds
                    durationFound = true
                    print("ChapterDBWebScraper: Extracted duration: \(hours):\(minutes):\(seconds) (\(duration) ms) from line \(index)")
                    break
                }
            }
        }
        
        if !durationFound {
            print("ChapterDBWebScraper: Could not extract duration, using 0")
        }

        // Create ChapterResult with empty chapters - chapters will be loaded on demand
        print("ChapterDBWebScraper: Creating ChapterResult with lazy-loaded chapters")
        return ChapterResult(title: title, duration: duration, id: id, confimations: confirmations, chapters: [])
    }
    
    private func parseDuration(from line: String) -> UInt64 {
        // Look for duration pattern like "02:16.17" or "02:16:17"
        let durationPattern = "(\\d{1,2}):(\\d{2})\\.?(\\d{2})"
        
        guard let regex = try? NSRegularExpression(pattern: durationPattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return 0
        }
        
        let nsString = line as NSString
        let hours = Int(nsString.substring(with: match.range(at: 1))) ?? 0
        let minutes = Int(nsString.substring(with: match.range(at: 2))) ?? 0
        let seconds = Int(nsString.substring(with: match.range(at: 3))) ?? 0
        
        return UInt64((hours * 3600 + minutes * 60 + seconds) * 1000) // Convert to milliseconds
    }
    
    private func fetchChapterDetails(id: UInt64) -> [Chapter]? {
        let detailURL = "\(baseURL)/browse/\(id)"
        
        guard let url = URL(string: detailURL),
              let data = fetch(url: url),
              let htmlString = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return parseChapterDetails(html: htmlString)
    }
    
    private func parseChapterDetails(html: String) -> [Chapter]? {
        var chapters: [Chapter] = []
        
        print("ChapterDBWebScraper: parseChapterDetails - Using manual parsing")
        
        // Look for the chapter table
        let lines = html.components(separatedBy: .newlines)
        var insideTable = false
        var insideRow = false
        var currentRow: [String] = []
        var rowCount = 0
        
        for (lineIndex, line) in lines.enumerated() {
            // Try multiple table patterns
            if line.contains("<table") && (line.contains("ui table") || line.contains("striped") || line.contains("fluid")) {
                print("ChapterDBWebScraper: Found potential chapter table at line \(lineIndex): \(line)")
                insideTable = true
            } else if line.contains("</table>") && insideTable {
                print("ChapterDBWebScraper: End of chapter table at line \(lineIndex)")
                insideTable = false
                break
            } else if insideTable {
                if line.contains("<tr>") {
                    insideRow = true
                    currentRow = []
                    rowCount += 1
                    print("ChapterDBWebScraper: Starting row \(rowCount) at line \(lineIndex)")
                } else if line.contains("</tr>") && insideRow {
                    insideRow = false
                    print("ChapterDBWebScraper: Ending row \(rowCount) with \(currentRow.count) lines")
                    // Process the collected row
                    if let chapter = parseChapterFromRow(currentRow) {
                        print("ChapterDBWebScraper: Successfully parsed chapter: \(chapter.name) at \(chapter.timestamp)")
                        chapters.append(chapter)
                    } else {
                        print("ChapterDBWebScraper: Failed to parse chapter from row \(rowCount)")
                        print("ChapterDBWebScraper: Row content:")
                        for (i, rowLine) in currentRow.enumerated() {
                            print("ChapterDBWebScraper:   Line \(i): \(rowLine)")
                        }
                    }
                } else if insideRow {
                    currentRow.append(line)
                }
            }
        }
        
        print("ChapterDBWebScraper: parseChapterDetails - Found \(chapters.count) chapters")
        return chapters.isEmpty ? nil : chapters
    }
    
    private func parseChapterFromRow(_ rowLines: [String]) -> Chapter? {
        var chapterNumber = 0
        var chapterName = ""
        var timestamp: UInt64 = 0
        var tdCount = 0
        
        print("ChapterDBWebScraper: parseChapterFromRow - Processing \(rowLines.count) lines")
        
        for (lineIndex, line) in rowLines.enumerated() {
            print("ChapterDBWebScraper:   Line \(lineIndex): \(line)")
            
            if line.contains("<td") && line.contains("</td>") {
                tdCount += 1
                print("ChapterDBWebScraper:   Found <td> element #\(tdCount)")
                
                if tdCount == 1 { // First <td> - chapter number
                    // Extract the number between <td> and </td>
                    if let startRange = line.range(of: ">"),
                       let endRange = line.range(of: "</td>") {
                        let contentStart = line.index(startRange.upperBound, offsetBy: 0)
                        let content = String(line[contentStart..<endRange.lowerBound])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        chapterNumber = Int(content) ?? 0
                        print("ChapterDBWebScraper:   Extracted chapter number: \(chapterNumber)")
                    }
                } else if tdCount == 2 { // Second <td> - chapter name
                    // Extract the content between <td> and </td>
                    if let startRange = line.range(of: ">"),
                       let endRange = line.range(of: "</td>") {
                        let contentStart = line.index(startRange.upperBound, offsetBy: 0)
                        let content = String(line[contentStart..<endRange.lowerBound])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "&nbsp;", with: " ")
                            .replacingOccurrences(of: "&amp;", with: "&")
                            .replacingOccurrences(of: "&lt;", with: "<")
                            .replacingOccurrences(of: "&gt;", with: ">")
                            .replacingOccurrences(of: "&quot;", with: "\"")
                            .replacingOccurrences(of: "&#39;", with: "'")
                        
                        chapterName = content
                        print("ChapterDBWebScraper:   Extracted chapter name: '\(chapterName)'")
                    }
                } else if tdCount == 3 { // Third <td> - timestamp
                    // Extract time pattern like "00:07:48.4262888"
                    let timePattern = "(\\d{1,2}):(\\d{2}):(\\d{2})\\.?(\\d*)"
                    if let regex = try? NSRegularExpression(pattern: timePattern),
                       let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                        let nsString = line as NSString
                        let hours = Int(nsString.substring(with: match.range(at: 1))) ?? 0
                        let minutes = Int(nsString.substring(with: match.range(at: 2))) ?? 0
                        let seconds = Int(nsString.substring(with: match.range(at: 3))) ?? 0
                        
                        timestamp = UInt64((hours * 3600 + minutes * 60 + seconds) * 1000)
                        print("ChapterDBWebScraper:   Extracted timestamp: \(hours):\(minutes):\(seconds) (\(timestamp) ms)")
                    } else {
                        print("ChapterDBWebScraper:   Failed to extract timestamp from: \(line)")
                    }
                }
            }
        }
        
        // If chapter name is empty, use "Chapter {number}" format
        if chapterName.isEmpty && chapterNumber > 0 {
            chapterName = String(format: "Chapter %02d", chapterNumber)
            print("ChapterDBWebScraper:   Using fallback chapter name: '\(chapterName)'")
        }
        
        print("ChapterDBWebScraper:   Final values - number: \(chapterNumber), name: '\(chapterName)', timestamp: \(timestamp)")
        
        // Only return a chapter if we found a valid chapter number and non-negative timestamp
        let isValid = (chapterNumber >= 0 && timestamp >= 0)
        print("ChapterDBWebScraper:   Is valid: \(isValid)")
        
        return isValid ? Chapter(name: chapterName, timestamp: timestamp) : nil
    }
    
    private func extractTitleFromColumn(_ column: String) -> String {
        // Extract title from format: [Title](/browse/ID)
        if let startBracket = column.range(of: "["),
           let endBracket = column.range(of: "]") {
            return String(column[startBracket.upperBound..<endBracket.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "Unknown Title"
    }
    
    private func createBasicChapters() -> [Chapter] {
        // Create basic chapters every 10 minutes as a fallback
        var chapters: [Chapter] = []
        let chapterInterval: UInt64 = 10 * 60 * 1000 // 10 minutes in milliseconds
        
        for i in 1...10 {
            let timestamp = UInt64(i) * chapterInterval
            let chapter = Chapter(name: "Chapter \(i)", timestamp: timestamp)
            chapters.append(chapter)
        }
        
        return chapters
    }
    
    // MARK: - Lazy Loading Support
    
    public func loadChapters(for result: ChapterResult, completion: @escaping ([Chapter]) -> Void) {
        print("ChapterDBWebScraper: loadChapters called for result ID: \(result.id)")
        
        // Load chapters in background
        DispatchQueue.global(qos: .userInitiated).async {
            let chapters = self.fetchChapterDetails(id: result.id) ?? []
            print("ChapterDBWebScraper: Loaded \(chapters.count) chapters for result ID: \(result.id)")
            
            DispatchQueue.main.async {
                completion(chapters)
            }
        }
    }
    

} 