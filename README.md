# Mindrop

Save a value under a keyword. Search the keyword in Spotlight. See the value.

Spotlight is the product; the app is the place to create, edit and copy what Spotlight shows.

## Layout

```
Mindrop/
├── Mindrop.xcodeproj           project.xcproj — the JSON format, not project.pbxproj
├── MindropCore/                 Swift package shared by the app and the extension
│   └── Sources/MindropCore/
│       ├── Memory.swift              model, validation, normalisation
│       ├── MemoryCategory.swift      the fixed categories, and the categorizer protocol
│       ├── MemoryLifetime.swift      how long a temporary memory is kept
│       ├── ValueLayout.swift         card/IBAN groups, recovery phrases, Wi-Fi QR payloads
│       ├── MemoryRepository.swift    the single owner of memories
│       ├── MemoryStore.swift         JSON persistence in the App Group
│       ├── CoordinatedFile.swift     cross-process safe file access
│       ├── SpotlightAttributes.swift the indexing strategy, as plain data
│       ├── SpotlightOptions.swift    what ships, and the Debug experiments
│       ├── SpotlightIndexer.swift    Core Spotlight boundary, and reading the index back
│       ├── SpotlightSynchronizer.swift  recoverable index synchronisation, the launch check
│       ├── SpotlightSyncState.swift  what is known about the index between launches, usage
│       ├── SpotlightRouter.swift     Spotlight result or search → memory id, search text
│       ├── ValueDetector.swift       phone numbers and addresses for Spotlight's buttons
│       └── SharedTextParser.swift    share sheet input → a value
│   └── Sources/MindropIntents/       NewMemoryIntent, shared by the app and MindropControls
│   └── Sources/MindropSaveUI/        the save form, shared by both extensions
│       ├── MemoryLifetimeSection.swift  the Keep picker, also used by the app's editor
│       ├── SaveToMindropView.swift
│       └── SaveToMindropViewController.swift
├── Mindrop/                     app target (iOS 26+)
│   ├── App/                          MindropApp, RootView, session and routing
│   ├── Features/                     MemoryList, MemoryDetail, MemoryEditor, Categories, Settings,
│   │                                 Spotlight (icons, highlighting, experiments)
│   └── Resources/Assets.xcassets     app icon, accent colour
├── MindropShare/                share extension — the share sheet's app row
├── MindropAction/               action extension — the share sheet's action row
├── MindropControls/             widget extension — the New Memory control for Control Center
├── MindropWatch/                Apple Watch app (watchOS 9+), embedded in the iPhone app
├── Tools/                       RenderAppIcon.swift (the app icon), MakeIconsaxSymbols.py
└── Design/                      the earlier Lucide brain icon and its ISC licence
```

Shared code is a local Swift package rather than files in two targets: the app and the
extension cannot drift, and `swift test` runs the whole suite in under a second with no
simulator involved.

## The project file

`Mindrop.xcodeproj/project.xcproj` is Xcode 26's JSON project format, not the old
`project.pbxproj`. It is a fifth the size, readable, and diffs sensibly, which matters here
because the project is maintained by hand. Converted with:

```bash
xcodebuild -project Mindrop.xcodeproj -convert-project "Xcode Project"
```

The folders are synchronized (`"kind": "folder"`), so a new source file in `Mindrop/`,
`MindropShare/` or `MindropAction/` joins its target with no project edit at all.

One consequence to know about: the `xcodeproj` Ruby gem cannot parse this format, so
fastlane's `build_app` has to be pointed at `Mindrop.xcodeproj/project.xcworkspace` rather
than the project, or it fails while listing build configurations.

## Build and run

