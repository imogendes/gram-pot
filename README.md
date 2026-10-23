# Gram Pot

Close friends in a private Telegram group chip in together to buy **one** collectible gift for **one** friend. There is no group ownership. The recipient is the only owner.

Someone posts a collectible in the group. A member opens the gift sheet, taps **⋯**, and chooses **Gram Pot**. The listing price in GRAM is split into equal spots. Each friend pays their spot from their Telegram GRAM wallet with one **Chip in** tap. Telegram holds that GRAM in escrow. When the pot is full, Telegram buys the gift and delivers it to the recipient only. If a member leaves before the pot fills, or it is not full within 24 hours, everyone is refunded to the same wallet.

This is a prototype of that flow inside the official Telegram-iOS tree, pinned to commit `fb0e62ba8a147f0821da6aa63c09da7d79a10111` (master, 22 October 2026). The story it is built around is the private group "Resistance 2018": Jack's birthday, Resistance Dog #1, five friends, 4,000 GRAM.

## How it works

1. A collectible is posted in a private group. In the story, Jack posts Resistance Dog #1 (owner Alicia, model Pink Cloud, backdrop Fandango, symbol Alkonost, value about $5,252.00) and says it is his birthday.
2. A member opens the gift sheet and taps **⋯**. The menu keeps Telegram's own items, including **Share**, and adds **Gram Pot** with a **New** badge and a people icon.
3. They start **Gram Pot for Jack**. The price is the listing, here 4,000 GRAM, locked when the pot starts. It is split into equal spots: five spots of 800 GRAM (about $1,050.40 each at $1.313 per GRAM). Jack is the recipient and does not take a spot.
4. The starter chips in first, from their GRAM wallet. The chip-in screen starts at 0 of 4,000, "you're first", then 800. Theo, Maya, Apollo, and Ellie chip in the same way. Each chip-in is one tap. There is no Send Money screen and no transfer to another person.
5. The chat fills live. Service lines read like "Theo chipped in 800", with the GRAM mark.
6. When the pot is full, Telegram spends the escrow, buys the gift, and delivers it to Jack only. Jack gets a message from the official Telegram account: "Imogen, Theo, Maya, Apollo and Ellie sent you a gift via Gram Pot", with a card "Gift from 5 friends".
7. After delivery, the gift sheet owner row is Jack's name only, with no avatar. The footer is "A gift from You, Theo, Maya, Apollo and Ellie via Gram Pot." The button is **Done**.

## Rules

- **Gram Pot** is offered only for a collectible sent in a **private group** (no public username) with **2–8 members**.
- The cost is split into equal spots. The recipient does not chip in. A group of six, including the recipient, is five spots.
- Amounts are integer nano-GRAM. 1 GRAM is 1,000,000,000 nano. Any remainder of 1 nano goes to the earliest spots, so the spots sum to the price exactly and differ by at most 1 nano.
- Each chip-in debits that member's in-app GRAM wallet into Telegram's escrow. Refunds credit the same wallet.
- The price and the fiat rate are locked when the pot starts.
- If a snapshotted member leaves before the pot is full, or the pot is not full within 24 hours, every contribution is refunded. The spots are not re-split.
- A completed pot is not refunded. The gift is bought once and given to the recipient only.
- There is no wishlist. The pot's own wording does not use the word "share". The menu's existing **Share** item stays as it is.
- The owner row shows the name only, with no avatar.

## Where the code is

New UI lives in its own module, `submodules/TelegramUI/Components/Gifts/GramPotScreen`. The pure rules (eligibility, equal split, the state machine, escrow) live twice, on purpose: once in the Swift package `GramPotLogic/`, which `swift test` runs on its own, and once as the same sources under the screen module, because Telegram-iOS does not import Swift packages.

Existing files only get thin integration points:

