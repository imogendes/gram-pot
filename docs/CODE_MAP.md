# Gram Pot — code map

How the relevant parts of Telegram-iOS work, and where Gram Pot plugs in. Paths are relative to a Telegram-iOS checkout. Line numbers refer to commit `fb0e62ba8a147f0821da6aa63c09da7d79a10111` (master as of 22 October 2026, "Bump version"). Facts were checked by reading that tree. Decisions that follow from them are in [DECISIONS.md](DECISIONS.md). The landing page is [../README.md](../README.md).

No Telegram-iOS file is modified for its own sake. Each edit below is an integration point. New behaviour sits in `GramPotScreen` and in `GramPotLogic`.

## 0. The main finding: the gift sheet, the GRAM wallet, and custom service text already exist

Gram Pot does not need a new chat type or a new wallet.

| Step | Where | What Gram Pot uses |
| --- | --- | --- |
| Open a collectible | `OpenResolvedUrl.swift`, case `.collectible` | `makeGiftViewScreen`, then push. `OpenURLContext.chat(peerId:message:)` is the group and the message. The author of that message is the recipient. |
| Gift sheet menu | `GiftViewScreen.openMore()` | `ContextMenuActionItem`. Copy Link and Share are always present for a unique gift. Gram Pot is one more item after Share. |
| Menu badge | `ContextMenuActionBadge` in `ContextController.swift` | The **New** badge. Same call shape make-an-offer uses for its menu item. |
| GRAM balance | `StarsContext` (`Stars.swift`), `context.tonContext` | `add(balance:)` debits with a negative `StarsAmount` and credits with a positive one. The context clamps at zero. |
| Price | `UniqueGift.resellAmounts`, currency `.ton` | Nano-GRAM. `StarsAmount.nanos` is 0 for TON; `value` is nanoton. 1 GRAM = 1_000_000_000. |
| Service line | `TelegramMediaAction.customText` | "Theo chipped in 800" without a new media-action case. |
| Pot card | A new message attribute, next to `PaidStarsMessageAttribute` | The bubble factory in `ChatMessageBubbleItemNode` already switches on attributes. |
| Buy | `payments.buyStarGift` | Exists, and must not be used for a completed pot. It would charge the wallet again after escrow. |

`makeGiftViewScreen` is called with `.uniqueGift(gift, nil)`. The nil is the chat context. Gram Pot does not change the `SharedAccountContext` protocol to thread the group through. `OpenResolvedUrl` assigns `gramPotOrigin` on the concrete `GiftViewScreen` after it is created. See D-011.

## 1. Gift sheet

**File.** `submodules/TelegramUI/Components/Gifts/GiftViewScreen/Sources/GiftViewScreen.swift`.

**Menu.** `openMore()` builds the context menu. For a unique gift the unconditional items are Copy Link, then Share (`Gift_View_Context_Share`, icon `Chat/Context Menu/Forward`). Other items (pin, price, hide, craft, transfer, theme) depend on ownership. For a collectible the viewer does not own, the menu is effectively Copy Link and Share. Gram Pot is inserted after Share:

- text `GramPot.Menu` ("Gram Pot");
- icon `Chat/Context Menu/Groups` (the people glyph already in the app);
- badge `ContextMenuActionBadge(value:color:style:)` with the **New** label, accent colour, `.label` style.

The peer fetched while the menu is built (`arguments.peerId ?? account`) is the gift owner, not the group. Eligibility uses `gramPotOrigin`, not that peer.

**Eligibility, evaluated when the menu opens.** The origin's peer must be a group:

- legacy `TelegramGroup`: no username (`addressNames` / `indexName` empty), `participantCount` in 2...8;
- supergroup: `TelegramChannelInfo.group`, `username == nil`, `usernames.isEmpty`, member count from `TelegramEngine.EngineData.Item.Peer.ParticipantCount` (`CachedChannelData.participantsSummary.memberCount`).

