# In-app purchases (English localization) and Review Notes

| Product ID | Type | Display name (en) | Description (en, ≤45) |
|---|---|---|---|
| `pass.trip30` | Non-renewing subscription | Trip Pass (30 days) | Full offline use for 30 days, no auto-renewal |
| `unlock.lifetime` | Non-consumable | Lifetime | Full offline use, forever |

Same text is in `App/TripApp/Products.storekit` (en_US) for local StoreKit testing; enter it in App Store Connect too.

## Review Notes (submit in English)
```
This app translates between Chinese, Indonesian and English fully on-device using an LLM
(Qwen2.5-1.5B fine-tune, Apache-2.0, ~1 GB) downloaded once over Wi-Fi on first launch. No account.
Network use: (1) one-time model download, (2) Apple speech/translation language assets,
(3) public FX rates from api.frankfurter.dev (no user data). Conversations never leave the device.
The UI is available in Chinese and English (follows the system language; override in
Settings > App language).
How to test: 1) Launch on Wi-Fi and wait for the download (~1-3 min). 2) Tap "Start conversation".
At the top choose "I speak" and "They speak" (e.g. English / Indonesian). 3) Paste or type
"Harganya Rp 100.000 kak" as the other side -> the translation shows "Rp 100,000 (≈ $5.6)".
Indonesian->English uses Apple on-device translation; the local model adds understanding for Chinese readers.
4) Phrases work immediately, even before the download completes. 5) "Demo" on the setup screen
shows a pre-recorded conversation without any download.
Trial: 24 hours from the first translated message; then IAP (30-day non-renewing Trip Pass or
Lifetime). Restore Purchases is in Settings > Purchase / Restore. Translations are for reference only.
```
