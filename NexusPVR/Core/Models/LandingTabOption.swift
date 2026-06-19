//
//  LandingTabOption.swift
//  nextpvr-apple-client
//
//  Convenience typealias for the landing tab option enum. The canonical
//  definition lives inside `UserPreferences` so the tvOS Top Shelf
//  extension (which only shares `UserPreferences.swift` from the
//  Core/Models folder) keeps compiling without needing this sibling file
//  to also be in its membership list.
//

typealias LandingTabOption = UserPreferences.LandingTabOption