```bash
xcodebuild -project Mindrop/Mindrop.xcodeproj -scheme Mindrop -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

```bash
swift test --package-path Mindrop/MindropCore
```

App Group `group.mfsaglam.Mindrop`; bundle ids `mfsaglam.Mindrop` and `mfsaglam.Mindrop.Share`.
Regenerate the icons after changing the renderer (the symbol needs SwiftDraw):

```bash
swift Tools/RenderAppIcon.swift Mindrop/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
swift Tools/RenderAppIcon.swift MindropAction/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png --template
swift Tools/RenderAppIcon.swift MindropControls/Assets.xcassets/mindrop.mark.symbolset --symbol
```

## Spotlight: what is indexed, and why

Per memory:

| Field | Value | Reason |
|---|---|---|
| `uniqueIdentifier` | the memory's UUID | how a tapped result routes back to the memory |
| `displayName` | the **value**, and the keyword when placement is `.displayedName` | what Spotlight draws, and the only field it matches against |
| `title` | the same string | fallback for surfaces that read the title |
| `textContent` | the keyword, when placement is `.bodyText` | drawn as a smaller second line |
| `keywords` | the keyword, plus each of its words | not displayed, and not matched on iOS 26 or 27 |
| `thumbnailData` | the category's icon | drawn in place of Mindrop's icon, with Mindrop's as a badge |
| `phoneNumbers`, `supportsPhoneCall` | a phone number in a Contacts or Family & People memory | Spotlight's **Call** button |
| `userCreated`, `lastUsedDate`, `rankingHint` | always true; last opened; how much it is opened | ranking signals |
| `domainIdentifier` | `memory` | lets one call clear everything Mindrop indexed, and lets the launch check find it all |
| `expirationDate` | the memory's expiry, else `.distantFuture` | **without this, indexed items expire about a month after indexing**; a temporary memory leaves Spotlight at its expiry even if the app is never opened |

Not `alternateNames`: iOS 27 draws its first entry as a grey second line, which only repeated
the keyword. Without it, a long value wraps onto two lines and keeps the keyword in view.

### What the device actually does

Three rounds on a physical iPhone (iOS 26), each a reinstall and a reindex:

| Round | Where the keyword was | Keyword search |
|---|---|---|
| 1 | `keywords`, `alternateNames`, `contentDescription` | **fails** |
| 2 | …and `title`, `displayName`, `textContent` | works — but the row showed the keyword three times |
| 3 | …minus `contentDescription` and `textContent`, so `title` but not `displayName` | **fails** |
| 4 | `textContent` only, display name back to the value | **fails** |

That isolates it: **`displayName` is the only field a Spotlight query matches against.**
`keywords`, `alternateNames`, `contentDescription`, `textContent` and even `title` are all
ignored by the matcher, whatever the documentation implies. Retested on iOS 27, on the
simulator and on a physical iPhone, with `.bodyText`: a keyword found with `.displayedName`
is not found at all, and nothing from Mindrop appears. Still true, so the placement is fixed
in code (`SpotlightAttributesFactory.keywordPlacement`), not a Debug experiment.

The practical consequence is that *the keyword must be visible in the result row for keyword
search to work at all*. There is no configuration that both hides the keyword and finds it.
The value leads the line, so it remains the prominent text.

`KeywordPlacement` is the single switch, and the cases are the trade:

- `.displayedName` → `"SuperFast2026! · wifi"` on one line. **Shipped**, and the only case in
  which keyword search works.
- `.bodyText` → big line `"SuperFast2026!"`, small `"wifi"` under it. Nicer, and the keyword
  cannot be found.
- `.hidden` → value only, no keyword search.

Changing any of this means bumping `SpotlightSynchronizer.currentIndexFormatVersion`, which
triggers one full reindex on the next launch.

### What else Spotlight does with an item

Measured on the simulator (iOS 27), where third-party results now appear:

- **Category icons work.** Each result shows its category's icon (`SpotlightIcons`, the
  category's symbol in white on its colour), with Mindrop's icon as a small badge, and the
  long-press card shows it too. An uncategorised memory keeps Mindrop's icon. Changing a
  category reindexes the memory, since the icon is part of the item.
- **The Call button works**, on the right of the row, and in the Top Hit card. Only for a
  memory filed under Contacts or Family & People: the system's phone-number detector also
  reads a social security number such as `987-65-4321` as a phone number. Never for a
  sensitive memory.
- **The Directions button works too**, given coordinates. Finding them means sending the
  address to Apple Maps (`MKGeocodingRequest`), so it is a Debug experiment, not shipped.
- **iOS only drew the Call and Directions buttons, and the "Search in App" link, after the
  simulator was restarted** following the install. Category icons appeared straight away.
- Spotlight matches what was typed literally on some letters: `Kadikoy` does not find
  `Kadıköy` (ı and i are different letters), and the keyboard's curly apostrophe in `mom’s`
  does not find a keyword saved as `mom's`.

### Search in Mindrop, and highlighting what was searched

- **Tapping a result passes what was typed** (`CSSearchQueryString`, documented only for
  continued searches, but there for taps too on iOS 27). The detail screen marks it, in the
  keyword and in the value, the way Notes marks a search (`HighlightedText`).
- **"Search in App"** sits on the Mindrop section's header in Spotlight, because Info.plist sets
  `CoreSpotlightContinuation`. It opens the list with the same search, matches marked.
- In-app search matches **every word, in any order**, against the keyword and the value, so a
  search carried on from Spotlight finds what Spotlight found. A sensitive memory still
  matches on its keyword only.

### Index synchronisation

`SpotlightSynchronizer` records every mutation as pending *before* attempting it and clears
it only once Core Spotlight confirms. On launch:

- metadata format (`currentIndexFormatVersion`) or options changed → one full reindex;
- otherwise → retry what was left pending, then **check the index** (`verify`).

**The launch check** asks Spotlight what it holds for Mindrop (`CSSearchQuery` on the domain,
fetching each item's drawn line) and puts right the difference: a memory missing or out of
date there is indexed again, an item with no memory behind it is removed. This matters
because Spotlight's index is not in a backup but Mindrop's record that everything was indexed
is: after restoring an iPhone, or moving to a new one, that record says all is well over an
empty index. Verified on the simulator by emptying the index (0 of 19 there, 19 put back), by
adding a memory to the file behind the app's back (1 put back), and by removing one (1
removed). If Spotlight cannot be asked, nothing is touched.

**Usage** (`SpotlightUsage`, in the Spotlight state file, per device, not synced): opening a
memory records when and how often, and reindexes it with `lastUsedDate` and a `rankingHint`
(1 use is 20, 3 are 40, 7 are 60, 31 or more are 100). Spotlight documents both as ranking
inputs; how much they move a result is Spotlight's business.

