import AppKit
import CmuxNotifications
import CmuxSidebar
import CmuxWorkspaces
@_spi(CmuxHostTransport) import CmuxExtensionKit
import SwiftUI
import Testing
#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct SidebarWorkspaceSnapshotRefreshPolicyTests {
    @Test @MainActor
    func extensionPanesTrackRealTabOrderAndMovesRatherThanFocus() throws {
        let workspace = Workspace(title: "Sidebar pane contract")
        let first = try #require(workspace.focusedPanelId)
        let paneA = try #require(workspace.paneId(forPanelId: first))
        let second = try #require(workspace.newTerminalSurface(inPane: paneA, focus: false))
        let split = try #require(workspace.newTerminalSplit(from: first, orientation: .horizontal, focus: false))
        let paneB = try #require(workspace.paneId(forPanelId: split.id))
        let initial = try #require(workspace.sidebarExtensionPanes())
        #expect(initial.map(\.id) == [paneA.id, paneB.id])
        #expect(initial.map(\.surfaceIDs) == [[first, second.id], [split.id]])

        workspace.focusPanel(second.id)
        #expect(workspace.sidebarExtensionPanes() == initial)
        #expect(workspace.moveSurface(panelId: second.id, toPane: paneB, atIndex: 0, focus: false))
        let moved = try #require(workspace.sidebarExtensionPanes())
        #expect(moved.map(\.surfaceIDs) == [[first], [second.id, split.id]])
        #expect(workspace.moveSurface(panelId: split.id, toPane: paneB, atIndex: 0, focus: false))
        #expect(workspace.sidebarExtensionPanes()?.last?.surfaceIDs == [split.id, second.id])
    }

    @Test @MainActor
    func layoutOnlyChangeInvalidatesExtensionSnapshotCache() throws {
        let workspaceID = UUID(), paneID = UUID(), a = UUID(), b = UUID()
        var workspace = CmuxSidebarWorkspace(
            id: workspaceID, title: "Pane",
            surfaces: [a, b].map { .init(id: $0, title: "Tab") },
            panes: [.init(id: paneID, surfaceIDs: [a, b])]
        )
        let cache = CMUXSidebarSnapshotCache()
        let initial = cache.replace(with: .init(sequence: 1, selectedWorkspaceID: workspaceID, workspaces: [workspace]))
        workspace.panes = [.init(id: paneID, surfaceIDs: [b, a])]
        let changed = cache.replace(with: .init(sequence: 1, selectedWorkspaceID: workspaceID, workspaces: [workspace]))
        #expect(changed.sequence > initial.sequence)
        #expect(changed.workspaces.first?.panes?.first?.surfaceIDs == [b, a])
    }

    @Test @MainActor
    func extensionSnapshotCacheDoesNotInflateSequenceForIdenticalProviderContent() throws {
        let workspaceID = UUID()
        let initial = CmuxSidebarSnapshot(
            sequence: 10,
            selectedWorkspaceID: workspaceID,
            workspaces: [CmuxSidebarWorkspace(id: workspaceID, title: "Pi")]
        )
        let cache = CMUXSidebarSnapshotCache()
        _ = cache.replace(with: initial)
        let unread = SidebarUnreadSnapshot(
            totalUnreadCount: 1,
            summaryByWorkspaceId: [
                workspaceID: SidebarWorkspaceUnreadSummary(
                    unreadCount: 1,
                    latestNotificationText: "Done"
                ),
            ]
        )
        let patched = try #require(cache.applyUnread(unread))
        let matchingProvider = CmuxSidebarSnapshot(
            sequence: 10,
            selectedWorkspaceID: workspaceID,
            workspaces: [
                CmuxSidebarWorkspace(
                    id: workspaceID,
                    title: "Pi",
                    unreadCount: 1,
                    latestNotification: "Done"
                ),
            ]
        )

        let firstPoll = cache.replace(with: matchingProvider)
        let secondPoll = cache.replace(with: matchingProvider)

        #expect(firstPoll.sequence == patched.sequence)
        #expect(secondPoll.sequence == patched.sequence)

        let changedProvider = CmuxSidebarSnapshot(
            sequence: 10,
            selectedWorkspaceID: workspaceID,
            workspaces: [
                CmuxSidebarWorkspace(
                    id: workspaceID,
                    title: "Pi renamed",
                    unreadCount: 1,
                    latestNotification: "Done"
                ),
            ]
        )
        let changedPoll = cache.replace(with: changedProvider)
        #expect(changedPoll.sequence == patched.sequence + 1)
        #expect(changedPoll.workspaces.first?.title == "Pi renamed")
    }

    @Test func contextMenuPinChangeUpdatesDisplayedFieldsAndDefersNoisyFields() {
        let current = Self.snapshot(
            title: "lmao",
            isPinned: false,
            customColorHex: nil,
            remoteConnectionStatusText: "Connected",
            latestConversationMessage: "old message",
            listeningPorts: [3000],
            finderDirectoryPath: "/old"
        )
        let next = Self.snapshot(
            title: "lmao",
            isPinned: true,
            customColorHex: nil,
            remoteConnectionStatusText: "Disconnected",
            latestConversationMessage: "new message",
            listeningPorts: [3000, 4000],
            finderDirectoryPath: nil
        )

        let decision = SidebarWorkspaceSnapshotRefreshPolicy().decision(
            current: current,
            next: next,
            force: false,
            contextMenuVisible: true
        )

        var expectedDisplayed = current
        expectedDisplayed = expectedDisplayed.applyingContextMenuImmediateFields(from: next)
        #expect(decision.workspaceSnapshotStorage == expectedDisplayed)
        #expect(decision.workspaceSnapshotStorage?.isPinned == true)
        #expect(decision.workspaceSnapshotStorage?.remoteConnectionStatusText == "Connected")
        #expect(decision.workspaceSnapshotStorage?.latestConversationMessage == "old message")
        #expect(decision.workspaceSnapshotStorage?.listeningPorts == [3000])
        #expect(decision.workspaceSnapshotStorage?.finderDirectoryPath == nil)
        #expect(decision.pendingWorkspaceSnapshot == next)
        #expect(decision.hasDeferredWorkspaceObservationInvalidation)
    }
    @Test func contextMenuImmediateOnlyChangeDoesNotCreateDeferredFlush() {
        let current = Self.snapshot(
            title: "old",
            customDescription: nil,
            isPinned: false,
            customColorHex: nil,
            finderDirectoryPath: nil
        )
        let next = Self.snapshot(
            title: "new",
            customDescription: "description",
            isPinned: true,
            customColorHex: "#C0392B",
            finderDirectoryPath: "/tmp/workspace"
        )

        let decision = SidebarWorkspaceSnapshotRefreshPolicy().decision(
            current: current,
            next: next,
            force: false,
            contextMenuVisible: true
        )

        #expect(decision.workspaceSnapshotStorage == next)
        #expect(decision.pendingWorkspaceSnapshot == nil)
        #expect(!decision.hasDeferredWorkspaceObservationInvalidation)
    }
    @Test func contextMenuMediaActivityChangeUpdatesDisplayedGlyphImmediately() {
        let current = Self.snapshot(
            remoteConnectionStatusText: "Connected",
            latestConversationMessage: "old message",
            listeningPorts: [3000],
            mediaActivity: BrowserMediaActivity(isPlayingAudio: true)
        )
        let next = Self.snapshot(
            remoteConnectionStatusText: "Disconnected",
            latestConversationMessage: "new message",
            listeningPorts: [3000, 4000],
            mediaActivity: BrowserMediaActivity(isPlayingAudio: false)
        )

        let decision = SidebarWorkspaceSnapshotRefreshPolicy().decision(
            current: current,
            next: next,
            force: false,
            contextMenuVisible: true
        )

        #expect(decision.workspaceSnapshotStorage?.mediaActivity.isPlayingAudio == false)
        #expect(decision.workspaceSnapshotStorage?.remoteConnectionStatusText == "Connected")
        #expect(decision.workspaceSnapshotStorage?.latestConversationMessage == "old message")
        #expect(decision.workspaceSnapshotStorage?.listeningPorts == [3000])
        #expect(decision.pendingWorkspaceSnapshot == next)
        #expect(decision.hasDeferredWorkspaceObservationInvalidation)
    }
    @Test func closedContextMenuStoresNextAndClearsPending() {
        let current = Self.snapshot(title: "old", isPinned: false)
        let next = Self.snapshot(title: "new", isPinned: true)

        let decision = SidebarWorkspaceSnapshotRefreshPolicy().decision(
            current: current,
            next: next,
            force: false,
            contextMenuVisible: false
        )

        #expect(decision.workspaceSnapshotStorage == next)
        #expect(decision.pendingWorkspaceSnapshot == nil)
        #expect(!decision.hasDeferredWorkspaceObservationInvalidation)
    }

    static func snapshot(
        presentationKey: SidebarWorkspaceSnapshotBuilder.PresentationKey? = nil,
        title: String = "workspace",
        customDescription: String? = nil,
        isPinned: Bool = false,
        customColorHex: String? = nil,
        remoteConnectionStatusText: String = "Disconnected",
        latestConversationMessage: String? = nil,
        listeningPorts: [Int] = [],
        finderDirectoryPath: String? = nil,
        mediaActivity: BrowserMediaActivity = BrowserMediaActivity(),
        activeCodingAgentCount: Int = 0
    ) -> SidebarWorkspaceSnapshotBuilder.Snapshot {
        SidebarWorkspaceSnapshotBuilder.Snapshot(
            presentationKey: presentationKey ?? Self.presentationKey(),
            title: title,
            customDescription: customDescription,
            isPinned: isPinned,
            customColorHex: customColorHex,
            remoteWorkspaceSidebarText: nil,
            remoteConnectionStatusText: remoteConnectionStatusText,
            remoteStateHelpText: "",
            showsRemoteReconnectAffordance: false,
            copyableSidebarSSHError: nil,
            latestConversationMessage: latestConversationMessage,
            metadataEntries: [],
            metadataBlocks: [],
            latestLog: nil,
            progress: nil,
            activeCodingAgentCount: activeCodingAgentCount,
            compactGitBranchSummaryText: nil,
            compactDirectoryCandidates: [],
            compactBranchDirectoryCandidates: [],
            branchDirectoryLines: [],
            branchLinesContainBranch: false,
            pullRequestRows: [],
            listeningPorts: listeningPorts,
            finderDirectoryPath: finderDirectoryPath,
            mediaActivity: mediaActivity,
            taskStatus: nil,
            todoStatusMenuModel: nil,
            hasManualTaskStatus: false,
            checklistItems: [],
            checklistCompletedCount: 0,
            checklistTotalCount: 0,
            checklistFirstUncheckedText: nil
        )
    }

    static func presentationKey(
        showsWorkspaceDescription: Bool = true,
        usesVerticalBranchLayout: Bool = true,
        showsGitBranch: Bool = true,
        usesViewportAwarePath: Bool = false,
        showsAgentActivity: Bool = true,
        visibleAuxiliaryDetails: SidebarWorkspaceAuxiliaryDetailVisibility = SidebarWorkspaceAuxiliaryDetailVisibility(
            showsMetadata: true,
            showsLog: true,
            showsProgress: true,
            showsBranchDirectory: true,
            showsPullRequests: true,
            showsPorts: true
        )
    ) -> SidebarWorkspaceSnapshotBuilder.PresentationKey {
        SidebarWorkspaceSnapshotBuilder.PresentationKey(
            showsWorkspaceDescription: showsWorkspaceDescription,
            usesVerticalBranchLayout: usesVerticalBranchLayout,
            showsGitBranch: showsGitBranch,
            usesViewportAwarePath: usesViewportAwarePath,
            showsAgentActivity: showsAgentActivity,
            visibleAuxiliaryDetails: visibleAuxiliaryDetails
        )
    }
}

