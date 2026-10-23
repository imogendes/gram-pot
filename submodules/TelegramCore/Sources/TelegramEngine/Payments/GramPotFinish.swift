import Foundation
import Postbox
import SwiftSignalKit

public enum GramPotFinishError: Equatable {
    /// `payments.finishGramPot` is not in the published schema. Placeholder only.
    /// Do not fall back to `buyStarGift`: the wallet was already debited into escrow.
    case proposedMethodUnavailable
}

public extension TelegramEngine.Payments {
    /// Proposed server method. Spends the escrow for `potId` and delivers the collectible to `recipientId`.
    ///
    /// This build does not send a TL query. The method number is not assigned.
    /// Layer: not assigned. Method: `payments.finishGramPot#00000000` flags:# pot_id:long slug:string recipient_id:InputPeer = Updates.
    func finishGramPot(potId: Int64, slug: String, recipientId: EnginePeer.Id) -> Signal<Never, GramPotFinishError> {
        let _ = (potId, slug, recipientId)
        return .fail(.proposedMethodUnavailable)
    }
}
