//
//  ProgramDetail.swift
//  nextpvr-apple-client
//
//  A program and its channel, as presented in the detail sheet or selected
//  in the macOS guide.
//

struct ProgramDetail: Identifiable {
    var id: Int { program.id }
    let program: Program
    let channel: Channel
}