A memory deleted before its indexing succeeded is removed from the index rather than
resurrected. A failed full reindex deliberately does not bump the version, so it runs again
next launch.

### Spotlight Experiments (Debug builds)

Settings → Debug → **Spotlight Experiments**: how many memories Spotlight holds, Check Now,
Reindex Everything, and *Empty Spotlight, as After a Restore* to watch the check put it back;
category icons, Call and Directions; and the keys of the last activity
Spotlight handed the app. Each change reindexes everything. The choices live in the App
Group, so the share extension indexes the same way. Release builds always use
`SpotlightOptions.shipping`.

### What was verified, and what was not

Verified on the iPhone 18 Pro Max simulator (iOS 27.0): everything in the app, and since
this round Spotlight too: results, category icons, Call, Directions, the long-press card,
opening a result with what was typed marked, Search in App, and the launch check.

Verified on a physical iPhone (iOS 26): indexing works, the value is found, and the keyword
is found as long as it is part of the drawn name — see the table above.

The simulator used to drop every third-party item (`searchd` logged "Set existence required
and no set exists, skipping donation" while the API reported success). On iOS 27.0 it no
longer does. If it comes back, restart the simulator.

### Device verification checklist

Run these on a real iPhone, which is the authoritative environment:

1. Save `wifi` / `SuperFast2026!`, go Home, swipe down, type `wifi` → the value appears as the
   prominent line. (iOS 17+ often needs **more than three characters** before Core Spotlight
   matches appear, so test `wifi`, not `wif`.)
2. Type `door` for a memory saved as `office door` → still found, via the word tokens.
3. Tap the result → Mindrop opens the right memory's detail screen, with no flash of the list,
   and the typed word marked.
4. Save a long value (an IBAN, a recovery phrase) → it wraps, and the keyword stays in view.
5. Edit the value, search again → the new value shows. Delete it, search again → gone.
6. Repeat in light and dark appearance; the category icons should read in both.
7. Share text from Safari → Mindrop → save with a keyword → search it in Spotlight **without
   opening the app**. Then repeat from the action row, and once more by sharing a page so the
   link arrives as the value.
8. Turn on Sensitive for a memory, search its keyword → the result reads `keyword · 🔒`, with
   no value and no Call button. Tap it → Mindrop opens it and asks for Face ID.
9. With iCloud Sync on and both iPhones signed in to the same account: add a memory on one,
   bring the other to the foreground → it appears there, and in that iPhone's Spotlight. Edit
   it on the second, delete it on the first → Recently Deleted on both.
10. A phone number under Contacts → a Call button on the result (restart the iPhone once if it
    does not appear). Tap **Search in App** on the Mindrop section → the list, searching.
11. Spotlight Experiments → Empty Spotlight → search: nothing. Relaunch Mindrop → found again.

### Limits Apple imposes

- Spotlight renders the row. No control over ordering, font, colour or truncation, and no
  way to highlight text inside it: Core Spotlight takes plain strings only.
- Items become searchable only after the app has been launched at least once.
- Indexing is asynchronous; a new memory may take a few seconds to become findable.
- Matching usually needs more than three typed characters (iOS 17+).
- Indexed titles are visible to anyone who can unlock the phone, which is why the editor says so.

## The share sheet

Two extensions, because iOS splits the share sheet into two rows that are populated
by two different extension points:

| Row | Extension point | Target |
|---|---|---|
| Apps (AirDrop, Messages, Mail, …) | `com.apple.share-services` | `MindropShare` |
| Actions (Copy, Add to Amazon, Ask ChatGPT, …) | `com.apple.ui-services` | `MindropAction` |

They do the same thing and share all their code: `SaveToMindropViewController` and
`SaveToMindropView` live in `MindropSaveUI`, and each target is a one-line subclass.

**Placement is not ours to control.** The app row is Favorites, which the user sets and
orders, followed by Suggestions, which iOS orders by its own relevance model. A freshly
installed extension lands at the end of Suggestions, behind the *More* button, and no API
promotes it. Users pin it through More → Edit → (+). The action row works the same way via
*Edit Actions…*; it is simply shorter in practice, so Mindrop is easier to spot there.

Both extensions accept **text and web URLs**. For a page share the value is the link; for a
text selection it is the text. When a host offers both, selected text wins, then the link,
and the host's own description last — for a page share that description is the page title,
which is rarely what someone wants stored.

The action extension ships its own icon: iOS draws action icons as a mask of the alpha
channel, so the opaque app icon would come out as a filled square. `RenderAppIcon.swift
--template` renders the icon's search glyph and cursor, drawn heavier, on a transparent
background instead.

## The detail screen's value

Tapping a Spotlight result opens the memory's detail screen, so that is where a value is
laid out to be read (`MemoryValueView`, using `ValueLayout`):

- **Card numbers and IBANs in blocks of four**, when the whole value is one and passes its
  check (Luhn, mod 97). A value with more after the number is shown as typed.
- **Recovery phrases as numbered words**: 12 to 24 lowercase words.
- **A QR code under a Wi-Fi memory**, for showing a guest the screen, made on the device by
  Core Image. If the value names the network ("Network: Home / Password: …", also in
  Turkish), the code joins it; otherwise it carries just the password, which a camera
  offers to copy.

Display only: tapping the value still copies it **exactly as saved**, never the grouped
form. The category chip, the expiry chip and Edit work as before.

## The look: glass cards

The list and the detail screen are built from native components and Liquid Glass, on the
plain system background.

- **The list is a grid of glass cards**, two columns: the keyword small at the top, the
  value as the card's headline. Each card's glass has a touch (8%) of its category's colour
  (`Glass.category`). Grouped by category, the section heading carries the category's
  symbol and the cards leave it out; as one list, each card shows its own symbol. A long
  press offers Copy and Delete (Recover and Delete for an expired one): a grid has no swipe
  actions. Recently Deleted is a glass row under the cards.
- **Search sits at the bottom right**, a toolbar item after a flexible spacer, not centred.
- **With nothing saved, the list is the onboarding** (`SpotlightGuide`): sample Spotlight
  searches typed out in glass, each showing its result the way Spotlight draws a memory,
  then three steps (save under a keyword, swipe down on the Home Screen, type the keyword)
  and Save Your First Memory. There is no separate onboarding screen. It also shows when
  every memory was deleted, above the Recently Deleted row. A search or a filter that finds
  nothing still gets the system's empty view.
- **Settings → How Mindrop Works shows the guide again** (`HowMindropWorksView`), for anyone
  who has saved since or never saw it (a first memory from the share sheet, Siri or the
  watch means the list was never empty). No button, and the preview types the user's own
  keywords: up to five memories that Spotlight shows in full (not sensitive, short enough
  for a card), the samples if none qualifies. They are taken once when the page opens, so a
  memory arriving by sync can't change the list under the animation. Below the guide,
  More Ways to Save: the share sheet, Control Center, the Action button, Siri (the quoted
  phrase must match the first one in `AppShortcuts.xcstrings`) and, only with a paired
  watch, Apple Watch. Nothing in the app leads to these otherwise. It never opens by itself.
- **Recently Deleted is the same grid in clear glass**: no category tint, so deleted
  memories read as set aside, with the category's icon still coloured. Each card counts
  down to its deletion for good ("in 29 days"), red in the last three days. Tapping a card
  offers Recover and Delete Now; Delete Now still asks first. **Delete All** (top right,
  only while something is there) deletes every one for good, after one alert. Empty (when its last memory
  is recovered or deleted for good), it shows a deleted memory's three stages: Deleted, 30
  days to recover, gone for good.
- **The detail screen is the value on one glass card**, tinted the same way, under the
  category's tile (the same icon as in Spotlight) and the keyword. Below it: Copy in the
  category's colour, which reads "Copied" for a moment; Share; and the value's own action
  when it has one (`MemoryAction`): Open for a web address, Directions to an address in
  Apple Maps, or Call for a number in Contacts, Family & People or Health. Then the line
  the memory shows in Spotlight.
- **The value's typeface follows its category** (`ValueStyle`). Monospaced, which tells 0
  from O and l from 1, for Codes & PINs, Banking, Accounts, Wi-Fi, IDs & Documents and
  Vehicles, and always for card numbers and IBANs; the system font for people and places;
  even-width digits for contacts; smaller for links. Health, Home & Devices, Other and
  uncategorised memories decide by the value: one word with a digit in it is a code. Long
  values step down in size.

Tried first, and dropped: the same view as Spotlight's long-press preview, through a Quick
Look preview extension with `QLSupportsSearchableItems`. On a device (iOS 27) Spotlight never
started the extension — not with the default content type, nor with an app-declared one
listed in `QLSupportedContentTypes` — and showed its own card, the row's text with "0 KB".
The extension was registered and its method reachable, so this looks reserved for Apple's
apps (News and Wallet ship such extensions).

## Icons: Iconsax

The app's own icons are from the free Iconsax set (iconsax.io), not SF Symbols, so Mindrop
does not look like a stock iOS app. Two styles:

- **Bulk for categories**, in section headers, on cards, the detail screen's tile and the
  Spotlight icons: a soft 40% shape under solid detail. The soft parts are the symbol's
  secondary layer, so `.symbolRenderingMode(.hierarchical)` draws them in a lighter shade of
  the category's colour, the same touch of colour as the cards' glass.
- **Linear for everything tapped**: the toolbar, Copy, Share, the value's action, menus,
  swipe and long-press actions, empty states. Filter turns Bold while a category is
  chosen, and the sensitive lock is Bold.
- **Menus use the Linear category icons** (`MemoryCategory.menuSymbolName`). iOS draws menus
  in one colour, where Bulk's soft layer would cover its detail.

They are custom symbols in `Assets.xcassets/Iconsax` (`ix.<name>.<style>`), so they size
with the text and work in toolbars and menus like SF Symbols. `Tools/MakeIconsaxSymbols.py`
makes them from the official `iconsax` npm package with SwiftDraw (`brew install
swiftdraw`); the list of icons is at its top. Two things it takes care of:

- **One fixed margin** around Iconsax's 24-point grid for every icon. SwiftDraw's automatic
  fitting drew them at about half the size of SF Symbols, each to its own outline.
- **Weights must interpolate.** Linear icons get a thinner and a heavier outline, so they
  follow bold text. When thickening a stroke changes its points, Xcode silently leaves the
  symbol out ("No image named …"); those icons keep one weight.

Still SF Symbols: what the system draws (back button, the search button and field, the share
sheet), the Siri/Shortcuts tile (`systemImageName` only), the share extension for now, the
ways to save on How Mindrop Works (they point at Apple's own features, so they carry Apple's
glyphs: share, Control Center, the Action button, Siri, Apple Watch), and the Debug screens. Iconsax has no infinity, so Keep Forever is
a paused timer.

Licence: free for apps, commercial ones included, without attribution; loose icon files may
not be redistributed, so the icons live only in the asset catalog. Changing them reindexes
Spotlight (index format 12), since its category icons are drawn from the same symbols.

## Temporary memories

A hotel room, a parking spot, a guest Wi-Fi password: things worth keeping for a while,
not forever. The editor and the share sheet's save form both have a **Keep** row —
Forever (the default), 1 Day, 1 Week, 1 Month, or Until a Date — shared as
`MemoryLifetimeSection` in `MindropSaveUI`.

- **At expiry it leaves Spotlight by itself.** The memory's expiry is the indexed item's
  `expirationDate`, so Spotlight drops it on time even if Mindrop is not opened.
- **In the app it is not deleted straight away.** It moves to an *Expired* section at the
  bottom of the list, saying when it will be deleted for good, and stays there for 7 days
  (`MemoryLifetime.expiredRetention`). Deletion for good happens at launch and on returning
  to the foreground (`MemoryRepository.deleteExpired`).
- **Recover** (a long press in the list, or a button on the detail screen) brings an expired
  memory back for good, not on a new timer, and reindexes it.
- **Before it expires** the row says "Expires tomorrow", and the detail screen's expiry
  chip offers 1 More Day, 1 More Week or Keep Forever.
- **Not a category.** How long something is kept says nothing about what it is: a hotel
  room code is still a code. Changing only the expiry does not move a memory up the list.
- Older files decode as kept forever: `expiresAt` is optional.

Verified on the simulator: the Keep picker, saving with 1 Week (stored expiry exactly a
week later), the timer on rows, the Expired section, and Recover. Spotlight dropping the
item at expiry needs a device, since the simulator's Spotlight drops all third-party items.

## Sensitive memories

Some values should not be readable by whoever picks up an unlocked iPhone and types a word
into Spotlight: an ID number, a card, a PIN. The editor and the share sheet's save form both
have a **Sensitive** switch (`SensitiveSection` in `MindropSaveUI`). It is off by default and
only the user turns it on or off; nothing turns it on by itself, whatever the category.

- **Spotlight never receives the value.** A sensitive memory is indexed as
  `"atlas ssn · 🔒"`: the keyword stays in `displayName`, the only field Spotlight matches, so
  it is still found, and tapping the result opens Mindrop. Spotlight itself cannot ask for
  Face ID, so leaving the value out is the only way to hide it there.
- **In the app the value is dots until unlocked**, in the list and on the detail screen.
  Opening a sensitive memory asks for Face ID (or Touch ID, or the passcode) straight away;
  cancelling leaves a **Show Value** button. Copying is a second tap after unlocking, and the
  Wi-Fi QR code is hidden too. Edit asks first, because the editor shows the value.
- **One unlock covers every sensitive memory until Mindrop goes to the background**
  (`SensitiveAccess`), the way locked notes stay open while you work with them. Not on
  merely becoming inactive: the Face ID prompt itself does that.
- **In-app search matches a sensitive memory's keyword only**, so typing part of a hidden
  value does not reveal which memory holds it.
- **An iPhone without a passcode shows the value**: there is nothing for iOS to ask for, and
  the phone is open to anyone anyway.
- Changing only the switch is not an edit: the memory keeps its place and its category, and
  is reindexed. Older files decode as not sensitive. Index format version 9 reindexes
  everything once, so existing items pick up the new format.

Verified on the simulator: the switch and its footer, saving, dots and the lock in the list,
the Face ID prompt on opening (with simulated enrolment and a matching face), the value after
unlocking, and dots again after going Home and coming back. The Spotlight line itself needs a
device, since the simulator's Spotlight drops all third-party items.

## iCloud sync and Recently Deleted

Memories stay the same on every device signed in to the same iCloud account. Sync is on by
default and can be turned off in Settings (**iCloud Sync**); turning it off deletes nothing,
here or in iCloud, and turning it back on sends whatever changed in the meantime.

- **CloudKit's private database, through `CKSyncEngine`** (`CloudSync` in `MindropCore`).
  One record per memory, named by its UUID, in a zone called `Memories`, container
  `iCloud.mfsaglam.Mindrop`. The engine does the batching, retries and push subscriptions;
  Mindrop decides what changed and how two versions become one.
- **The local file stays the source of truth.** The app works the same offline. Changes are
  found by comparison, not recorded as they happen: a memory whose `modifiedAt` differs from
  what iCloud last agreed to (`CloudSyncState.known`) is sent. So a memory saved by the share
  extension, which does not sync itself, is sent the next time the app runs.
- **End-to-end encrypted.** Keyword, value and category are CloudKit encrypted fields, with
  keys in the user's iCloud Keychain: Apple cannot read them, whether or not Advanced Data
  Protection is on. Dates and flags are plain. Sensitive memories sync like any other; on
  every device Spotlight shows them only as `keyword · 🔒`. If the iCloud Keychain is reset,
  the zone's data is lost to iCloud and the devices send their memories again.
- **Two versions become one** (`Memory.merged`): the later change wins as a whole, except that
  newer text is never lost to a later change of something else. If one iPhone files a memory
  under a category while another edits its text, the edit is kept, with its own category
  unless the user picked one. `modifiedAt` records any change; `updatedAt`, as before, only
  text edits, and still orders the list.
- **Each device keeps its own Spotlight index.** Changes from iCloud go through the same
  Spotlight synchronisation as local edits (`MemoryRepository.applyRemote`).
- **Pushes.** The remote-notification background mode lets iCloud wake Mindrop when another
  device changes something, so its Spotlight catches up without the app being opened. iOS
  decides when; on returning to the foreground the app also asks for changes.
- **Accounts.** Signing out of iCloud keeps the memories on the device. Signing in, or
  switching accounts, sends them all to the new account. Two iPhones that each had memories
  before syncing keep both sets: nothing is matched by keyword.

**Recently Deleted.** Because a delete now reaches every device, deleting no longer deletes:
it moves the memory to Recently Deleted (`deletedAt`), out of the list and Spotlight, for 30
days. The delete alert still asks first. Recently Deleted is a row at the bottom of the list,
shown only when something is in it; there a memory can be recovered or deleted for good
(**Delete Now**, which asks again). After 30 days it is deleted for good, on every device
(`MemoryRepository.purge`, which also ends expired memories after their 7 days). A memory
deleted for good is a deleted CloudKit record; Recently Deleted itself syncs as a field.

Verified on the simulator: deleting, the Recently Deleted row and screen, Recover, and the
sync engine starting and waiting for an account (the simulator was not signed in to iCloud).
The device build is signed with the iCloud container and push entitlements. Not yet verified:
sync between two real devices. Before an App Store release, the CloudKit schema has to be
deployed from the development environment to production in the CloudKit Console.

## Apple Watch

The watch app saves memories without reaching for the iPhone: Keyword, Details, Sensitive,
Save. It only adds. It keeps no library, so nothing sensitive lives on the wrist, and there
is no Spotlight on watchOS to search in. The iPhone does the rest: files the memory, adds it
to Spotlight, gets its category from Apple Intelligence, and sends it to iCloud.

Each memory leaves the watch two ways, and arriving twice is harmless (one identifier):

- **To the iPhone through WatchConnectivity**, always: a user-info transfer, which the
  system queues and delivers whenever the iPhone is reachable, even with either app
  closed. The iPhone's `WatchLink` takes it in with `applyRemote`, as if it had been synced
  from another device, then asks iCloud sync to send it on.
- **Straight to iCloud**, only while the iPhone says iCloud Sync is on (`WatchLink` keeps
  the watch told, through the application context; until it hears, the watch assumes off).
  `CloudRecordUpload` saves the same encrypted record the iPhone's sync engine writes, so it
  reaches the iPhone even when the iPhone is far away. No account, or an iPhone that has
  never synced, means WatchConnectivity alone.

**watchOS 9 and later**, the oldest Xcode 27 builds for: Series 4 and later, the first SE,
every Ultra. A Series 3 stops at watchOS 8 and cannot run it. Liquid Glass (the Save button)
from watchOS 26, the standard filled button before; `ObservableObject` rather than
`@Observable` (watchOS 10). The iPhone-only parts of `MindropCore` (`MemoryRepository`,
`CloudSync`) are marked watchOS 10, since the watch uses neither.

Until one of them has it, a memory waits on the watch in a small outbox file
(`WatchSender`), and the screen says how many are waiting. The wire format both sides share
is `WatchHandoff`. watchOS has no Core Spotlight, so `MindropCore` builds for watchOS with
the Spotlight indexer and router left out.

Testing: the Mindrop scheme embeds the watch app; the MindropWatch scheme runs it on a
watch simulator paired with the iPhone simulator (`xcrun simctl pair`). In Debug builds,
`-debugSave "keyword=value"` on the watch saves a memory at launch, and
`-debugWatchArrival "keyword=value"` on the iPhone feeds one in as if it had come from the
watch. Verified on the simulators: the watch app runs; the iPhone's iCloud setting reaches
the watch; a memory "from the watch" arriving while the app starts is filed and categorised.
Not verifiable there: on the watchOS 27.2 / iOS 27.2 simulators the transfer left the watch
but the iPhone's WatchConnectivity daemon failed internally and never handed it to the app,
and simulators have no iCloud account. Both need a real iPhone and Apple Watch.

## New Memory from anywhere

One intent, `NewMemoryIntent`, opens Mindrop on a blank editor with the keyboard up. It is
offered in three places:

- **Control Center and the Lock Screen**: the *New Memory* control, from the
  `MindropControls` widget extension. Added through Control Center → + → Add a Control →
  Mindrop. Its icon is the app icon's mark, the search icon and cursor, as the custom
  symbol `mindrop.mark`: controls draw only symbols. Control Center caches a control's
  look, so after changing the symbol it shows the old one until Control Center is edited.
- **The Action button**: an App Shortcut, so Settings → Action Button → Shortcut lists
  Mindrop → New Memory with nothing to build in the Shortcuts app.
- **Siri**: "New memory in Mindrop", "Add a memory to Mindrop", translated in
  `AppShortcuts.xcstrings`.

The intent lives in its own package target, `MindropIntents`, because a control's intent
must be compiled into both the app and the widget extension, and the share extensions,
which link `MindropCore`, must not offer it. It sets `openAppWhenRun`, so it always runs in
the app. All it does is raise `NewMemoryRequest.shared.isPending`; the list watches that
flag and presents the editor. A flag rather than a call, because the intent can run before
the list is on screen on a cold launch.

Verified on the iPhone 18 Pro Max simulator (iOS 27): the control appears in the gallery
under Mindrop, and tapping it opens the editor both from a cold launch and with the app
in the background. The simulator's control gallery only picked the control up after the
simulator was restarted. The Action button needs a device.

## Localization

English plus 14 languages: Turkish, German, French, Spanish, Italian, Portuguese (Brazil),
Dutch, Russian, Arabic, Hindi, Japanese, Korean, Simplified and Traditional Chinese.

Three UI String Catalogs, because the extensions cannot reach the app's (plus
`Mindrop/Resources/AppShortcuts.xcstrings` for Siri's phrases and
`Mindrop/Resources/InfoPlist.xcstrings` for the Face ID explanation):

