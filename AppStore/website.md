# Mindrop website and App Store links

The English website is a buildless static site in `docs/`. No package installation,
tracking, external fonts, or build step is required. All paths work under the GitHub
Pages project prefix `/mindrop/`.

## App Store Connect

After a successful Pages deployment, use these URLs:

| Field | URL |
| --- | --- |
| Marketing URL | https://mfsaglam.github.io/mindrop/ |
| Support URL | https://mfsaglam.github.io/mindrop/support.html |
| Privacy Policy URL | https://mfsaglam.github.io/mindrop/privacy.html |
| Terms of Use | https://mfsaglam.github.io/mindrop/terms.html |

Developer and support contact: **Fatih Saglam**, **mfsaglam1@icloud.com**.
The app’s Settings links to the same privacy, terms, and support pages.

The Terms of Use page references Apple’s Standard EULA. Keep the default license
agreement in App Store Connect unless you deliberately adopt a custom EULA; this
website’s explanatory terms are not a replacement custom app license.

## GitHub Pages

1. In the repository’s **Settings → Pages**, set **Source → GitHub Actions**.
2. Push the website and `.github/workflows/pages.yml` to `main`.
3. Check the **Deploy GitHub Pages** workflow for its deployment result.

The workflow publishes only `docs/`, never app source, repository documentation,
or secrets. It deploys on changes to the website/workflow on `main`, and can also
be run manually. The `github-pages` environment records the public deployment URL.
There is no custom domain configured.

## Preview and maintain

From the repository root:

```sh
python3 -m http.server 4173 --directory docs
```

Open http://localhost:4173. Page content is ordinary HTML; shared styles and the
Spotlight animation are in `docs/assets/`. Without JavaScript or with Reduce
Motion enabled, the demo displays a complete static example. A visible button
pauses/resumes the animation, which also stops while the tab is hidden.

Replace “Coming to the App Store” with the real App Store listing link once the
listing is available. Keep policy dates and descriptions in sync with future
changes to storage, syncing, data collection, or monetization.

## Release facts to revisit

`AppStore/copy.md` contains earlier listing copy that predates iCloud Sync,
Sensitive memories, and category grouping. Its claims about no Face ID,
no encryption, and nothing leaving the phone must be revised before submission.
Do not use those old claims as the basis of the App Privacy questionnaire.
Review the questionnaire against the shipping build and Apple’s definitions.

The website alone does not finish App Store submission: also complete the current
App Privacy questionnaire, age rating, screenshots, review information, export
compliance, and production CloudKit setup. The repository README documents the
remaining real-device iCloud/Watch checks and CloudKit schema deployment.

Official references:
- https://developer.apple.com/app-store/review/guidelines/ (support contact and privacy policy, including in-app access)
- https://developer.apple.com/app-store/app-privacy-details/ (privacy disclosures)
- https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement/ (standard and custom EULAs)
- https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages (Pages workflow)
