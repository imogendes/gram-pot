import Foundation
import TelegramCore

/// Gift sheet that can remember the private group a collectible was opened from.
/// `OpenResolvedUrl` talks to this protocol so it does not need a new `makeGiftViewScreen` parameter.
public protocol GramPotGiftScreen: AnyObject {
    func gramPotSetOrigin(groupPeerId: EnginePeer.Id, messageId: EngineMessage.Id?, recipientId: EnginePeer.Id?)
    func gramPotSetDelivery(contributorNames: [String], viewerName: String)
}
