//
//  TopicKeywordStoreTests.swift
//  NexusPVRTests
//
//  Topic keywords kept one timestamped entry per keyword, so edits made on
//  two devices at once merge instead of one list replacing the other.
//

import Testing
import Foundation
@testable import NextPVR

struct TopicKeywordStoreTests {

    private func scratchDefaults() -> UserDefaults {
        let suite = "TopicKeywordStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }

    private func store(_ list: [String], at seconds: TimeInterval = 0) -> TopicKeywordStore {
        var store = TopicKeywordStore()
        store.setKeywords(list, at: date(seconds))
        return store
    }

    // MARK: - Editing

    @Test("The list keeps its order")
    func order() {
        #expect(store(["Hockey", "News", "Cooking"]).keywords == ["Hockey", "News", "Cooking"])
    }

    @Test("Blank and duplicate keywords are ignored, whatever their case")
    func duplicates() {
        #expect(store(["Hockey", " ", "hockey", "News"]).keywords == ["Hockey", "News"])
    }

    @Test("A removed keyword stays as an entry")
    func removalIsAnEntry() {
        var topics = store(["Hockey", "News"])
        topics.remove("news", at: date(10))
        #expect(topics.keywords == ["Hockey"])
        #expect(topics.entryCount == 2)
        #expect(topics.entries["news"]?.isRemoved == true)
    }

    @Test("Only the edited keywords get a new timestamp")
    func onlyEditedKeywordsAreStamped() {
        var topics = store(["A", "B", "C"])
        topics.move("C", by: -1, at: date(10))
        #expect(topics.keywords == ["A", "C", "B"])
        #expect(topics.entries["a"]?.updatedAt == date(0))
        #expect(topics.entries["b"]?.updatedAt == date(10))
        #expect(topics.entries["c"]?.updatedAt == date(10))
    }

    @Test("Adding a removed keyword back brings it back")
    func reAdd() {
        var topics = store(["Hockey"])
        topics.remove("Hockey", at: date(10))
        topics.add("HOCKEY", at: date(20))
        #expect(topics.keywords == ["HOCKEY"])
    }

    // MARK: - Merging

    @Test("Keywords added on two devices at once both survive")
    func concurrentAdds() {
        var phone = store(["Hockey"])
        var tv = phone
        phone.add("News", at: date(10))
        tv.add("Cooking", at: date(20))

        var merged = phone
        merged.merge(tv)

        #expect(Set(merged.keywords) == ["Hockey", "News", "Cooking"])
    }

    @Test("A removal wins over an older copy of the keyword, and loses to a newer one")
    func removalVersusAdd() {
        var phone = store(["Hockey", "News"])
        let older = phone
        phone.remove("News", at: date(10))

        var merged = older
        merged.merge(phone)
        #expect(merged.keywords == ["Hockey"])

        var tv = older
        tv.setKeywords(["Hockey", "News"], at: date(20))   // unchanged: no new timestamp
        tv.remove("News", at: date(20))
        tv.add("News", at: date(30))
        merged.merge(tv)
        #expect(merged.keywords.contains("News"))
    }

    @Test("Merging is the same in either direction")
    func mergeIsSymmetric() {
        var a = store(["Hockey", "News"])
        a.add("Tennis", at: date(5))
        var b = TopicKeywordStore()
        b.setKeywords(["hockey", "Cooking"], at: date(5))

        var ab = a
        ab.merge(b)
        var ba = b
        ba.merge(a)

        #expect(ab == ba)
    }

    // MARK: - Size

    @Test("Removed keywords are dropped before current ones")
    func keepNewestDropsRemovalsFirst() {
        var topics = store(["A", "B", "C"])
        topics.remove("A", at: date(100))
        topics.keepNewest(2)
        #expect(topics.keywords == ["B", "C"])
        #expect(topics.entries["a"] == nil)
    }

    // MARK: - Legacy import and storage

    @Test("Keywords from the preferences are imported once, dated 1970")
    func legacyImport() {
        let defaults = scratchDefaults()
        let first = TopicKeywordStore.load(from: defaults, cloudData: nil, legacyKeywords: { ["Hockey", "News"] })
        #expect(first.keywords == ["Hockey", "News"])
        #expect(first.entries["hockey"]?.updatedAt == TopicKeywordStore.legacyDate)

        let second = TopicKeywordStore.load(from: defaults, cloudData: nil, legacyKeywords: { ["Ignored"] })
        #expect(second.keywords == ["Hockey", "News"])
    }

    @Test("An imported keyword another device already removed stays removed")
    func legacyImportLosesToRemoval() throws {
        var cloud = TopicKeywordStore()
        cloud.importLegacy(["Hockey", "News"])
        cloud.remove("News", at: date(10))

        let store = TopicKeywordStore.load(
            from: scratchDefaults(), cloudData: cloud.encoded, legacyKeywords: { ["Hockey", "News"] }
        )

        #expect(store.keywords == ["Hockey"])
    }

    @Test("Reconciling reports what changed on each side")
    func reconcile() {
        let defaults = scratchDefaults()
        store(["Hockey"]).saveLocally(to: defaults)
        defaults.set(true, forKey: TopicKeywordStore.legacyImportedKey)
        var cloud = store(["Hockey"])
        cloud.add("News", at: date(10))

        let result = TopicKeywordStore.reconcile(defaults: defaults, cloudData: cloud.encoded, legacyKeywords: { [] })

        #expect(result.store.keywords == ["Hockey", "News"])
        #expect(result.localChanged)
        #expect(!result.cloudIsBehind)
    }

    @Test("The server format round-trips unchanged")
    func serverRoundTrip() throws {
        var topics = store(["Hockey", "News"])
        topics.remove("News", at: Date())
        let data = try #require(DispatcharrAppData.encode(topics))
        #expect(DispatcharrAppData.decode(TopicKeywordStore.self, from: data) == topics)
    }
}
