import XCTest
@testable import GramPotLogic

final class GramPotLogicTests: XCTestCase {
    private let nano = gramPotNanoPerGram
    private let rate: Int64 = 1_313_000
    private let you = GramPotMemberID(rawValue: 1)
    private let theo = GramPotMemberID(rawValue: 2)
    private let maya = GramPotMemberID(rawValue: 3)
    private let apollo = GramPotMemberID(rawValue: 4)
    private let ellie = GramPotMemberID(rawValue: 5)
    private let jack = GramPotMemberID(rawValue: 6)
    private let createdAt: Int64 = 1_700_000_000

    private var friends: [GramPotMemberID] {
        [self.you, self.theo, self.maya, self.apollo, self.ellie, self.jack]
    }

    private func storyPot() throws -> GramPot {
        let started = GramPot.start(
            id: 1,
            priceNano: 4_000 * self.nano,
            microUsdPerGram: self.rate,
            recipientId: self.jack,
            memberIds: self.friends,
            createdAt: self.createdAt
        )
        return try started.get()
    }

    func testResistanceStorySplitsFiveExactSpots() throws {
        let pot = try self.storyPot()
        XCTAssertEqual(pot.phase, .open)
        XCTAssertEqual(pot.contributions, [])
        XCTAssertEqual(pot.deadline, self.createdAt + 86_400)
        XCTAssertEqual(pot.spotOrder, [self.you, self.theo, self.maya, self.apollo, self.ellie])
        let spot = 800 * self.nano
        for member in pot.spotOrder {
            XCTAssertEqual(pot.spotAmounts[member], spot)
        }
        XCTAssertNil(pot.spotAmounts[self.jack])
        XCTAssertEqual(pot.spotAmounts.values.reduce(0, +), pot.priceNano)
        XCTAssertEqual(gramPotUsdCents(nanoGram: pot.priceNano, microUsdPerGram: self.rate), 525_200)
        XCTAssertEqual(gramPotUsdCents(nanoGram: spot, microUsdPerGram: self.rate), 105_040)
        XCTAssertEqual(gramPotUsdText(cents: 525_200), "$5,252.00")
        XCTAssertEqual(gramPotUsdText(cents: 105_040), "$1,050.40")
        XCTAssertEqual(gramPotGramText(nano: pot.priceNano), "4,000")
        XCTAssertEqual(gramPotGramText(nano: spot), "800")
    }

    func testChipInDebitsWalletIntoEscrowAndCompletesWithoutASecondCharge() throws {
        var pot = try self.storyPot()
        var balances = Dictionary(uniqueKeysWithValues: self.friends.map { ($0, 10_000 * self.nano) })
        var escrow = GramPotEscrow()
        let spot = 800 * self.nano
        let order = [self.you, self.theo, self.maya, self.apollo, self.ellie]

        for (index, member) in order.enumerated() {
            let before = balances[member]!
            let transition = pot.chipIn(memberId: member, nano: spot, balanceNano: before, now: self.createdAt + 10)
            XCTAssertNil(transition.error)
            escrow.apply(transition.effects)
            let delta = GramPot.localWalletDelta(effects: transition.effects, localMemberId: member)
            balances[member] = before + delta
            XCTAssertEqual(delta, -spot)
            XCTAssertEqual(balances[member], before - spot)
            if index == 0 {
                XCTAssertEqual(pot.phase, .filling)
                XCTAssertEqual(transition.effects.map(\.kind), [.debit])
            }
            if index < order.count - 1 {
                XCTAssertEqual(pot.phase, .filling)
                XCTAssertEqual(escrow.spentNano, 0)
                XCTAssertEqual(escrow.heldNano, spot * Int64(index + 1))
            }
        }

        XCTAssertEqual(pot.phase, .complete)
        XCTAssertEqual(escrow.heldNano, 0)
        XCTAssertEqual(escrow.spentNano, pot.priceNano)
        for member in order {
            XCTAssertEqual(balances[member], 10_000 * self.nano - spot)
        }
        XCTAssertEqual(balances[self.jack], 10_000 * self.nano)

        let leave = pot.memberLeft(memberId: self.theo, now: self.createdAt + 20)
        XCTAssertEqual(leave.effects, [])
        XCTAssertEqual(pot.phase, .complete)
        let later = pot.advance(now: self.createdAt + 86_400)
        XCTAssertEqual(later.effects, [])
        XCTAssertEqual(pot.phase, .complete)
    }

    func testStartDoesNotDebitAndRecipientCannotChipIn() throws {
        var pot = try self.storyPot()
        XCTAssertEqual(pot.phase, .open)
        XCTAssertEqual(pot.contributedNano, 0)
        let refused = pot.chipIn(memberId: self.jack, nano: 800 * self.nano, balanceNano: 10_000 * self.nano, now: self.createdAt)
        XCTAssertEqual(refused.error, .isRecipient)
        XCTAssertEqual(refused.effects, [])
        XCTAssertEqual(pot.phase, .open)
    }

