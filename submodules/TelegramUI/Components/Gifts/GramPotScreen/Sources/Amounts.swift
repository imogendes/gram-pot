import Foundation

/// 1 GRAM is 1_000_000_000 nano, the same unit `StarsAmount.value` uses for TON.
public let gramPotNanoPerGram: Int64 = 1_000_000_000

/// 1 USD is 1_000_000 micro-USD. Stored as an integer so the locked rate does not drift.
public let gramPotMicroUsdPerUsd: Int64 = 1_000_000

/// 1 cent is 10_000 micro-USD.
public let gramPotMicroUsdPerCent: Int64 = 10_000

/// Equal spots in nano-GRAM. The first `price % count` spots receive one extra nano,
/// so the spots differ by at most 1 nano and sum to `priceNano`.
/// Every spot is at least 1 nano. Returns nil when the price or the count cannot be split that way.
public func gramPotEqualSpotAmounts(priceNano: Int64, spotCount: Int) -> [Int64]? {
    guard priceNano > 0, spotCount > 0 else {
        return nil
    }
    let count = Int64(spotCount)
    guard priceNano >= count else {
        return nil
    }
    let base = priceNano / count
    let remainder = priceNano % count
    var amounts: [Int64] = []
    amounts.reserveCapacity(spotCount)
    for index in 0 ..< spotCount {
        let extra: Int64 = Int64(index) < remainder ? 1 : 0
        amounts.append(base + extra)
    }
    return amounts
}

/// Fiat cents for a nano-GRAM amount at a locked micro-USD-per-GRAM rate.
/// Half-up, and nil if the value is negative or the result does not fit in `Int64`.
public func gramPotUsdCents(nanoGram: Int64, microUsdPerGram: Int64) -> Int64? {
    guard nanoGram >= 0, microUsdPerGram >= 0 else {
        return nil
    }
    // cents = round_half_up(nano * microUsdPerGram / (nanoPerGram * microUsdPerCent))
    let divisor = UInt64(gramPotNanoPerGram) * UInt64(gramPotMicroUsdPerCent)
    guard let cents = multiplyThenDivideRoundingHalfUp(
        UInt64(nanoGram),
        UInt64(microUsdPerGram),
        divisor
    ) else {
        return nil
    }
    guard cents <= UInt64(Int64.max) else {
        return nil
    }
    return Int64(cents)
}

/// "4,000" or "800.000000001". Nil for a negative amount.
public func gramPotGramText(nano: Int64) -> String? {
    guard nano >= 0 else {
        return nil
    }
    let whole = nano / gramPotNanoPerGram
    let fraction = nano % gramPotNanoPerGram
    guard let wholeText = groupedDecimal(whole) else {
        return nil
    }
    if fraction == 0 {
        return wholeText
    }
    var digits = String(fraction)
    if digits.count < 9 {
        digits = String(repeating: "0", count: 9 - digits.count) + digits
    }
    while digits.last == "0" {
        digits.removeLast()
    }
    return wholeText + "." + digits
}

/// "$1,050.40". Nil for a negative number of cents.
public func gramPotUsdText(cents: Int64) -> String? {
    guard cents >= 0 else {
        return nil
    }
    let dollars = cents / 100
    let remainder = cents % 100
    guard let dollarText = groupedDecimal(dollars) else {
        return nil
    }
    let remText = remainder < 10 ? "0\(remainder)" : "\(remainder)"
    return "$" + dollarText + "." + remText
}

func groupedDecimal(_ value: Int64) -> String? {
    guard value >= 0 else {
        return nil
    }
    if value == 0 {
        return "0"
    }
    var rest = value
    var digits: [Character] = []
    var group = 0
    while rest > 0 {
        if group == 3 {
            digits.append(",")
            group = 0
        }
        let digit = rest % 10
        digits.append(contentsOf: String(digit))
        rest /= 10
        group += 1
    }
    return String(digits.reversed())
}

/// (a * b) / divisor, half away from zero on a tie. Nil if the quotient does not fit in 64 bits.
func multiplyThenDivideRoundingHalfUp(_ a: UInt64, _ b: UInt64, _ divisor: UInt64) -> UInt64? {
    guard divisor > 0 else {
        return nil
    }
    let (hi, lo) = multiplyWide(a, b)
    guard let divided = divideWide(hi: hi, lo: lo, by: divisor) else {
        return nil
    }
    var quotient = divided.quotient
    let remainder = divided.remainder
    let threshold = (divisor - 1) / 2
    if remainder > threshold {
        guard quotient < UInt64.max else {
            return nil
        }
        quotient += 1
    }
    return quotient
}

func multiplyWide(_ a: UInt64, _ b: UInt64) -> (hi: UInt64, lo: UInt64) {
    let a0 = a & 0xFFFF_FFFF
    let a1 = a >> 32
    let b0 = b & 0xFFFF_FFFF
    let b1 = b >> 32
    let p00 = a0 * b0
    let p01 = a0 * b1
    let p10 = a1 * b0
    let p11 = a1 * b1
    let mid = (p00 >> 32) + (p01 & 0xFFFF_FFFF) + (p10 & 0xFFFF_FFFF)
    let lo = (p00 & 0xFFFF_FFFF) | ((mid & 0xFFFF_FFFF) << 32)
    let hi = p11 + (p01 >> 32) + (p10 >> 32) + (mid >> 32)
    return (hi, lo)
}

func divideWide(hi: UInt64, lo: UInt64, by divisor: UInt64) -> (quotient: UInt64, remainder: UInt64)? {
    if divisor == 0 {
        return nil
    }
    if hi == 0 {
        return (lo / divisor, lo % divisor)
    }
    if hi >= divisor {
        return nil
    }
    var remainder: UInt64 = 0
    var quotient: UInt64 = 0
    for index in stride(from: 127, through: 0, by: -1) {
        let bit: UInt64
        if index >= 64 {
            bit = (hi >> UInt64(index - 64)) & 1
        } else {
            bit = (lo >> UInt64(index)) & 1
        }
        let carried = remainder > (UInt64.max >> 1)
        remainder = (remainder << 1) | bit
        if carried || remainder >= divisor {
            remainder &-= divisor
            if index >= 64 {
                return nil
            }
            quotient |= 1 << UInt64(index)
        }
    }
    return (quotient, remainder)
}