- `Mindrop/Resources/Localizable.xcstrings` — the app.
- `MindropCore/Sources/MindropSaveUI/Localizable.xcstrings` — the save form both
  extensions show. Strings in a package resolve against `Bundle.main`, which inside an
  extension is the extension's own bundle, so that view goes through a `localized(_:)`
  helper that names `Bundle.module`.
- `MindropControls/Localizable.xcstrings` — the control's name and description.

Two traps worth remembering:

- **`navigationTitle(someString)` does not localize.** Only literals become a
  `LocalizedStringKey`; a `String` variable ships the English through. The editor's title
  is typed as `LocalizedStringKey` for exactly this reason, and it was caught only by
  running the app in Arabic.
- A memory's keyword and value are user content and must never be looked up. They reach
  `Text` as `String` variables, which is the verbatim initializer, so they are safe.

"Memory" is rendered as *entry*, *item* or *record* in the translations — the literal translation
means a recollection and reads wrong for a saved keyword/value pair.

The copy uses short, direct sentences and a consistent form of address in each language.
Describe what the user saves as *details* or *content*, rather than a mathematical
*value*. Keep standard platform actions familiar. Explain recovery periods explicitly
(30 days after deletion, 7 days after expiry), and label permanent deletion clearly.
Privacy copy must say what is visible in Spotlight and what stays hidden until unlock.

