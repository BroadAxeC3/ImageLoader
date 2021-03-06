//
//  ImageLoader.swift
//  ImageLoader
//
//  MIT License
//
//  Copyright (c) 2017 Mobelux
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

public class ImageLoader {
    private enum Constants {
        static let timeoutInterval: TimeInterval = 60

        // URLSesson won't put things into the cache (memory or disk) if they are > then 5% of the total cache size
        static let memoryCacheSizeMB = 25 * 1024 * 1024
        static let diskCacheSizeMB = 250 * 1024 * 1024
    }

    /// The cache policy to use for an image request.
    /// NOTE: If the device can't reach the internet, the cached image's headers will be ignored and we will return a stale image from the cache (if it exists) no matter the policy specified
    ///
    /// - useCacheIfValid: If the image is in the cache & the cache headers say the image is valid, then use the cache. Else load from server
    /// - forceReload: Forces a reload from the server
    public enum CachePolicy {
        case useCacheIfValid
        case forceReload
    }

    /// Task that allows cancelling of an image load
    public struct LoadingTask {
        /// The URL of the image that is being loaded
        public let url: URL
        private let task: SessionDataTask
        /// Has this task been cancelled
        public private(set) var cancelled: Bool = false

        /// Cancel this image load
        public mutating func cancel() {
            guard !cancelled else { return }
            task.cancel()
            cancelled = true
        }

        fileprivate init(url: URL, task: SessionDataTask) {
            self.url = url
            self.task = task
        }
    }

    public typealias Complete = (_ image: UIImage?, _ fromCache: Bool) -> Void

    static let cache: URLCache = URLCache(memoryCapacity: Constants.memoryCacheSizeMB, diskCapacity: Constants.diskCacheSizeMB, diskPath: "ImageLoader")

    static let sessionConfiguration: URLSessionConfiguration = {
        var configuration = URLSessionConfiguration.default
        configuration.allowsCellularAccess = true
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.urlCache = cache
        return configuration
    }()

    public static let shared: ImageLoader = {
        let session = URLSession(configuration: sessionConfiguration)
        let reachable = Reachability()
        return ImageLoader(session: session, cache: cache, reachable: reachable)
    }()

    private let session: Session
    private let cache: URLCache
    private let reachable: Reachable

    init(session: Session, cache: URLCache, reachable: Reachable) {
        self.session = session
        self.cache = cache
        self.reachable = reachable
    }

    /// Load an image
    ///
    /// - Parameters:
    ///   - url: The URL of the image to load
    ///   - cachePolicy: How to use the cache
    ///   - complete: Called on the main queue once the load completes (not called when the task was cancelled).
    /// - Returns: A `LoadingTask` that you can use to cancel the load at a later time
    public func image(from url: URL, cachePolicy: CachePolicy = .useCacheIfValid, complete: @escaping Complete) -> LoadingTask? {

        let requestCachePolicy = self.cachePolicy(cachePolicy)
        var request = URLRequest(url: url, cachePolicy: requestCachePolicy, timeoutInterval: Constants.timeoutInterval)
        request.httpMethod = "GET"

        if let cachedResponse = cache.cachedResponse(for: request) {
            complete(UIImage(data: cachedResponse.data), true)
            return nil
        } else {
            let task = session.sessionDataTask(with: request) { (data, response, error) in
                if let error = error as NSError?, error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
                    return
                }
                guard let data = data else {
                    DispatchQueue.main.async {
                        complete(nil, false)
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    complete(UIImage(data: data), false)
                }
            }
            
            task.resume()
            return LoadingTask(url: url, task: task)
        }
    }

    private func cachePolicy(_ cachePolicy: CachePolicy) -> URLRequest.CachePolicy {
        let requestCachePolicy: URLRequest.CachePolicy

        if reachable.isReachable {
            switch cachePolicy {
            case .forceReload:
                requestCachePolicy = .reloadRevalidatingCacheData
            case .useCacheIfValid:
                requestCachePolicy = .useProtocolCachePolicy
            }
        } else {
            // By using this policy if we aren't able to hit the server, we will force the system to used even expired cache data. Better to display a stale image then nothing if we can't connect
            requestCachePolicy = .returnCacheDataElseLoad
        }

        return requestCachePolicy
    }
}
