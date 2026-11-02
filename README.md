# news

Data and app for **apex** (working name), Tirth's personal Android news app.

A scheduled Claude task researches trusted sources 3 times a day and pushes one
edition (a JSON file) here. The app downloads new editions and stores them on
the phone. This repo is only a drop box: it keeps the **last 7 days**, and the
phone keeps the full archive.

| When (IST) | Slot |
| --- | --- |
| 7:30 AM | `morning` (Sunday: `weekend`, with the Weekend Special) |
| 1:30 PM | `midday` |
| 8:30 PM | `evening` |

## Layout

```
app/                      Flutter app (Phase 2)
data/
  latest.json             exact copy of the newest edition
  index.json              editions still in the repo, newest first (rebuilt by prune.py)
  editions/YYYY/MM/DD-<slot>.json
schema/edition.schema.json
tools/
  validate.py             checks editions + index; run before every commit
  prune.py                deletes editions older than 7 days, rebuilds index.json
  requirements.txt        pip install -r tools/requirements.txt
.github/workflows/        validate-data.yml (and build-apk.yml in Phase 3)
```

The app reads:

- `https://raw.githubusercontent.com/tirthgujarati/news/main/data/latest.json`
- `https://raw.githubusercontent.com/tirthgujarati/news/main/data/index.json`
- `https://raw.githubusercontent.com/tirthgujarati/news/main/data/editions/<path>`

This repo is public. Never put secrets or private data in it.

---

# Editor rules

Every scheduled run starts with no memory. These rules are the whole brief:
follow them exactly.

## Sections and trusted sources

Every edition has these 5 sections, in this order, with these titles.

| id | Title | What goes in | Trusted sources | Stories |
| --- | --- | --- | --- | --- |
| `india` | India | Economy, RBI, government policy, big domestic news | PIB (pib.gov.in), RBI (rbi.org.in), Mint (livemint.com), Business Standard, The Hindu, Indian Express | 3 to 5 |
| `world` | World | Wars, elections, diplomacy, sanctions, trade deals | Reuters, AP (apnews.com), BBC, Al Jazeera (for the Middle East) | 3 to 5 |
| `currency` | Currency Desk | Rupee vs dollar and euro, dollar index, India forex reserves, what moved them | RBI, Reuters, Moneycontrol, Business Standard | 2 to 4 |
| `markets` | Money & Markets | Nifty, Sensex, US indices, gold, oil, crypto, central bank decisions | Reuters, Moneycontrol, Mint, CNBC | 3 to 5 |
| `built` | Built This Week | Any company, any sector, that made or launched something remarkable: chips, drugs, rockets, EVs, AI, energy, materials | Company press releases and official blogs, confirmed by a major outlet above | 2 to 5 |

Stories counts are maximums to aim for, not quotas. **Never pad.**

**Weekend Special** (Sunday morning only, slot `weekend`): the 5 to 7 biggest
stories of the past 7 days across all sections, ranked (`rank` 1 = biggest),
each with a 2 to 3 sentence `why_it_matters`. The normal sections are still
included in that edition. Weekend Special stories have `lead: false` and
`image: null`.

Also trusted, because they can be opened by Claude: **All India Radio**
(newsonair.gov.in), **RBI**, **CNBC**, **Al Jazeera**, and official sites
(government departments, central banks, stock exchanges, company newsrooms).

## How to research

Many of the outlets above (Reuters, AP, BBC, Mint, Moneycontrol, The Hindu,
Indian Express, Business Standard...) block Claude from opening their pages.
So:

1. **Search** the web to find the day's stories from all trusted outlets.
2. **Open and read** every page that can be opened (All India Radio, RBI, CNBC,
   Al Jazeera, official sites, and any outlet that loads) and take facts and
   numbers from those pages first.
3. For an outlet that blocks Claude, its article URL found in search may be cited,
   with the facts taken from the search results. Cross-check them.
4. Analyse, merge, rank and write the stories yourself.

## Accuracy rules (strict)

1. Every story cites at least one source from the trusted list, by name and URL.
2. Every number (rupee rate, index level, price, percentage) is checked against
   a second source when possible. If the two disagree, use the more official
   source and say so in `note`.
3. `"verified": true` means the facts were confirmed by at least two different
   sources; list each one in `sources`. A story from **one trusted source** is
   allowed, with `"verified": false` and `note` saying so, e.g.
   `"Single source: All India Radio."`. The app shows a "single source" tag.
