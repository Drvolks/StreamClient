//
//  VODCategoryPicker.swift
//  DispatcherPVR
//
//  The On Demand category menu (#17). Equatable, and used through
//  `.equatable()`: the index re-renders on every `AppState` change (the
//  10-second activity polls among them), and rebuilding an open menu sends
//  its list back to the top.
//

#if DISPATCHERPVR
import SwiftUI

struct VODCategoryPicker: View, Equatable {
    let categories: [VODCategory]
    let selection: VODCategory?
    let onSelect: (VODCategory?) -> Void

    #if os(tvOS)
    @State private var isChoosing = false
    #endif

    nonisolated static func == (lhs: VODCategoryPicker, rhs: VODCategoryPicker) -> Bool {
        lhs.categories == rhs.categories && lhs.selection == rhs.selection
    }

    var body: some View {
        #if os(tvOS)
        Button {
            isChoosing = true
        } label: {
            TVMidnightOutlineLabel(
                title: selection?.name ?? "All categories",
                systemImage: "line.3.horizontal.decrease"
            )
        }
        .buttonStyle(TVMidnightButtonStyle(focusScale: 1.04))
        .accessibilityIdentifier("vod-category-picker")
        .confirmationDialog("Category", isPresented: $isChoosing, titleVisibility: .visible) {
            Button("All categories") { onSelect(nil) }
            ForEach(categories) { category in
                Button(category.name) { onSelect(category) }
            }
        }
        #else
        MidnightPicker(
            title: "Category",
            selection: Binding(
                get: { selection },
                set: { onSelect($0) }
            ),
            options: [(label: "All categories", value: VODCategory?.none)]
                + categories.map { (label: $0.name, value: Optional($0)) }
        )
        .accessibilityIdentifier("vod-category-picker")
        #endif
    }
}
#endif
