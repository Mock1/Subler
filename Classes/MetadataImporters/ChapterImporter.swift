//
//  ChapterImporter.swift
//  Subler
//
//  Created by Damiano Galassi on 31/07/2017.
//

import Foundation

public protocol ChapterService {
    func search(title: String, duration: UInt64) -> [ChapterResult]
}

public enum ChapterSearch {
    case movieSeach(service: ChapterService, title: String, duration: UInt64)

    public func search(completionHandler: @escaping ([ChapterResult]) -> Void) -> Runnable {
        switch self {
        case let .movieSeach(service, title, duration):
            print("ChapterSearch: movieSeach called with title: '\(title)', duration: \(duration)")
            let task = RunnableTask(search: {
                print("ChapterSearch: About to call service.search")
                let results = service.search(title: title, duration: duration)
                print("ChapterSearch: service.search returned \(results.count) results")
                return results
            }, completionHandler: { results in
                print("ChapterSearch: completionHandler called with \(results().count) results")
                completionHandler(results())
            })
            return task
        }
    }
}
