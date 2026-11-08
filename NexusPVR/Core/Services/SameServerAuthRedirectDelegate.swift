//
//  SameServerAuthRedirectDelegate.swift
//  nextpvr-apple-client
//
//  Follows a redirect with the original auth headers when it stays on the
//  same server. URLSession drops `Authorization` when it follows a redirect,
//  so Dispatcharr's `/recordings/<id>/file/` → `/hls/index.m3u8` hop (a
//  recording whose MKV was never written) otherwise arrives with no
//  credentials and gets a 403.
//

import Foundation

nonisolated final class SameServerAuthRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let headers: [String: String]

    init(headers: [String: String]) {
        self.headers = headers
    }

    // The completion-handler form, like DispatcharrNoRedirectDelegate: the
    // async one crashes the Swift compiler in this target.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(Self.redirect(request, from: task.originalRequest?.url, headers: headers))
    }

    /// The redirected request, with `headers` added back when it goes to the
    /// same scheme, host and port as `original`. Never sends them elsewhere.
    static func redirect(_ request: URLRequest, from original: URL?, headers: [String: String]) -> URLRequest {
        guard let original, let target = request.url,
              original.scheme?.lowercased() == target.scheme?.lowercased(),
              original.host?.lowercased() == target.host?.lowercased(),
              original.port == target.port else { return request }
        var redirected = request
        for (field, value) in headers where redirected.value(forHTTPHeaderField: field) == nil {
            redirected.setValue(value, forHTTPHeaderField: field)
        }
        return redirected
    }
}
