import Foundation
import TripCore

/// v4 情境快捷回复：按「对方上一句」推荐回复。纯规则，不调用模型；还价金额由程序计算。
/// 译文为人工撰写，上线前需母语者审校（docs/交互改版方案_v4.md §5）。
public enum ContextReplies {
    public enum Kind: String, Equatable, Sendable { case price, place, time, question, negative, fallback }

    static let placeWords = ["jalan", "jl.", "jln", "di mana", "dimana", "kiri", "kanan", "lurus", "belok", "alamat", "lokasi", "maps", "gang", "depan", "street", "left", "right", "straight", "turn", "address", "location", "where"]
    static let timeWords = ["jam ", "menit", "besok", "nanti", "sebentar", "tunggu", "minute", "hour", "o'clock", "tomorrow", "later", "wait"]
    static let negativeWords = ["tidak ada", "gak ada", "nggak ada", "ga ada", "habis", "tutup", "kosong", "sold out", "not available", "closed", "don't have", "no more"]
    static let questionWords = ["apa", "berapa", "mau", "bisa", "sudah", "kapan", "siapa", "gimana", "bagaimana", "kah", "do you", "are you", "would you", "can you", "what", "which"]

    public static func classify(_ text: String) -> Kind {
        let s = " " + text.lowercased() + " "
        if !AmountNormalizer.findAmounts(in: text).flatMap(\.values).filter({ $0 >= 100 }).isEmpty { return .price }
        if negativeWords.contains(where: { s.contains($0) }) { return .negative }
        if placeWords.contains(where: { s.contains($0) }) { return .place }
        if timeWords.contains(where: { s.contains($0) }) || s.range(of: #"\d{1,2}[:.]\d{2}"#, options: .regularExpression) != nil { return .time }
        let words = Set(s.split { !$0.isLetter }.map(String.init))
        if text.contains("?") || text.contains("？") || questionWords.contains(where: { words.contains($0) }) { return .question }
        return .fallback
    }

    /// 还价：报价 × 80%，Rp 按 1.000 取整（小于 10.000 按 100 取整）。纯整数运算。
    public static func counterOffer(_ price: Int) -> Int {
        let step = price >= 10_000 ? 1_000 : 100
        let v = (price * 8 / 10) / step * step
        return max(step, v)
    }

    static func counterPhrase(_ price: Int) -> Phrase {
        let v = counterOffer(price)
        return Phrase(RupiahFormatter.format(v, lang: "zh-Hans") + "印尼盾行吗？", // i18n-ok
                      id: RupiahFormatter.format(v, lang: "id") + " boleh?",
                      en: "Would " + RupiahFormatter.format(v, lang: "en") + " work?")
    }

    static let tooExpensive = Phrase("太贵了，便宜点", id: "Terlalu mahal, bisa kurang?", en: "Too expensive, can you go lower?") // i18n-ok
    static let inclDelivery = Phrase("含运费吗？", id: "Sudah termasuk ongkir?", en: "Does that include delivery?") // i18n-ok
    static let dealOK = Phrase("好的，就这个价", id: "Oke, harga itu saja", en: "OK, that price is fine") // i18n-ok
    static let noThanks = Phrase("不要了，谢谢", id: "Tidak jadi, terima kasih", en: "No thanks") // i18n-ok
    static let takeMeHere = Phrase("请带我去这里", id: "Tolong antar saya ke sini", en: "Please take me here") // i18n-ok
    static let howFar = Phrase("多远？", id: "Berapa jauh?", en: "How far is it?") // i18n-ok
    static let writeDown = Phrase("能写下来吗？", id: "Bisa tolong ditulis?", en: "Could you write it down?") // i18n-ok
    static let whatTime = Phrase("几点？", id: "Jam berapa?", en: "What time?") // i18n-ok
    static let howLong = Phrase("要等多久？", id: "Harus tunggu berapa lama?", en: "How long do I need to wait?") // i18n-ok
    static let illWait = Phrase("好的，我等", id: "Oke, saya tunggu", en: "OK, I'll wait") // i18n-ok
    static let yes = Phrase("是的", id: "Ya", en: "Yes") // i18n-ok
    static let no = Phrase("不是", id: "Bukan", en: "No") // i18n-ok
    static let dontUnderstand = Phrase("我听不懂", id: "Saya tidak mengerti", en: "I don't understand") // i18n-ok
    static let anythingElse = Phrase("那有别的吗？", id: "Ada yang lain?", en: "Is there anything else?") // i18n-ok
    static let thanks = Phrase("谢谢", id: "Terima kasih", en: "Thank you") // i18n-ok

    public static func replies(for kind: Kind, price: Int? = nil) -> [Phrase] {
        switch kind {
        case .price:
            var out = [tooExpensive]
            if let p = price { out.append(counterPhrase(p)) }
            return out + [inclDelivery, dealOK, noThanks]
        case .place: return [takeMeHere, howFar, writeDown]
        case .time: return [whatTime, howLong, illWait]
        case .question: return [yes, no, dontUnderstand]
        case .negative: return [anythingElse, thanks]
        case .fallback: return [thanks, dontUnderstand, writeDown]
        }
    }

    /// 对话里对方的最后一句 → 推荐；没有对方消息时返回 nil（界面改用场景短语）。
    public static func suggest(messages: [Message]) -> (kind: Kind, phrases: [Phrase])? {
        guard let last = messages.last(where: { $0.role == .them }) else { return nil }
        // 对方之后我已经回过话：仍按对方那句推荐（还在同一话题里）
        let kind = classify(last.source)
        let price = AmountNormalizer.findAmounts(in: last.source).flatMap(\.values).first { $0 >= 100 }
        return (kind, replies(for: kind, price: price))
    }
}