English has explicit catalog values too. The lookup keys stay stable even when the
visible wording changes; edit the `en` localization instead of renaming keys in Swift.
Keep shared wording identical across the app, save form and Control Center catalogs.
Siri's two alternative phrases belong in a `stringSet` for each language, with
`${applicationName}` preserved in every phrase.

Failure screens use localized recovery guidance instead of raw Swift error descriptions.
The original errors remain in view/session state for debugging.

Arabic flips the layout right to left; the native components handle it, and it was checked
on the simulator. Add a language by adding its code to each catalog and to `knownRegions`
in the project.

The editorial pass covers English and all 14 translations. Native-speaker review is
still separate from this copy and terminology review.

## Categories

Each memory is filed under one of a fixed set of categories (`MemoryCategory`) by the
on-device Apple Intelligence model, through the Foundation Models framework. The list is in
sections by category (uncategorised last), or, with *Group by Category* off in Settings, one
list newest first with each category's symbol. A filter menu narrows either. The detail
screen shows the category and lets the user pick another, or hand it back with *Automatic*.
Until anything is categorised the list stays flat, so without Apple Intelligence it looks as
it always did.

- **A colour per category**, from the thirteen system colours (Wi-Fi blue, Banking green,
  Health red, …), on section headers, the cards' glass and the detail screen's tile. The
  names stay in the text colour, so they read well whatever the tint.
