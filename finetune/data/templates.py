# -*- coding: utf-8 -*-
"""场景模板（人工撰写，非任何模型生成）。
记号：
  «w»   可俚语化的词：原文随机换成缩写；字面里若原文用了缩写则保留缩写（模拟系统直译看不懂），否则用中文
  {A}{B} 金额槽：原文随机写成 50rb / 50 ribu / 50k / Rp 50.000 / 1,5jt / 1.5 juta；目标里用 ⟨A1⟩⟨A2⟩（由 App 换算器填）
  {HON}  称呼 kak/pak/bu/mas：字面直译成「姐姐/先生/女士/哥」，目标里省略
  {N}    小整数；{M} 分钟数；{H} 钟点；{PL} 地点；{IT} 物品
  ctx    上下文轮次 [(role, 原文, 中文或对方看到的译文)]
方向：dir="them" 对方印尼语 → 中文理解；dir="me" 我的中文含指代 → 澄清后的中文（不得新增数字）
"""
SLANG = {
    "sudah": (["udh", "sdh", "udah"], "已经"), "belum": (["blm"], "还没"), "tidak": (["gk", "ga", "nggak", "gak"], "不"),
    "berapa": (["brp"], "多少"), "saya": (["sy", "aku"], "我"), "lagi": (["lg"], "再"), "menit": (["mnt"], "分钟"),
    "saja": (["aja"], "就"), "banget": (["bgt"], "非常"), "terima kasih": (["makasih", "mksh"], "谢谢"),
    "lokasi": (["lok"], "位置"), "bisa": (["bs"], "可以"), "yang": (["yg"], "的"), "dengan": (["dgn"], "和"),
    "sebentar": (["bntr"], "一会儿"), "jalan": (["jln"], "路"), "dulu": (["dl"], "先"), "kalau": (["kalo", "klo"], "如果"),
    "sampai": (["sampe", "smp"], "到"), "tunggu": (["tggu"], "等"), "gimana": (["gmn"], "怎么样"), "bagaimana": (["gmn"], "怎么样"),
}
HON = {"kak": "姐姐", "pak": "先生", "bu": "女士", "mas": "哥"}
PL = {"lobby": ("大堂", "大堂"), "pintu depan": ("前门", "正门口"), "parkiran": ("停车场", "停车场"), "gerbang": ("大门", "大门口"),
      "pom bensin": ("加油站", "加油站"), "masjid": ("清真寺", "清真寺")}
IT = {"baju": ("衣服", "衣服"), "sarung": ("纱笼", "纱笼"), "tas": ("包", "包"), "kopi": ("咖啡", "咖啡"), "kaos": ("T恤", "T恤"),
      "topi": ("帽子", "帽子"), "patung": ("雕像", "木雕"), "sandal": ("凉鞋", "拖鞋")}

