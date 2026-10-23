import Foundation
import TelegramCore

/// Maps a Telegram peer onto the facts `gramPotIsEligible` understands.
/// A legacy group has no public username. A supergroup counts only when its info is `.group` and it has no username.
/// An unknown channel member count stays ineligible.
public func gramPotGroupFacts(
    peer: EnginePeer?,
    cachedParticipantCount: Int?,
    viewerIsRecipient: Bool,
    openedFromGroupMessage: Bool,
    hasTonPrice: Bool
) -> GramPotGroupFacts {
    switch peer {
    case let .legacyGroup(group):
        return GramPotGroupFacts(
            isGroup: true,
            hasPublicUsername: false,
            memberCount: cachedParticipantCount ?? group.participantCount,
            openedFromGroupMessage: openedFromGroupMessage,
            viewerIsRecipient: viewerIsRecipient,
            hasTonPrice: hasTonPrice
        )
    case let .channel(channel):
        let isGroup: Bool
        if case .group = channel.info {
            isGroup = true
        } else {
            isGroup = false
        }
        let hasPublicUsername = channel.username != nil || !channel.usernames.isEmpty
        return GramPotGroupFacts(
            isGroup: isGroup,
            hasPublicUsername: hasPublicUsername,
            memberCount: cachedParticipantCount,
            openedFromGroupMessage: openedFromGroupMessage,
            viewerIsRecipient: viewerIsRecipient,
            hasTonPrice: hasTonPrice
        )
    default:
        return GramPotGroupFacts(
            isGroup: false,
            hasPublicUsername: false,
            memberCount: nil,
            openedFromGroupMessage: openedFromGroupMessage,
            viewerIsRecipient: viewerIsRecipient,
            hasTonPrice: hasTonPrice
        )
    }
}

public func gramPotMemberId(_ peerId: EnginePeer.Id) -> GramPotMemberID {
    GramPotMemberID(rawValue: peerId.toInt64())
}

/// One-time conversion of a USD-per-GRAM quote into the integer the pot locks.
/// `payments.currencyRates` reports a `Double`. After this, the pot does not read the `Double` again.
public func gramPotMicroUsdPerGram(usdPerGram: Double) -> Int64? {
    guard usdPerGram.isFinite, usdPerGram >= 0 else {
        return nil
    }
    let micro = (usdPerGram * Double(gramPotMicroUsdPerUsd)).rounded()
    guard micro <= Double(Int64.max) else {
        return nil
    }
    return Int64(micro)
}