    func testRefusesDoubleWrongOutsiderAndShortBalance() throws {
        var pot = try self.storyPot()
        let spot = 800 * self.nano
        let first = pot.chipIn(memberId: self.you, nano: spot, balanceNano: spot, now: self.createdAt)
        XCTAssertNil(first.error)
        XCTAssertEqual(GramPot.localWalletDelta(effects: first.effects, localMemberId: self.you), -spot)

        let again = pot.chipIn(memberId: self.you, nano: spot, balanceNano: spot, now: self.createdAt)
        XCTAssertEqual(again.error, .alreadyContributed)
        XCTAssertEqual(pot.contributions.count, 1)

        let wrong = pot.chipIn(memberId: self.theo, nano: spot - 1, balanceNano: spot, now: self.createdAt)
        XCTAssertEqual(wrong.error, .wrongAmount)

        let outsider = GramPotMemberID(rawValue: 99)
        let outside = pot.chipIn(memberId: outsider, nano: spot, balanceNano: spot, now: self.createdAt)
        XCTAssertEqual(outside.error, .notAMember)

        let short = pot.chipIn(memberId: self.theo, nano: spot, balanceNano: spot - 1, now: self.createdAt)
        XCTAssertEqual(short.error, .insufficientBalance)
        XCTAssertEqual(pot.phase, .filling)
        XCTAssertEqual(pot.contributions.map(\.memberId), [self.you])
    }

    func testLeaveRefundsEveryWalletAndDoesNotResplit() throws {
        var pot = try self.storyPot()
        let spot = 800 * self.nano
        var escrow = GramPotEscrow()
        var balances: [GramPotMemberID: Int64] = [
            self.you: 5_000 * self.nano,
            self.theo: 5_000 * self.nano,
            self.maya: 5_000 * self.nano
        ]
        for member in [self.you, self.theo, self.maya] {
            let transition = pot.chipIn(memberId: member, nano: spot, balanceNano: balances[member]!, now: self.createdAt + 5)
            escrow.apply(transition.effects)
            balances[member]! += GramPot.localWalletDelta(effects: transition.effects, localMemberId: member)
        }
        XCTAssertEqual(escrow.heldNano, spot * 3)

        let stranger = pot.memberLeft(memberId: GramPotMemberID(rawValue: 50), now: self.createdAt + 6)
        XCTAssertEqual(stranger.effects, [])
        XCTAssertEqual(pot.phase, .filling)

        let left = pot.memberLeft(memberId: self.ellie, now: self.createdAt + 6)
        XCTAssertNil(left.error)
        XCTAssertEqual(pot.phase, .refunded)
        XCTAssertEqual(pot.contributions, [])
        escrow.apply(left.effects)
        for effect in left.effects {
            let member = try XCTUnwrap(effect.memberId)
            balances[member, default: 0] += GramPot.localWalletDelta(effects: [effect], localMemberId: member)
        }
        XCTAssertEqual(escrow.heldNano, 0)
        XCTAssertEqual(escrow.spentNano, 0)
        XCTAssertEqual(balances[self.you], 5_000 * self.nano)
        XCTAssertEqual(balances[self.theo], 5_000 * self.nano)
        XCTAssertEqual(balances[self.maya], 5_000 * self.nano)
        XCTAssertEqual(Set(left.effects.map(\.kind)), [.credit])

        let after = pot.chipIn(memberId: self.apollo, nano: spot, balanceNano: spot, now: self.createdAt + 7)
        XCTAssertEqual(after.error, .closed)
    }

    func testTimeoutRefundsAndALateChipInDoesNotDebit() throws {
        var pot = try self.storyPot()
        let spot = 800 * self.nano
        var escrow = GramPotEscrow()
        let paid = pot.chipIn(memberId: self.you, nano: spot, balanceNano: spot * 2, now: self.createdAt + 1)
        escrow.apply(paid.effects)

        let stillOpen = pot.advance(now: pot.deadline - 1)
        XCTAssertEqual(stillOpen.effects, [])
        XCTAssertEqual(pot.phase, .filling)

        var balance = spot * 2 - spot
        let late = pot.chipIn(memberId: self.theo, nano: spot, balanceNano: balance, now: pot.deadline)
        XCTAssertEqual(late.error, .expired)
        XCTAssertEqual(pot.phase, .expired)
        XCTAssertEqual(late.effects.map(\.kind), [.credit])
        XCTAssertEqual(late.effects.first?.memberId, self.you)
        balance += GramPot.localWalletDelta(effects: late.effects, localMemberId: self.theo)
        let youBack = GramPot.localWalletDelta(effects: late.effects, localMemberId: self.you)
        XCTAssertEqual(youBack, spot)
        XCTAssertEqual(balance, spot * 2 - spot)
        escrow.apply(late.effects)
        XCTAssertEqual(escrow.heldNano, 0)

        let again = pot.advance(now: pot.deadline + 10)
        XCTAssertEqual(again.effects, [])
    }

