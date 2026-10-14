import Foundation
import TripCore

/// 试用横幅文案（决策 D3）
public enum TrialBanner {
    public static func text(_ s: EntitlementState) -> String? {
        switch s {
        case .unlocked: return nil
        case .notStarted: return L10n.t("免费试用 24 小时：从第一条翻译开始计时")
        case .expired: return L10n.t("24 小时试用已结束")
        case .trial(let left):
            let h = Int((left / 3600).rounded(.up))
            return L10n.f("试用还剩约 %@ 小时，期间不限条数", String(h)) + (h <= TrialPolicy.warnHours ? L10n.t(" · 没网时不能购买，建议现在连网购买") : "")
        }
    }
}

public enum MessageStatus: String, Codable, Equatable, Sendable { case translating, ready, failed, trialBlocked }

public struct Message: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var role: Role
    public var createdAt: Date
    public var source: String                 // 对方原文 / 我的中文
    public var sourceLocale: String
    public var literal: String?               // 对方：字面中文
    public var display: String?               // 对方：主行（理解后）
    public var understood = false             // true 且与字面不同 → 显示「字面」行
    public var foreign: String?               // 我：给对方的话
    public var backTranslation: String?
    public var showBackTranslation = false
    public var offerRetranslateAs: String?
    public var status: MessageStatus = .translating
    /// G2：这句由本机模型兜底翻译（Apple 翻译不支持 / 没装好），质量较低；可选以兼容旧存档
    public var lowQuality: Bool?

    /// 主行（PRD v2 §7.2）
    public var mainLine: String {
        switch role {
        case .me: return source
        case .them:
            if let d = display ?? literal { return d }
            return status == .failed ? L10n.t("这句还没翻译出来") : L10n.t("正在看这句")
        }
    }
    public var literalLine: String? { role == .them && understood ? literal.map { L10n.f("字面：%@", $0) } : nil }
    public var canCopyOrPresent: Bool { role == .me && status == .ready && !(foreign ?? "").isEmpty }
}

public protocol Clock: Sendable { func now() -> Date }
public struct SystemClock: Clock { public init() {}; public func now() -> Date { Date() } }

/// 对话页的业务逻辑（PRD v2 §7）。不依赖 UI，可在 Linux 上测试。
@MainActor
public final class ConversationModel {
    public private(set) var messages: [Message] = []
    public var theirLanguage: String = "id"
    /// 我方语言（三语改造 P1）：zh-Hans / id / en，默认中文，行为与改造前一致
    public var myLanguage: String = Lang.tourist
    /// 当前场景，写进模型上下文（UX 改版）
    public var scene: Scenario? { didSet { understander?.builder.scene = scene?.contextName } }
    public var onChange: (() -> Void)?
    public private(set) var inputHint: String?               // 输入框下的临时提示
    public let trial: TrialCounter
    public let metrics: MetricsSettings?
    public var understandBudget: TimeInterval = 3.0          // 从消息创建起
    public var mineRewriteBudget: TimeInterval = 1.0

    private let translator: Translating
    func usedFallback(from: String, to: String) -> Bool { (translator as? FallbackTranslator)?.usedFallback["\(from)>\(to)"] == true }
    private let understander: Understander?
    private let clock: Clock

    public init(translator: Translating, understander: Understander?, trial: TrialCounter, metrics: MetricsSettings? = nil, clock: Clock = SystemClock()) {
        self.translator = translator; self.understander = understander; self.trial = trial; self.metrics = metrics; self.clock = clock
    }

    public var isTranslating: Bool { messages.contains { $0.status == .translating } }
    public var canSend: Bool { !isTranslating }

    public var bannerText: String? {
        TrialBanner.text(trial.state)
    }

    // MARK: 语言选择（P4）：只影响之后的新消息，已有消息不重译

    public func setLanguages(me: String? = nil, them: String? = nil) {
        if let me { myLanguage = Lang.normalize(me) }
        if let them { theirLanguage = Lang.normalize(them) }
        onChange?()
    }
    public func swapLanguages() { setLanguages(me: theirLanguage, them: myLanguage) }

    // MARK: 发送中文（PRD v2 §7.3、§7.4）

    public enum SendCheck: Equatable { case ok, empty, notChinese, wrongLanguage, busy }

