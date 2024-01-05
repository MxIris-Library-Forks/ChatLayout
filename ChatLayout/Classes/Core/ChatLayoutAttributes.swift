//
// ChatLayout
// ChatLayoutAttributes.swift
// https://github.com/ekazaev/ChatLayout
//
// Created by Eugene Kazaev in 2020-2023.
// Distributed under the MIT license.
//
// Become a sponsor:
// https://github.com/sponsors/ekazaev
//

import Foundation
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

/// Custom implementation of `UICollectionViewLayoutAttributes`
public final class ChatLayoutAttributes: CollectionViewLayoutAttributes {
    /// Alignment of the current item. Can be changed within `UICollectionViewCell.preferredLayoutAttributesFitting(...)`
    public var alignment: ChatItemAlignment = .fullWidth

    /// Inter item spacing. Can be changed within `UICollectionViewCell.preferredLayoutAttributesFitting(...)`
    public var interItemSpacing: CGFloat = 0

    /// `CollectionViewChatLayout`s additional insets setup using `ChatLayoutSettings`. Added for convenience.
    public internal(set) var additionalInsets: EdgeInsets = .zero

    /// `UICollectionView`s frame size. Added for convenience.
    public internal(set) var viewSize: CGSize = .zero

    /// `UICollectionView`s adjusted content insets. Added for convenience.
    public internal(set) var adjustedContentInsets: EdgeInsets = .zero

    /// `CollectionViewChatLayout`s visible bounds size excluding `adjustedContentInsets`. Added for convenience.
    public internal(set) var visibleBoundsSize: CGSize = .zero

    /// `CollectionViewChatLayout`s visible bounds size excluding `adjustedContentInsets` and `additionalInsets`. Added for convenience.
    public internal(set) var layoutFrame: CGRect = .zero

    #if DEBUG
    var id: UUID?
    #endif

    convenience init(kind: ItemKind, indexPath: IndexPath = IndexPath(item: 0, section: 0)) {
        switch kind {
        case .cell:
            #if canImport(AppKit) && !targetEnvironment(macCatalyst)
            self.init(forItemWith: indexPath)
            #endif

            #if canImport(UIKit)
            self.init(forCellWith: indexPath)
            #endif
        case .header:
            self.init(forSupplementaryViewOfKind: CollectionView.elementKindSectionHeader, with: indexPath)
        case .footer:
            self.init(forSupplementaryViewOfKind: CollectionView.elementKindSectionFooter, with: indexPath)
        }
    }

    /// Returns an exact copy of `ChatLayoutAttributes`.
    public override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone) as! ChatLayoutAttributes
        copy.viewSize = viewSize
        copy.alignment = alignment
        copy.interItemSpacing = interItemSpacing
        copy.layoutFrame = layoutFrame
        copy.additionalInsets = additionalInsets
        copy.visibleBoundsSize = visibleBoundsSize
        copy.adjustedContentInsets = adjustedContentInsets
        #if DEBUG
        copy.id = id
        #endif
        return copy
    }

    /// Returns a Boolean value indicating whether two `ChatLayoutAttributes` are considered equal.
    public override func isEqual(_ object: Any?) -> Bool {
        super.isEqual(object)
            && alignment == (object as? ChatLayoutAttributes)?.alignment
            && interItemSpacing == (object as? ChatLayoutAttributes)?.interItemSpacing
    }

    /// `ItemKind` represented by this attributes object.
    public var kind: ItemKind {
        switch (representedElementCategory, representedElementKind) {
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        case (.item, nil):
            return .cell
        #endif
        #if canImport(UIKit)
        case (.cell, nil):
            return .cell
        #endif
        case (.supplementaryView, .some(CollectionView.elementKindSectionHeader)):
            return .header
        case (.supplementaryView, .some(CollectionView.elementKindSectionFooter)):
            return .footer
        default:
            preconditionFailure("Unsupported element kind.")
        }
    }

    func typedCopy() -> ChatLayoutAttributes {
        guard let typedCopy = copy() as? ChatLayoutAttributes else {
            fatalError("Internal inconsistency.")
        }
        return typedCopy
    }
}
