import Foundation

public struct GramPotMemberID: Hashable, Sendable, Codable, RawRepresentable {
    public var rawValue: Int64

    public init(rawValue: Int64) {
        self.rawValue = rawValue
    }
}

public enum GramPotPhase: String, Sendable, Equatable, Codable {
    /// Created, price locked, nobody has chipped in.
    case open
    /// At least one spot is paid and the pot is not full.
    case filling
    /// The spots sum to the price. Escrow is spent on the gift. Not refunded.
    case complete
    /// A snapshotted member left before the pot filled. Every contribution was credited back.
    case refunded
    /// 24 hours passed before the pot filled. Every contribution was credited back.
    case expired
}

public enum GramPotError: Error, Equatable, Sendable {
    case invalidPrice
    case invalidRate
    case recipientNotInGroup
    case duplicateMember
    case noSpots
    case timestampOverflow
    case closed
    case expired
    case isRecipient
    case notAMember
    case alreadyContributed
    case wrongAmount
    case insufficientBalance
}

/// A change to someone's Telegram GRAM wallet, or to the escrow that wallet was debited into.
///
/// `.debit` is the Chip in tap: that member's wallet pays the spot into escrow.
/// `.credit` is the refund of that debit, back to the same wallet.
/// `.spendEscrow` buys the gift from escrow. It does not debit a wallet again.
public struct GramPotWalletEffect: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case debit
        case credit
        case spendEscrow
    }

    public var kind: Kind
    /// Nil for `.spendEscrow`, which is not a wallet movement.
    public var memberId: GramPotMemberID?
    public var nano: Int64

    public init(kind: Kind, memberId: GramPotMemberID?, nano: Int64) {
        self.kind = kind
        self.memberId = memberId
        self.nano = nano
    }
}

/// What a call did. `error` is set when the requested action was refused.
/// `effects` are still applied in that case when the pot had to expire in order to refuse.
public struct GramPotTransition: Equatable, Sendable {
    public var effects: [GramPotWalletEffect]
    public var error: GramPotError?

    public init(effects: [GramPotWalletEffect], error: GramPotError?) {
        self.effects = effects
        self.error = error
    }

    public var succeeded: Bool {
        self.error == nil
    }
}

public struct GramPotContribution: Equatable, Sendable, Codable {
    public var memberId: GramPotMemberID
    public var nano: Int64

    public init(memberId: GramPotMemberID, nano: Int64) {
        self.memberId = memberId
        self.nano = nano
    }
}

/// One pot. The price, the fiat rate, and the member list are locked at the start.
/// Chip-in debits a wallet into escrow. Start itself does not.
public struct GramPot: Equatable, Sendable {
    public static let deadlineInterval: Int64 = 86_400

    public let id: Int64
    public let priceNano: Int64
    public let microUsdPerGram: Int64
    public let recipientId: GramPotMemberID
    /// Snapshot order, including the recipient.
    public let memberIds: [GramPotMemberID]
    public let createdAt: Int64
    /// Payers in snapshot order, recipient excluded. Earliest spots take the remainder nano.
    public let spotOrder: [GramPotMemberID]
    public let spotAmounts: [GramPotMemberID: Int64]
    public private(set) var contributions: [GramPotContribution]
    public private(set) var phase: GramPotPhase

    public var deadline: Int64 {
        self.createdAt + GramPot.deadlineInterval
    }

    public var contributedNano: Int64 {
        self.contributions.reduce(0) { $0 + $1.nano }
    }

    public static func start(
        id: Int64,
        priceNano: Int64,
        microUsdPerGram: Int64,
        recipientId: GramPotMemberID,
        memberIds: [GramPotMemberID],
        createdAt: Int64
    ) -> Result<GramPot, GramPotError> {
        guard priceNano > 0 else {
            return .failure(.invalidPrice)
        }
        guard microUsdPerGram >= 0 else {
            return .failure(.invalidRate)
        }
        guard memberIds.contains(recipientId) else {
            return .failure(.recipientNotInGroup)
        }
        var seen: Set<GramPotMemberID> = []
        for memberId in memberIds {
            if seen.contains(memberId) {
                return .failure(.duplicateMember)
            }
            seen.insert(memberId)
        }
        let spotOrder = memberIds.filter { $0 != recipientId }
        guard !spotOrder.isEmpty else {
            return .failure(.noSpots)
        }
        guard let amounts = gramPotEqualSpotAmounts(priceNano: priceNano, spotCount: spotOrder.count) else {
            return .failure(.invalidPrice)
        }
        let (_, overflow) = createdAt.addingReportingOverflow(deadlineInterval)
        if overflow {
            return .failure(.timestampOverflow)
        }
        var spotAmounts: [GramPotMemberID: Int64] = [:]
        for (memberId, amount) in zip(spotOrder, amounts) {
            spotAmounts[memberId] = amount
        }
        let pot = GramPot(
            id: id,
            priceNano: priceNano,
            microUsdPerGram: microUsdPerGram,
            recipientId: recipientId,
            memberIds: memberIds,
            createdAt: createdAt,
            spotOrder: spotOrder,
            spotAmounts: spotAmounts,
            contributions: [],
            phase: .open
        )
        return .success(pot)
    }

