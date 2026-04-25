//
//  ImageCacheTests.swift
//  NexusPVRTests
//
//  Tests for ImageCache's NSLock-guarded NSCache behavior. We exercise the
//  synchronous paths (image(for:), setImage(_:for:), remove, clear) directly
//  to cover the lock/unlock happy path without touching the preload machinery
//  which requires real network.
//

import Testing
import Foundation
@testable import NextPVR

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ImageCacheTests {

    private func makeImage() -> PlatformImage {
        #if canImport(UIKit)
        // 1x1 transparent PNG
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 1, height: 1), false, 1)
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return img
        #elseif canImport(AppKit)
        return NSImage(size: NSSize(width: 1, height: 1))
        #else
        fatalError("Unsupported platform")
        #endif
    }

    private func uniqueURL(_ tag: String) -> URL {
        URL(string: "https://example.com/imagecache-test/\(tag)-\(UUID().uuidString).png")!
    }

    @Test("image(for:) returns nil for an unknown URL")
    func unknownURLReturnsNil() {
        let cache = ImageCache()
        let url = uniqueURL("unknown")
        #expect(cache.image(for: url) == nil)
    }

    @Test("setImage + image round-trip returns the stored image")
    func setAndGet() {
        let cache = ImageCache()
        let url = uniqueURL("set-get")
        let img = makeImage()
        cache.setImage(img, for: url)
        #expect(cache.image(for: url) != nil)
    }

    @Test("removeImage clears a previously cached entry")
    func removeClears() {
        let cache = ImageCache()
        let url = uniqueURL("remove")
        cache.setImage(makeImage(), for: url)
        #expect(cache.image(for: url) != nil)
        cache.removeImage(for: url)
        #expect(cache.image(for: url) == nil)
    }

    @Test("clearCache removes all previously cached entries")
    func clearWipes() {
        let cache = ImageCache()
        let a = uniqueURL("clear-a")
        let b = uniqueURL("clear-b")
        cache.setImage(makeImage(), for: a)
        cache.setImage(makeImage(), for: b)
        cache.clearCache()
        #expect(cache.image(for: a) == nil)
        #expect(cache.image(for: b) == nil)
    }

    @Test("Different URLs don't collide in the cache")
    func distinctURLsAreSeparate() {
        let cache = ImageCache()
        let a = uniqueURL("distinct-a")
        let b = uniqueURL("distinct-b")
        cache.setImage(makeImage(), for: a)
        #expect(cache.image(for: a) != nil)
        #expect(cache.image(for: b) == nil)
    }
}