- the gift sheet menu, the delivery footer, and the **Done** button: `GiftViewScreen.swift`;
- remembering which private group the collectible was opened from: `OpenResolvedUrl.swift`;
- the owner row without an avatar: `PeerTableCellComponent.swift`;
- the pot card and the service lines in the bubble: `ChatMessageBubbleItemNode.swift` and a new bubble content node;
- English strings: `Localizable.strings`.

The wallet debit and the refund are `StarsContext.add` on the account's GRAM (`ton`) context. A negative amount debits, a positive amount credits. The client does not open the Send Money sheet, and it does not call `buyStarGift` after the debit (that would charge the wallet a second time). Buying the gift from escrow is a proposed server method, `payments.finishGramPot`.

## Repository layout

| Path | Role |
| --- | --- |
| `GramPotLogic/` | Standalone Swift package. State machine, eligibility, split maths, escrow. Run with `swift test`. |
| `submodules/` | New and changed Telegram-iOS sources at the paths they occupy in the client. |
| `Telegram/` | The English string keys appended for the feature. |
| `gram-pot.patch` | The same edits as a patch against Telegram-iOS `fb0e62ba`. |
| [docs/CODE_MAP.md](docs/CODE_MAP.md) | Which Telegram-iOS modules were read, and where Gram Pot plugs in. |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Short decision log. |

`submodules/` and `Telegram/` are readable copies, the same idea as [make-an-offer](https://github.com/imogendes/make-an-offer). They are not a buildable slice of Telegram-iOS on their own.

## Apply and run

The logic package does not need the client:

```sh
cd GramPotLogic
swift test
```

Requires Swift 6.0. The package is the part of this prototype that is compiled and tested here.

To read the feature inside the client, clone Telegram-iOS and apply the patch. The patch is against commit `fb0e62ba8a147f0821da6aa63c09da7d79a10111`.

```sh
git clone --recursive https://github.com/TelegramMessenger/Telegram-iOS.git
cd Telegram-iOS
git checkout fb0e62ba8a147f0821da6aa63c09da7d79a10111
git apply /path/to/gram-pot/gram-pot.patch
```

Check it applies before building:

```sh
git apply --check /path/to/gram-pot/gram-pot.patch
```

Building the client needs macOS, Xcode, and Telegram's Bazel setup (`python3 build-system/Make/Make.py`). New English strings in `Localizable.strings` become `strings.GramPot_*` only after `GenerateStrings`. That codegen is not run in this repository, so the patched client target is not compiled here.

The proposed TL method is not on Telegram's servers. Until it is, a full pot can update the local wallet mirror and the local chat, and the official-account delivery is rendered as a preview. See [docs/DECISIONS.md](docs/DECISIONS.md).

## What is real and what is temporary

**Specified and covered by tests:**

- Eligibility: private group, no public username, 2–8 members, viewer is not the recipient, a GRAM listing price.
- Equal split in nano-GRAM, and fiat in integer micro-USD, half-up.
- Phases: open, filling, complete, refunded, expired.
- One chip-in per spot, debited from a balance, held in escrow, refunded in full on leave or on the 24 hour deadline.
- Price and rate locked at the start. No resplit.

**In the client tree, not built on this machine:**

- The gift sheet menu item, the start and chip-in screens, the owner row, the pot card, and the delivery footer. They are written against the pinned sources and checked with `git apply --check`. They are not compiled with Bazel or Xcode here.
- `PresentationStrings` for the new keys. The English file is updated; the generated Swift is not.

**Temporary (prototype only):**

- `payments.finishGramPot` is a proposed method. The client must not call `buyStarGift` for a pot, because the wallet was already debited into escrow.
- The message from the verified Telegram account (peer `777000`) is produced by the server. The client can show a local preview of that card.

## Further reading

- [docs/CODE_MAP.md](docs/CODE_MAP.md): the gift sheet, the wallet, and the bubble, and why each file changes.
- [docs/DECISIONS.md](docs/DECISIONS.md): each decision in brief, with its reason.

Suggested by [@imogen](https://t.me/imogen).