    /// 我方语言为中文时要求含汉字（旧行为）；为印尼语/英语时不能含汉字，且要有字母或数字。
    public static func check(_ raw: String, lang: String = Lang.tourist) -> SendCheck {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .empty }
        if t.allSatisfy({ $0.isNumber || $0 == "." }) { return .ok }
        let han = t.unicodeScalars.contains(where: { $0.properties.isIdeographic })
        if Lang.normalize(lang) == "zh-Hans" { return han ? .ok : .notChinese }
        return han ? .wrongLanguage : .ok
    }

    @discardableResult
    public func sendMine(_ raw: String) async -> SendCheck {
        let c = Self.check(raw, lang: myLanguage)
        guard c == .ok else {
            if c == .notChinese { flash(L10n.t("请用中文说你要讲的")) }
            if c == .wrongLanguage { flash(L10n.f("请用%@说你要讲的", Lang.displayName(myLanguage))) }
            return c
        }
        guard canSend else { return .busy }
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        let mine = myLanguage, theirs = theirLanguage
        var m = Message(id: UUID(), role: .me, createdAt: clock.now(), source: text, sourceLocale: mine,
                        foreignLocaleHint: theirs)
        if !trial.allowsFull {
            m.status = .trialBlocked
            append(m); return .ok
        }
        append(m)
        if text.allSatisfy({ $0.isNumber || $0 == "." }) || LangRoute.route(from: mine, to: theirs) == .same {
            update(m.id) { $0.foreign = text; $0.status = .ready }
            trial.recordCompleteTurn(); return .ok
        }
        // 指代澄清（技术设计 v2 §8.1）：金额不一致则用原文
        var mtInput = text
        var rewritten = false
        if mine == "zh-Hans", let u = understander, Self.hasReference(text), messages.count > 1 {
            u.builder.target = "zh-Hans"; u.builder.scene = scene?.contextName
            let ctx = contextTurns(excluding: m.id)
            u.timeout = mineRewriteBudget
            if case .replaced(let s) = await u.understand(context: ctx, source: text, literal: text),
               Self.numbers(in: s) == Self.numbers(in: text) {
                mtInput = s; rewritten = true
            }
        }
        do {
            let foreign = try await translator.translate(mtInput, from: mine, to: theirs)
            let lq = usedFallback(from: mine, to: theirs)
            update(m.id) { $0.foreign = foreign; $0.status = .ready; $0.lowQuality = lq ? true : nil }
            trial.recordCompleteTurn()
            let back = try? await translator.translate(foreign, from: theirs, to: mine)
            update(m.id) {
                $0.backTranslation = back
                $0.showBackTranslation = back != nil && (rewritten || !BackTranslation.consistent(original: text, back: back!))
            }
        } catch {
            update(m.id) { $0.status = .failed }
        }
        return .ok
    }

    /// 场景快捷短语：预置译文，不调用翻译、不计试用条数，立即可出示。
    public func sendPhrase(_ p: Phrase) {
        var m = Message(id: UUID(), role: .me, createdAt: clock.now(), source: p.text(myLanguage), sourceLocale: myLanguage, foreignLocaleHint: theirLanguage)
        m.foreign = p.text(theirLanguage)
        m.status = .ready
        append(m)
    }

    // MARK: 对方消息（PRD v2 §7.2）

    public func receiveTheirs(_ raw: String) async {
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !text.isEmpty else { return }
        let lang = theirLanguage
        var m = Message(id: UUID(), role: .them, createdAt: clock.now(), source: text, sourceLocale: lang)
        if let g = LanguageGuess.guess(text), g != lang, g != myLanguage { m.offerRetranslateAs = g }
        append(m)
        await translateTheirs(id: m.id, as: lang)
    }

    /// 「按英语重译」：只改这一句，不改开关。
    public func retranslate(_ id: UUID, as lang: String) async {
        update(id) { $0.sourceLocale = lang; $0.offerRetranslateAs = nil; $0.literal = nil; $0.display = nil; $0.understood = false; $0.status = .translating }
        await translateTheirs(id: id, as: lang, count: false)
    }

    private func translateTheirs(id: UUID, as lang: String, count: Bool = true) async {
        guard let m = messages.first(where: { $0.id == id }) else { return }
        let full = trial.allowsFull
        let target = myLanguage
        let route = LangRoute.route(from: lang, to: target)
        if route == .same {
            update(id) { $0.literal = $0.source; $0.status = .ready }
            if count && full { trial.recordCompleteTurn() }
            return
        }
        // 金额占位（P2：所有目标语言）：中文还原成「5万」，英文「Rp 50,000」，印尼语「Rp 50.000」
        let (ph, table) = AmountNormalizer.placeholderize(m.source)
        var literal: String
        do {
            if table.isEmpty {
                literal = try await translator.translate(m.source, from: lang, to: target)
            } else {
                let t = try await translator.translate(ph, from: lang, to: target)
                if let r = AmountNormalizer.restore(t, table: table, lang: target) {
                    literal = r
                } else {
                    let plain = try await translator.translate(m.source, from: lang, to: target)
                    let ds = table.keys.sorted().compactMap { table[$0]?.display(for: target) }
                    literal = target == "zh-Hans" ? plain + "（" + ds.joined(separator: "，") + "）" : plain + " (" + ds.joined(separator: ", ") + ")"
                }
            }
        } catch {
            update(id) { $0.status = .failed }; return
        }
        let lq = usedFallback(from: lang, to: target)
        update(id) { $0.literal = literal; $0.status = .ready; $0.lowQuality = lq ? true : nil }
        if count && full { trial.recordCompleteTurn() }
        guard full, route == .translateAndUnderstand, let u = understander else { return }
        let remaining = understandBudget - clock.now().timeIntervalSince(m.createdAt)
        guard remaining > 0.05 else { return }
        u.timeout = remaining
        u.builder.theirLanguageName = Lang.chineseName(lang)
        u.builder.target = target
        u.builder.scene = scene?.contextName(for: target)
        let outcome = await u.understand(context: contextTurns(excluding: id), source: m.source, literal: literal)
        // 时间窗外不再改（PRD v2 §7.2）
        guard clock.now().timeIntervalSince(m.createdAt) <= understandBudget + 0.05 else { return }
        if case .replaced(let s) = outcome {
            update(id) { $0.display = s; $0.understood = true }
            metrics?.increment("understood.replaced")
        }
    }

    // MARK: 工具

    public var onPersist: (([Message]) -> Void)?

    public func newConversation() { messages = []; onChange?(); onPersist?(messages) }

    /// 恢复上次的这场（被系统杀掉后再打开）。翻译中的半截消息改为失败，不产生半截气泡。
    public func restore(_ saved: [Message]) {
        messages = saved.filter { !($0.status == .translating && $0.role == .me && $0.foreign == nil && $0.source.isEmpty) }
            .map { var m = $0; if m.status == .translating { m.status = .failed }; return m }
        onChange?()
    }

    func contextTurns(excluding id: UUID) -> [ContextTurn] {
        messages.filter { $0.id != id && $0.status == .ready }.map {
            $0.role == .them ? ContextTurn(role: .them, source: $0.source, zhDisplay: $0.display ?? $0.literal)
                             : ContextTurn(role: .me, source: $0.source, foreign: $0.foreign)
        }
    }

    static let referenceWords = ["这个", "那个", "刚才", "之前", "同上", "还是", "那里", "这里"] // i18n-ok
    static func hasReference(_ s: String) -> Bool { referenceWords.contains { s.contains($0) } }
    nonisolated static func numbers(in s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#)
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private func append(_ m: Message) { messages.append(m); onChange?(); onPersist?(messages) }
    private func update(_ id: UUID, _ f: (inout Message) -> Void) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        f(&messages[i]); onChange?()
        if messages[i].status != .translating { onPersist?(messages) }
    }
    private func flash(_ s: String) { inputHint = s; onChange?() }
    public func clearHint() { inputHint = nil; onChange?() }
}