@Suite struct SidebarSelectedWorkspaceScrollPolicyTests {
    @Test func skipsScrollWhenSelectedWorkspaceIdIsNil() {
        #expect(!SidebarSelectedWorkspaceScrollPolicy.shouldScrollSelectedWorkspace(
            selectedWorkspaceId: nil as String?,
            oldWorkspaceIds: ["a"],
            newWorkspaceIds: ["a"]
        ))
    }

    @Test func requestsScrollWhenSelectedWorkspaceFirstAppears() {
        #expect(SidebarSelectedWorkspaceScrollPolicy.shouldScrollSelectedWorkspace(
            selectedWorkspaceId: "b",
            oldWorkspaceIds: ["a"],
            newWorkspaceIds: ["a", "b"]
        ))
    }

    @Test func requestsScrollWhenSelectedWorkspaceMovesToTop() {
        #expect(SidebarSelectedWorkspaceScrollPolicy.shouldScrollSelectedWorkspace(
            selectedWorkspaceId: "c",
            oldWorkspaceIds: ["a", "b", "c"],
            newWorkspaceIds: ["c", "a", "b"]
        ))
    }

    @Test func requestsScrollWhenAnotherReorderShiftsSelectedWorkspaceIndex() {
        #expect(SidebarSelectedWorkspaceScrollPolicy.shouldScrollSelectedWorkspace(
            selectedWorkspaceId: "b",
            oldWorkspaceIds: ["a", "b", "c"],
            newWorkspaceIds: ["c", "a", "b"]
        ))
    }

    @Test func skipsScrollWhenWorkspaceBeforeSelectedWorkspaceCloses() {
        #expect(!SidebarSelectedWorkspaceScrollPolicy.shouldScrollSelectedWorkspace(selectedWorkspaceId: "d", oldWorkspaceIds: ["a", "b", "c", "d"], newWorkspaceIds: ["a", "c", "d"]))
    }
    @Test func skipsScrollWhenReorderLeavesSelectedWorkspaceIndexUnchanged() {
        #expect(!SidebarSelectedWorkspaceScrollPolicy.shouldScrollSelectedWorkspace(
            selectedWorkspaceId: "a",
            oldWorkspaceIds: ["a", "b", "c"],
            newWorkspaceIds: ["a", "c", "b"]
        ))
    }

    @Test func skipsScrollWhenSelectedWorkspaceIsMissing() {
        #expect(!SidebarSelectedWorkspaceScrollPolicy.shouldScrollSelectedWorkspace(
            selectedWorkspaceId: "b",
            oldWorkspaceIds: ["a", "b"],
            newWorkspaceIds: ["a", "c"]
        ))
    }

    @Test func scrollTargetIsSelfWithoutGroup() {
        let workspaceId = UUID()
        #expect(SidebarSelectedWorkspaceScrollPolicy.scrollTargetWorkspaceId(
            selectedWorkspaceId: workspaceId,
            group: nil
        ) == workspaceId)
    }

    @Test func scrollTargetIsSelfInExpandedGroup() {
        let workspaceId = UUID()
        #expect(SidebarSelectedWorkspaceScrollPolicy.scrollTargetWorkspaceId(
            selectedWorkspaceId: workspaceId,
            group: makeGroup(isCollapsed: false, anchorWorkspaceId: UUID())
        ) == workspaceId)
    }

    @Test func scrollTargetIsGroupAnchorWhenGroupIsCollapsed() {
        let anchorId = UUID()
        #expect(SidebarSelectedWorkspaceScrollPolicy.scrollTargetWorkspaceId(
            selectedWorkspaceId: UUID(),
            group: makeGroup(isCollapsed: true, anchorWorkspaceId: anchorId)
        ) == anchorId)
    }

    private func makeGroup(isCollapsed: Bool, anchorWorkspaceId: UUID) -> WorkspaceGroup {
        WorkspaceGroup(
            id: UUID(),
            name: "group",
            isCollapsed: isCollapsed,
            isPinned: false,
            anchorWorkspaceId: anchorWorkspaceId,
            customColor: nil,
            iconSymbol: nil
        )
    }
}