Engine data items `Peer.Peer`, `Peer.CachedData`, and `Peer.ParticipantCount` are combined with `combineLatest`. Basic-group membership for the snapshot is `CachedGroupData.participants` (`GroupParticipant.peerId`). Supergroup membership is `peerChannelMemberCategoriesContextsManager.recent(...)`, whose state list is rendered channel participants; each participant's `peerId` is the member. If a channel's count is missing, the item stays hidden (D-008).

The viewer must not be the recipient. The recipient is `gramPotOrigin.messageAuthor`. The gift must have a `.ton` resale amount (D-010).

**Owner row.** `PeerTableCellComponent` (`submodules/TelegramUI/Components/PeerTableCellComponent/Sources/PeerTableCellComponent.swift`) always adds a 22pt `AvatarNode` and insets the name by the avatar width plus 6. The owner calls (two sites in `GiftViewScreen`, around the owner section) pass `showsAvatar: false`. The component's default stays `true`.

**After delivery.** The selling footer (`Gift_View_SellingGiftInfo`) is replaced, when `gramPotDelivery` is set, by "A gift from … via Gram Pot." The Buy button is replaced by Done. The outer condition that chooses the footer includes this case, otherwise the selling footer still wins.

**Value row.** The sheet formats `uniqueGift.valueAmount` and `valueCurrency` with `formatCurrencyAmount`. The story's $5,252.00 is that value, not a second field. The pot locks its own micro-USD rate at start (D-013) for the spot lines.

## 2. Opening the sheet from a group

**File.** `submodules/TelegramUI/Sources/OpenResolvedUrl.swift`, case `.collectible`.

The controller is created with `context.sharedContext.makeGiftViewScreen(...)` and pushed. Between those two lines, when `urlContext` is `.chat(peerId, message, _)`, the code casts to `GiftViewScreen` and sets:

- group peer id;
- message id;
- author id (`message?.author?.id`), which is the recipient.

`EngineRawMessage` is `Message` (`EnginePostboxCoding.swift`). `import GiftViewScreen` is added in this file. The protocol in `AccountContext` and the two `makeGiftViewScreen` implementations in `SharedAccountContext.swift` stay as they are.

## 3. Wallet

