import Foundation
import Testing
@_spi(CmuxHostTransport) import CmuxExtensionKit

@Suite struct SidebarPaneTests {
    @Test func orderedPaneMembershipSurvivesTransport() throws {
        let workspace = try decodeWorkspace(panes: [
            ["id": paneA.uuidString, "surfaceIDs": [surfaceA.uuidString, surfaceB.uuidString]],
            ["id": paneB.uuidString, "surfaceIDs": [surfaceC.uuidString]],
        ])
        let snapshot = CmuxSidebarSnapshot(
            sequence: 1, selectedWorkspaceID: workspace.id, workspaces: [workspace]
        )
        let transported = try CmuxSidebarXPCCodec.decodeSnapshot(CmuxSidebarXPCCodec.encodeSnapshot(snapshot))
        let actual = try encodedPanes(#require(transported.workspaces.first))
        #expect(actual?.map { $0["id"] as? String } == [paneA.uuidString, paneB.uuidString])
        #expect(actual?.first?["surfaceIDs"] as? [String] == [surfaceA.uuidString, surfaceB.uuidString])
    }

    @Test func tabMovesReordersAndPaneClosureChangeTheSnapshot() throws {
        let before = try decodeWorkspace(panes: [
            ["id": paneA.uuidString, "surfaceIDs": [surfaceA.uuidString, surfaceB.uuidString]],
            ["id": paneB.uuidString, "surfaceIDs": [surfaceC.uuidString]],
        ])
        let moved = try decodeWorkspace(panes: [
            ["id": paneB.uuidString, "surfaceIDs": [surfaceB.uuidString, surfaceC.uuidString]],
            ["id": paneA.uuidString, "surfaceIDs": [surfaceA.uuidString]],
        ])
        let closed = try decodeWorkspace(panes: [
            ["id": paneB.uuidString, "surfaceIDs": [surfaceB.uuidString, surfaceC.uuidString, surfaceA.uuidString]],
        ])
        #expect(before != moved)
        #expect(moved != closed)
    }

    @Test func paneMembershipRequiresSurfaceMetadataPermission() throws {
        let workspace = try decodeWorkspace(panes: [
            ["id": paneA.uuidString, "surfaceIDs": [surfaceA.uuidString, surfaceB.uuidString]],
        ])
        #expect(try encodedPanes(workspace.filtered(for: [.workspaceMetadata])) == nil)
        #expect(try encodedPanes(workspace.filtered(for: [.workspaceMetadata, .surfaceMetadata]))?.count == 1)
        let snapshot = CmuxSidebarSnapshot(sequence: 1, selectedWorkspaceID: nil, workspaces: [workspace])
        let listOnly = try #require(snapshot.filtered(for: [.workspaceList, .surfaceMetadata]).workspaces.first)
        #expect(try encodedPanes(listOnly) == nil)
    }

    @Test func oldHostsOmitLayoutRatherThanReportingNoPanes() throws {
        #expect(try encodedPanes(decodeWorkspace(panes: nil)) == nil)
        #expect(try encodedPanes(decodeWorkspace(panes: []))?.isEmpty == true)
    }

    private let workspaceID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let paneA = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let paneB = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let surfaceA = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    private let surfaceB = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
    private let surfaceC = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!

    private func decodeWorkspace(panes: [[String: Any]]?) throws -> CmuxSidebarWorkspace {
        let workspace = CmuxSidebarWorkspace(
            id: workspaceID, title: "Pane layout",
            surfaces: [surfaceA, surfaceB, surfaceC].map { .init(id: $0, title: "Tab") }
        )
        var wire = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace)) as? [String: Any])
        wire["panes"] = panes
        return try JSONDecoder().decode(CmuxSidebarWorkspace.self, from: JSONSerialization.data(withJSONObject: wire))
    }

    private func encodedPanes(_ workspace: CmuxSidebarWorkspace) throws -> [[String: Any]]? {
        let wire = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace)) as? [String: Any])
        return wire["panes"] as? [[String: Any]]
    }
}
