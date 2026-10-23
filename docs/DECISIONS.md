# Gram Pot — decision log

What was decided while building the prototype, and why. Each entry is one decision. Replaced decisions stay in the list, marked, so the numbers other documents refer to stay valid.

The client facts were read from Telegram-iOS commit `fb0e62ba8a147f0821da6aa63c09da7d79a10111`.

## Shape of the repository

**D-001. Publish a small concept repository, not a full clone of Telegram-iOS.** [make-an-offer](https://github.com/imogendes/make-an-offer) is the model: a landing README, a patch, and readable copies of the touched sources. The visual-quote entry is the model for the writing: a feature README, a code map, and this log, in English.

**D-002. Put the feature at the real Telegram-iOS paths.** New screens live under `submodules/TelegramUI/Components/...`. Edits to existing files keep those files' paths. A reader can diff them against the pinned commit.

**D-003. Keep the rules in a Swift package that does not import Telegram.** `GramPotLogic` is what `swift test` runs. The screen module vendors the same sources, because the client builds with Bazel and does not take a Swift package. The two copies must stay the same.

**D-004. Pin the patch to `fb0e62ba8a147f0821da6aa63c09da7d79a10111`.** That is master as read on 22 October 2026 ("Bump version"). `git apply --check` is the check that is possible here. A Bazel or Xcode build of Telegram-iOS is not.

**D-005. No demo video.** A full client build is not available on this machine, so there is no recording of the signed-in app. The screens in the brief are the UI source of truth.

**D-006. Licence.** make-an-offer ships no licence file. This repository says so in `LICENSE`. Files derived from Telegram-iOS stay under GPL-2.0, which is what that project requires. The notes and `GramPotLogic` follow make-an-offer's publication, with no extra copyright assignment.

## Who can start a pot

**D-007. Gram Pot is a menu item on the collectible gift sheet, after Share.** `GiftViewScreen.openMore()` already builds `ContextMenuActionItem`s. Copy Link and Share are always there for a unique gift. Gram Pot is appended after Share. The existing Share item is unchanged. The pot's own strings do not use the word "share".

**D-008. The menu item exists only for a collectible sent in a private group of 2–8 members.** A legacy group counts when it has no username. A supergroup counts when `TelegramChannelInfo` is `.group` and both `username` and `usernames` are empty. Member count is `TelegramGroup.participantCount`, or `CachedChannelData.participantsSummary.memberCount` for a channel. If the channel count is unknown, the item stays hidden.

**D-009. The recipient does not see the item, and does not take a spot.** The recipient is the author of the message the collectible was opened from. Spots are the other members. A group of six including the recipient is five spots. A group of two is one spot, and that spot pays the whole price. That is still eligible.

**D-010. Only a gift with a GRAM (TON) resale price can start a pot.** The price is `resellAmounts` for `.ton`. Stars-only listings are out. GRAM amounts are nano-ton: `StarsAmount.value` with `nanos == 0`, and 1 GRAM = 1_000_000_000 nano. 4,000 GRAM is 4_000_000_000_000 nano. 800 GRAM is 800_000_000_000 nano.

**D-011. The group is not on `makeGiftViewScreen`.** Unique gifts are opened as `.uniqueGift(gift, nil)`, so the chat context is nil. Changing `SharedAccountContext` would break every caller. Instead `OpenResolvedUrl` sets a public `gramPotOrigin` on the `GiftViewScreen` it just created, when `OpenURLContext` is `.chat`. The origin carries the group peer and the message author.

## Money

**D-012. Chip-in debits the member's Telegram GRAM wallet in one tap.** The balance is `context.tonContext`, a `StarsContext` with `ton: true`. `StarsContext.add(balance:)` updates the local mirror. A negative `StarsAmount` debits; the context clamps at zero. Refunds are a positive `add`. There is no Send Money screen and no transfer to another person.

**D-013. Telegram holds the debited GRAM in escrow until the pot resolves.** The price and the fiat rate are locked at the start. Fiat in the story is $1.313 per GRAM, so 4,000 GRAM is $5,252.00 and 800 GRAM is $1,050.40. The rate is stored as integer micro-USD per GRAM (1_313_000) and converted half-up, so the display does not depend on binary floating point.

**D-014. Do not call `buyStarGift` when the pot completes.** That method charges the buyer again. The wallet was already debited into escrow. Completing the pot spends the escrow. The proposed server method is `payments.finishGramPot`. The client mirrors only the local user's wallet; other members' devices apply their own debits and credits.

**D-015. A member leaving, or 24 hours, refunds everyone. No resplit.** The member list is snapshotted when the pot starts. If any of those peers leaves while the pot is open or filling, every contribution is credited back and the phase is `refunded`. If `now` passes `createdAt + 24h` while still open or filling, the phase is `expired` and the same credits are issued. A completed pot does not refund.

**D-016. Equal spots, remainder to the earliest spots.** Integer division of the nano price by the spot count. The first `price % count` spots get one extra nano. Spots differ by at most 1 nano and sum to the price. 4,000 GRAM across 5 spots is exact, 800 each.

## State and chat

**D-017. Phases are open, filling, complete, refunded, expired.** `open` is created with the price locked and nobody in yet. The chip-in screen can say "0 of 4,000 · you're first". The first successful chip-in moves to `filling`. `complete` is when the contributed nano equals the price. Start does not debit. Chip in does.

**D-018. One chip-in per spot, for the assigned amount, and only from a member.** Reject the recipient, an outsider, a second chip-in, a wrong amount, a non-positive price, a recipient who is not in the group, and a balance below the spot. If the deadline has passed, chip-in expires the pot instead of accepting.

**D-019. Service lines reuse `TelegramMediaAction.customText`.** A new media-action case would force a long list of exhaustive switches across the client. "You started a Gram Pot for Jack", "Theo chipped in 800", and "Gram Pot complete · Jack received the gift" are custom text. The pot card and Jack's gift card are a new `GramPotMessageAttribute` plus a bubble content node, registered with `declareEncodable` from `telegramUIDeclareEncodables()`.

**D-020. The owner row drops the avatar only for this row.** `PeerTableCellComponent` always drew a 22pt avatar. A `showsAvatar` flag defaults to true, so the From row and the Telegram row stay as they are. The owner row passes false. Name-only and address rows already had no avatar.

**D-021. After delivery the sheet is not a shop.** The selling footer becomes "A gift from … via Gram Pot." The Buy button becomes Done.

**D-022. The keypad is the wallet keypad, and it does not change the price.** `WalletSendKeyboardComponent` is on screen because that is the GRAM keypad people already see. The listing and the spot amount are locked. Key presses do not retarget the pot.

**D-023. "You" is substituted in place.** The English list is "A, B, C and D", with no Oxford comma. The viewer's name is replaced with "You" where it stands. The names are not reordered to put "You" first.

## Strings and the proposed API

**D-024. New copy is English keys under the `GramPot` prefix.** `GramPot.Menu` becomes `strings.GramPot_Menu` after codegen. Keys are appended to `Localizable.strings`. Codegen is not run here.

**D-025. The server method is marked proposed.** `payments.finishGramPot` is documented as not part of the current schema. Layer and method numbers in the patch are placeholders, not assigned TL ids.
