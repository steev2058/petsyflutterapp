# Syria real-data research (Petsy)

Collected **2026-11-09**. Goal: fill Petsy with **real, complete, trusted** Syria data — not fake rows and not incomplete Facebook posts.

## Hard limits (honest)

1. **Facebook groups cannot be fully scraped** into complete pet/shop/vet records (login walls, incomplete posts, stale listings, ToS).
2. **SMP medical directory** has hundreds of vet *names* but most rows lack phone → **not import-ready**.
3. **Shop catalogs** need merchant consent + current prices/photos.
4. **Adoption** should come from shelters/orgs or complete owner listings with consent — not copy-paste half posts.

## What we shipped in this folder

| File | Contents |
|------|----------|
| `verified_vets.json` | Clinics with public phone + city + address (Maps / Aleef / directories) |
| `shops_and_adoption.json` | Pet shops to partner with + STAR / Ernesto / Aleef + FB groups (manual) |

## Recommended fill order

1. **Vets** — import only `confidence: high` and `phone != null` after a live call/WhatsApp check.
2. **Shop** — call Furry Friends (Damascus) + Pet House Syria (Aleppo); ask for CSV/photos; onboard as `market_owner`.
3. **Adoption** — email STAR + Ernesto for partnership; optionally invite complete posters from Damascus FB groups into the app.

## Completeness checklist before any row goes live

- Vet: name, clinic, phone, city, address, specialty
- Product: name, category, price (SYP), image, brand/pet_type, stock, seller
- Pet adoption: name/species, sex, age, city, photo, owner contact or shelter, vaccines if known
