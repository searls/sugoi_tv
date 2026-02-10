# YoiTV API & Streaming Architecture

Reverse-engineered from `play.yoitv.com` — a Vue.js (Element UI) web app using
HLS.js for video playback. All findings below are sufficient to build a native
macOS/iOS/tvOS replacement.

---

## 1. Architecture Overview

```
┌──────────────┐     login/refresh      ┌──────────────────────┐
│  Native App  │ ───────────────────────▶│  crm.yoitv.com       │
│              │ ◀─ access_token ────────│  (Auth/CRM Server)   │
│              │     + product_config    │  HTTPS :443           │
│              │                         └──────────────────────┘
│              │     channel list +
│              │     EPG data            ┌──────────────────────┐
│              │ ───────────────────────▶│  live.yoitv.com:9083 │
│              │ ◀─ JSON ───────────────│  (VMS - Live)        │
│              │                         └──────────────────────┘
│              │     HLS master →
│              │     variant → .ts       ┌──────────────────────┐
│              │ ───────────────────────▶│  67.21.92.86:9083    │
│              │ ◀─ MPEG-TS ────────────│  (CDN / Edge)        │
│              │                         └──────────────────────┘
│              │     VOD / recorded      ┌──────────────────────┐
│              │ ───────────────────────▶│  vod.yoitv.com:9083  │
│              │ ◀─ HLS ────────────────│  (VMS - VOD)         │
│              │                         └──────────────────────┘
│              │     favorites/history   ┌──────────────────────┐
│              │ ───────────────────────▶│  crm.yoitv.com/tvum  │
│              │ ◀─ JSON ───────────────│  (User Data API)     │
└──────────────┘                         └──────────────────────┘
```

### Servers (from `product_config`)

| Role | Host | Protocol |
|------|------|----------|
| Auth/CRM | `https://crm.yoitv.com` | HTTPS |
| Live VMS (channel list, thumbnails) | `http://live.yoitv.com:9083` | HTTP |
| Live RTMFP (legacy Flash) | `rtmfp://live.yoitv.com:9035` | RTMFP (unused) |
| VOD VMS | `http://vod.yoitv.com:9083` | HTTP |
| VOD RTMFP (legacy Flash) | `rtmfp://vod.yoitv.com:9035` | RTMFP (unused) |
| CDN / Edge (actual stream delivery) | `http://67.21.92.86:9083` | HTTP |
| Single-play enforcement | `https://crm.yoitv.com/single.sjs` | HTTPS |

---

## 2. Authentication

### 2.1 Login

```
GET https://crm.yoitv.com/logon.sjs
    ?from_app=1
    &cid={CUSTOMER_ID}
    &password={PASSWORD}
    &app_id={APP_ID}           // can be empty string
    &device_id={DEVICE_ID}     // 32-char hex, generated once and persisted
```

**Response** (JSON):
```json
{
  "access_token": "ZZVWXJbb...Krg==",
  "token_type": "bearer",
  "expires_in": 1770770216,
  "refresh_token": "HegSNm...0zg==",
  "expired": false,
  "disabled": false,
  "confirmed": true,
  "cid": "AABC538835997",
  "type": "tvum_cid",
  "trial": 0,
  "create_time": 1652403783,
  "expire_time": 1782959503,
  "product_config": "{...}",   // JSON string (double-encoded)
  "server_time": 1770755816,
  "code": "OK"
}
```

Key fields:
- `access_token` — Bearer token for all authenticated requests. URL-encoded as `__cross_domain_user` for stream auth.
- `refresh_token` — Used to refresh the session (see below).
- `product_config` — JSON string containing all VMS server addresses and account config. **Must be JSON.parse()'d**.
- `expires_in` — Unix timestamp when the access token expires.
- `expire_time` — Unix timestamp when the subscription expires.

### 2.2 Device ID Generation

A one-time random 16-byte hex string, persisted in localStorage:

```swift
// Swift equivalent
func generateDeviceId() -> String {
    (0..<16).map { _ in String(format: "%02X", UInt8.random(in: 0...255)) }.joined()
}
// Store in UserDefaults, reuse forever
```

### 2.3 Token Refresh

Tokens should be refreshed every 30 minutes (1800 seconds):

```
GET https://crm.yoitv.com/refresh.sjs
    ?refresh_token={REFRESH_TOKEN}
    &cid={CID}
    &app_id={APP_ID}
    &device_id={DEVICE_ID}
```

Response is identical in shape to the login response. If the response has
`code: "AUTH"`, the session is invalid — log out and re-authenticate.

### 2.4 Product Config

The `product_config` field from login (after JSON.parse) looks like:

```json
{
  "vms_host": "http://live.yoitv.com:9083",
  "vms_rtmfp_host": "rtmfp://live.yoitv.com:9035",
  "vms_vod_host": "http://vod.yoitv.com:9083",
  "vms_vod_rtmfp": "rtmfp://vod.yoitv.com:9035",
  "vms_uid": "C2D9261F3D5753E74E97EB28FE2D8B26",
  "vms_live_cid": "A1B9470C288260372598FC7C577E4C61",
  "vms_referer": "http://play.yoitv.com",
  "website": "",
  "priceLink": "https://download.yoitv.com/app/price.json",
  "purchaseLink": "",
  "epg_days": 30,
  "single": "https://crm.yoitv.com/single.sjs"
}
```

Derived server roles:
- **channelListHost** = `vms_channel_list_host` ?? `vms_host`
- **liveHost** = `vms_live_host` ?? `vms_host`
- **vodHost** = `vms_vod_host` ?? `vms_host`
- **recordHost** = `vms_record_host` ?? `vms_vod_host` ?? `vms_host`
- **liveUid** = `vms_live_uid` ?? `vms_uid`
- **liveCid** = `vms_live_cid`
- **referer** = `vms_referer`

### 2.5 Single-Play Enforcement

The service enforces single-device playback. Before playing, the web app checks:

```
GET https://crm.yoitv.com/single.sjs
    ?&ua=webpc               // or: ipad, iphone, ipod, ios
    &own={true|false}
    &access_token={ACCESS_TOKEN}
```

If the response `own` field is `false`, another device is already playing.

---

## 3. Channel List API

### 3.1 Fetch All Channels

```
GET {channelListHost}/api
    ?action=listLives
    &cid={liveCid}
    &uid={liveUid}
    &details=0
    &page_size=200
    &sort=no%20asc
    &sort=created_time%20desc
    &type=video
    &no_epg=1
    &referer={referer}
```

**Note**: No authentication header needed — the `cid`/`uid` pair acts as the content scope identifier.

**Response**:
```json
{
  "result": [
    {
      "id": "AA6EC2B2BC19EFE5FA44BE23187CDA63",
      "uid": "C2D9261F3D5753E74E97EB28FE2D8B26",
      "name": "NHK総合・東京",
      "description": "[HD]NHK General",
      "tags": "$LIVE_CAT_関東",
      "no": 101024,
      "timeshift": 1,
      "timeshift_len": 900,
      "epg_keep_days": 28,
      "state": 2,
      "running": 1,
      "playpath": "/query/s/Hqm-m7jqkFlA1CloJoaJZQ==",
      "live_type": "video",
      ...
    },
    ...
  ],
  "code": "OK"
}
```

Key fields per channel:
- `id` — Unique channel ID (32-char hex).
- `name` — Display name (Japanese).
- `description` — Optional English/supplementary description.
- `tags` — Comma-separated. Categories are prefixed with `$LIVE_CAT_` (e.g. `$LIVE_CAT_関東`, `$LIVE_CAT_関西`, `$LIVE_CAT_BS`).
- `playpath` — Base path for stream URLs and thumbnails. Always starts with `/query/s/` for live or `/query/` for VOD.
- `running` — 1 = currently broadcasting.
- `no` — Sort order number.
- `timeshift` — 1 = supports timeshift/catch-up.

### 3.2 Categories

