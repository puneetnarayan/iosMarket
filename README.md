# MarketWatch

A personal iOS watchlist app for Indian equities (NSE/BSE). Create any number of
named watchlists, add scrips to each by company name or symbol, and rename or
delete lists as needed.

## Features

- Multiple watchlists — create, rename, delete (swipe actions on the list screen)
- Add/remove scrips within a watchlist
- Search-to-add for NSE scrips (autocomplete against nseindia.com)
- Manual add for BSE scrips, or any NSE scrip search doesn't find
- Pull-to-refresh fetches live NSE prices for scrips in the open list

## Data source — read this before relying on it

NSE has no official public API for third-party apps. `NSEService.swift` calls
the same unofficial, undocumented JSON endpoints `nseindia.com` itself uses in
the browser (`/api/search/autocomplete`, `/api/quote-equity`). This is a
commonly used approach for personal projects, but:

- It can break at any time if NSE changes the endpoint shape or tightens
  bot-detection — there's no guarantee it keeps working.
- It's unofficial and may fall outside NSE's site terms for automated access;
  this is for personal, non-commercial use.
- There's no equivalent wired up for BSE — I don't have verified, current
  knowledge of a stable unofficial BSE JSON API, so BSE scrips (and any NSE
  scrip the search can't find) are added manually and won't get live price
  updates. If you find a working BSE endpoint, add a case for it in
  `NSEService.swift`.

If search or refresh stop working, open nseindia.com in a desktop browser,
open dev tools' Network tab, and see what the current request/response shapes
look like, then adjust the `AutocompleteResponse` / `QuoteResponse` structs in
`NSEService.swift` accordingly.

## Project structure

```
MarketWatch/
  project.yml              # XcodeGen spec — generates the .xcodeproj
  MarketWatch/
    MarketWatchApp.swift
    Models/
      WatchList.swift
      Scrip.swift
    Views/
      WatchListsView.swift       # list of watchlists: create/rename/delete
      WatchListDetailView.swift  # scrips in one list, refresh prices
      AddScripView.swift         # search NSE + manual add
    Services/
      NSEService.swift
```

Persistence is via SwiftData (`WatchList` <-> `Scrip`, one-to-many), stored
locally on device — nothing syncs off the device.

## Opening the project

This repo doesn't check in a generated `.xcodeproj` (Xcode project files are
better generated than hand-maintained). On a Mac with Xcode installed:

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you don't have
   it: `brew install xcodegen`
2. From the `MarketWatch/` directory, run:
   ```
   cd MarketWatch
   xcodegen generate
   ```
3. Open the generated `MarketWatch.xcodeproj` in Xcode, select a simulator or
   your device (target: iOS 17+), and run.

## Known limitations / things to verify

- **Not built or run in Xcode as part of producing this code** — this was
  written in a Linux environment without Xcode/a simulator available, so it
  has not been compiled or tested. Expect to fix small build errors on first
  open (Swift/SwiftData APIs move between Xcode versions).
- NSE session cookies are fetched by loading nseindia.com's homepage once per
  app launch before calling the JSON endpoints — a common workaround for their
  bot protection, not a documented contract. If requests start failing outright,
  this is the first thing to check.
- No app icon / launch screen asset catalog is included; Xcode will use
  defaults.
