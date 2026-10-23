import Foundation
import UIKit
import Display
import ComponentFlow
import ViewControllerComponent
import MultilineTextComponent
import ButtonComponent
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import WalletSendKeyboardComponent
import TemporaryCachedPeerDataManager

public struct GramPotOrigin: Equatable {
    public let groupPeerId: EnginePeer.Id
    public let messageId: EngineMessage.Id?
    public let recipientId: EnginePeer.Id?

    public init(groupPeerId: EnginePeer.Id, messageId: EngineMessage.Id?, recipientId: EnginePeer.Id?) {
        self.groupPeerId = groupPeerId
        self.messageId = messageId
        self.recipientId = recipientId
    }
}

public struct GramPotDelivery: Equatable {
    public let contributorNames: [String]
    public let viewerName: String

    public init(contributorNames: [String], viewerName: String) {
        self.contributorNames = contributorNames
        self.viewerName = viewerName
    }
}

/// Chip-in screen. One tap debits the viewer's GRAM wallet into escrow.
/// The keypad is the wallet keypad. It is on screen and does not change the locked spot.
public final class GramPotScreen: ViewControllerComponentContainer {
    private let context: AccountContext
    private let groupPeerId: EnginePeer.Id
    private let recipientId: EnginePeer.Id
    private let priceNano: Int64
    private let slug: String
    private let giftTitle: String
    private let model: String
    private let backdrop: String
    private let symbol: String

    private var pot: GramPot?
    private var names: [GramPotMemberID: String] = [:]
    private var viewerName: String = ""
    private var microUsdPerGram: Int64 = 0
    private var balanceNano: Int64 = 0
    private var statusText: String = ""
    private var disposable: Disposable?
    private var memberListDisposable: Disposable?

    public init(
        context: AccountContext,
        groupPeerId: EnginePeer.Id,
        recipientId: EnginePeer.Id,
        priceNano: Int64,
        slug: String,
        giftTitle: String,
        model: String,
        backdrop: String,
        symbol: String
    ) {
        self.context = context
        self.groupPeerId = groupPeerId
        self.recipientId = recipientId
        self.priceNano = priceNano
        self.slug = slug
        self.giftTitle = giftTitle
        self.model = model
        self.backdrop = backdrop
        self.symbol = symbol

        super.init(
            context: context,
            component: GramPotScreenComponent(
                title: "",
                amountText: "",
                fiatText: "",
                progressText: "",
                noteText: "",
                balanceText: "",
                buttonTitle: "",
                buttonEnabled: false,
                theme: context.sharedContext.currentPresentationData.with { $0 }.theme,
                strings: context.sharedContext.currentPresentationData.with { $0 }.strings,
                dateTimeFormat: context.sharedContext.currentPresentationData.with { $0 }.dateTimeFormat,
                chipIn: {},
                dismiss: {}
            ),
            navigationBarAppearance: .default
        )

        self.title = "Gram Pot"
        self.navigationPresentation = .modal
        self.load()
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.disposable?.dispose()
        self.memberListDisposable?.dispose()
    }

