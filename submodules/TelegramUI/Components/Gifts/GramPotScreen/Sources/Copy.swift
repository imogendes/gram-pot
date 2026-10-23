import Foundation

/// Joins names the way the gift footer does: "A", "A and B", "A, B, C and D". No comma before the last name.
public func gramPotJoinedNames(_ names: [String]) -> String {
    switch names.count {
    case 0:
        return ""
    case 1:
        return names[0]
    case 2:
        return names[0] + " and " + names[1]
    default:
        let head = names.dropLast().joined(separator: ", ")
        return head + " and " + names[names.count - 1]
    }
}

/// Replaces the viewer's own name with "You" where it already stands. Does not move it.
public func gramPotNamesForViewer(_ names: [String], viewerName: String) -> [String] {
    names.map { name in
        name == viewerName ? "You" : name
    }
}

public func gramPotGiftFromFooter(names: [String], viewerName: String) -> String {
    let shown = gramPotJoinedNames(gramPotNamesForViewer(names, viewerName: viewerName))
    return "A gift from " + shown + " via Gram Pot."
}

public func gramPotSentYouText(names: [String], viewerName: String) -> String {
    let shown = gramPotJoinedNames(gramPotNamesForViewer(names, viewerName: viewerName))
    return shown + " sent you a gift via Gram Pot"
}

public func gramPotStartedText(actor: String, recipient: String) -> String {
    actor + " started a Gram Pot for " + recipient
}

/// The amount is the GRAM figure ("800"). The chat draws the GRAM mark beside it.
public func gramPotChippedInText(actor: String, amount: String) -> String {
    actor + " chipped in " + amount
}

public func gramPotCompleteText(recipient: String) -> String {
    "Gram Pot complete · " + recipient + " received the gift"
}

public func gramPotProgressText(contributed: String, price: String) -> String {
    contributed + " of " + price
}