Categories are extracted from the `tags` field:
```
$LIVE_CAT_関東  → "関東" (Kanto region)
$LIVE_CAT_関西  → "関西" (Kansai region)
$LIVE_CAT_BS    → "BS" (satellite)
...
```

Channels without a `$LIVE_CAT_*` tag go into "Others".

### 3.3 Channel Thumbnails

```
{channelListHost}{playpath}.jpg?type=live&thumbnail=thumbnail_small.jpg
```

Example:
```
http://live.yoitv.com:9083/query/s/Hqm-m7jqkFlA1CloJoaJZQ==.jpg?type=live&thumbnail=thumbnail_small.jpg
```

---

## 4. EPG (Electronic Program Guide)

### 4.1 Fetch EPG for a Channel

```
GET {channelListHost}/api
    ?action=listLives
    &cid={liveCid}
    &uid={liveUid}
    &vid={channel_id}
    &details=0
    &page_size=200
    &sort=no%20asc
    &sort=created_time%20desc
    &type=video
    &no_epg=0
    &epg_days=30
    &referer={referer}
```

The only difference from the channel list call: `vid={channel_id}`, `no_epg=0`, `epg_days=30`.

**Response** includes a `record_epg` field (JSON string) on the channel object:

```json
{
  "result": [{
    "id": "AA6EC2B2BC19EFE5FA44BE23187CDA63",
    "name": "NHK総合・東京",
    "record_epg": "[{\"time\":1768338000,\"title\":\"NHKニュース おはよう日本\",\"path\":\"/query/wtkmHz1XU-dOl-so_i2LJlsegL7gV3_laXirRbM5SSM=\"}, ...]",
    ...
  }]
}
```

Each EPG entry:
```json
{
  "time": 1768338000,       // Unix timestamp (seconds) of program start
  "title": "NHKニュース おはよう日本▼日韓首脳会談の成果は",
  "path": "/query/wtkmHz1XU-dOl-so_i2LJlsegL7gV3_laXirRbM5SSM="
}
```

- `time` — Program start time in **Unix seconds**.
- `title` — Program title (Japanese, full-width characters common).
- `path` — VOD playback path for the recorded program. If `path` is empty string `""`, the program is live-only (no recording available).

### 4.2 Time Zone Note

EPG times are in Unix seconds. The web app applies a `+9h (32400s)` offset for JST display: `1000 * epg.time + 32400000` ms.

---

## 5. Video Streaming (HLS)

### 5.1 Live Streams — Direct HLS (directHLS mode)

The web app uses `directHLS: true`, which means it skips the JSON info endpoint and goes directly to the M3U8.

**Master Playlist URL**:
```
{liveHost}{playpath}.M3U8?type=live&__cross_domain_user={URL_ENCODED_ACCESS_TOKEN}
```

Example:
```
http://live.yoitv.com:9083/query/s/Hqm-m7jqkFlA1CloJoaJZQ==.M3U8
  ?type=live
  &__cross_domain_user=idqJLucJVTnQfT%2BARugyBID%2BQPPdA80MlQeUm2aBwx4x...
```

**Master Playlist Response** (HLS variant playlist):
```m3u8
#EXTM3U
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=598000
http://67.21.92.86:9083/live/LV1PLUS-lv1/lp/1E/lp1EK-chAIUgDfzVr6EvYw==/live.livesegments.M3U8
  ?sc_tk=Pu6%2Fw3pv5rji4xCU1qwQO...%3D
  &filekey=nFc_uqQSydqjLISMdvIbi...%3D
```

This redirects to an **edge server** (67.21.92.86:9083) with `sc_tk` (session token) and `filekey` parameters.

**Variant/Segments Playlist** (standard HLS live):
```m3u8
#EXTM3U
#EXT-X-TARGETDURATION:7
#EXT-X-VERSION:2
#EXT-X-MEDIA-SEQUENCE:21103905
#EXTINF:7,
live.segments/21103905.fplsegment.ts?sc_tk=...&filekey=...
#EXTINF:7,
live.segments/21103906.fplsegment.ts?sc_tk=...&filekey=...
```

