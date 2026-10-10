import Foundation

/// 把 token 字节流拼成合法 UTF-8：多字节汉字可能跨 token。
public struct UTF8Accumulator {
    private var pending: [UInt8] = []
    public init() {}
    public mutating func append(_ bytes: [UInt8]) -> String {
        pending += bytes
        var end = pending.count
        // 找到最后一个完整字符边界
        var i = pending.count - 1, back = 0
        while i >= 0 && back < 4 {
            let b = pending[i]
            if b & 0xC0 != 0x80 {
                let need = b >= 0xF0 ? 4 : b >= 0xE0 ? 3 : b >= 0xC0 ? 2 : 1
                if pending.count - i < need { end = i }
                break
            }
            i -= 1; back += 1
        }
        let s = String(decoding: pending[..<end], as: UTF8.self)
        pending.removeFirst(end)
        return s
    }
}
