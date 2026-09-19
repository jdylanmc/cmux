import Foundation

/// A split pane's stable identity and tabs in their current tab-bar order.
public struct CmuxSidebarPane: Codable, Equatable, Identifiable, Sendable {
    /// The pane identifier, independent of the selected tab.
    public var id: UUID
    /// Ordered identifiers referencing surfaces in the containing workspace.
    ///
    /// These describe visual placement, not agent ownership. The first entry
    /// remains the first tab even when a different tab is focused.
    public var surfaceIDs: [UUID]

    /// Creates a pane with authoritative ordered tab membership.
    /// - Parameters:
    ///   - id: The host's stable pane identifier.
    ///   - surfaceIDs: Surface identifiers in tab-bar order, or empty for an empty pane.
    public init(id: UUID, surfaceIDs: [UUID]) {
        self.id = id
        self.surfaceIDs = surfaceIDs
    }
}