- Segment duration: **7 seconds**
- Segment format: MPEG-TS (`.ts`)
- No DRM/encryption on the segments themselves
- `sc_tk` and `filekey` must be forwarded on each segment request

### 5.2 Recorded/Catch-up Programs

**URL Pattern**:
```
{recordHost}{epg.path}.m3u8?type=vod&__cross_domain_user={ACCESS_TOKEN}
```

Note: VOD uses lowercase `.m3u8`, live uses uppercase `.M3U8`.

Example:
```
http://vod.yoitv.com:9083/query/wtkmHz1XU-dOl-so_i2LJlsegL7gV3_laXirRbM5SSM=.m3u8
  ?type=vod
  &__cross_domain_user=...
```

### 5.3 Favorite VOD Playback

For playing a favorite VOD item by vid:
```
{vodHost}/query/{vid}.m3u8?type=vod&__cross_domain_user={ACCESS_TOKEN}
```

If `dupVid` exists on the favorite, use that instead of `vid`.

### 5.4 Non-Direct HLS (fallback path)

If `directHLS` is `false`, the app first fetches stream info:

```
GET {host}{playpath}.json?type={live|vod}&callback=?
```

Response includes `substreams` array with `http_url`, `stream_name`, and `sc_tk`.
The HLS URL is then constructed from those fields. This path is not used in the
current web app (directHLS is always true) but exists as fallback.

### 5.5 AVFoundation Compatibility

The streams are **standard HLS** with no DRM:
- No FairPlay Streaming
- No Widevine
- No clear-key encryption
- MPEG-TS segments (not fMP4)
- Single bandwidth variant (~598 Kbps)

This means `AVPlayer` can play them directly:

```swift
let url = URL(string: "\(liveHost)\(playpath).M3U8?type=live&__cross_domain_user=\(accessToken.urlEncoded)")!
let playerItem = AVPlayerItem(url: url)
let player = AVPlayer(playerItem: playerItem)
player.play()
```

**Important**: The VMS server checks the `Referer` header. Set it to `http://play.yoitv.com` on all stream requests. For AVFoundation, use a custom `AVAssetResourceLoaderDelegate` or set the referer via `AVURLAsset` headers:

```swift
let headers = ["Referer": "http://play.yoitv.com"]
let asset = AVURLAsset(url: hlsURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
```

---

## 6. User Data APIs (Favorites, History)

All user data APIs use Bearer token auth:

```
Authorization: Bearer {access_token}
```

### 6.1 Favorite Live Channels

**List**:
```
GET https://crm.yoitv.com/tvum?controller=tvum_favorite&action=listLive
Authorization: Bearer {access_token}
```

Response: `{ "data": [...], "max": 300, "code": "OK" }`

**Sync (add/remove)**:
```
POST https://crm.yoitv.com/tvum?controller=tvum_favorite&action=syncLive
Authorization: Bearer {access_token}
Content-Type: application/json

{ "updates": [{ "vid": "channel_id", "name": "Channel Name", "childLock": 0, "sortOrder": 0 }] }
// or
{ "removals": ["channel_id_1", "channel_id_2"] }
```

### 6.2 Favorite VOD Programs

**List**:
```
GET https://crm.yoitv.com/tvum?controller=tvum_favorite&action=listVod
Authorization: Bearer {access_token}
```

Response: `{ "records": [...], "lastKey": null, "max": 1000, "code": "OK" }`

**Sync**:
```
POST https://crm.yoitv.com/tvum?controller=tvum_favorite&action=syncVod
Authorization: Bearer {access_token}
Content-Type: application/json

{ "updates": [{ "vid": "program_id", "name": "Program Title", "channelId": "...", "channelName": "...", "childLock": 0 }] }
```

### 6.3 Play History / Resume

**List**:
```
GET https://crm.yoitv.com/tvum?controller=tvum_favorite&action=listPlayRecord
Authorization: Bearer {access_token}
```