    private func load() {
        let peerSignal = self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: self.groupPeerId))
        let cachedSignal = self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.CachedData(id: self.groupPeerId))
        let recipientSignal = self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: self.recipientId))
        let viewerSignal = self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: self.context.account.peerId))
        let ratesSignal = self.context.engine.payments.currencyRates()

        self.disposable = (combineLatest(peerSignal, cachedSignal, recipientSignal, viewerSignal, ratesSignal)
        |> deliverOnMainQueue).start(next: { [weak self] peer, cached, recipient, viewer, rates in
            guard let self else {
                return
            }
            if let viewer {
                self.viewerName = viewer.compactDisplayTitle
            }
            if let recipient {
                self.names[gramPotMemberId(recipient.id)] = recipient.compactDisplayTitle
            }
            if let usd = rates?.first(where: { $0.currency == "USD" }) {
                self.microUsdPerGram = gramPotMicroUsdPerGram(usdPerGram: usd.rate) ?? 0
            }
            self.readBalance()

            if case .legacyGroup = peer, let cachedGroup = cached as? CachedGroupData {
                let ids = cachedGroup.participants?.participants.map { $0.peerId } ?? []
                self.startIfPossible(memberPeerIds: ids)
            } else if case .channel = peer {
                self.memberListDisposable?.dispose()
                self.memberListDisposable = self.context.peerChannelMemberCategoriesContextsManager.recent(
                    engine: self.context.engine,
                    accountPeerId: self.context.account.peerId,
                    peerId: self.groupPeerId,
                    count: Int32(8),
                    updated: { [weak self] state in
                        Queue.mainQueue().async {
                            self?.startIfPossible(memberPeerIds: state.list.map { $0.peer.id })
                        }
                    }
                ).0
            }
        })
    }

    private func readBalance() {
        if let tonContext = self.context.tonContext, tonContext.ton, let state = tonContext.currentState {
            self.balanceNano = state.balance.value
        }
    }

    private func startIfPossible(memberPeerIds: [EnginePeer.Id]) {
        guard self.pot == nil else {
            self.reload()
            return
        }
        var memberIds: [GramPotMemberID] = []
        var seen = Set<GramPotMemberID>()
        for peerId in memberPeerIds {
            let memberId = gramPotMemberId(peerId)
            if seen.insert(memberId).inserted {
                memberIds.append(memberId)
            }
        }
        let recipientMember = gramPotMemberId(self.recipientId)
        if !memberIds.contains(recipientMember) {
            memberIds.append(recipientMember)
        }
        let createdAt = Int64(Date().timeIntervalSince1970)
        switch GramPot.start(
            id: createdAt,
            priceNano: self.priceNano,
            microUsdPerGram: self.microUsdPerGram,
            recipientId: recipientMember,
            memberIds: memberIds,
            createdAt: createdAt
        ) {
        case let .success(pot):
            self.pot = pot
            self.loadNames(memberPeerIds)
            self.reload()
        case .failure:
            self.statusText = self.currentStrings.GramPot_Unavailable
            self.reload()
        }
    }

    private var currentStrings: PresentationStrings {
        self.context.sharedContext.currentPresentationData.with { $0 }.strings
    }

    private func loadNames(_ peerIds: [EnginePeer.Id]) {
        for peerId in peerIds {
            let _ = (self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
            |> deliverOnMainQueue).start(next: { [weak self] peer in
                guard let self, let peer else {
                    return
                }
                self.names[gramPotMemberId(peer.id)] = peer.compactDisplayTitle
                self.reload()
            })
        }
    }

    private func chipIn() {
        guard var pot = self.pot else {
            return
        }
        self.readBalance()
        let localId = gramPotMemberId(self.context.account.peerId)
        guard let spot = pot.spotAmounts[localId] else {
            return
        }
        let now = Int64(Date().timeIntervalSince1970)
        let wasOpen = pot.phase == .open
        let transition = pot.chipIn(memberId: localId, nano: spot, balanceNano: self.balanceNano, now: now)
        gramPotApplyLocalWallet(context: self.context, effects: transition.effects, localMemberId: localId)
        self.pot = pot
        self.readBalance()

        let strings = self.currentStrings
        let actor = "You"
        let recipientName = self.names[pot.recipientId] ?? ""
        if wasOpen, transition.succeeded {
            gramPotEnqueueServiceText(
                context: self.context,
                groupPeerId: self.groupPeerId,
                text: strings.GramPot_Started(actor, recipientName).string
            )
        }
        if transition.succeeded {
            let amount = gramPotGramText(nano: spot) ?? ""
            gramPotEnqueueServiceText(
                context: self.context,
                groupPeerId: self.groupPeerId,
                text: strings.GramPot_ChippedIn(actor, amount).string
            )
            self.postCard(pot: pot, kind: .pot)
        }
        if pot.phase == .complete, transition.succeeded {
            gramPotEnqueueServiceText(
                context: self.context,
                groupPeerId: self.groupPeerId,
                text: strings.GramPot_Complete(recipientName).string
            )
            self.postCard(pot: pot, kind: .deliveredGift)
            let contributors = pot.spotOrder.compactMap { self.names[$0] }
            if let navigationController = self.navigationController {
                for controller in navigationController.viewControllers {
                    if let gift = controller as? GramPotGiftScreen {
                        gift.gramPotSetDelivery(contributorNames: contributors, viewerName: self.viewerName)
                    }
                }
            }
            let _ = self.context.engine.payments.finishGramPot(potId: pot.id, slug: self.slug, recipientId: self.recipientId).start(error: { _ in
            })
        }
        if transition.error == .insufficientBalance {
            self.statusText = strings.GramPot_NotEnough
        } else if transition.error == .expired {
            self.statusText = strings.GramPot_Held
        }
        self.reload()
    }

    private func postCard(pot: GramPot, kind: GramPotMessageAttribute.Kind) {
        let names = pot.contributions.compactMap { self.names[$0.memberId] }
        let attribute = GramPotMessageAttribute(
            potId: pot.id,
            kind: kind,
            priceNano: pot.priceNano,
            contributedNano: pot.contributedNano,
            recipientName: self.names[pot.recipientId] ?? "",
            contributorNames: names,
            giftTitle: self.giftTitle,
            model: self.model,
            backdrop: self.backdrop,
            symbol: self.symbol
        )
        gramPotEnqueueCard(context: self.context, groupPeerId: self.groupPeerId, attribute: attribute)
    }

    private func reload() {
        let strings = self.currentStrings
        let presentation = self.context.sharedContext.currentPresentationData.with { $0 }
        let recipientName = self.pot.flatMap { self.names[$0.recipientId] } ?? ""
        let localId = gramPotMemberId(self.context.account.peerId)
        let spot = self.pot?.spotAmounts[localId]
        let contributed = self.pot?.contributedNano ?? 0
        let price = self.pot?.priceNano ?? self.priceNano
        let contributedText = gramPotGramText(nano: contributed) ?? "0"
        let priceText = gramPotGramText(nano: price) ?? ""
        let spotText = gramPotGramText(nano: spot ?? 0) ?? ""
        let amountText = spotText.isEmpty ? priceText : spotText
        var fiatText = ""
        if let spot, let cents = gramPotUsdCents(nanoGram: spot, microUsdPerGram: self.microUsdPerGram), let text = gramPotUsdText(cents: cents) {
            fiatText = text
        }
        let progress = gramPotProgressText(contributed: contributedText, price: priceText)
        var note = strings.GramPot_Held
        if self.pot?.phase == .open {
            note = strings.GramPot_YoureFirst + "\n" + note
        }
        if !self.statusText.isEmpty {
            note = self.statusText
        }
        let spots = self.pot?.spotOrder.count ?? 0
        let split = spots > 0 ? strings.GramPot_SplitWays("\(spots)").string : ""
        let balanceText = strings.GramPot_Balance(gramPotGramText(nano: self.balanceNano) ?? "0").string
        let canChip = self.pot?.phase == .open || self.pot?.phase == .filling
        let already = self.pot?.contributions.contains(where: { $0.memberId == localId }) == true
        let buttonTitle = strings.GramPot_ChipIn(amountText).string

        self.updateComponent(
            component: AnyComponent(GramPotScreenComponent(
                title: strings.GramPot_Title(recipientName).string,
                amountText: amountText,
                fiatText: fiatText,
                progressText: progress + (split.isEmpty ? "" : "\n" + split),
                noteText: note,
                balanceText: balanceText,
                buttonTitle: buttonTitle,
                buttonEnabled: canChip && !already && spot != nil,
                theme: presentation.theme,
                strings: strings,
                dateTimeFormat: presentation.dateTimeFormat,
                chipIn: { [weak self] in
                    self?.chipIn()
                },
                dismiss: { [weak self] in
                    self?.dismiss()
                }
            )),
            transition: .immediate
        )
    }
}

