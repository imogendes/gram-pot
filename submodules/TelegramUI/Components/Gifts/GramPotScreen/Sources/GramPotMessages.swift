import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit

/// Posts a service line with `TelegramMediaAction.customText`, so no new media-action case is required.
func gramPotEnqueueServiceText(context: AccountContext, groupPeerId: EnginePeer.Id, text: String) {
    let _ = enqueueMessages(
        account: context.account,
        peerId: groupPeerId,
        messages: [
            .message(
                text: "",
                attributes: [],
                inlineStickers: [:],
                mediaReference: .standalone(media: TelegramMediaAction(action: .customText(text: text, entities: [], additionalAttributes: nil))),
                threadId: nil,
                replyToMessageId: nil,
                replyToStoryId: nil,
                localGroupingKey: nil,
                correlationId: nil,
                bubbleUpEmojiOrStickersets: []
            )
        ]
    ).startStandalone()
}

/// Posts the pot card or the local preview of the gift card. The official-account delivery is server-authored.
func gramPotEnqueueCard(context: AccountContext, groupPeerId: EnginePeer.Id, attribute: GramPotMessageAttribute) {
    let _ = enqueueMessages(
        account: context.account,
        peerId: groupPeerId,
        messages: [
            .message(
                text: "",
                attributes: [attribute],
                inlineStickers: [:],
                mediaReference: nil,
                threadId: nil,
                replyToMessageId: nil,
                replyToStoryId: nil,
                localGroupingKey: nil,
                correlationId: nil,
                bubbleUpEmojiOrStickersets: []
            )
        ]
    ).startStandalone()
}

/// Applies only this device's wallet delta. Other members' debits and credits happen on their own clients.
/// `.spendEscrow` is not a wallet movement.
func gramPotApplyLocalWallet(context: AccountContext, effects: [GramPotWalletEffect], localMemberId: GramPotMemberID) {
    let delta = GramPot.localWalletDelta(effects: effects, localMemberId: localMemberId)
    guard delta != 0, let tonContext = context.tonContext, tonContext.ton else {
        return
    }
    tonContext.add(balance: StarsAmount(value: delta, nanos: 0))
}