Response:
```json
{
  "code": "OK",
  "data": [
    {
      "vid": "1813E2FB2946FB4176867F5AFB944899",
      "name": "ＤａｙＤａｙ．【超速報!五輪日本メダル最新情報】",
      "duration": 6271899,        // milliseconds
      "pos": 701697,              // playback position in ms
      "platAt": 1770727745,       // last played timestamp (Unix seconds)
      "channelId": "CAD5FED3093396B3A4D49F326DE10CBD",
      "channelName": "日テレ",
      "playAt": 1770727043
    },
    ...
  ]
}
```

**Sync**:
```
POST https://crm.yoitv.com/tvum?controller=tvum_favorite&action=syncPlayRecord
Authorization: Bearer {access_token}
Content-Type: application/json

{ "updates": [{ "vid": "...", "name": "...", "duration": 6271899, "pos": 701697, "ended": false, "channelId": "...", "channelName": "..." }] }
```

---

## 7. App Update Check (Optional)

```
GET https://crm.yoitv.com/tvum?controller=tvum_update&app_id={APP_ID}
```

Can be ignored for a native app.

---

## 8. Complete Flow for a Native App

### Startup
1. Generate or load `deviceId` (32-char hex, persist in Keychain/UserDefaults)
2. If stored `refresh_token` exists → try refresh. On failure → show login.
3. If no stored session → show login screen.