private final class GramPotScreenComponent: Component {
    typealias EnvironmentType = ViewControllerComponentContainer.Environment

    let title: String
    let amountText: String
    let fiatText: String
    let progressText: String
    let noteText: String
    let balanceText: String
    let buttonTitle: String
    let buttonEnabled: Bool
    let theme: PresentationTheme
    let strings: PresentationStrings
    let dateTimeFormat: PresentationDateTimeFormat
    let chipIn: () -> Void
    let dismiss: () -> Void

    init(
        title: String,
        amountText: String,
        fiatText: String,
        progressText: String,
        noteText: String,
        balanceText: String,
        buttonTitle: String,
        buttonEnabled: Bool,
        theme: PresentationTheme,
        strings: PresentationStrings,
        dateTimeFormat: PresentationDateTimeFormat,
        chipIn: @escaping () -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.title = title
        self.amountText = amountText
        self.fiatText = fiatText
        self.progressText = progressText
        self.noteText = noteText
        self.balanceText = balanceText
        self.buttonTitle = buttonTitle
        self.buttonEnabled = buttonEnabled
        self.theme = theme
        self.strings = strings
        self.dateTimeFormat = dateTimeFormat
        self.chipIn = chipIn
        self.dismiss = dismiss
    }

    static func ==(lhs: GramPotScreenComponent, rhs: GramPotScreenComponent) -> Bool {
        return lhs.title == rhs.title
            && lhs.amountText == rhs.amountText
            && lhs.fiatText == rhs.fiatText
            && lhs.progressText == rhs.progressText
            && lhs.noteText == rhs.noteText
            && lhs.balanceText == rhs.balanceText
            && lhs.buttonTitle == rhs.buttonTitle
            && lhs.buttonEnabled == rhs.buttonEnabled
            && lhs.theme === rhs.theme
            && lhs.strings === rhs.strings
    }

