# Bundled Flutter Web fallback shards

Flutter Web dynamically requests fallback fonts when the active font lacks a
glyph. `web/flutter_bootstrap.js` changes that base URL to this same-origin
directory so the app never falls back to Google's CDN at runtime.

These files match the paths in Flutter 3.41.4 engine revision
`e4b8dca3f1b4ede4c30371002441c88c12187ed6`. They cover the editor symbols
and the QA sample `Hello 👨‍👩‍👧‍👦 雪界 العربية`. They are intentionally not a
complete mirror of Flutter's fallback corpus: another unsupported glyph can
produce a local 404/tofu glyph, but it cannot trigger a cross-origin request.

| Family | Runtime path | Bytes | SHA-256 |
|---|---|---:|---|
| Noto Sans Symbols | `notosanssymbols/v43/rP2up3q65FkAtHfwd-eIS2brbDN6gxP34F9jRRCe4W3gfQ8gb_VFRkzrbQ.woff2` | 69116 | `08202e258ea583254c036cff46a7077bb5af4f82c41a6c0a6775f6e44d99f1aa` |
| Noto Sans Arabic | `notosansarabic/v28/nwpxtLGrOAZMl5nJ_wfgRg3DrWFZWsnVBJ_sS6tlqHHFlhQ5l3sQWIHPqzCfyGyvvnCBFQLaig.woff2` | 66412 | `53251baf8845f9b2c35517a8d157b76aa80ab871fa9848ff2374c7f5f0e4ef97` |
| Noto Color Emoji | `notocoloremoji/v32/Yq6P-KqIXTD0t4D9z1ESnKM3-HpFabsE4tq3luCC7p-aXxcn.8.woff2` | 347976 | `ee9007c489ff2b25249350c44325bfe91830870d4c89addd8ccf363321064242` |
| Noto Sans SC | `notosanssc/v37/k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaG9_FnYkldv7JjxkkgFsFSSOPMOkySAZ73y9ViAt3acb8NexQ2w.114.woff2` | 30780 | `7bfac406b34c8a16f53513e23e6a294a9e8cca4af54558753de4cdc0f7e97801` |
| Noto Sans SC | `notosanssc/v37/k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaG9_FnYkldv7JjxkkgFsFSSOPMOkySAZ73y9ViAt3acb8NexQ2w.116.woff2` | 28216 | `79bb760c71ec87a5d65ccd803fab5f3e07a3a25b1b5f003a5f4369cb0d0c9e15` |

The runtime files came from the exact `fonts.gstatic.com` paths embedded in
that Flutter engine. Copyright notices were cross-checked against the matching
Google Fonts directories at commit
`ec626514f79f831f1ab848a82114a0ce7e2d6372`. See `OFL.txt` for the combined
notices and SIL Open Font License 1.1.