extension Message {
    public init(id: UUID, role: Role, createdAt: Date, source: String, sourceLocale: String, foreignLocaleHint: String? = nil) {
        self.id = id; self.role = role; self.createdAt = createdAt; self.source = source; self.sourceLocale = sourceLocale
    }
}

/// 回译一致判定（技术设计 v2 §6.1）：数字一致、否定词一致，再看字符重合率。
public enum BackTranslation {
    public static var threshold = 0.6
    static let negations: [Character] = ["不", "没", "别", "无"] // i18n-ok
    static let negationWords: Set<String> = ["not", "no", "don't", "never", "tidak", "bukan", "jangan", "nggak", "gak", "belum", "tdk"]
    public static func consistent(original: String, back: String) -> Bool {
        if ConversationModel.numbers(in: original) != ConversationModel.numbers(in: back) { return false }
        let cn: Set<Character> = ["一","二","两","三","四","五","六","七","八","九","十","百","千","万","半"] // i18n-ok
        if original.filter({ cn.contains($0) }) != back.filter({ cn.contains($0) }) { return false }
        let words = { (s: String) in s.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init) }
        let n1 = original.contains { negations.contains($0) } || words(original).contains { negationWords.contains($0) }
        let n2 = back.contains { negations.contains($0) } || words(back).contains { negationWords.contains($0) }
        if n1 != n2 { return false }
        let a = OutputValidator.normalize(original), b = OutputValidator.normalize(back)
        guard !a.isEmpty, !b.isEmpty else { return a == b }
        var bag: [Character: Int] = [:]
        for c in b { bag[c, default: 0] += 1 }
        var inter = 0
        for c in a where (bag[c] ?? 0) > 0 { inter += 1; bag[c]! -= 1 }
        return Double(inter) / Double(max(a.count, b.count)) >= threshold
    }
}

/// 粘贴语言猜测（技术设计 1.1 §10）：只用于提示「按英语重译」。
public enum LanguageGuess {
    static let id: Set<String> = ["yang","tidak","nggak","gak","gk","sudah","udh","udah","belum","bisa","bs","mau","ini","itu","saja","aja","dong","ya","di","ke","dari","untuk","dengan","ada","harga","ongkos","ribu","rb","berapa","brp","kak","pak","saya","depan","pintu","sampai","kurang","uang","kecil","sini","mana","tunggu","terima","kasih","sekali","mahal"]
    static let en: Set<String> = ["the","and","you","this","that","with","for","not","can","please","pls","price","wait","how","much","where","is","it's","i'm"]
    public static func guess(_ text: String) -> String? {
        let scalars = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        let han = scalars.filter { $0.properties.isIdeographic }.count
        if han > 0 { return Double(han) / Double(max(1, scalars.count)) >= 0.3 ? "zh-Hans" : nil }
        let words = text.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init)
        let i = words.filter { id.contains($0) }.count, e = words.filter { en.contains($0) }.count
        if i >= 2 && i > e { return "id" }
        if e >= 2 && e > i { return "en" }
        return nil
    }
}
