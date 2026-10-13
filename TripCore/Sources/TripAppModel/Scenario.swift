import Foundation

/// 一句预置短语。印尼语 / 英语译文为人工撰写（上线前需母语者审校），离线可用、零时延。
public struct Phrase: Identifiable, Equatable, Sendable {
    public var id: String { zh }
    public let zh: String
    public let id_: String
    public let en: String
    /// 来自社区真实语料痛点、尚未经母语者审校的新短语（docs/社区真实语料.md）。
    public let needsNativeReview: Bool
    public init(_ zh: String, id: String, en: String, needsNativeReview: Bool = false) {
        self.zh = zh; self.id_ = id; self.en = en; self.needsNativeReview = needsNativeReview
    }
    public func foreign(_ lang: String) -> String { lang == "en" ? en : id_ }
}

/// 场景（UX 改版，见 docs/场景与痛点研究.md）：只是「可选的上下文提示 + 快捷短语」，
/// 进入后仍是同一个通用多轮对话；不做任何场景专用工具。
public enum Scenario: String, CaseIterable, Identifiable, Codable, Sendable {
    case arrival
    case ride
    case delivery
    case restaurant
    case shopping
    case money
    case hotel
    case tour
    case spa
    case health
    case emergency
    case directions
    case chat

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .arrival: return "机场入境"
        case .ride: return "打车 · 接车"
        case .delivery: return "外卖骑手"
        case .restaurant: return "餐厅点餐"
        case .shopping: return "购物 · 付款"
        case .money: return "换汇 · ATM"
        case .hotel: return "酒店 · 别墅"
        case .tour: return "包车 · 快艇"
        case .spa: return "按摩 · SPA"
        case .health: return "看病 · 药店"
        case .emergency: return "紧急求助"
        case .directions: return "问路"
        case .chat: return "闲聊 · 礼貌"
        }
    }
    public var subtitle: String {
        switch self {
        case .arrival: return "落地签、入境卡二维码、回程票"
        case .ride: return "接车点、还要多久、按 App 价"
        case .delivery: return "放门口、找不到门、换菜"
        case .restaurant: return "不要辣、过敏、打包、买单"
        case .shopping: return "多少钱、QRIS、刷卡、找零"
        case .money: return "汇率、自己点钞、附近 ATM"
        case .hotel: return "入住、押金、热水、报修"
        case .tour: return "几点出发、含什么、在哪集合"
        case .spa: return "力度、时长、价格"
        case .health: return "拉肚子、发烧、怎么吃"
        case .emergency: return "报警、丢东西、叫救护车"
        case .directions: return "在哪里、怎么走、远不远"
        case .chat: return "谢谢、没关系、我来自中国"
        }
    }
    /// SF Symbols 名称
    public var symbol: String {
        switch self {
        case .arrival: return "airplane.arrival"
        case .ride: return "car.fill"
        case .delivery: return "bag.fill"
        case .restaurant: return "fork.knife"
        case .shopping: return "creditcard.fill"
        case .money: return "banknote.fill"
        case .hotel: return "bed.double.fill"
        case .tour: return "ferry.fill"
        case .spa: return "leaf.fill"
        case .health: return "cross.case.fill"
        case .emergency: return "exclamationmark.triangle.fill"
        case .directions: return "map.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        }
    }
    /// 写进模型上下文的场景名
    public var contextName: String {
        switch self {
        case .arrival: return "机场入境（落地签/海关）"
        case .ride: return "打车/网约车接送"
        case .delivery: return "外卖（GoFood/GrabFood 骑手聊天）"
        case .restaurant: return "餐厅点餐"
        case .shopping: return "商店/市场购物付款"
        case .money: return "换汇/取款"
        case .hotel: return "酒店/别墅前台或房东"
        case .tour: return "包车/导游/快艇"
        case .spa: return "按摩/SPA"
        case .health: return "药店/诊所"
        case .emergency: return "紧急求助/报警"
        case .directions: return "问路"
        case .chat: return "日常闲聊"
        }
    }

    public var phrases: [Phrase] {
        switch self {
        case .arrival: return [
            Phrase("这是我的入境卡二维码（All Indonesia）", id: "Ini QR All Indonesia saya.", en: "This is my All Indonesia arrival card QR code."),
            Phrase("这是我的回程机票", id: "Ini tiket pulang saya.", en: "This is my return ticket."),
            Phrase("落地签在哪里办？", id: "Bayar VOA di mana?", en: "Where do I pay for the visa on arrival?"),
            Phrase("我住在这家酒店", id: "Saya menginap di hotel ini.", en: "I'm staying at this hotel."),
        ]
        case .ride: return [
            Phrase("我在这里，请到这个位置接我", id: "Saya di sini, tolong jemput di lokasi ini.", en: "I'm here, please pick me up at this location."),
            Phrase("还要多久？", id: "Berapa lama lagi?", en: "How much longer?"),
            Phrase("按 App 上的价格", id: "Sesuai harga di aplikasi, ya.", en: "The price in the app, please."),
            Phrase("我就在定位点这里", id: "Saya sudah di titik jemput ya, Pak.", en: "I'm at the pickup point.", needsNativeReview: true),
            Phrase("定位点不对的话，我发位置给你", id: "Kalau titiknya salah, saya share lokasi ya, Pak.", en: "If the pin is wrong, I'll share my location.", needsNativeReview: true),
            Phrase("请按 App 走，不付现金", id: "Maaf Pak, saya bayar lewat aplikasi saja, tidak cash.", en: "Sorry, I'll pay through the app, not cash.", needsNativeReview: true),
            Phrase("我不取消，接不了请您取消", id: "Maaf Pak, saya tidak cancel. Kalau tidak bisa jemput, Bapak yang cancel ya.", en: "Sorry, I won't cancel. If you can't pick me up, please cancel.", needsNativeReview: true),
            Phrase("不在 App 外加价，谢谢", id: "Maaf Pak, saya tidak mau tambah harga di luar aplikasi. Terima kasih.", en: "Sorry, no extra charge outside the app. Thank you.", needsNativeReview: true),
            Phrase("请开空调", id: "Tolong nyalakan AC.", en: "Please turn on the AC."),
            Phrase("在这里停就好", id: "Berhenti di sini saja.", en: "Just stop here, please."),
        ]
        case .delivery: return [
            Phrase("请放在门口", id: "Tolong taruh di depan pintu.", en: "Please leave it at the door."),
            Phrase("我马上下来", id: "Saya segera turun.", en: "I'm coming down now."),
            Phrase("卖完了就取消吧", id: "Kalau habis, batalkan saja.", en: "If it's sold out, just cancel it."),
            Phrase("我在大门口等你", id: "Saya tunggu di depan gerbang.", en: "I'll wait at the front gate."),
            Phrase("小费送到后在 App 里给", id: "Tipnya nanti saya kasih lewat aplikasi setelah sampai ya, Kak.", en: "I'll tip in the app after delivery.", needsNativeReview: true),
            Phrase("有停车票吗？", id: "Maaf Kak, ada karcis parkirnya?", en: "Sorry, do you have the parking ticket?", needsNativeReview: true),
            Phrase("请按 App 订单送，不加单", id: "Pesanan sesuai aplikasi saja ya, Kak. Tidak ada tambahan.", en: "Just the order in the app, nothing extra.", needsNativeReview: true),
            Phrase("地址就是定位点", id: "Alamatnya sesuai titik ya, Kak.", en: "The address is at the pin.", needsNativeReview: true),
        ]
        case .restaurant: return [
            Phrase("可以看看菜单吗？", id: "Boleh lihat menunya?", en: "Can I see the menu?"),
            Phrase("不要辣", id: "Jangan pedas, ya.", en: "Not spicy, please."),
            Phrase("我对花生过敏", id: "Saya alergi kacang tanah.", en: "I'm allergic to peanuts."),
            Phrase("含税和服务费吗？", id: "Sudah termasuk pajak dan servis?", en: "Are tax and service included?"),
            Phrase("打包", id: "Dibungkus, ya.", en: "To go, please."),
            Phrase("买单", id: "Minta bonnya, ya.", en: "The bill, please."),
        ]
        case .shopping: return [
            Phrase("这个多少钱？", id: "Ini berapa harganya?", en: "How much is this?"),
            Phrase("能便宜一点吗？", id: "Bisa kurang sedikit?", en: "Can you make it a bit cheaper?"),
            Phrase("可以用 QRIS 吗？", id: "Bisa bayar pakai QRIS?", en: "Can I pay with QRIS?"),
            Phrase("可以刷卡吗？", id: "Bisa bayar pakai kartu?", en: "Can I pay by card?"),
            Phrase("我没有零钱", id: "Saya tidak ada uang kecil.", en: "I don't have small change."),
        ]
        case .money: return [
            Phrase("今天人民币汇率多少？", id: "Kurs yuan hari ini berapa?", en: "What's today's rate for yuan?"),
            Phrase("我自己再数一遍", id: "Saya hitung sendiri dulu, ya.", en: "Let me count it myself."),
            Phrase("附近有 ATM 吗？", id: "Ada ATM di dekat sini?", en: "Is there an ATM nearby?"),
            Phrase("请给我十万面额的", id: "Minta pecahan seratus ribu.", en: "Hundred-thousand notes, please."),
        ]
        case .hotel: return [
            Phrase("我已经预订了房间", id: "Saya sudah pesan kamar.", en: "I have a reservation."),
            Phrase("押金什么时候退？", id: "Depositnya kapan dikembalikan?", en: "When will the deposit be returned?"),
            Phrase("没有热水", id: "Air panasnya tidak ada.", en: "There's no hot water."),
            Phrase("房间空调坏了", id: "AC di kamar rusak.", en: "The AC in my room is broken."),
            Phrase("可以寄存行李吗？", id: "Boleh titip koper?", en: "Can I leave my luggage here?"),
        ]
        case .tour: return [
            Phrase("几点出发？", id: "Berangkat jam berapa?", en: "What time do we leave?"),
            Phrase("价格包含什么？", id: "Harganya sudah termasuk apa saja?", en: "What does the price include?"),
            Phrase("在哪里集合？", id: "Kumpul di mana?", en: "Where do we meet?"),
            Phrase("请等我十分钟", id: "Tolong tunggu sepuluh menit.", en: "Please wait ten minutes."),
        ]
        case .spa: return [
            Phrase("轻一点", id: "Pelan-pelan saja, ya.", en: "A bit softer, please."),
            Phrase("重一点", id: "Lebih keras sedikit.", en: "A bit harder, please."),
            Phrase("六十分钟多少钱？", id: "Enam puluh menit berapa?", en: "How much for sixty minutes?"),
        ]
        case .health: return [
            Phrase("我拉肚子", id: "Saya diare.", en: "I have diarrhea."),
            Phrase("我发烧了", id: "Saya demam.", en: "I have a fever."),
            Phrase("这个药一天吃几次？", id: "Obat ini diminum berapa kali sehari?", en: "How many times a day do I take this?"),
            Phrase("我对青霉素过敏", id: "Saya alergi penisilin.", en: "I'm allergic to penicillin."),
        ]
        case .emergency: return [
            Phrase("请帮帮我", id: "Tolong bantu saya.", en: "Please help me."),
            Phrase("我的护照丢了", id: "Paspor saya hilang.", en: "I lost my passport."),
            Phrase("请叫救护车", id: "Tolong panggil ambulans.", en: "Please call an ambulance."),
            Phrase("警察局在哪里？", id: "Kantor polisi di mana?", en: "Where is the police station?"),
        ]
        case .directions: return [
            Phrase("这个地方怎么走？", id: "Ke tempat ini lewat mana?", en: "How do I get to this place?"),
            Phrase("远吗？", id: "Jauh tidak?", en: "Is it far?"),
            Phrase("厕所在哪里？", id: "Toiletnya di mana?", en: "Where is the toilet?"),
        ]
        case .chat: return [
            Phrase("谢谢", id: "Terima kasih.", en: "Thank you."),
            Phrase("没关系", id: "Tidak apa-apa.", en: "No problem."),
            Phrase("我来自中国", id: "Saya dari Tiongkok.", en: "I'm from China."),
            Phrase("我不会说印尼语", id: "Saya tidak bisa bahasa Indonesia.", en: "I don't speak Indonesian."),
        ]
        }
    }
}
