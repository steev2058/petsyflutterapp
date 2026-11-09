#!/usr/bin/env python3
"""Sync public Aleef Syria data into Petsy (vets, adoption pets, lost_found).

Aleef currently publishes very little: 2 clinics, 1 adoption, 1 lost, 0 shop products.
Idempotent by phone / external_id.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

from motor.motor_asyncio import AsyncIOMotorClient


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def norm_phone(raw: str | None) -> str | None:
    if not raw:
        return None
    # strip bidi marks
    raw = re.sub(r"[\u200e\u200f\u202a-\u202e]", "", str(raw))
    digits = re.sub(r"\D+", "", raw)
    if not digits:
        return None
    if digits.startswith("963"):
        return f"+{digits}"
    if digits.startswith("0"):
        return f"+963{digits[1:]}"
    if len(digits) == 9:
        return f"+963{digits}"
    return f"+{digits}"


def download(url: str, dest: Path) -> bool:
    try:
        req = Request(url, headers={"User-Agent": "PetsyAleefSync/1.0"})
        with urlopen(req, timeout=45) as resp:
            dest.write_bytes(resp.read())
        return dest.stat().st_size > 800
    except Exception as e:
        print(f"download_fail {url}: {e}")
        return False


async def ensure_user(db, *, email: str, name: str, phone: str | None, city: str, role: str = "user") -> str:
    existing = await db.users.find_one({"email": email})
    if existing:
        return existing["id"]
    uid = str(uuid.uuid4())
    await db.users.insert_one(
        {
            "id": uid,
            "email": email,
            "name": name,
            "phone": phone,
            "city": city,
            "password_hash": None,
            "is_verified": True,
            "is_admin": False,
            "role": role,
            "language": "ar",
            "created_at": utcnow(),
            "directory_import": True,
            "source": "aleefsyria",
        }
    )
    return uid


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw-dir", default=str(Path(__file__).resolve().parents[1] / "data/syria_research/aleef_raw"))
    ap.add_argument("--uploads-dir", default="/opt/petsy/backend/uploads")
    ap.add_argument("--public-base", default="https://petsy.company/uploads")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    raw = Path(args.raw_dir)
    cities = {c["id"]: c for c in json.loads((raw / "cities.json").read_text(encoding="utf-8"))}
    businesses = json.loads((raw / "business_listings.json").read_text(encoding="utf-8"))
    photos = json.loads((raw / "listing_photos.json").read_text(encoding="utf-8"))
    rescues = json.loads((raw / "rescue_posts.json").read_text(encoding="utf-8"))
    products = json.loads((raw / "products.json").read_text(encoding="utf-8"))
    photos_by = {}
    for p in photos:
        photos_by.setdefault(p["listing_id"], []).append(p["url"])

    db = AsyncIOMotorClient(os.environ["MONGO_URL"])[os.environ.get("DB_NAME", "petsy")]
    uploads = Path(args.uploads_dir)
    if not args.dry_run:
        uploads.mkdir(parents=True, exist_ok=True)
    now = utcnow()

    summary = {
        "aleef_clinics": 0,
        "aleef_shops": 0,
        "vets_upserted": 0,
        "adoptions_upserted": 0,
        "lost_upserted": 0,
        "products_available_on_aleef": len(products),
        "shop_products_imported": 0,
    }

    # ---- Clinics -> vet_profiles ----
    for b in businesses:
        if not b.get("is_published") or b.get("verification_status") != "approved":
            continue
        btype = (b.get("type") or "").lower()
        phone = norm_phone(b.get("phone"))
        if not phone:
            continue
        city = cities.get(b.get("city_id") or "", {})
        city_name = city.get("name_ar") or "سوريا"
        name = (b.get("name") or "").strip()
        nb = (b.get("neighborhood_text") or "").strip()
        desc = (b.get("description") or "").strip()
        hours = (b.get("opening_hours") or "").strip()
        img_remote = (photos_by.get(b["id"]) or [None])[0]
        image_url = img_remote
        if img_remote and not args.dry_run:
            fname = f"aleef_clinic_{b['id'][:8]}.jpg"
            dest = uploads / fname
            # keep extension-ish
            if img_remote.lower().endswith(".webp"):
                fname = f"aleef_clinic_{b['id'][:8]}.webp"
                dest = uploads / fname
            if download(img_remote, dest):
                image_url = f"{args.public_base.rstrip('/')}/{fname}"

        if btype == "clinic":
            summary["aleef_clinics"] += 1
            patch = {
                "name": name,
                "clinic_name": name,
                "specialty": "طب بيطري عام",
                "specialties": ["عام"],
                "experience_years": 0,
                "phone": phone,
                "city": city_name,
                "location_text": nb,
                "pet_types_supported": ["all"],
                "rating_avg": 0,
                "rating_count": 0,
                "available_hours": hours or None,
                "services": ["checkup"],
                "bio": desc or "عيادة موثّقة على منصة أليف سوريا.",
                "consultation_note": "بيانات مستوردة من أليف سوريا؛ يُفضّل تأكيد الموعد بالاتصال.",
                "status": "active",
                "verified": True,
                "is_public": True,
                "image_url": image_url,
                "latitude": b.get("latitude"),
                "longitude": b.get("longitude"),
                "whatsapp_link": b.get("whatsapp_link"),
                "external_id": f"aleef-business-{b['id']}",
                "source_import": "aleefsyria",
                "source_url": f"https://aleefsyria.com/directory/{b['id']}",
                "verification_notes": "Synced from Aleef Syria public business_listings",
                "updated_at": now,
            }
            existing = await db.vet_profiles.find_one(
                {"$or": [{"phone": phone}, {"external_id": patch["external_id"]}]}
            )
            if args.dry_run:
                print("VET", "UPDATE" if existing else "INSERT", name, city_name, phone)
            elif existing:
                await db.vet_profiles.update_one({"id": existing["id"]}, {"$set": patch})
            else:
                owner_id = await ensure_user(
                    db,
                    email=f"aleef.clinic.{phone[-8:]}@users.petsy.company",
                    name=name,
                    phone=phone,
                    city=city_name,
                    role="vet",
                )
                await db.vet_profiles.insert_one(
                    {"id": str(uuid.uuid4()), "user_id": owner_id, "created_at": now, **patch}
                )
            summary["vets_upserted"] += 1
        elif btype in {"shop", "store", "pet_shop"}:
            summary["aleef_shops"] += 1
            # No product rows on Aleef yet — store partner stub in emergency/notes collection optional.
            print(f"SHOP_LISTING_ONLY {name} {phone} (no products to import)")

    # ---- Rescue posts ----
    for r in rescues:
        if not r.get("is_published") or (r.get("status") or "").lower() not in {"open", "active"}:
            continue
        rtype = (r.get("type") or "").lower()
        phone = norm_phone(r.get("contact_phone"))
        city = cities.get(r.get("city_id") or "", {})
        city_name = city.get("name_ar") or "دمشق"
        photos_r = r.get("photo_urls") or []
        image_url = photos_r[0] if photos_r else None
        ext = f"aleef-rescue-{r['id']}"
        title = (r.get("title") or "").strip() or "بلاغ"
        desc = (r.get("description") or "").strip()
        contact = (r.get("contact_name") or "للتواصل").strip()
        nb = (r.get("neighborhood_text") or "").strip()
        req = (r.get("adoption_requirements") or "").strip()
        species = (r.get("pet_type") or "cat").lower()
        if species not in {"cat", "dog", "bird", "rabbit", "other"}:
            species = "other"

        if image_url and not args.dry_run:
            fname = f"aleef_rescue_{r['id'][:8]}.jpg"
            dest = uploads / fname
            if download(image_url, dest):
                image_url = f"{args.public_base.rstrip('/')}/{fname}"

        if rtype == "adoption":
            full_desc = desc
            if req:
                full_desc += f"\n\nشروط التبني: {req}"
            if phone:
                full_desc += f"\n\nللتواصل: {contact} — {phone}"
            full_desc += "\nالمصدر: أليف سوريا (منشور علني)."
            owner_email = f"aleef.adoption.{(phone or r['id'])[-8:]}@users.petsy.company"
            pet = {
                "name": title,
                "species": species if species in {"cat", "dog", "bird"} else "cat",
                "breed": None,
                "age": None,
                "gender": "female" if "قطة" in title or species == "cat" else "male",
                "color": None,
                "description": full_desc,
                "image": image_url,
                "status": "for_adoption",
                "price": None,
                "location": city_name,
                "vaccinated": True,
                "neutered": False,
                "likes": 0,
                "views": 0,
                "external_id": ext,
                "source_url": f"https://aleefsyria.com/rescue/{r['id']}",
                "contact_phone": phone,
                "source_import": "aleefsyria",
                "updated_at": now,
            }
            existing = await db.pets.find_one({"external_id": ext})
            if args.dry_run:
                print("ADOPTION", "UPDATE" if existing else "INSERT", title, city_name, phone)
            else:
                owner_id = await ensure_user(
                    db, email=owner_email, name=contact, phone=phone, city=city_name, role="user"
                )
                pet["owner_id"] = owner_id
                if existing:
                    await db.pets.update_one({"id": existing["id"]}, {"$set": pet})
                else:
                    pet["id"] = str(uuid.uuid4())
                    pet["created_at"] = now
                    await db.pets.insert_one(pet)
            summary["adoptions_upserted"] += 1

        elif rtype == "lost":
            full_desc = desc
            if phone:
                full_desc += f"\n\nللتواصل: {contact} — {phone}"
            full_desc += "\nالمصدر: أليف سوريا (منشور علني)."
            last_seen = nb or city_name
            post = {
                "type": "lost",
                "pet_species": species,
                "breed": None,
                "color": None,
                "description": full_desc,
                "last_seen_location": last_seen,
                "last_seen_date": (r.get("last_seen_at") or r.get("created_at") or "")[:10]
                or now.date().isoformat(),
                "contact_phone": phone or "",
                "image": image_url,
                "lat": None,
                "lng": None,
                "status": "active",
                "city": city_name,
                "title": title,
                "external_id": ext,
                "source_url": f"https://aleefsyria.com/rescue/{r['id']}",
                "source_import": "aleefsyria",
                "updated_at": now,
            }
            existing = await db.lost_found.find_one({"external_id": ext})
            if args.dry_run:
                print("LOST", "UPDATE" if existing else "INSERT", title, last_seen, phone)
            else:
                owner_id = await ensure_user(
                    db,
                    email=f"aleef.lost.{(phone or r['id'])[-8:]}@users.petsy.company",
                    name=contact,
                    phone=phone,
                    city=city_name,
                    role="user",
                )
                post["user_id"] = owner_id
                if existing:
                    await db.lost_found.update_one({"id": existing["id"]}, {"$set": post})
                else:
                    post["id"] = str(uuid.uuid4())
                    post["created_at"] = now
                    await db.lost_found.insert_one(post)
            summary["lost_upserted"] += 1

    # products empty on Aleef
    if products:
        print(f"NOTE: {len(products)} Aleef products found — importer not expanded yet")

    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
