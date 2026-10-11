# Mindrop

Save a value under a keyword. Search the keyword in Spotlight. See the value.

Spotlight is the product; the app is the place to create, edit and copy what Spotlight shows.

## Layout

```
Mindrop/
├── Mindrop.xcodeproj
├── MindropCore/                 Swift package shared by the app and the extension
│   └── Sources/MindropCore/
│       ├── Memory.swift              model, validation, normalisation
│       ├── MemoryRepository.swift    the single owner of memories
│       ├── MemoryStore.swift         JSON persistence in the App Group
│       ├── CoordinatedFile.swift     cross-process safe file access
│       ├── SpotlightAttributes.swift the indexing strategy, as plain data
│       ├── SpotlightIndexer.swift    Core Spotlight boundary
│       ├── SpotlightSynchronizer.swift  recoverable index synchronisation
│       ├── SpotlightSyncState.swift  what is known about the index between launches
│       ├── SpotlightRouter.swift     Spotlight result → memory id
│       └── SharedTextParser.swift    share sheet input → a value
├── Mindrop/                     app target (iOS 26+)
│   ├── App/                          MindropApp, RootView, session and routing
│   ├── Features/                     MemoryList, MemoryDetail, MemoryEditor
│   └── Resources/Assets.xcassets     app icon, accent colour
├── MindropShare/                share extension (text only)
├── Tools/RenderAppIcon.swift    renders the icon from the Lucide SVG
└── Design/                      lucide-brain.svg and its ISC licence
```

Shared code is a local Swift package rather than files in two targets: the app and the
extension cannot drift, and `swift test` runs the whole suite in under a second with no
simulator involved.

## Build and run

```bash
xcodebuild -project Mindrop/Mindrop.xcodeproj -scheme Mindrop -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

```bash
swift test --package-path Mindrop/MindropCore
```

App Group `group.mfsaglam.Mindrop`; bundle ids `mfsaglam.Mindrop` and `mfsaglam.Mindrop.Share`.
Regenerate the icon after changing the SVG:

```bash
swift Mindrop/Tools/RenderAppIcon.swift Mindrop/Design/lucide-brain.svg Mindrop/Mindrop/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

## Spotlight: what is indexed, and why

Per memory:

| Field | Value | Reason |
|---|---|---|
| `uniqueIdentifier` | the memory's UUID | how a tapped result routes back to the memory |
| `title` | the **value**, then the keyword | Spotlight renders the title as the result's prominent line, and it is the only field observed to match a query |
| `displayName` | same as the title | some surfaces prefer `displayName` over `title` |
| `contentDescription` | the keyword | shown as the smaller second line |
| `keywords` | the keyword, plus each of its words | `"office door"` should also be findable by typing `door` |
| `alternateNames` | the same words | matched but not displayed |
| `textContent` | keyword and value | full-text matching, not displayed |
| `domainIdentifier` | `memory` | lets one call clear everything Mindrop indexed |
| `expirationDate` | `.distantFuture` | **without this, indexed items expire about a month after indexing** |

The keyword sits in the title because **metadata-only keyword matching does not work on
device**. Measured on a physical iPhone: searching a memory's value finds it, searching its
keyword does not — with `keywords` and `contentDescription` both populated. So the matcher
is reading the title and ignoring the metadata fields, whatever the documentation implies.

The title is therefore `"SuperFast2026! — wifi"`: the value still leads the line and stays the
prominent text, and `wifi` now has something to match against. `alternateNames` and
`textContent` carry the keyword too, in case a future iOS consults them.

`SpotlightAttributesFactory.keywordInTitle = false` restores a value-only title if you want
to retest metadata-only matching on a later iOS. Changing the metadata shape means bumping
`SpotlightSynchronizer.currentIndexFormatVersion`, which triggers one full reindex on the
next launch.

### Index synchronisation

`SpotlightSynchronizer` records every mutation as pending *before* attempting it and clears
it only once Core Spotlight confirms. On launch:

- metadata format changed (`currentIndexFormatVersion`) → one full reindex, then never again;
- otherwise → retry only what was left pending; nothing else is touched.

A memory deleted before its indexing succeeded is removed from the index rather than
resurrected. A failed full reindex deliberately does not bump the version, so it runs again
next launch.