# (id, scene, dir, src, literal, target, ctx, glossary, amount_kinds)
# amount_kinds: 每个金额槽的数值范围类型: small(5k-95k) mid(100k-900k) big(1jt-5jt) rate(汇率)
T = [
# 1 机场入境
("ar1","arrival","them","«tolong» tunjukkan QR e-CD {HON}","请出示 e-CD 二维码{HON}","请出示海关申报二维码",[],[["e-CD","海关电子申报"]],[]),
("ar2","arrival","them","bayar VOA {A}, «bisa» pakai kartu","付 VOA {A}，«bisa»用卡","落地签要付⟨A1⟩，可以刷卡",[],[["VOA","落地签"]],["voa"]),
("ar3","arrival","them","tiket pulang «sudah» ada {HON}?","回程票«sudah»有{HON}？","你有回程机票吗？",[],[],[]),
("ar4","arrival","them","«tunggu» di «sini» «sebentar», «saya» cek paspornya","在这里«tunggu»«sebentar»，«saya»检查护照","请在这里稍等，我查一下护照",[],[],[]),
("ar5","arrival","them","pajak turis Bali {A} per orang, «sudah» bayar?","巴厘岛游客税{A}每人，«sudah»付了吗？","巴厘岛游客税每人⟨A1⟩，你付过了吗？",[],[],["tax"]),
# 2 机场接车
("pk1","pickup","them","«saya» «sudah» di P{N} lantai dasar, mobil {COL}","«saya»«sudah»在P{N}底楼，汽车{COLZ}","我已经到了，在P{N}停车场一楼，{COLZ}的车",[],[],[]),
("pk2","pickup","them","keluar pintu kedatangan, «jalan» ke parkiran ya {HON}","出到达门，«jalan»到停车场吧{HON}","从到达出口出来，走到停车场",[],[],[]),
("pk3","pickup","them","{HON} «sudah» keluar «belum»? «saya» «tunggu» di zona jemput","{HON}«sudah»出来«belum»？«saya»在接送区«tunggu»","你出来了吗？我在接送区等你",[],[],[]),
("pk4","pickup","them","jangan ikut orang «yang» nawarin taksi «di sini» ya","不要跟着«yang»提供出租车的人在这里","别跟这里主动拉你坐出租车的人走",[],[],[]),
# 3 打车
("rd1","ride","them","«share» «lokasi» «saja» {HON}, alamatnya «tidak» ketemu","«share»«lokasi»«saja»{HON}，地址«tidak»找到","发个定位给我吧，地址找不到",[],[],[]),
("rd2","ride","them","macet «banget» {HON}, mungkin {M} «menit» «lagi»","非常macet {HON}，也许{M}«menit»«lagi»","堵得很厉害，大概还要{M}分钟",[],[],[]),
("rd3","ride","them","tambah {A} ya, «jalan»nya jauh","加{A}吧，路很远","路很远，要加⟨A1⟩",[],[],["small"]),
("rd4","ride","them","di «sini» «tidak» boleh jemput, «jalan» dikit ke depan ya","这里«tidak»可以接，往前走一点吧","这里不让接客，往前走一点",[],[],[]),
("rd5","ride","them","«saya» otw, {M} «menit» «sampai»","«saya» otw，{M}«menit»«sampai»","我在路上了，{M}分钟到",[],[],[]),
("rd6","ride","them","bayar cash ya {HON}, {A} sesuai aplikasi","付现金吧{HON}，{A}按应用","按 App 上的价格付现金，⟨A1⟩",[],[],["small"]),
("rd7","ride","them","«saya» «sudah» di depan {PL}, mobil {COL}","«saya»«sudah»在{PLL}前面，汽车{COLZ}","我已经在{PLZ}前面了，{COLZ}的车",[],[],[]),
("rd8","ride","them","tol «atau» «tidak» {HON}? lewat tol tambah {A}","收费路还是«tidak»{HON}？走收费路加{A}","要不要走收费路？走收费路要多付⟨A1⟩",[],[],["small"]),
("rd9","ride","me","就停在刚才那个地方","就停在刚才那个地方","就停在刚才说的那个{PLZ}",[("them","«saya» «sudah» di depan {PL}","我已经在{PLZ}前面")],[],[]),
# 4 定位/地址
("lc1","location","them","«kirim» lok «dong» {HON}, «saya» «tidak» tau gang-nya","«kirim» lok吧{HON}，«saya»«tidak»知道gang","发个定位给我吧，我不知道是哪条小巷",[],[["gang","小巷"]],[]),
("lc2","location","them","pin-nya salah {HON}, «yang» bener «di mana»?","针错了{HON}，«yang»对的在哪？","定位标错了，正确的位置在哪里？",[],[],[]),
("lc3","location","them","«saya» «sudah» «sampai» titik, «tapi» «tidak» lihat {HON}","«saya»«sudah»«sampai»点，«tapi»«tidak»看见{HON}","我已经到定位点了，但是没看到你",[],[],[]),
# 5 外卖
("dl1","delivery","them","pesanan «sudah» «saya» ambil, otw ya {HON}","订单«sudah»«saya»拿了，otw {HON}","我已经取到餐了，在路上",[],[],[]),
("dl2","delivery","them","{HON} menu {FOOD} habis, mau ganti apa?","{HON}菜单{FOOD}完了，要换什么？","{FOODZ}卖完了，要换成什么？",[],[],[]),
("dl3","delivery","them","bayar cash ya {HON}, totalnya {A}","付现金吧{HON}，总共{A}","付现金，一共⟨A1⟩",[],[],["small"]),
("dl4","delivery","them","«saya» «sudah» di depan gerbang, «tolong» turun ya","«saya»«sudah»在大门前面，请下来吧","我已经到大门口了，请下来拿",[],[],[]),
("dl5","delivery","them","ongkirnya naik {A} karena hujan","运费涨了{A}因为下雨","因为下雨，运费涨了⟨A1⟩",[],[["ongkir","运费"]],["small"]),
("dl6","delivery","them","«tidak» ada kembalian {HON}, uang pas «saja» ya","«tidak»有找零{HON}，正好的钱«saja»","我没有零钱找，请付整数",[],[],[]),
# 6 餐厅
("rs1","restaurant","them","mau level pedas «berapa»? 0 «sampai» 5","要辣度«berapa»？0«sampai»5","要几级辣？0到5级",[],[],[]),
("rs2","restaurant","them","harga «belum» termasuk pajak 10% dan service 5%","价格«belum»包括税10%和服务5%","价格还不含10%的税和5%的服务费",[],[],[]),
("rs3","restaurant","them","{FOOD} {A}, porsinya besar","{FOOD} {A}，份量大","{FOODZ}⟨A1⟩，份量很大",[],[],["small"]),
("rs4","restaurant","them","ada kacang di sausnya {HON}","酱里有花生{HON}","酱里有花生",[("me","我对花生过敏","Saya alergi kacang")],[],[]),
("rs5","restaurant","them","totalnya {A}, harga nett ya","总共{A}，净价","一共⟨A1⟩，已经是含税的最终价",[],[["nett","含税最终价"]],["mid"]),
("rs6","restaurant","them","«yang» ini «tidak» pedas, «yang» itu pedas «banget»","«yang»这个«tidak»辣，«yang»那个非常辣","这个不辣，那个特别辣",[],[],[]),
("rs7","restaurant","me","我要刚才说的那个","我要刚才说的那个","我要刚才说的那份{FOODZ}",[("them","{FOOD} enak, «tidak» pedas","{FOODZ}好吃，不辣")],[],[]),
("rs8","restaurant","them","harganya {N}0 ++ ya","价格是{N}0 ++","价格是{N}万，另外还要加税和服务费",[("them","menu mulai {A}","菜单{A}起")],[["++","另加税和服务费"]],["small"]),
# 7 购物/市场
("sh1","shopping","them","ini {A}, «bisa» kurang dikit","这个{A}，«bisa»少一点","这个⟨A1⟩，可以便宜一点",[],[],["small"]),
("sh2","shopping","them","{IT} «yang» tadi {N}0 «saja»","刚才的{ITL}{N}0«saja»","刚才那件{ITZ}{N}万就行",[("them","{IT} ini {A}","这个{ITZ}{A}")],[],["mid"]),
("sh3","shopping","them","beli dua «bisa» {A}","买两个«bisa»{A}","买两个的话⟨A1⟩",[],[],["mid"]),
("sh4","shopping","them","harga pas {HON}, «tidak» «bisa» kurang «lagi»","固定价格{HON}，«tidak»«bisa»再少","这是实价，不能再便宜了",[],[],[]),
("sh5","shopping","me","那个我也要","那个我也要","刚才那件{ITZ}我也要",[("them","{IT} ini juga ada","这个{ITZ}也有")],[],[]),
("sh6","shopping","them","{IT} «yang» besar {A}, «yang» kecil {B}","{ITL}«yang»大的{A}，«yang»小的{B}","大的{ITZ}⟨A1⟩，小的⟨A2⟩",[],[],["mid","small"]),
# 8 换汇/ATM
("mx1","money","them","rate hari ini {RATE} per yuan, minimal tukar {A}","今天汇率每元{RATE}，最低兑换{A}","今天汇率是一元人民币换{RATEZ}印尼盾，最少要换⟨A2⟩",[],[],["big"]),
("mx2","money","them","uangnya dihitung «lagi» ya {HON} di «sini»","钱在这里«lagi»数吧{HON}","请在这里再数一遍钱",[],[],[]),
("mx3","money","them","ATM «tidak» terima kartu ini, coba BCA «saja»","ATM«tidak»收这张卡，试试BCA«saja»","这台ATM不收这张卡，去BCA的试试",[],[],[]),
("mx4","money","them","pilih rupiah ya, jangan konversi","选卢比吧，不要转换","请选印尼盾结算，不要选货币转换",[],[["konversi","动态货币转换(DCC)"]],[]),
("mx5","money","them","total {A}, mau pecahan «berapa»?","总共{A}，要«berapa»面额？","一共⟨A1⟩，要什么面额的？",[],[],["big"]),
# 9 付款
("py1","payment","them","«bisa» QRIS «atau» cash, kartu «tidak» «bisa»","«bisa» QRIS或现金，卡«tidak»«bisa»","可以用QRIS或现金，不能刷卡",[],[],[]),
("py2","payment","them","kembaliannya «tidak» ada, uang pas «saja»","找零«tidak»有，正好的钱«saja»","没零钱找，请付正好的金额",[],[],[]),
("py3","payment","them","QRIS-nya error {HON}, cash «saja» ya {A}","QRIS错误{HON}，现金«saja»{A}","QRIS付不了，请付现金⟨A1⟩",[],[],["small"]),
("py4","payment","them","kena biaya kartu 3% {HON}","卡费3%{HON}","刷卡要另收3%手续费",[],[],[]),
# 10 电话卡
("sm1","sim","them","paket {D} hari {G}GB {A}, perlu paspor","{D}天{G}GB套餐{A}，需要护照","{D}天{G}GB的套餐⟨A1⟩，需要护照",[],[],["mid"]),
("sm2","sim","them","kuotanya «sudah» habis, isi ulang {A}","流量«sudah»用完，充值{A}","流量已经用完了，充值要⟨A1⟩",[],[["kuota","流量"]],["small"]),
("sm3","sim","them","eSIM «bisa», HP-nya «sudah» unlock «belum»?","eSIM«bisa»，手机«sudah»解锁«belum»？","可以用eSIM，你的手机解锁了吗？",[],[],[]),
# 11 酒店/别墅
("ht1","hotel","them","check in jam {HS} siang, «sekarang» kamarnya «belum» siap","下午{HS}点入住，现在房间«belum»准备好","下午{HS}点才能入住，现在房间还没准备好",[],[],[]),
("ht2","hotel","them","deposit {A}, nanti dikembalikan pas check out","押金{A}，退房时会退回","押金⟨A1⟩，退房时退还",[],[],["mid"]),
("ht3","hotel","them","air panasnya harus «tunggu» {M} «menit» «dulu» ya","热水要«tunggu»{M}«menit»«dulu»","热水要先等{M}分钟",[],[],[]),
("ht4","hotel","them","teknisi «sudah» «saya» panggil, {M} «menit» «lagi» datang","技术员«sudah»«saya»叫了，{M}«menit»«lagi»来","我已经叫了维修工，{M}分钟后到",[("me","房间空调坏了","AC di kamar rusak")],[],[]),
("ht5","hotel","them","late check out tambah {A} «sampai» jam {HS}","晚退房加{A}«sampai»{HS}点","延迟退房到下午{HS}点要加⟨A1⟩",[],[],["mid"]),
("ht6","hotel","them","sarapan jam 7 «sampai» 10 di lantai {N}","早餐7点«sampai»10点在{N}楼","早餐时间7点到10点，在{N}楼",[],[],[]),
("ht7","hotel","me","这个可以退吗","这个可以退吗","押金可以退吗",[("them","deposit {A} ya","押金{A}")],[],["mid"]),
# 12 包车/快艇
("tr1","tour","them","sewa mobil {N2} jam {A} «sudah» termasuk bensin","租车{N2}小时{A}«sudah»含汽油","包车{N2}小时⟨A1⟩，已经含油费",[],[],["mid"]),
("tr2","tour","them","kapal ke Gili jam {H}, harus di pelabuhan jam {H0}.30","去Gili的船{H}点，必须{H0}.30在码头","去Gili的船{H}点开，{H0}点半之前要到码头",[],[],[]),
("tr3","tour","them","tiket «belum» termasuk tiket masuk {A} per orang","票«belum»包括门票{A}每人","票价还不含门票，每人⟨A1⟩",[],[],["small"]),
("tr4","tour","them","«saya» jemput di hotel jam {H} pagi","«saya»在酒店接早上{H}点","我早上{H}点到酒店接你",[],[],[]),
# 13 按摩
("sp1","spa","them","pijat {M2} «menit» {A}, tipnya terserah","按摩{M2}«menit»{A}，小费随意","按摩{M2}分钟⟨A1⟩，小费随意",[],[],["mid"]),
("sp2","spa","them","tekanannya mau keras «atau» pelan?","压力要硬还是慢？","力度要重一点还是轻一点？",[],[],[]),
("sp3","spa","them","mandi «dulu» «sebentar» ya {HON}, handuknya di «sini»","«dulu»洗澡«sebentar»{HON}，毛巾在这里","请先冲个澡，毛巾在这里",[],[],[]),
# 14 药店/看病
("md1","health","them","diminum {X}x sehari sesudah makan","一天{X}x饭后喝","一天{X}次，饭后吃",[],[],[]),
("md2","health","them","ini obat diare, «kalau» demam harus ke dokter","这是腹泻药，«kalau»发烧必须去医生","这是止泻药，如果发烧要去看医生",[],[],[]),
("md3","health","them","antibiotik harus pakai resep dokter {HON}","抗生素必须用医生处方{HON}","抗生素要有医生处方才能买",[],[],[]),
("md4","health","them","obatnya {A}, diminum sebelum tidur","药{A}，睡前喝","药⟨A1⟩，睡前吃",[],[],["small"]),
("md5","health","them","sakitnya «sudah» «berapa» hari?","痛«sudah»«berapa»天？","疼了几天了？",[],[],[]),
# 15 紧急
("em1","emergency","them","«sudah» lapor polisi? perlu surat kehilangan","«sudah»报警了吗？需要遗失信","报警了吗？需要开丢失证明",[],[],[]),
("em2","emergency","them","«tunggu» «di sini», ambulans «sudah» «saya» panggil","在这里«tunggu»，救护车«sudah»«saya»叫了","在这里等着，我已经叫了救护车",[],[],[]),
("em3","emergency","them","HP-nya «sudah» ketemu {HON}, ambil di pos satpam","手机«sudah»找到{HON}，在保安亭拿","手机找到了，去保安亭领",[],[],[]),
# 16 问路
("dr1","directions","them","lurus «saja», nanti di perempatan belok {LR}","直走«saja»，然后在十字路口转{LRL}","一直走，到十字路口{LRZ}转",[],[],[]),
("dr2","directions","them","«tidak» jauh, jalan kaki {M} «menit»","«tidak»远，走路{M}«menit»","不远，走路{M}分钟",[],[],[]),
("dr3","directions","them","masuk gang «yang» sebelah {PL}","进{PLL}旁边«yang»gang","进{PLZ}旁边的那条小巷",[],[["gang","小巷"]],[]),
("dr4","directions","me","那边怎么走","那边怎么走","{PLZ}那边怎么走",[("them","{PL}nya di «sana»","{PLZ}在那边")],[],[]),
# 17 闲聊
("ch1","chat","them","dari mana {HON}? pertama kali ke Bali?","{HON}从哪里来？第一次来巴厘岛？","你从哪里来？第一次来巴厘岛吗？",[],[],[]),
("ch2","chat","them","gpp {HON}, santai «saja»","gpp {HON}，放松«saja»","没关系，别着急",[],[],[]),
("ch3","chat","them","«terima kasih» {HON}, hati-hati di «jalan» ya","«terima kasih»{HON}，路上小心","谢谢，路上小心",[],[],[]),
("me1","ride","me","就按刚才那个价","就按刚才那个价","就按刚才说的App上的价格",[("them","bayar sesuai aplikasi {A} ya","按应用付{A}")],[],["small"]),
("me2","hotel","me","那个几点开始","那个几点开始","早餐几点开始",[("them","sarapan di lantai {N} ya","早餐在{N}楼")],[],[]),
("me3","shopping","me","还是之前那个吧","还是之前那个吧","还是要之前那件{ITZ}吧",[("them","{IT} ini lebih bagus","这个{ITZ}更好")],[],[]),
("me4","tour","me","那里远吗","那里远吗","{PLZ}远吗",[("them","ketemu di {PL} ya","在{PLZ}见")],[],[]),
("me5","health","me","这个饭前吃还是饭后吃","这个饭前吃还是饭后吃","这个药饭前吃还是饭后吃",[("them","ini obat sakit perut","这是胃痛药")],[],[]),
("me6","delivery","me","放在那里就行","放在那里就行","放在{PLZ}就行",[("them","«saya» «sudah» di depan {PL}","我已经在{PLZ}前面")],[],[]),
("me7","money","me","这个怎么用","这个怎么用","这台ATM怎么用",[("them","ATM-nya di sebelah kiri","ATM在左边")],[],[]),
("me8","spa","me","刚才那样再来一次","刚才那样再来一次","刚才那个力度再来一次",[("them","tekanannya begini, cukup?","力度这样够吗？")],[],[]),
("me9","restaurant","me","那个不要了","那个不要了","{FOODZ}不要了",[("them","{FOOD} «sudah» dipesan","{FOODZ}已经点了")],[],[]),
("me10","sim","me","这个能用多久","这个能用多久","这个流量套餐能用多久",[("them","paket internet {A}","上网套餐{A}")],[],["mid"]),
("ch4","chat","them","«sudah» makan «belum»?","«sudah»吃了«belum»？","吃饭了吗？",[],[],[]),
]
COL = {"hitam": "黑色", "putih": "白色", "silver": "银色", "merah": "红色", "abu-abu": "灰色"}
FOOD = {"ayam geprek": "印尼辣椒炸鸡", "nasi goreng": "炒饭", "mie goreng": "炒面", "sate ayam": "鸡肉沙爹", "babi guling": "烤乳猪"}
EOF=1

FALLBACK_ZH = {"tolong": "请", "sini": "这里", "atau": "还是", "share": "分享", "kirim": "发", "dong": "吧", "di mana": "在哪",
               "tapi": "但是", "sekarang": "现在", "sana": "那边", "di sini": "在这里"}
