//
//  DispatcharrNoRedirectDelegate.swift
//  DispatcherPVR
//
//  Hands a redirect back to the caller instead of following it, so the
//  client can read the HLS session token off Dispatcharr's redirect (#193).
//

import Foundation

nonisolated final class DispatcharrNoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    // The completion-handler form: the async one crashes the Swift compiler
    // (ASTLoweringRequest) in this target.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