    func testRemainderGoesToTheEarliestSpots() {
        let amounts = gramPotEqualSpotAmounts(priceNano: 10, spotCount: 3)
        XCTAssertEqual(amounts, [4, 3, 3])
        XCTAssertEqual(amounts?.reduce(0, +), 10)

        let oneNanoApart = gramPotEqualSpotAmounts(priceNano: 1_000, spotCount: 6)
        XCTAssertEqual(oneNanoApart, [167, 167, 167, 167, 166, 166])
        XCTAssertEqual(oneNanoApart?.reduce(0, +), 1_000)
        let distinct = Set(oneNanoApart ?? [])
        XCTAssertLessThanOrEqual(distinct.max()! - distinct.min()!, 1)

        XCTAssertNil(gramPotEqualSpotAmounts(priceNano: 0, spotCount: 3))
        XCTAssertNil(gramPotEqualSpotAmounts(priceNano: -5, spotCount: 3))
        XCTAssertNil(gramPotEqualSpotAmounts(priceNano: 2, spotCount: 0))
        XCTAssertNil(gramPotEqualSpotAmounts(priceNano: 2, spotCount: 5))
    }

    func testFiatHalfUpAndWideMultiply() {
        XCTAssertEqual(gramPotUsdCents(nanoGram: 0, microUsdPerGram: self.rate), 0)
        XCTAssertNil(gramPotUsdCents(nanoGram: -1, microUsdPerGram: self.rate))
        XCTAssertNil(gramPotUsdCents(nanoGram: 1, microUsdPerGram: -1))

        let halfNano: Int64 = 5_000_000_000_000
        XCTAssertEqual(gramPotUsdCents(nanoGram: halfNano, microUsdPerGram: 1), 1)
        XCTAssertEqual(gramPotUsdCents(nanoGram: halfNano - 1, microUsdPerGram: 1), 0)

        let eightThousand = 8_000 * self.nano
        XCTAssertEqual(gramPotUsdCents(nanoGram: eightThousand, microUsdPerGram: self.rate), 1_050_400)
        XCTAssertEqual(gramPotUsdText(cents: 1_050_400), "$10,504.00")
        XCTAssertEqual(gramPotGramText(nano: 800 * self.nano + 1), "800.000000001")
        XCTAssertNil(gramPotGramText(nano: -1))
        XCTAssertNil(gramPotUsdText(cents: -1))
    }

    func testEligibilityIsPrivateGroupOfTwoToEight() {
        func facts(
            isGroup: Bool = true,
            hasPublicUsername: Bool = false,
            memberCount: Int? = 6,
            openedFromGroupMessage: Bool = true,
            viewerIsRecipient: Bool = false,
            hasTonPrice: Bool = true
        ) -> GramPotGroupFacts {
            GramPotGroupFacts(
                isGroup: isGroup,
                hasPublicUsername: hasPublicUsername,
                memberCount: memberCount,
                openedFromGroupMessage: openedFromGroupMessage,
                viewerIsRecipient: viewerIsRecipient,
                hasTonPrice: hasTonPrice
            )
        }
        XCTAssertTrue(gramPotIsEligible(facts()))
        XCTAssertTrue(gramPotIsEligible(facts(memberCount: 2)))
        XCTAssertTrue(gramPotIsEligible(facts(memberCount: 8)))
        XCTAssertFalse(gramPotIsEligible(facts(memberCount: 1)))
        XCTAssertFalse(gramPotIsEligible(facts(memberCount: 9)))
        XCTAssertFalse(gramPotIsEligible(facts(memberCount: nil)))
        XCTAssertFalse(gramPotIsEligible(facts(isGroup: false)))
        XCTAssertFalse(gramPotIsEligible(facts(hasPublicUsername: true)))
        XCTAssertFalse(gramPotIsEligible(facts(openedFromGroupMessage: false)))
        XCTAssertFalse(gramPotIsEligible(facts(viewerIsRecipient: true)))
        XCTAssertFalse(gramPotIsEligible(facts(hasTonPrice: false)))
        XCTAssertEqual(gramPotSpotCount(memberCount: 6), 5)
        XCTAssertEqual(gramPotSpotCount(memberCount: 2), 1)
        XCTAssertNil(gramPotSpotCount(memberCount: 1))
    }

