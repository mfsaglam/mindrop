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
│       ├── MemoryRepository.swift    the single owner of memories
│       ├── MemoryStore.swift         JSON persistence in the App Group
│       ├── CoordinatedFile.swift     cross-process safe file access
│       ├── SpotlightAttributes.swift the indexing strategy, as plain data
│       ├── SpotlightIndexer.swift    Core Spotlight boundary
│       ├── SpotlightSynchronizer.swift  recoverable index synchronisation
│       ├── SpotlightSyncState.swift  what is known about the index between launches
│       ├── SpotlightRouter.swift     Spotlight result → memory id
│       └── SharedTextParser.swift    share sheet input → a value
│   └── Sources/MindropSaveUI/        the save form, shared by both extensions
│       ├── SaveToMindropView.swift
│       └── SaveToMindropViewController.swift
├── Mindrop/                     app target (iOS 26+)
│   ├── App/                          MindropApp, RootView, session and routing
│   ├── Features/                     MemoryList, MemoryDetail, MemoryEditor
│   └── Resources/Assets.xcassets     app icon, accent colour
├── MindropShare/                share extension — the share sheet's app row
├── MindropAction/               action extension — the share sheet's action row
├── Tools/RenderAppIcon.swift    renders the icon from the Lucide SVG
└── Design/                      lucide-brain.svg and its ISC licence
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
Regenerate the icon after changing the SVG:

```bash
swift Tools/RenderAppIcon.swift Design/lucide-brain.svg Mindrop/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
swift Tools/RenderAppIcon.swift Design/lucide-brain.svg MindropAction/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png --template
```

## Spotlight: what is indexed, and why

Per memory:

| Field | Value | Reason |
|---|---|---|
| `uniqueIdentifier` | the memory's UUID | how a tapped result routes back to the memory |
| `displayName` | the **value**, and the keyword when placement is `.displayedName` | what Spotlight draws, and matches against |
| `title` | the same string | fallback for surfaces that read the title |
| `textContent` | the keyword, when placement is `.bodyText` | drawn as a smaller second line |
| `keywords` | the keyword, plus each of its words | not displayed, and not matched on iOS 26 |
| `alternateNames` | the same words | not displayed |
| `domainIdentifier` | `memory` | lets one call clear everything Mindrop indexed |
| `expirationDate` | `.distantFuture` | **without this, indexed items expire about a month after indexing** |

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
ignored by the matcher, whatever the documentation implies.

The practical consequence is that *the keyword must be visible in the result row for keyword
search to work at all*. There is no configuration that both hides the keyword and finds it.
The brief's "the keyword does not need to appear in the result" is not achievable on this
iOS version alongside keyword search; the value still leads the line, so it remains the
prominent text.

`KeywordPlacement` is the single switch, and the cases are the trade:

- `.displayedName` → `"SuperFast2026! · wifi"` on one line. **Shipped**, and the only case in
  which keyword search works.
- `.bodyText` → big line `"SuperFast2026!"`, small `"wifi"` under it. Nicer, and the keyword
  cannot be found. Kept for retesting on a later iOS.
- `.hidden` → value only, no keyword search.

`keywords` and `alternateNames` stay populated in every case: no visual cost, and a later iOS
may consult them.

Changing any of this means bumping `SpotlightSynchronizer.currentIndexFormatVersion`, which
triggers one full reindex on the next launch.

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

Verified on a physical iPhone (iOS 26): indexing works, the value is found, and the keyword
is found as long as it is part of the drawn name — see the table above for the three rounds
that established this. Each reinstall reindexes once, because the format version changed.

Round 4 settled the last open question: `textContent` is not matched either, so the keyword
has to share the value's line. The one-line row is as clean as this gets on iOS 26.

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
   opening the app**. Then repeat from the action row, and once more by sharing a page so the
   link arrives as the value.

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
--template` renders the same Lucide brain on a transparent background instead.

## Localization

English plus 14 languages: Turkish, German, French, Spanish, Italian, Portuguese (Brazil),
Dutch, Russian, Arabic, Hindi, Japanese, Korean, Simplified and Traditional Chinese.

Two String Catalogs, because the extensions cannot reach the app's:

- `Mindrop/Resources/Localizable.xcstrings` — the app.
- `MindropCore/Sources/MindropSaveUI/Localizable.xcstrings` — the save form both
  extensions show. Strings in a package resolve against `Bundle.main`, which inside an
  extension is the extension's own bundle, so that view goes through a `localized(_:)`
  helper that names `Bundle.module`.

Two traps worth remembering:

- **`navigationTitle(someString)` does not localize.** Only literals become a
  `LocalizedStringKey`; a `String` variable ships the English through. The editor's title
  is typed as `LocalizedStringKey` for exactly this reason, and it was caught only by
  running the app in Arabic.
- A memory's keyword and value are user content and must never be looked up. They reach
  `Text` as `String` variables, which is the verbatim initializer, so they are safe.

"Memory" is rendered as *entry* or *record* in every language — the literal translation
means a recollection and reads wrong for a saved keyword/value pair.

Arabic flips the layout right to left; the native components handle it, and it was checked
on the simulator. Add a language by adding its code to each catalog and to `knownRegions`
in the project.

These translations have not been reviewed by native speakers. The strings are short and
conventional, but Arabic, Hindi and Korean deserve a pass before release.

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