- **Fixed, not free-form.** A model naming categories freely produces "Wi-Fi", "WiFi
  Password" and "Network" for the same thing, which defeats a filter and cannot be
  translated. The reply is checked against the raw values.
- **Built from real misses.** Version 1 filed a child's social security number under
  *vehicles* (the child is called Atlas), another under *codes*, blood types and birthdays
  under *other*, a credit card under *codes*, and a coffee machine's descale button pattern
  under *codes*. Version 2 adds *Family & People* and *Home & Devices*, and the prompt says
  outright that a leading name is whose note it is, never what it is, and that being made of
  digits does not make something a code. On a 33-entry set built from those misses: 21/33
  for version 1, 33/33 for version 2. That set shaped the prompt, so expect less on real data.
- **Permissive guardrails.** The default guardrails refuse card numbers, passports,
  allergies and birthdays as "may contain sensitive content" — the very things people keep
  here. `.permissiveContentTransformations` lets them through, but allows only a plain text
  reply, not guided generation, so the model answers with one word and
  `AppleIntelligenceCategorizer.parse` maps it back: a category name, or failing that the
  category whose description the reply quotes (it often says "access" for a door code).
- **Rules before the model.** A bare `http(s)` value is a link and a Luhn-valid card number
  is banking (`MemoryCategory.evident(fromValue:)`); the model is not asked.
