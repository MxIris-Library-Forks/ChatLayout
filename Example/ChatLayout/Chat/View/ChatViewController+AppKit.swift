//
//  ChatViewController+AppKit.swift
//  ChatLayout
//
//  Created by JH on 2024/9/25.
//  Copyright © 2024 CocoaPods. All rights reserved.
//

import Foundation
import ChatLayout
import DifferenceKit

#if canImport(AppKit) && !targetEnvironment(macCatalyst)

import AppKit

final class ChatViewController: NSViewController {
    private enum ReactionTypes {
        case delayedUpdate
    }

    private enum InterfaceActions {
        case changingKeyboardFrame
        case changingContentInsets
        case changingFrameSize
        case sendingMessage
        case scrollingToTop
        case scrollingToBottom
        case showingPreview
        case showingAccessory
        case updatingCollectionInIsolation
    }

    private enum ControllerActions {
        case loadingInitialMessages
        case loadingPreviousMessages
        case updatingCollection
    }

    override var acceptsFirstResponder: Bool { true }

    private var currentInterfaceActions: SetActor<Set<InterfaceActions>, ReactionTypes> = SetActor()
    private var currentControllerActions: SetActor<Set<ControllerActions>, ReactionTypes> = SetActor()
    private let editNotifier: EditNotifier
    private let swipeNotifier: SwipeNotifier
    private let collectionView: NSCollectionView = .init(frame: .zero)
    private let scrollView: NSScrollView = .init()
    private var chatLayout = CollectionViewChatLayout()
    private let chatController: ChatController
    private let dataSource: ChatCollectionDataSource
    private var animator: ManualAnimator?

    private var translationX: CGFloat = 0
    private var currentOffset: CGFloat = 0

    private lazy var panGesture: NSPanGestureRecognizer = {
        let gesture = NSPanGestureRecognizer(target: self, action: #selector(handleRevealPan(_:)))
        gesture.delegate = self
        return gesture
    }()

    init(
        chatController: ChatController,
        dataSource: ChatCollectionDataSource,
        editNotifier: EditNotifier,
        swipeNotifier: SwipeNotifier
    ) {
        self.chatController = chatController
        self.dataSource = dataSource
        self.editNotifier = editNotifier
        self.swipeNotifier = swipeNotifier
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable, message: "Use init(messageController:) instead")
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        fatalError()
    }

    @available(*, unavailable, message: "Use init(messageController:) instead")
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.frame = .init(x: 0, y: 0, width: 1024, height: 768)
        view.addSubview(scrollView)
        chatLayout.settings.interItemSpacing = 8
        chatLayout.settings.interSectionSpacing = 8
        chatLayout.settings.additionalInsets = NSEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        chatLayout.keepContentOffsetAtBottomOnBatchUpdates = true
        chatLayout.processOnlyVisibleItemsOnAnimatedBatchUpdates = false
        chatLayout.keepContentAtBottomOfVisibleArea = true
        chatLayout.delegate = dataSource

        collectionView.collectionViewLayout = chatLayout
        collectionView.dataSource = dataSource
        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        
        scrollView.documentView = collectionView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 0),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0),
        ])

        
        dataSource.prepare(with: collectionView)

        currentControllerActions.options.insert(.loadingInitialMessages)
        chatController.loadInitialMessages { sections in
            self.currentControllerActions.options.remove(.loadingInitialMessages)
            self.processUpdates(with: sections, animated: true, requiresIsolatedProcess: false)
        }

//        collectionView.addGestureRecognizer(panGesture)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        collectionView.collectionViewLayout?.invalidateLayout()
    }
}

extension ChatViewController: NSCollectionViewDelegate {}

extension ChatViewController: ChatControllerDelegate {
    func update(with sections: [Section], requiresIsolatedProcess: Bool) {
        // if `chatLayout.keepContentAtBottomOfVisibleArea` is enabled and content size is actually smaller than the visible size - it is better to process each batch update
        // in isolation. Example: If you insert a cell animatingly and then reload some cell - the reload animation will appear on top of the insertion animation.
        // Basically everytime you see any animation glitches - process batch updates in isolation.
        let requiresIsolatedProcess = chatLayout.keepContentAtBottomOfVisibleArea == true && chatLayout.collectionViewContentSize.height < chatLayout.visibleBounds.height ? true : requiresIsolatedProcess
        processUpdates(with: sections, animated: true, requiresIsolatedProcess: requiresIsolatedProcess)
    }

