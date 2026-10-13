# App Store Connect「App 隐私」填写建议

- **是否收集数据**：否（Data Not Collected）。
  - 理由：对话/语音只在设备端处理；汇率请求不含用户数据；购买由 Apple 处理；试用时间仅存本机 Keychain，不传给开发者。
- **跟踪（ATT）**：否，不调用 AppTrackingTransparency。
- 若将来加入崩溃统计/分析 SDK，必须改为「诊断/使用数据—不关联身份」并更新本文件与隐私政策。
- 隐私清单 `PrivacyInfo.xcprivacy`（待加，需 Mac）：NSPrivacyTracking=false；Required Reason API：UserDefaults（CA92.1）、文件时间戳（C617.1，若下载器读 mtime）、`systemUptime`（35F9.1，试用防改时钟若使用）。上线前在 Xcode 里核对实际调用。
- 麦克风/语音识别用途说明（Info.plist）：「用于把你或对方说的话转成文字，在本机处理，不上传。」