- **The general model, not the `.contentTagging` adapter**, which filed lockers, bike locks
  and links under *other*. Asking the model to describe the value before choosing ("think
  first") scored no better, so it was dropped.
- **Versioned.** `AppleIntelligenceCategorizer.version` is stored with each automatic
  category; bumping it redoes every automatic category on the next launch. Manual ones stay.
- **Automatic vs manual.** An automatic category is dropped when the keyword or value is
  edited, and the memory is categorised again. A category the user picked is never
  overwritten. Changing a category does not move the memory up the list; it does reindex
  the memory, since Spotlight shows the category's icon.
- **The app does it, not the extensions.** The share and action extensions are torn down
  too quickly to wait for the model; the app categorises whatever they saved the next time
  it comes to the foreground.
- **Without Apple Intelligence** — an older iPhone, the feature turned off, the model still
  downloading — memories stay uncategorised and the filter menu does not appear, so the app
  looks as it did. Categories can still be set by hand.
- **Speed.** About 16 seconds per memory on the simulator, one at a time in the
  background. Not yet measured on a device.
- **Debug log.** Debug builds add *Apple Intelligence Log* to Settings: every request this launch,
  grouped by memory with a request count, each with its prompt, raw reply, outcome and
  duration, plus *Recategorise All* for trying a prompt change. It lives in memory only and
  is compiled out of Release builds, since it holds keywords and values.

## Privacy

Values are treated as arbitrary text. With iCloud Sync on (the default), memories go to the
user's private iCloud database, keyword, value and category end-to-end encrypted (see *iCloud
sync and Recently Deleted*); nothing else leaves the device. A memory the user marks
as sensitive is kept out of Spotlight and hidden in the app until Face ID or the passcode
(see *Sensitive memories*); its value is stored like any other. Categorisation sends the keyword and the first 200 characters of the value to
the on-device model only; Apple Intelligence's on-device model does not use the network. Storage lives in the App Group container with file
protection `completeUnlessOpen`. Nothing logs keywords or values — the Spotlight logger
records counts only. Both editors state plainly that saved values can appear in Spotlight,
where anyone using the iPhone may see them, under the switch that prevents it. Device lock is not a guarantee that Spotlight
metadata stays private.