    private func processUpdates(with sections: [Section], animated: Bool = true, requiresIsolatedProcess: Bool, completion: (() -> Void)? = nil) {
        guard isViewLoaded else {
            dataSource.sections = sections
            return
        }

        guard currentInterfaceActions.options.isEmpty else {
            let reaction = SetActor<Set<InterfaceActions>, ReactionTypes>.Reaction(
                type: .delayedUpdate,
                action: .onEmpty,
                executionType: .once,
                actionBlock: { [weak self] in
                    guard let self else {
                        return
                    }
                    processUpdates(with: sections, animated: animated, requiresIsolatedProcess: requiresIsolatedProcess, completion: completion)
                }
            )
            currentInterfaceActions.add(reaction: reaction)
            return
        }

        func process() {
            // If there is a big amount of changes, it is better to move that calculation out of the main thread.
            // Here is on the main thread for the simplicity.
            let changeSet = StagedChangeset(source: dataSource.sections, target: sections).flattenIfPossible()

            guard !changeSet.isEmpty else {
                completion?()
                return
            }

            if requiresIsolatedProcess {
                chatLayout.processOnlyVisibleItemsOnAnimatedBatchUpdates = true
                currentInterfaceActions.options.insert(.updatingCollectionInIsolation)
            }
            currentControllerActions.options.insert(.updatingCollection)
            collectionView.reload(
                using: changeSet,
                interrupt: { changeSet in
                    guard changeSet.sectionInserted.isEmpty else {
                        return true
                    }
                    return false
                },
                onInterruptedReload: {
                    let positionSnapshot = ChatLayoutPositionSnapshot(indexPath: IndexPath(item: 0, section: sections.count - 1), kind: .footer, edge: .bottom)
                    self.collectionView.reloadData()
                    // We want so that user on reload appeared at the very bottom of the layout
                    self.chatLayout.restoreContentOffset(with: positionSnapshot)
                },
                completion: { _ in
                    DispatchQueue.main.async {
                        self.chatLayout.processOnlyVisibleItemsOnAnimatedBatchUpdates = false
                        if requiresIsolatedProcess {
                            self.currentInterfaceActions.options.remove(.updatingCollectionInIsolation)
                        }
                        completion?()
                        self.currentControllerActions.options.remove(.updatingCollection)
                    }
                },
                setData: { data in
                    self.dataSource.sections = data
                }
            )
        }

        if animated {
            process()
        } else {
            NSView.performWithoutAnimation {
                process()
            }
        }
    }
}

extension ChatViewController: NSGestureRecognizerDelegate {
    @objc
    private func handleRevealPan(_ gesture: NSPanGestureRecognizer) {
        guard let collectionView = gesture.view as? NSCollectionView,
              !editNotifier.isEditing else {
            currentInterfaceActions.options.remove(.showingAccessory)
            return
        }

        switch gesture.state {
        case .began:
            currentInterfaceActions.options.insert(.showingAccessory)
        case .changed:
            translationX = gesture.translation(in: gesture.view).x
            currentOffset += translationX

            gesture.setTranslation(.zero, in: gesture.view)
            updateTransforms(in: collectionView)
        default:
            NSView.animate(withDuration: 0.25, animations: { () in
                self.translationX = 0
                self.currentOffset = 0
                self.updateTransforms(in: collectionView, transform: .identity)
            }, completion: { _ in
                self.currentInterfaceActions.options.remove(.showingAccessory)
            })
        }
    }

    private func updateTransforms(in collectionView: NSCollectionView, transform: CGAffineTransform? = nil) {
        for indexPathsForVisibleItem in collectionView.indexPathsForVisibleItems() {
            guard let cell = collectionView.item(at: indexPathsForVisibleItem) else {
                continue
            }
            updateTransform(transform: transform, cell: cell, indexPath: indexPathsForVisibleItem)
        }
    }

    private func updateTransform(transform: CGAffineTransform?, cell: NSUICollectionViewCell, indexPath: IndexPath) {
        var x = currentOffset

        let maxOffset: CGFloat = -100
        x = max(x, maxOffset)
        x = min(x, 0)

        swipeNotifier.setSwipeCompletionRate(x / maxOffset)
    }

    public func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        [gestureRecognizer, otherGestureRecognizer].contains(panGesture)
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        if let gesture = gestureRecognizer as? NSPanGestureRecognizer, gesture == panGesture {
            let translation = gesture.translation(in: gesture.view)
            return (abs(translation.x) > abs(translation.y)) && (gesture == panGesture)
        }

        return true
    }
}

#endif