### What was verified, and what was not

Verified on the iPhone 18 Pro Max simulator (iOS 27.0): the app persists, lists, searches,
opens, copies, edits and deletes memories; deletions and edits reach storage; `UIPasteboard`
receives the complete value; indexing is attempted exactly once per change and not repeated
on later launches.

Verified on a physical iPhone (iOS 26): indexing works, and a memory is found by searching
its **value**. Searching its **keyword** returned nothing while the keyword lived only in
`keywords` and `contentDescription` — which is what moved the keyword into the title. Retest
after a reinstall: the first launch reindexes everything once, because the format version
changed.

On the **simulator** (iOS 27.0) nothing is searchable at all, for a different and system-side
reason. Core Spotlight accepts every donation and reports success, while `searchd` drops it:

```
Submitting donation: {CSInlineDonation[async]: "mfsaglam.Mindrop" add-update-items:6 ...}
  Set existence required and no set exists, skipping donation
Completed donation: ... result: success
```

This happens for a full reindex, for single additions, and for deletions, after a `simctl`
launch and after a real Home Screen launch. The same simulator surfaces Contacts and
Calendar results normally, so Spotlight itself works there; only third-party donations are
refused. Note the trap this creates: **the API reports success, so an app cannot detect that
its items were dropped** — the pending-retry machinery has nothing to retry.

There is no app-side fix for this; Spotlight work has to be checked on a physical iPhone.

### Device verification checklist

Run these on a real iPhone, which is the only authoritative environment:

1. Save `wifi` / `SuperFast2026!`, go Home, swipe down, type `wifi` → the value appears as the
   prominent line. (iOS 17+ often needs **more than three characters** before Core Spotlight
   matches appear, so test `wifi`, not `wif`.)
2. Type `door` for a memory saved as `office door` → still found, via the word tokens.
3. Tap the result → Mindrop opens the right memory's detail screen, with no flash of the list.
4. Save a long value (an IBAN, a recovery phrase) → note where Spotlight truncates the line.
   Truncation is Spotlight's, not ours; the full value is still copied in the app.
5. Edit the value, search again → the new value shows. Delete it, search again → gone.
6. Repeat in light and dark appearance.
7. Share text from Safari → Mindrop → save with a keyword → search it in Spotlight **without
   opening the app**.

Still open: whether the keyword previously failed because Spotlight never matched the
metadata, or because it matched and the result ranked below the system's own hits for a
common word like `wifi`. Searching an unusual keyword that has no system results would tell
them apart. Either way the title now carries the keyword, which addresses both. Do not expect
more than that: result ordering, fonts, truncation and layout belong to Spotlight.

### Limits Apple imposes

- Spotlight renders the row. No control over ordering, font, colour or truncation.
- Items become searchable only after the app has been launched at least once.
- Indexing is asynchronous; a new memory may take a few seconds to become findable.
- Matching usually needs more than three typed characters (iOS 17+).
- Indexed titles are visible to anyone who can unlock the phone, which is why the editor says so.

## Privacy

Values are treated as arbitrary text: no classification, no detection, no per-record
protection, nothing leaves the device. Storage lives in the App Group container with file
protection `completeUnlessOpen`. Nothing logs keywords or values — the Spotlight logger
records counts only. Both editors state plainly that saved values can appear in Spotlight,
where anyone using the iPhone may see them. Device lock is not a guarantee that Spotlight
metadata stays private.

## Tests

38 Swift Testing cases in `MindropCore/Tests`, covering creation, editing, deletion, keyword
and value validation, value preservation, file persistence across processes, Spotlight
metadata, index recovery after failures, routing by UUID, missing memories, and share
extension input. The repository exposes `indexingTask` so tests await indexing instead of
guessing at timing.

What the unit tests cannot cover, and what therefore needs the checklist above: whether iOS
actually shows the items.

## Icon

`Tools/RenderAppIcon.swift` parses `Design/lucide-brain.svg` and strokes the original path
data onto a 1024×1024 canvas — white on black, centred, about 46% of the canvas. The geometry
is Lucide's, unmodified. Lucide is ISC licensed; the notice is in `Design/LUCIDE-LICENSE.txt`.