## Tests

119 Swift Testing cases in `MindropCore/Tests`, covering creation, editing, deletion, keyword
and value validation, value preservation, file persistence across processes, Spotlight
metadata, index recovery after failures, routing by UUID, missing memories, and share
extension input, categorisation (automatic and manual, stale results, edits), and temporary
memories (lifetimes, expiry, recovery, deletion after 7 days), sensitive memories (what
Spotlight receives, search, the switch, older files), Recently Deleted (deleting, recovering,
30 days, change times), iCloud sync (merging two versions, the CloudKit record, what is
pending, the state file), how a value is laid out
(card numbers, IBANs, recovery phrases, Wi-Fi labels), and Spotlight's extras (the launch
check, usage and ranking, category icons, the Call rule, search words and highlights, a
continued search). The repository exposes `indexingTask` so tests await indexing instead of
guessing at timing.

What the unit tests cannot cover, and what therefore needs the checklist above: whether iOS
actually shows the items.

## Icon

The icon is the search field from the empty list's Spotlight guide, cut into a square: a
white glass field about two thirds of the icon's height, its rounded left end inside the
icon and the rest running off the right edge, on the guide's light grey panel. In the field,
the app's own search icon (Iconsax "search-normal", Linear) and a black text cursor waiting
for a keyword. It says what Mindrop is for, finding a saved value by searching, and stays
readable as Spotlight's small badge on each result.

`Tools/RenderAppIcon.swift` draws it with Core Graphics onto a 1024×1024 canvas, from the
Iconsax path data written into the file, and writes it with no alpha channel, which App
Store validation requires. Iconsax's free licence allows its icons in an app icon, but not
a stock icon as a registered trademark: redraw the magnifier before registering the icon.
The same goes for the Control Center symbol, which `--symbol` makes from the same paths.

Before it, the icon was Lucide's brain, white on black (`Design/lucide-brain.svg`, ISC
licensed, notice in `Design/LUCIDE-LICENSE.txt`).