4. No rumours. "Reportedly" or anonymous-source stories are left out.
5. **One-side claims.** When a government, army, company or party makes a claim
   about itself or a rival (e.g. Iran saying tankers hit mines), write it as
   "<who> says ..." in the headline and summary. It counts as `verified: true`
   only if an independent source confirms the facts; several outlets repeating
   the same side's claim is still one claim, so `verified: false` with a `note`
   such as `"Claim by Iran's IRGC; not independently confirmed."`.
6. Write every headline and summary in your own words. No copied sentences.
   Quotes under 15 words, at most one per source.
7. Stamp the edition with its generation time in IST (`+05:30`), and give every
   snapshot number an `as_of` time. If only the date of a time is known, use
   `T00:00:00` with the source's offset; never invent a time.
8. If a section has no real news, include fewer stories. Never pad.
9. Don't repeat a story from the previous edition (`data/latest.json` before you
   overwrite it) unless something new happened. If so, say what changed.

## Sorting and writing

- Inside each section, rank by `importance` (1 to 5): impact on India, on
  markets, or how new the achievement is. Highest first.
- Merge duplicate reports of the same event into one story with several sources.
- The single most important story of the edition gets `"lead": true`. Exactly one.
- Headline under 90 characters. Summary 1 to 3 plain, short sentences.
- `why_it_matters`: one sentence, only for important stories (else `null`).
- Story `id` is stable: `<section>-<short-slug>-<YYYY-MM-DD>` (the date the story
  broke). Reuse the same id if the story carries over with an update.

## Photos

Photos go on **the lead story and the first story of each section only**
(about 6 per edition). Every other story has `"image": null`.

- Use the main photo of a trusted source article you opened for that story
  (usually the page's `og:image`). Prefer the page cited in `sources`.
- If no news article has a usable photo, a **real photograph from an official
  source** is allowed: a company's own product or press photo (newsroom, press
  kit), or a government/PIB/agency photo of the event. `credit` names that
  source (e.g. `"Apple"`, `"PIB"`); `source_url` is the official page.
- It must be a **real, clear photograph** of the subject: no AI-generated or
  illustrated images, no 3D renders, no animations/GIFs, no logos, charts, maps,
  murals, text overlays, stock "concept" art, or generic placeholder images. If
  there's no good real photo, use `null`.
- Download each candidate to `/tmp` and look at it before using it.
- `url` is the direct link to the image file; `source_url` is the article page;
  `credit` is the photographer/agency as shown on the page (else the publisher
  name); `alt` is a short plain description of what the photo shows.
- Never download or commit image files. Only links.

## Market snapshot

Cover, each with `value`, `change` (percent as a string, or `null` if unknown),
`dir` (`up` / `down` / `flat`), `as_of` and `source`:

`usdinr` USD/INR · `eurinr` EUR/INR · `dxy` Dollar index · `fx_reserves` India
forex reserves · `nifty` Nifty 50 · `sensex` Sensex · `spx` S&P 500 · `nasdaq`
Nasdaq · `gold_usd` Gold (USD/oz) · `gold_mcx` Gold MCX · `brent` Brent crude ·
`btc` Bitcoin · `us10y` US 10Y yield.

Prefer numbers confirmed by two sources; one official or trusted source is
acceptable. If sources disagree and none is official, leave that item out. If
the previous value is unknown, set `change` to `null` and `dir` to `flat` (the
app then shows no arrow).

## Week ahead

The next 7 days, one entry per day that has events, in date order. Each event:
short `text` and the `section` it belongs to. Only scheduled, confirmed events
(policy meetings, data releases, elections, earnings, launches).

## Field rules

- `slot` is one of `morning`, `midday`, `evening`, `weekend`.
- `edition_id` is `<date>-<slot>`; the file is `data/editions/YYYY/MM/DD-<slot>.json`.
- `sections` always lists all 5 sections in order; an empty section has `"stories": []`.
- `weekend_special` is `null` except in the `weekend` slot.
- `title` like `Monday Morning Edition`, `Monday Midday Edition`,
  `Monday Evening Edition`, `Sunday Weekend Edition`.
- If an edition with the same id already exists, replace it with the new one.

## Publishing steps

1. `pip install -r tools/requirements.txt`
2. Write the edition to `data/editions/YYYY/MM/DD-<slot>.json`.
3. Copy it byte-for-byte to `data/latest.json`.
4. `python tools/prune.py` (deletes editions older than 7 days, rebuilds `index.json`).
5. `python tools/validate.py`. If it fails, fix the edition and run it again.
   **Never commit an invalid file.**
6. Commit `edition: YYYY-MM-DD <slot> (N stories)` and push to `main`.
7. If the edition could not be published (push refused, validation still
   failing, or no edition written), send a phone notification saying why. Send
   none when it publishes normally.