    final class View: UIView {
        private let title = ComponentView<Empty>()
        private let amount = ComponentView<Empty>()
        private let fiat = ComponentView<Empty>()
        private let progress = ComponentView<Empty>()
        private let note = ComponentView<Empty>()
        private let balance = ComponentView<Empty>()
        private let button = ComponentView<Empty>()
        private let keyboard = ComponentView<Empty>()

        func update(component: GramPotScreenComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: ComponentTransition) -> CGSize {
            let env = environment[EnvironmentType.self].value
            let side = max(env.safeInsets.left, env.safeInsets.right) + 16.0
            let width = availableSize.width - side * 2.0
            var y = env.navigationHeight + 12.0

            func place(_ view: ComponentView<Empty>, text: String, font: UIFont, color: UIColor, heightLimit: CGFloat) -> CGFloat {
                guard !text.isEmpty else {
                    return 0.0
                }
                let size = view.update(
                    transition: .immediate,
                    component: AnyComponent(MultilineTextComponent(
                        text: .plain(NSAttributedString(string: text, font: font, textColor: color, paragraphAlignment: .center))
                    )),
                    environment: {},
                    containerSize: CGSize(width: width, height: heightLimit)
                )
                if let child = view.view {
                    if child.superview == nil {
                        self.addSubview(child)
                    }
                    child.frame = CGRect(x: side + floor((width - size.width) / 2.0), y: y, width: size.width, height: size.height)
                }
                return size.height
            }

            y += place(self.title, text: component.title, font: Font.semibold(20.0), color: component.theme.list.itemPrimaryTextColor, heightLimit: 60.0)
            y += 18.0
            y += place(self.amount, text: component.amountText + " GRAM", font: Font.semibold(36.0), color: component.theme.list.itemPrimaryTextColor, heightLimit: 50.0)
            y += 4.0
            y += place(self.fiat, text: component.fiatText, font: Font.regular(15.0), color: component.theme.list.itemSecondaryTextColor, heightLimit: 24.0)
            y += 12.0
            y += place(self.progress, text: component.progressText, font: Font.regular(15.0), color: component.theme.list.itemPrimaryTextColor, heightLimit: 80.0)
            y += 8.0
            y += place(self.note, text: component.noteText, font: Font.regular(13.0), color: component.theme.list.itemSecondaryTextColor, heightLimit: 80.0)
            y += 8.0
            y += place(self.balance, text: component.balanceText, font: Font.regular(13.0), color: component.theme.list.itemSecondaryTextColor, heightLimit: 24.0)

            let buttonSize = self.button.update(
                transition: .immediate,
                component: AnyComponent(ButtonComponent(
                    background: ButtonComponent.Background(
                        style: .glass,
                        color: component.theme.list.itemCheckColors.fillColor,
                        foreground: component.theme.list.itemCheckColors.foregroundColor,
                        pressedColor: component.theme.list.itemCheckColors.fillColor.withMultipliedAlpha(0.8),
                        cornerRadius: 26.0
                    ),
                    content: AnyComponentWithIdentity(
                        id: AnyHashable("chip"),
                        component: AnyComponent(MultilineTextComponent(
                            text: .plain(NSAttributedString(string: component.buttonTitle, font: Font.semibold(17.0), textColor: component.theme.list.itemCheckColors.foregroundColor, paragraphAlignment: .center))
                        ))
                    ),
                    isEnabled: component.buttonEnabled,
                    action: component.chipIn
                )),
                environment: {},
                containerSize: CGSize(width: width, height: 52.0)
            )
            if let buttonView = self.button.view {
                if buttonView.superview == nil {
                    self.addSubview(buttonView)
                }
                buttonView.frame = CGRect(x: side, y: y + 16.0, width: width, height: buttonSize.height)
            }

            let keyboardHeight: CGFloat = 260.0
            let _ = self.keyboard.update(
                transition: .immediate,
                component: AnyComponent(WalletSendKeyboardComponent(
                    theme: component.theme,
                    safeInsets: env.safeInsets,
                    isLandscape: env.orientation?.isLandscape == true,
                    mode: .decimal(separator: component.dateTimeFormat.decimalSeparator),
                    deleteTitle: component.strings.Common_Delete,
                    isEnabled: true,
                    action: { _ in
                        // The listing price and the spot are locked. Key presses do not retarget the pot.
                    }
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width, height: keyboardHeight)
            )
            if let keyboardView = self.keyboard.view {
                if keyboardView.superview == nil {
                    self.addSubview(keyboardView)
                }
                keyboardView.frame = CGRect(x: 0.0, y: availableSize.height - keyboardHeight - env.safeInsets.bottom, width: availableSize.width, height: keyboardHeight)
            }
            return availableSize
        }
    }

    func makeView() -> View {
        View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: ComponentTransition) -> CGSize {
        view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