    func testGroupOfTwoPaysTheWholePrice() throws {
        let pot = try GramPot.start(
            id: 2,
            priceNano: 4_000 * self.nano,
            microUsdPerGram: self.rate,
            recipientId: self.jack,
            memberIds: [self.you, self.jack],
            createdAt: self.createdAt
        ).get()
        XCTAssertEqual(pot.spotAmounts[self.you], pot.priceNano)
        var mutable = pot
        let transition = mutable.chipIn(memberId: self.you, nano: pot.priceNano, balanceNano: pot.priceNano, now: self.createdAt)
        XCTAssertNil(transition.error)
        XCTAssertEqual(mutable.phase, .complete)
        XCTAssertEqual(transition.effects.map(\.kind), [.debit, .spendEscrow])
    }

    func testStartRejectsABadPot() {
        XCTAssertEqual(
            GramPot.start(id: 1, priceNano: 0, microUsdPerGram: 1, recipientId: self.jack, memberIds: self.friends, createdAt: 0).failure,
            .invalidPrice
        )
        XCTAssertEqual(
            GramPot.start(id: 1, priceNano: 10, microUsdPerGram: -1, recipientId: self.jack, memberIds: [self.you, self.jack], createdAt: 0).failure,
            .invalidRate
        )
        XCTAssertEqual(
            GramPot.start(id: 1, priceNano: 10, microUsdPerGram: 1, recipientId: self.jack, memberIds: [self.you, self.theo], createdAt: 0).failure,
            .recipientNotInGroup
        )
        XCTAssertEqual(
            GramPot.start(id: 1, priceNano: 10, microUsdPerGram: 1, recipientId: self.jack, memberIds: [self.jack, self.jack], createdAt: 0).failure,
            .duplicateMember
        )
        XCTAssertEqual(
            GramPot.start(id: 1, priceNano: 10, microUsdPerGram: 1, recipientId: self.jack, memberIds: [self.jack], createdAt: 0).failure,
            .noSpots
        )
        XCTAssertEqual(
            GramPot.start(id: 1, priceNano: 10, microUsdPerGram: 1, recipientId: self.jack, memberIds: [self.you, self.jack], createdAt: Int64.max - 10).failure,
            .timestampOverflow
        )
        XCTAssertEqual(
            GramPot.start(id: 1, priceNano: 3, microUsdPerGram: 1, recipientId: self.jack, memberIds: self.friends, createdAt: 0).failure,
            .invalidPrice
        )
    }

    func testNamesStayInPlaceAndDoNotSayShare() {
        let names = ["Imogen", "Theo", "Maya", "Apollo", "Ellie"]
        XCTAssertEqual(gramPotJoinedNames(names), "Imogen, Theo, Maya, Apollo and Ellie")
        XCTAssertEqual(gramPotJoinedNames(["Imogen"]), "Imogen")
        XCTAssertEqual(gramPotJoinedNames(["Imogen", "Theo"]), "Imogen and Theo")
        let shown = gramPotNamesForViewer(names, viewerName: "Imogen")
        XCTAssertEqual(shown, ["You", "Theo", "Maya", "Apollo", "Ellie"])
        XCTAssertEqual(
            gramPotGiftFromFooter(names: names, viewerName: "Imogen"),
            "A gift from You, Theo, Maya, Apollo and Ellie via Gram Pot."
        )
        XCTAssertEqual(
            gramPotSentYouText(names: names, viewerName: "Jack"),
            "Imogen, Theo, Maya, Apollo and Ellie sent you a gift via Gram Pot"
        )
        let middle = gramPotNamesForViewer(["Theo", "Imogen", "Maya"], viewerName: "Imogen")
        XCTAssertEqual(middle, ["Theo", "You", "Maya"])
        XCTAssertEqual(gramPotStartedText(actor: "You", recipient: "Jack"), "You started a Gram Pot for Jack")
        XCTAssertEqual(gramPotChippedInText(actor: "Theo", amount: "800"), "Theo chipped in 800")
        XCTAssertEqual(gramPotCompleteText(recipient: "Jack"), "Gram Pot complete · Jack received the gift")
        XCTAssertEqual(gramPotProgressText(contributed: "0", price: "4,000"), "0 of 4,000")

        let copy = [
            gramPotGiftFromFooter(names: names, viewerName: "Imogen"),
            gramPotSentYouText(names: names, viewerName: "Jack"),
            gramPotStartedText(actor: "You", recipient: "Jack"),
            gramPotChippedInText(actor: "Theo", amount: "800"),
            gramPotCompleteText(recipient: "Jack"),
            gramPotProgressText(contributed: "0", price: "4,000")
        ].joined(separator: " ")
        XCTAssertNil(copy.range(of: "share", options: .caseInsensitive))
    }
}

private extension Result {
    var failure: Failure? {
        switch self {
        case .success:
            return nil
        case let .failure(error):
            return error
        }
    }
}
