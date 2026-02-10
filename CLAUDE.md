# SugoiTV

A native multiplatform Apple app (iOS, macOS, tvOS) for streaming Japanese IPTV
via the YoiTV service. Built in cooperation with yoi.tv developers as an
alternative frontend to their web player at play.yoitv.com.

## Project Charter

Replace the Vue.js web interface with a native Swift/SwiftUI application that
provides channel browsing, live TV playback, catch-up/recorded program viewing,
and favorites management — using the same YoiTV backend APIs and streaming
infrastructure.

## Tech Stack

- **Language**: Swift 6 (strict concurrency)
- **UI**: SwiftUI with Liquid Glass design language
- **Minimum deployment**: iOS 26, macOS 26, tvOS 26
- **Video playback**: AVFoundation (AVPlayer + AVURLAsset)
- **Networking**: Foundation URLSession (no third-party HTTP libraries)
- **Data persistence**: SwiftData for local cache; Keychain for credentials
- **Architecture**: MVVM with Swift concurrency (async/await, actors)
- **Project structure**: Single Xcode project, multiplatform target(s)

## API Reference

All backend API details, authentication flows, data models, and streaming
mechanics are documented in [YOITV_API.md](./YOITV_API.md). That file is the
source of truth for how to interact with the YoiTV service.

## Key Design Decisions

### Authentication
- Device ID: generate a random 32-character hex string on first launch, persist
  in Keychain, reuse forever
- Store `access_token`, `refresh_token`, `cid`, and the parsed `product_config`
  in Keychain
- Refresh tokens on a 30-minute background timer; compare against `server_time`
  from the API (not local clock) to handle clock skew
- On refresh failure with `AUTH` code, clear session and present login

### Networking
- All server hostnames come from `product_config` in the login response. Never
  hardcode VMS hosts or CDN IPs — always resolve dynamically at runtime
- The `product_config` field is a JSON string inside the JSON login response
  (double-encoded). Decode it in a separate pass
- Stream requests require `Referer: http://play.yoitv.com` header. Set this via
  `AVURLAssetHTTPHeaderFieldsKey` on `AVURLAsset`. If this proves unreliable on
  any platform, implement a local HTTP proxy as fallback
- Credentials pass as GET query parameters (matching the existing web API
  contract). Do not log full URLs in debug builds

### App Transport Security
The VMS and CDN servers use plain HTTP. Configure `Info.plist` with exception
domains:
- `live.yoitv.com` (port 9083)
- `vod.yoitv.com` (port 9083)
- `NSAllowsArbitraryLoads` may be needed for CDN edge IPs that vary

### Video Playback
- Live streams: `{liveHost}{playpath}.M3U8?type=live&__cross_domain_user={token}` (uppercase .M3U8)
- VOD streams: `{recordHost}{path}.m3u8?type=vod&__cross_domain_user={token}` (lowercase .m3u8)
- Standard HLS, MPEG-TS segments, no DRM — AVPlayer handles natively
- Single bandwidth variant (~598 Kbps). No adaptive bitrate to manage
- Participate in single-play enforcement by polling `/single.sjs` during
  playback. Pass `ua=ios`, `ua=macos`, or `ua=tvos` as appropriate

### EPG (Electronic Program Guide)
- Timestamps are Unix seconds. Use `Date(timeIntervalSince1970:)` and format in
  Asia/Tokyo timezone for display
- Programs with a non-empty `path` field support catch-up VOD playback
- Programs with an empty `path` are live-only (no recording available)

## Application Structure

```
SugoiTV/
  App/
    SugoiTVApp.swift              # Entry point, scene setup
  Models/
    Channel.swift                 # Channel, Category
    EPGEntry.swift                # Program guide entries
    PlayRecord.swift              # Watch history / resume position
    License.swift                 # Auth tokens, product config
  Services/
    AuthService.swift             # Login, refresh, logout, device ID
    ChannelService.swift          # Channel list, EPG fetching
    FavoritesService.swift        # Cloud favorites sync
    StreamURLBuilder.swift        # HLS URL construction + referer
    SinglePlayService.swift       # Concurrent playback enforcement
  Views/
    LoginView.swift
    ChannelListView.swift         # Sidebar/grid of channels by category
    EPGView.swift                 # Program schedule for selected channel
    PlayerView.swift              # AVPlayer wrapper with transport controls
    FavoritesView.swift
    SettingsView.swift
  Platform/
    macOS/                        # macOS-specific adaptations
    tvOS/                         # tvOS focus-based navigation, top shelf
```

## Platform Considerations

### iOS
- Channel list as primary tab, player presents modally or inline
- Support Picture-in-Picture
- Background audio entitlement for audio-only listening

### macOS
- Sidebar navigation with channel categories
- Resizable window with inline player
- Menu bar integration for quick channel switching

### tvOS
- Focus-based navigation for channel grid and EPG
- Top Shelf extension showing currently-playing channels with thumbnails
- Full-screen player as primary experience
- Siri Remote swipe for channel surfing

## Credentials

Test credentials are in environment variables `YOITV_USER` and `YOITV_PASS`.
Never commit credentials to the repository. For development, use an
`.xcconfig` file excluded from git, or pass via Xcode scheme environment
variables.

## Development Notes

- Running this app will kick any concurrent session on play.yoitv.com (and vice
  versa) due to single-play enforcement. Close the web player before testing.
- Channel thumbnails are served from the VMS host and can be used for channel
  grid previews without any auth token.
- The EPG endpoint can return up to 30 days of listings. Consider lazy-loading
  EPG data per-channel on selection rather than bulk-fetching all 87 channels.
