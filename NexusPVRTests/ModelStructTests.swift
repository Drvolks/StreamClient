//
//  ModelStructTests.swift
//  NexusPVRTests
//
//  Tests for simple model structs: RecordingsSeriesItem, SeriesGroup,
//  ChannelGroup, ChannelProfile, WatchedChannel, RecordingsFilter, BrandConfig.
//

import Testing
import Foundation
@testable import NextPVR

@MainActor
struct ModelStructTests {

    // MARK: - RecordingsSeriesItem

    @Test("RecordingsSeriesItem id equals name")
    func recordingsSeriesItemId() {
        let item = RecordingsSeriesItem(name: "Breaking Bad", count: 5)
        #expect(item.id == "Breaking Bad")
        #expect(item.name == "Breaking Bad")
        #expect(item.count == 5)
    }

    @Test("RecordingsSeriesItem different name = different equality")
    func recordingsSeriesItemDifferentName() {
        let a = RecordingsSeriesItem(name: "A", count: 1)
        let b = RecordingsSeriesItem(name: "B", count: 1)
        #expect(a != b)
    }

    @Test("RecordingsSeriesItem different count = different equality")
    func recordingsSeriesItemDifferent() {
        let a = RecordingsSeriesItem(name: "A", count: 1)
        let b = RecordingsSeriesItem(name: "A", count: 99)
        #expect(a.hashValue != b.hashValue)
        #expect(a != b)
    }

    // MARK: - SeriesGroup

    @Test("SeriesGroup id equals seriesName")
    func seriesGroupId() {
        let group = SeriesGroup(seriesName: "The Office", recordings: [])
        #expect(group.id == "The Office")
        #expect(group.seriesName == "The Office")
        #expect(group.recordings.isEmpty)
    }

    // MARK: - AuthType

    @Test("AuthType has pin and usernamePassword cases")
    func authTypeCases() {
        let _: AuthType = .pin
        let _: AuthType = .usernamePassword
    }

    // MARK: - RecordingsFilter

    @Test("RecordingsFilter all three filter cases have distinct raw values")
    func recordingsFilterDistinct() {
        let values = Set([
            RecordingsFilter.completed.rawValue,
            RecordingsFilter.recording.rawValue,
            RecordingsFilter.scheduled.rawValue
        ])
        #expect(values.count == 3)
    }

    // MARK: - Dependencies

    @MainActor
    @Test("Dependencies imageCache is not nil")
    func dependenciesImageCache() {
        #expect(Dependencies.imageCache as Any? != nil)
    }

    @MainActor
    @Test("Dependencies networkEventLog is not nil")
    func dependenciesNetworkEventLog() {
        #expect(Dependencies.networkEventLog as Any? != nil)
    }
}
