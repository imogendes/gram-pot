import Foundation

/// Facts the gift sheet already knows when it decides whether to show Gram Pot.
public struct GramPotGroupFacts: Equatable, Sendable {
    /// Legacy group, or a supergroup. A broadcast channel is not a group.
    public var isGroup: Bool
    /// True when the group has a public username. Private groups have none.
    public var hasPublicUsername: Bool
    /// Nil when the count is not loaded yet. An unknown count stays hidden.
    public var memberCount: Int?
    /// The collectible was opened from a message in this group, not from a profile or a link alone.
    public var openedFromGroupMessage: Bool
    /// The viewer is the person the pot would be for.
    public var viewerIsRecipient: Bool
    /// The collectible has a GRAM (TON) resale price.
    public var hasTonPrice: Bool

    public init(
        isGroup: Bool,
        hasPublicUsername: Bool,
        memberCount: Int?,
        openedFromGroupMessage: Bool,
        viewerIsRecipient: Bool,
        hasTonPrice: Bool
    ) {
        self.isGroup = isGroup
        self.hasPublicUsername = hasPublicUsername
        self.memberCount = memberCount
        self.openedFromGroupMessage = openedFromGroupMessage
        self.viewerIsRecipient = viewerIsRecipient
        self.hasTonPrice = hasTonPrice
    }
}

/// Gram Pot is offered only for a collectible sent in a private group of 2–8 members,
/// with a GRAM price, to someone other than the viewer.
public func gramPotIsEligible(_ facts: GramPotGroupFacts) -> Bool {
    guard facts.isGroup, !facts.hasPublicUsername, facts.openedFromGroupMessage, !facts.viewerIsRecipient, facts.hasTonPrice else {
        return false
    }
    guard let memberCount = facts.memberCount, (2 ... 8).contains(memberCount) else {
        return false
    }
    return true
}

/// Spots are the members other than the recipient. Nil when the group is too small to have one.
public func gramPotSpotCount(memberCount: Int) -> Int? {
    guard memberCount >= 2 else {
        return nil
    }
    return memberCount - 1
}
