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
        let url = uniqueURL("unknown")
        #expect(ImageCache.shared.image(for: url) == nil)
    }

    @Test("setImage + image round-trip returns the stored image")
    func setAndGet() {
        let url = uniqueURL("set-get")
        let img = makeImage()
        ImageCache.shared.setImage(img, for: url)
        #expect(ImageCache.shared.image(for: url) != nil)
    }

    @Test("removeImage clears a previously cached entry")
    func removeClears() {
        let url = uniqueURL("remove")
        ImageCache.shared.setImage(makeImage(), for: url)
        #expect(ImageCache.shared.image(for: url) != nil)
        ImageCache.shared.removeImage(for: url)
        #expect(ImageCache.shared.image(for: url) == nil)
    }

    @Test("clearCache removes all previously cached entries")
    func clearWipes() {
        let a = uniqueURL("clear-a")
        let b = uniqueURL("clear-b")
        ImageCache.shared.setImage(makeImage(), for: a)
        ImageCache.shared.setImage(makeImage(), for: b)
        ImageCache.shared.clearCache()
        #expect(ImageCache.shared.image(for: a) == nil)
        #expect(ImageCache.shared.image(for: b) == nil)
    }

    @Test("Different URLs don't collide in the cache")
    func distinctURLsAreSeparate() {
        let a = uniqueURL("distinct-a")
        let b = uniqueURL("distinct-b")
        ImageCache.shared.setImage(makeImage(), for: a)
        #expect(ImageCache.shared.image(for: a) != nil)
        #expect(ImageCache.shared.image(for: b) == nil)
    }
}
