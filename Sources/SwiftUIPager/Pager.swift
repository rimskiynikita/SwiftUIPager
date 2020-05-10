//
//  Pager.swift
//  SwiftUIPager
//
//  Created by Fernando Moya de Rivas on 05/12/2019.
//  Copyright © 2019 Fernando Moya de Rivas. All rights reserved.
//

import SwiftUI

///
/// `Pager` is a view built on top of native SwiftUI components. Given a `ViewBuilder` and some `Identifiable` and `Equatable` data,
/// this view will create a scrollable container to display a handful of pages. The pages are recycled on scroll. `Pager` is easily customizable through a number
/// of view-modifier functions.  You can change the vertical insets, spacing between items, ... You can also make the pages size interactive.
///
/// # Example #
///
///     Pager(page: $page
///           data: data,
///           content: { index in
///               self.pageView(index)
///     }).interactive(0.8)
///         .itemSpacing(10)
///         .padding(30)
///         .pageAspectRatio(0.6)
///
/// This snippet creates a pager with:
/// - 10 px beetween pages
/// - 30 px of vertical insets
/// - 0.6 shrink ratio for items that aren't focused.
///
public struct Pager<Element, ID, PageView>: View  where PageView: View, Element: Equatable, ID: Hashable {

    /// `Direction` determines the direction of the swipe gesture
    enum Direction {
        /// Swiping  from left to right
        case forward
        /// Swiping from right to left
        case backward
    }

    /*** Constants ***/

    /// Manages the number of items that should be displayed in the screen.
    /// A ratio of 3, for instance, would mean the items held in memory are enough
    /// to cover 3 times the size of the pager
    let recyclingRatio = 5
    
    /// Duration of selecting page switcheng animation
    let animationDuration: Double = 0.3

    /// Angle of rotation when should rotate
    let rotationDegrees: Double = 20

    /// Angle of rotation when should rotate
    let rotationInteractiveScale: CGFloat = 0.7

    /// Axis of rotation when should rotate
    let rotationAxis: (x: CGFloat, y: CGFloat, z: CGFloat) = (0, 1, 0)

    /*** Dependencies ***/

    /// Angle to dermine the direction of the scroll
    var scrollDirectionAngle: Angle = .zero

    /// `ViewBuilder` block to create each page
    let content: (Element) -> PageView

    /// `KeyPath` to data id property
    let id: KeyPath<Element, ID>

    /// Array of items that will populate each page
    var data: [Element]

    /*** ViewModified properties ***/

    /// Hittable area
    var swipeInteractionArea: SwipeInteractionArea = .page

    /// Item alignment inside `Pager`
    var itemAlignment: PositionAlignment = .center

    /// The elements alignment relative to the container
    var alignment: PositionAlignment = .center

    /// `true` if the pager is horizontal
    var isHorizontal: Bool = true

    /// Shrink ratio that affects the items that aren't focused
    var interactiveScale: CGFloat = 1

    /// `true` if pages should have a 3D rotation effect
    var shouldRotate: Bool = false

    /// Used to modify `Pager` offset outside this view
    var pageOffset: Double = 0

    /// Vertical padding
    var sideInsets: CGFloat = 0

    /// Space between pages
    var itemSpacing: CGFloat = 0

    /// Will apply this ratio to each page item. The aspect ratio follows the formula _width / height_
    var itemAspectRatio: CGFloat?

    /*** State and Binding properties ***/

    /// Size of the view
    @State var size: CGSize = .zero

    /// Translation on the X-Axis
    @State var draggingOffset: CGFloat = 0

    /// The moment when the dragging gesture started
    @State var draggingStartTime: Date! = nil

    /// Page index
    @Binding var pageIndex: Int

    /// Initializes a new `Pager`.
    ///
    /// - Parameter page: Binding to the page index
    /// - Parameter data: Array of items to populate the content
    /// - Parameter id: KeyPath to identifiable property
    /// - Parameter content: Factory method to build new pages
    public init(page: Binding<Int>, data: [Element], id: KeyPath<Element, ID>, @ViewBuilder content: @escaping (Element) -> PageView) {
        self._pageIndex = page
        self.data = data
        self.id = id
        self.content = content
    }

    public var body: some View {
        let stack = HStack(spacing: interactiveItemSpacing) {
            ForEach(dataDisplayed, id: id) { item in
                self.content(item)
                    .frame(size: self.pageSize)
                    .scaleEffect(self.scale(for: item))
                    .rotation3DEffect((self.isHorizontal ? .zero : Angle(degrees: -90)) - self.scrollDirectionAngle,
                                      axis: (0, 0, 1))
                    .rotation3DEffect(self.angle(for: item),
                                      axis: self.axis(for: item))
            }
            .offset(x: self.xOffset, y : self.yOffset)
            .animation(.easeOut(duration: animationDuration))
        }
        .frame(size: size)

        let wrappedView: AnyView = swipeInteractionArea == .page ? AnyView(stack) : AnyView(stack.contentShape(Rectangle()))

        return wrappedView.highPriorityGesture(swipeGesture, including: .all)
            .rotation3DEffect((isHorizontal ? .zero : Angle(degrees: 90)) + scrollDirectionAngle,
                              axis: (0, 0, 1))
            .sizeTrackable($size)
    }
}

extension Pager where ID == Element.ID, Element : Identifiable {

    /// Initializes a new Pager.
    ///
    /// - Parameter data: Array of items to populate the content
    /// - Parameter content: Factory method to build new pages
    public init(page: Binding<Int>, data: [Element], @ViewBuilder content: @escaping (Element) -> PageView) {
        self._pageIndex = page
        self.data = data
        self.id = \Element.id
        self.content = content
    }

}

// MARK: Gestures

extension Pager {

    /// Helper function to scroll to a specific item.
    func scrollToItem(_ item: Element) {
        guard let index = data.firstIndex(of: item) else { return }
        self.pageIndex = index
    }

    func tapGesture(for item: Element) -> some Gesture {
        TapGesture(count: 1)
            .onEnded({ _ in
                withAnimation(.spring()) {
                    self.scrollToItem(item)
                }
            })
    }

    /// `DragGesture` customized to work with `Pager`
    var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                withAnimation {
                    self.draggingStartTime = self.draggingStartTime ?? value.time
                    self.draggingOffset = value.translation.width
                }
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let velocity = -Double(value.translation.width) / value.time.timeIntervalSince(self.draggingStartTime ?? Date())
                var newPage = self.currentPage
                if newPage == self.page, abs(velocity) > 1000 {
                    newPage = newPage + Int(velocity / abs(velocity))
                }
                newPage = max(0, min(self.numberOfPages - 1, newPage))

                withAnimation(.easeOut) {
                    self.pageIndex = newPage
                    self.draggingOffset = 0
                    self.draggingStartTime = nil
                }
            }
    }
}