### Login
1. `GET /logon.sjs?from_app=1&cid={user}&password={pass}&app_id=&device_id={deviceId}`
2. Parse response, store `access_token`, `refresh_token`, `cid`, and `product_config`
3. Parse `product_config` (it's a JSON string within the JSON response)

### Load Channel List
1. `GET {channelListHost}/api?action=listLives&cid={liveCid}&uid={liveUid}&details=0&page_size=200&sort=no%20asc&sort=created_time%20desc&type=video&no_epg=1&referer={referer}`
2. Group channels by `tags` → extract category from `$LIVE_CAT_*`
3. Display channel names and thumbnails

### Load EPG for Selected Channel
1. Same endpoint but add `vid={channelId}`, `no_epg=0`, `epg_days=30`
2. Parse `record_epg` JSON string from the first result

### Play Live Channel
1. Check single-play: `GET {single}?&ua=macos&own={owning}&access_token={accessToken}`
2. Build HLS URL: `{liveHost}{channel.playpath}.M3U8?type=live&__cross_domain_user={urlEncode(accessToken)}`
3. Set `Referer: http://play.yoitv.com` header
4. Feed to AVPlayer

### Play Recorded Program
1. Build HLS URL: `{recordHost}{epg.path}.m3u8?type=vod&__cross_domain_user={urlEncode(accessToken)}`
2. Set `Referer: http://play.yoitv.com` header
3. Feed to AVPlayer. Optionally seek to saved position from play history.

### Token Refresh (background timer)
1. Every 30 minutes: `GET /refresh.sjs?refresh_token={refresh_token}&cid={cid}&app_id=&device_id={deviceId}`
2. Update stored tokens and product_config
3. If refresh fails with `AUTH` code → force re-login

---

## 9. Data Model Summary

### Channel
```
id: String           // "AA6EC2B2BC19EFE5FA44BE23187CDA63"
name: String          // "NHK総合・東京"
description: String?  // "[HD]NHK General"
tags: String          // "$LIVE_CAT_関東"
playpath: String      // "/query/s/Hqm-m7jqkFlA1CloJoaJZQ=="
no: Int               // 101024 (sort order)
running: Int          // 1 = broadcasting
timeshift: Int        // 1 = supports catch-up
epg_keep_days: Int    // 28
```

### EPG Entry
```
time: Int             // Unix timestamp (seconds)
title: String         // "NHKニュース おはよう日本"
path: String          // "/query/wtkmHz1XU-..." (VOD playback path, "" if live-only)
```

### Play Record
```
vid: String           // Program ID
name: String          // Program title
duration: Int         // Total duration in milliseconds
pos: Int              // Current position in milliseconds
channelId: String     // Source channel ID
channelName: String   // Source channel name
playAt: Int           // Unix timestamp of last play
```

---

## 10. Important Implementation Notes

1. **Referer Header**: The VMS server validates the `Referer` header. Always set `Referer: http://play.yoitv.com` on HLS requests. Without it, you get HTTP 403.

2. **URL Encoding**: The `access_token` contains `+`, `/`, and `=` characters (base64). Must be properly URL-encoded when used as the `__cross_domain_user` parameter.

3. **Live vs VOD M3U8 extension**: Live streams use uppercase `.M3U8`, VOD uses lowercase `.m3u8`. This matters.

4. **No cookies needed**: Auth is entirely via query parameters (`__cross_domain_user`) and Bearer tokens (for user data APIs). No cookie management required.

5. **Single-play enforcement**: The server limits to one concurrent stream per account. The `single.sjs` endpoint should be polled when playing. Pass `ua=macos` or `ua=ios` etc.

6. **Segment duration**: 7-second MPEG-TS segments. Standard HLS, no fragmented MP4.

7. **Single bandwidth**: Currently only one variant at ~598 Kbps. No adaptive bitrate switching.

8. **EPG timestamps**: All in Unix seconds. Add `32400` (9 hours) to convert from Unix to JST display offset, or use proper timezone handling.

9. **product_config is double-encoded**: The login response contains `product_config` as a JSON string value. You must `JSON.parse()` / `JSONDecoder` it separately from the outer response.

10. **Edge server IPs may change**: The master playlist redirects to an IP-based edge URL. Don't hardcode `67.21.92.86` — always follow the master playlist.

---

## 11. Implementation Risks & Concerns

### Red Flags

1. **Single-play enforcement** — The server actively polls to ensure only one
   device streams at a time via `/single.sjs`. A native app must participate in
   this protocol or risk getting kicked mid-stream. This also means you cannot
   run the web app and native app simultaneously during development without one
   interrupting the other.

2. **Credentials in query strings** — Login sends the password as a GET
   parameter (not POST), and the access token is passed as a URL query param
   (`__cross_domain_user`) on every HLS request. This means tokens appear in
   server logs, browser history, and potentially proxy logs. The native app must
   match this scheme exactly. Avoid logging full URLs in debug output.

### Yellow Flags

3. **Referer header on HLS requests** — All stream requests require
   `Referer: http://play.yoitv.com` or the server returns 403. On Apple
   platforms, `AVURLAsset` supports custom headers via the
   `AVURLAssetHTTPHeaderFieldsKey` option, but this key is technically
   undocumented/private on some OS versions. Needs testing across macOS, iOS,
   and tvOS. If unreliable, a local HTTP reverse proxy that injects the header
   is the fallback.

4. **HTTP (not HTTPS) for all streams** — The VMS hosts
   (`live.yoitv.com:9083`, `vod.yoitv.com:9083`) and CDN edge server use plain
   HTTP. App Transport Security on iOS/macOS/tvOS blocks insecure HTTP by
   default. The app's `Info.plist` must include either `NSAllowsArbitraryLoads`
   or domain-specific `NSExceptionDomains` for these hosts and any CDN edge IPs.

5. **Token expiry is a Unix timestamp, not a duration** — The `expires_in`
   field is an absolute Unix timestamp (not seconds-from-now as OAuth2 normally
   defines). The refresh logic compares against `server_time` from the response.
   Device clock skew could cause premature or missed refreshes if not handled
   carefully — always compare against `server_time`, not local clock.

6. **Single bandwidth variant** — Streams are ~598 Kbps with one quality level.
   No adaptive bitrate. This is fine for reliability but picture quality will be
   limited on large displays (tvOS on a 4K TV).

7. **product_config could change** — All server hostnames come dynamically from
   the login response's `product_config` field. The native app must use these
   values at runtime rather than hardcoding any hosts, since they could change
   per-account or if the service migrates infrastructure.