**File.** `submodules/TelegramCore/Sources/State/Stars.swift` (and the account's `tonContext` on `AccountContext`).

`StarsAmount(value:nanos:)`. For `.ton`, nanos are 0 and `value` is nanoton. `CurrencyAmount` carries `.ton` or `.stars`. `StarsContext.add(balance:addTransaction:)` does `max(0, state.balance + balance)` and flags a pending balance.

Chip-in of 800 GRAM is `add(balance: StarsAmount(value: -800_000_000_000, nanos: 0))`. A refund is the same call with a positive value. The screen that performs it is `GramPotScreen`, not `WalletSendScreen`. One button, one debit, into escrow (D-012, D-014).

`payments.currencyRates()` returns `[CurrencyRate]` (a currency code and a `Double`). The pot converts the GRAM rate to micro-USD once, at start, and stores the integer. Display maths in `GramPotLogic` uses that integer, half-up, and checks the multiply for overflow.

`context.engine.payments.buyStarGift(slug:peerId:price:...)` is the existing purchase. Gram Pot does not call it. The proposed method, sketched next to the payments engine, spends escrow and delivers the gift:

`payments.finishGramPot`

It is marked proposed. It is not in the published schema. Placeholder ids are not real TL numbers (D-025).

## 4. Chat messages

**Service lines.** Enqueue with the same helper make-an-offer uses: `enqueueMessages(account:peerId:messages:[.message(...)])`. The media is `.customText(text:entities:additionalAttributes:)`. No new `TelegramMediaAction` case, so the existing switches stay exhaustive.

Copy, in order:

- first successful chip-in also posts "You started a Gram Pot for Jack" and the pot card;
- each later chip-in posts "X chipped in 💎 N";
- full posts "Gram Pot complete · Jack received the gift".

**Pot card and Jack's card.** `GramPotMessageAttribute` conforms to the Postbox coding used by `PaidStarsMessageAttribute`. It is registered with `declareEncodable` from `telegramUIDeclareEncodables()` (`TelegramUIDeclareEncodables.swift`). The type hash is `murMurHash32` of the type name, which is what `Coding.swift` expects.

`ChatMessageBubbleItemNode.contentNodeMessagesAndClassesForItem` walks attributes (the loop begins just after the imports, beside the paid-stars case) and gift cases (including the gift-offer bubble). A new case returns `ChatMessageGramPotBubbleContentNode`. The node's BUILD target is a dependency of the bubble module. `GramPotScreen` does not depend on the TelegramUI app target, so the attribute type lives where both the screen and the bubble can see it without a cycle.

The official delivery ("Imogen, Theo, Maya, Apollo and Ellie sent you a gift via Gram Pot", card "Gift from 5 friends") is authored by the server as peer `777000`. The client renders the attribute and can enqueue a local preview. It does not pretend to be that account on the wire.

`Message.withUpdatedAttributes` exists for local updates of a message already in the chat.

## 5. Screens

**Module.** `submodules/TelegramUI/Components/Gifts/GramPotScreen/`.

| Piece | Role |
| --- | --- |
| `GramPotLogic` sources | Vendored copy of the package: phase, eligibility, split, escrow effects. |
| Start / chip-in screen | Title "Gram Pot for {name}", locked amount, "Split N ways", balance line, **Chip in**. |
| Keypad | `WalletSendKeyboardComponent` in decimal mode, shown and ignored for the amount (D-022). |
| Buttons | `ButtonComponent.Background` glass style, which is the pill. |
| Avatar | `AvatarComponent` for members on the pot, not for the owner row. |
| Ribbon | `GiftItemComponent` ribbon for the pot card and the gift card. |

The chip-in screen shows progress ("0 of 4,000", then the amount in), "you're first" before anyone has paid, and who still has to chip in. Names use "You" in place (D-023). The list joins with "and" and no comma before the last name.

Strings live in `Telegram/Telegram-iOS/en.lproj/Localizable.strings`, appended after the current end of that file (`Gift.Delete.Success`). A key `GramPot.Menu` is `strings.GramPot_Menu` once `GenerateStrings` runs. This repository does not run that generator.

## 6. Logic package

`GramPotLogic/` is the tested core. Types are `Sendable`. Swift tools version 6.0.

| Type / function | Role |
| --- | --- |
| `NanoGram` | `Int64` nanoton. |
| `gramPotEqualSpotAmounts(priceNano:spotCount:)` | Remainder to the earliest spots. |
| `gramPotUsdCents(nanoGram:microUsdPerGram:)` | Half-up fiat. |
| `GramPotGroupFacts`, `gramPotIsEligible` | Private group, no public username, 2...8 members. |
| `GramPotPhase` | `open`, `filling`, `complete`, `refunded`, `expired`. |
| `GramPot` | Locked price, locked micro-USD rate, member snapshot, recipient, `createdAt`, deadline `createdAt + 86400`, contributions. |
| `chipIn` / `memberLeft` / `advance` | Return wallet effects: `.debit`, `.credit`, `.spendEscrow`. |

`GramPotEscrow` is the ledger the tests assert against: debits in, credits out, spend on complete, and the invariant that a resolved pot has moved every nano back to wallets or into the purchase.

Reject: price ≤ 0, recipient not in the group, wrong amount, double chip-in, outsider, insufficient balance, chip-in after the deadline.

The word in the model is "spot". User-facing strings do not say "share".

## 7. What this map does not claim

- It does not claim a green Bazel or Xcode build. The patch is checked with `git apply --check` against the pinned tree.
- It does not claim `RenderedChannelParticipant`'s stored property names beyond `peerId` on `ChannelParticipant`, which is what the member snapshot reads.
- It does not claim the proposed TL method exists on the server.
- `valueUsdAmount` on `UniqueGift` is not what the sheet displays, and the pot does not read it. Fiat comes from the locked rate.