    /// One Chip in tap. Debits `memberId`'s wallet by the locked spot when `balanceNano` covers it.
    /// A tap after the deadline expires the pot and refunds what was already held.
    public mutating func chipIn(
        memberId: GramPotMemberID,
        nano: Int64,
        balanceNano: Int64,
        now: Int64
    ) -> GramPotTransition {
        if self.isTerminal {
            return GramPotTransition(effects: [], error: .closed)
        }
        if now >= self.deadline {
            return self.expire(refusingChipIn: true)
        }
        guard let expected = self.spotAmounts[memberId] else {
            if memberId == self.recipientId {
                return GramPotTransition(effects: [], error: .isRecipient)
            }
            return GramPotTransition(effects: [], error: .notAMember)
        }
        if self.contributions.contains(where: { $0.memberId == memberId }) {
            return GramPotTransition(effects: [], error: .alreadyContributed)
        }
        if nano != expected {
            return GramPotTransition(effects: [], error: .wrongAmount)
        }
        if balanceNano < nano {
            return GramPotTransition(effects: [], error: .insufficientBalance)
        }
        self.contributions.append(GramPotContribution(memberId: memberId, nano: nano))
        var effects = [GramPotWalletEffect(kind: .debit, memberId: memberId, nano: nano)]
        if self.contributedNano == self.priceNano {
            self.phase = .complete
            effects.append(GramPotWalletEffect(kind: .spendEscrow, memberId: nil, nano: self.priceNano))
        } else {
            self.phase = .filling
        }
        return GramPotTransition(effects: effects, error: nil)
    }

    /// A snapshotted member leaving while the pot is open or filling refunds everyone. No resplit.
    /// Leaving after complete, refund, or expiry does nothing. Someone who was not in the snapshot does nothing.
    public mutating func memberLeft(memberId: GramPotMemberID, now: Int64) -> GramPotTransition {
        if self.isTerminal {
            return GramPotTransition(effects: [], error: nil)
        }
        if now >= self.deadline {
            return self.expire(refusingChipIn: false)
        }
        guard self.memberIds.contains(memberId) else {
            return GramPotTransition(effects: [], error: nil)
        }
        let effects = self.takeRefunds()
        self.phase = .refunded
        return GramPotTransition(effects: effects, error: nil)
    }

    /// Moves an open or filling pot to expired once `now` reaches the deadline, and refunds.
    public mutating func advance(now: Int64) -> GramPotTransition {
        if self.isTerminal || now < self.deadline {
            return GramPotTransition(effects: [], error: nil)
        }
        return self.expire(refusingChipIn: false)
    }

    /// Signed nano delta for one wallet. Debit is negative, credit is positive.
    /// Escrow spend is not a wallet movement: the wallet was already debited at chip-in.
    public static func localWalletDelta(effects: [GramPotWalletEffect], localMemberId: GramPotMemberID) -> Int64 {
        var delta: Int64 = 0
        for effect in effects {
            guard effect.memberId == localMemberId else {
                continue
            }
            switch effect.kind {
            case .debit:
                delta -= effect.nano
            case .credit:
                delta += effect.nano
            case .spendEscrow:
                break
            }
        }
        return delta
    }

    private var isTerminal: Bool {
        switch self.phase {
        case .complete, .refunded, .expired:
            return true
        case .open, .filling:
            return false
        }
    }

    private mutating func expire(refusingChipIn: Bool) -> GramPotTransition {
        let effects = self.takeRefunds()
        self.phase = .expired
        return GramPotTransition(effects: effects, error: refusingChipIn ? .expired : nil)
    }

    private mutating func takeRefunds() -> [GramPotWalletEffect] {
        let effects = self.contributions.map { contribution in
            GramPotWalletEffect(kind: .credit, memberId: contribution.memberId, nano: contribution.nano)
        }
        self.contributions = []
        return effects
    }
}

/// Holds GRAM between the wallet debit and either the purchase or the refund.
public struct GramPotEscrow: Equatable, Sendable {
    public private(set) var heldNano: Int64
    public private(set) var spentNano: Int64

    public init(heldNano: Int64 = 0, spentNano: Int64 = 0) {
        self.heldNano = heldNano
        self.spentNano = spentNano
    }

    public mutating func apply(_ effects: [GramPotWalletEffect]) {
        for effect in effects {
            switch effect.kind {
            case .debit:
                self.heldNano += effect.nano
            case .credit:
                self.heldNano -= effect.nano
            case .spendEscrow:
                self.heldNano -= effect.nano
                self.spentNano += effect.nano
            }
        }
    }
}
