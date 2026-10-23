import Foundation
import Postbox

/// Card attached to a local message: the pot in the group, or the preview of the gift Jack receives.
/// The verified Telegram account message (peer 777000) is produced by the server. This attribute is how our client draws the card.
public final class GramPotMessageAttribute: Equatable, MessageAttribute {
    public enum Kind: Int32 {
        case pot = 0
        case deliveredGift = 1
    }

    public let potId: Int64
    public let kind: Kind
    public let priceNano: Int64
    public let contributedNano: Int64
    public let recipientName: String
    public let contributorNames: [String]
    public let giftTitle: String
    public let model: String
    public let backdrop: String
    public let symbol: String

    public init(
        potId: Int64,
        kind: Kind,
        priceNano: Int64,
        contributedNano: Int64,
        recipientName: String,
        contributorNames: [String],
        giftTitle: String,
        model: String,
        backdrop: String,
        symbol: String
    ) {
        self.potId = potId
        self.kind = kind
        self.priceNano = priceNano
        self.contributedNano = contributedNano
        self.recipientName = recipientName
        self.contributorNames = contributorNames
        self.giftTitle = giftTitle
        self.model = model
        self.backdrop = backdrop
        self.symbol = symbol
    }

    public required init(decoder: PostboxDecoder) {
        self.potId = decoder.decodeInt64ForKey("id", orElse: 0)
        self.kind = Kind(rawValue: decoder.decodeInt32ForKey("k", orElse: 0)) ?? .pot
        self.priceNano = decoder.decodeInt64ForKey("p", orElse: 0)
        self.contributedNano = decoder.decodeInt64ForKey("c", orElse: 0)
        self.recipientName = decoder.decodeStringForKey("r", orElse: "")
        self.contributorNames = decoder.decodeStringArrayForKey("n")
        self.giftTitle = decoder.decodeStringForKey("t", orElse: "")
        self.model = decoder.decodeStringForKey("m", orElse: "")
        self.backdrop = decoder.decodeStringForKey("b", orElse: "")
        self.symbol = decoder.decodeStringForKey("s", orElse: "")
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt64(self.potId, forKey: "id")
        encoder.encodeInt32(self.kind.rawValue, forKey: "k")
        encoder.encodeInt64(self.priceNano, forKey: "p")
        encoder.encodeInt64(self.contributedNano, forKey: "c")
        encoder.encodeString(self.recipientName, forKey: "r")
        encoder.encodeStringArray(self.contributorNames, forKey: "n")
        encoder.encodeString(self.giftTitle, forKey: "t")
        encoder.encodeString(self.model, forKey: "m")
        encoder.encodeString(self.backdrop, forKey: "b")
        encoder.encodeString(self.symbol, forKey: "s")
    }

    public static func ==(lhs: GramPotMessageAttribute, rhs: GramPotMessageAttribute) -> Bool {
        return lhs.potId == rhs.potId
            && lhs.kind == rhs.kind
            && lhs.priceNano == rhs.priceNano
            && lhs.contributedNano == rhs.contributedNano
            && lhs.recipientName == rhs.recipientName
            && lhs.contributorNames == rhs.contributorNames
            && lhs.giftTitle == rhs.giftTitle
            && lhs.model == rhs.model
            && lhs.backdrop == rhs.backdrop
            && lhs.symbol == rhs.symbol
    }
}

private let gramPotAttributeDeclared: Void = {
    declareEncodable(GramPotMessageAttribute.self, f: { GramPotMessageAttribute(decoder: $0) })
    return
}()

/// Called once from `telegramUIDeclareEncodables`. A second call is a no-op.
public func gramPotDeclareMessageAttribute() {
    let _ = gramPotAttributeDeclared
}
