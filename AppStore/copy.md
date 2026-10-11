# App Store copy

Paste-ready text for App Store Connect, plus the captions that go on the screenshots.
Character limits are Apple's; the counts in brackets are what the text below actually uses.

Listing locales at launch: **English (U.S.)** as primary, **Turkish**. Every other language
falls back to the primary listing, while the app itself still runs in all 15 languages.

---

## English (U.S.)

**App Name** — limit 30 [24]

```
Mindrop — Keyword Lookup
```

**Subtitle** — limit 30 [29]

```
Find your info from Spotlight
```

**Keywords** — limit 100 [97], comma separated, no spaces. Words already in the name and
subtitle are indexed anyway, so they are not repeated here.

```
wifi,password,pin,code,door,locker,iban,plate,note,memo,clipboard,copy,search,shortcut,quick,save
```

**Promotional Text** — limit 170 [164]. Can be changed any time without a review.

```
Spotlight is the app. Save a value under a keyword, then type that keyword on your Home Screen — the value is right there in the results. Tap it in Mindrop to copy.
```

**Description** — limit 4000

```
Mindrop does one thing: it puts a piece of information where you will actually look for it.

Save a value under a keyword. Later, swipe down on your Home Screen, type the keyword, and the value is right there in the Spotlight results. You don't have to open Mindrop at all.

wifi → SuperFast2026!
office door → 482916
car plate → 34 ABC 123
gym locker → 0713

WHAT IT IS
• Two fields: a keyword and a value. Nothing else.
• A plain list of what you saved, searchable inside the app too.
• Tap a value to copy all of it to the clipboard.
• Save text or a link from any app through the share sheet.
• Works offline. No account, no sign-in, no tracking, nothing leaves your iPhone.
• 15 languages.

WHAT IT IS NOT
Mindrop is not a password manager. There is no encryption, no Face ID lock, no vault. Saved values show up in Spotlight search results, which means anyone who can unlock your iPhone can read them. That is exactly how the app is meant to work — and the reason not to put anything in it you wouldn't want read over your shoulder.
```

---

## Turkish

**App Name** — limit 30 [23]

```
Mindrop — Anahtarla Bul
```

**Subtitle** — limit 30 [25]

```
Bilgini Spotlight'tan bul
```

**Keywords** — limit 100 [90]

```
şifre,wifi,pin,kod,kapı,dolap,iban,plaka,not,pano,kopyala,ara,kısayol,hızlı,kaydet,anahtar
```

**Promotional Text** — limit 170 [164]

```
Asıl arayüz Spotlight. Bir değeri anahtar kelimeyle kaydedin, ana ekranda o kelimeyi yazın — değer sonuçlarda karşınızda. Kopyalamak için Mindrop'ta üstüne dokunun.
```

**Description** — limit 4000

```
Mindrop tek bir iş yapar: bir bilgiyi, onu gerçekten arayacağınız yere koyar.

Bir değeri anahtar kelimeyle kaydedin. Sonra ana ekranda aşağı kaydırıp o kelimeyi yazın — değer, arama sonuçlarında karşınızda. Mindrop'u açmanıza bile gerek yok.

wifi → SuperFast2026!
ofis kapısı → 482916
araba plakası → 34 ABC 123
spor dolabı → 0713

NEDİR
• İki alan: anahtar kelime ve değer. Başka hiçbir şey.
• Kaydettiklerinizin düz bir listesi; uygulama içinde de aranabiliyor.
• Değere dokunun, tamamı panoya kopyalansın.
• Paylaş sayfasından, herhangi bir uygulamadan metin veya bağlantı kaydedin.
• Çevrimdışı çalışır. Hesap yok, giriş yok, takip yok; hiçbir şey telefonunuzdan çıkmaz.
• 15 dil.

NE DEĞİLDİR
Mindrop bir parola yöneticisi değildir. Şifreleme yok, Face ID kilidi yok, kasa yok. Kaydedilen değerler Spotlight arama sonuçlarında görünür; yani telefonunuzun kilidini açabilen herkes onları okuyabilir. Uygulamanın çalışma mantığı tam olarak budur — ve omzunuzun üstünden okunmasını istemeyeceğiniz hiçbir şeyi buraya koymamanızın sebebi de budur.
```

---

## Screenshots

Order matters: the first three are what shows in search results without scrolling.

| # | Screen | Caption (EN) | Caption (TR) | Captured by |
|---|---|---|---|---|
| 1 | Spotlight result for a keyword | Search the keyword. See the value. | Anahtarı ara. Değeri gör. | **Physical iPhone** |
| 2 | Detail screen with "Copied" showing | One tap copies it. | Tek dokunuş, kopyalandı. | Simulator |
| 3 | The memory list | One list. No folders, no tags. | Tek liste. Klasör yok, etiket yok. | Simulator |
| 4 | New Memory form, filled in | Two fields. That's the whole app. | İki alan. Uygulamanın tamamı bu. | Simulator |
| 5 | Saving from the share sheet | Save from any app. | Her uygulamadan kaydet. | **Physical iPhone** |

Shots 1 and 5 cannot come from the simulator: third-party Core Spotlight content is dropped
there, and synthetic taps cannot drive the share sheet. See the README for the detail.

Size: 1320×2868 (6.9", iPhone 17/18 Pro Max). One set covers every iPhone. Screenshots also
fall back to the primary locale, so an English set is enough to ship.

---

## The rest of the App Store Connect form

| Field | Value |
|---|---|
| Primary category | Utilities |
| Secondary category | Productivity |
| Age rating | 4+ |
| Price | Free |
| App Privacy | Data Not Collected — nothing is gathered, nothing leaves the device |
| Export compliance | Already answered in the build: `ITSAppUsesNonExemptEncryption = NO` |
| Review notes | No account or sign-in. To test: open the app, add a keyword and a value, then search that keyword in Spotlight from the Home Screen. |

Still needed, both mandatory and neither written yet: a **privacy policy URL** and a
**support URL**.
