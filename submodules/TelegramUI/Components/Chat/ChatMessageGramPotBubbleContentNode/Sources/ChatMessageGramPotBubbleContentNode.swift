import Foundation
import UIKit
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore
import TelegramPresentationData
import TextFormat
import AccountContext
import LottieSettings
import ComponentFlow
import WallpaperBackgroundNode
import TextNodeWithEntities
import ChatMessageBubbleContentNode
import ChatMessageItemCommon
import GramPotScreen

public final class ChatMessageGramPotBubbleContentNode: ChatMessageBubbleContentNode {
    private var mediaBackgroundContent: WallpaperBubbleBackgroundNode?
    private let titleNode: TextNode
    private let detailNode: TextNode

    private var absoluteRect: (CGRect, CGSize)?

    override public var disablesClipping: Bool {
        return true
    }

    required public init(lottieSettings: LottieRenderingSettings) {
        self.titleNode = TextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.displaysAsynchronously = false

        self.detailNode = TextNode()
        self.detailNode.isUserInteractionEnabled = false
        self.detailNode.displaysAsynchronously = false

        super.init(lottieSettings: lottieSettings)

        self.addSubnode(self.titleNode)
        self.addSubnode(self.detailNode)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func asyncLayoutContent() -> (_ item: ChatMessageBubbleContentItem, _ layoutConstants: ChatMessageItemLayoutConstants, _ preparePosition: ChatMessageBubblePreparePosition, _ messageSelection: Bool?, _ constrainedSize: CGSize, _ avatarInset: CGFloat) -> (ChatMessageBubbleContentProperties, unboundSize: CGSize?, maxWidth: CGFloat, layout: (CGSize, ChatMessageBubbleContentPosition) -> (CGFloat, (CGFloat) -> (CGSize, (ListViewItemUpdateAnimation, Bool, ListViewItemApply?) -> Void))) {
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        let makeDetailLayout = TextNode.asyncLayout(self.detailNode)

        return { [weak self] item, _, _, _, _, _ in
            let contentProperties = ChatMessageBubbleContentProperties(hidesSimpleAuthorHeader: true, headerSpacing: 0.0, hidesBackground: .always, forceFullCorners: false, forceAlignment: .center)
            return (contentProperties, nil, CGFloat.greatestFiniteMagnitude, { [weak self] _, _ in
                let cardWidth: CGFloat = 260.0
                let textColor = serviceMessageColorComponents(theme: item.presentationData.theme.theme, wallpaper: item.presentationData.theme.wallpaper).primaryText
                let attribute = item.message.attributes.first(where: { $0 is GramPotMessageAttribute }) as? GramPotMessageAttribute

                let title: String
                let detail: String
                if let attribute {
                    switch attribute.kind {
                    case .deliveredGift:
                        let count = attribute.contributorNames.count
                        title = item.presentationData.strings.GramPot_GiftFromFriends("\(count)").string
                        detail = [attribute.model, attribute.backdrop, attribute.symbol].filter { !$0.isEmpty }.joined(separator: "\n")
                    case .pot:
                        title = attribute.giftTitle
                        let price = gramPotGramText(nano: attribute.priceNano) ?? ""
                        let contributed = gramPotGramText(nano: attribute.contributedNano) ?? ""
                        detail = gramPotProgressText(contributed: contributed, price: price) + " GRAM"
                    }
                } else {
                    title = ""
                    detail = ""
                }

                let titleString = NSAttributedString(string: title, font: Font.semibold(15.0), textColor: textColor, paragraphAlignment: .center)
                let detailString = NSAttributedString(string: detail, font: Font.regular(13.0), textColor: textColor, paragraphAlignment: .center)
                let constrained = CGSize(width: cardWidth - 32.0, height: CGFloat.greatestFiniteMagnitude)
                let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(attributedString: titleString, backgroundColor: nil, maximumNumberOfLines: 2, truncationType: .end, constrainedSize: constrained, alignment: .center, cutout: nil, insets: UIEdgeInsets()))
                let (detailLayout, detailApply) = makeDetailLayout(TextNodeLayoutArguments(attributedString: detailString, backgroundColor: nil, maximumNumberOfLines: 6, truncationType: .end, constrainedSize: constrained, alignment: .center, cutout: nil, insets: UIEdgeInsets()))

                let cardHeight = 28.0 + titleLayout.size.height + 8.0 + detailLayout.size.height + 28.0
                let backgroundSize = CGSize(width: cardWidth, height: cardHeight)

                return (backgroundSize.width, { [weak self] boundingWidth in
                    return (backgroundSize, { [weak self] animation, _, _ in
                        guard let strongSelf = self else {
                            return
                        }
                        strongSelf.item = item
                        let _ = titleApply()
                        let _ = detailApply()

                        let originX = floorToScreenPixels((boundingWidth - cardWidth) / 2.0)
                        let frame = CGRect(origin: CGPoint(x: originX, y: 0.0), size: backgroundSize)

                        if strongSelf.mediaBackgroundContent == nil, let backgroundContent = item.controllerInteraction.presentationContext.backgroundNode?.makeBubbleBackground(for: .free) {
                            backgroundContent.clipsToBounds = true
                            backgroundContent.cornerRadius = 24.0
                            strongSelf.mediaBackgroundContent = backgroundContent
                            strongSelf.insertSubnode(backgroundContent, at: 0)
                        }
                        if let backgroundContent = strongSelf.mediaBackgroundContent {
                            animation.animator.updateFrame(layer: backgroundContent.layer, frame: frame, completion: nil)
                            backgroundContent.cornerRadius = 24.0
                        }

                        let titleFrame = CGRect(
                            origin: CGPoint(x: frame.minX + floorToScreenPixels((frame.width - titleLayout.size.width) / 2.0), y: frame.minY + 20.0),
                            size: titleLayout.size
                        )
                        strongSelf.titleNode.frame = titleFrame
                        strongSelf.detailNode.frame = CGRect(
                            origin: CGPoint(x: frame.minX + floorToScreenPixels((frame.width - detailLayout.size.width) / 2.0), y: titleFrame.maxY + 8.0),
                            size: detailLayout.size
                        )
                    })
                })
            })
        }
    }

    override public func updateAbsoluteRect(_ rect: CGRect, within containerSize: CGSize) {
        self.absoluteRect = (rect, containerSize)
    }

    override public func tapActionAtPoint(_ point: CGPoint, gesture: TapLongTapOrDoubleTapGesture, isEstimating: Bool) -> ChatMessageBubbleContentTapAction {
        if self.mediaBackgroundContent?.frame.contains(point) == true {
            return ChatMessageBubbleContentTapAction(content: .openMessage)
        } else {
            return ChatMessageBubbleContentTapAction(content: .none)
        }
    }
}
