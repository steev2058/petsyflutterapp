#!/usr/bin/env python3
"""Import high-confidence Syria vet listings into Petsy vet_profiles.

Idempotent by phone (normalized). Unpublishes known demo placeholder profiles.
Run on the VPS with petsy.env loaded.
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

from motor.motor_asyncio import AsyncIOMotorClient

DEMO_PHONE_SUFFIX = "900000000"
DEMO_NAME_MARKERS = ("تجريبي", "اختبار")


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def norm_phone(raw: str | None) -> str | None:
    if not raw:
        return None
    digits = re.sub(r"\D+", "", str(raw))
    if not digits:
        return None
    if digits.startswith("963"):
        return f"+{digits}"
    if digits.startswith("0") and len(digits) >= 9:
        return f"+963{digits[1:]}"
    if len(digits) == 9:
        return f"+963{digits}"
    return f"+{digits}" if not str(raw).startswith("+") else str(raw).strip()


def slugify(text: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9]+", "-", text.strip().lower()).strip("-")
    return (s or "clinic")[:40]


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--json",
        default=str(Path(__file__).resolve().parents[1] / "data/syria_research/verified_vets.json"),
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    mongo_url = os.environ["MONGO_URL"]
    db_name = os.environ.get("DB_NAME", "petsy")
    data = json.loads(Path(args.json).read_text(encoding="utf-8"))
    rows = data.get("vets") or []

    candidates = []
    for row in rows:
        if row.get("confidence") != "high":
            continue
        if row.get("import_ready") is False:
            continue
        phone = norm_phone(row.get("phone"))
        if not phone:
            continue
        candidates.append({**row, "phone": phone})

    client = AsyncIOMotorClient(mongo_url)
    db = client[db_name]
    now = utcnow()

    # Hide demo / placeholder public listings.
    demo_q = {
        "$or": [
            {"phone": {"$regex": DEMO_PHONE_SUFFIX}},
            {"name": {"$regex": "|".join(DEMO_NAME_MARKERS)}},
            {
                "clinic_name": "عيادة الشام البيطرية",
                "location_text": "شارع بغداد",
                "bio": {"$regex": "بيتا Petsy"},
            },
        ]
    }
    demo_count = await db.vet_profiles.count_documents(demo_q)
    print(f"demo_profiles_matched={demo_count}")
    if not args.dry_run and demo_count:
        await db.vet_profiles.update_many(
            demo_q,
            {
                "$set": {
                    "is_public": False,
                    "status": "suspended",
                    "verification_notes": "Unpublished: placeholder/demo listing replaced by verified Syria directory import (2026-11-09).",
                    "updated_at": now,
                }
            },
        )
        print("demo_profiles_unpublished=ok")

    inserted = updated = skipped = 0
    for row in candidates:
        phone = row["phone"]
        existing = await db.vet_profiles.find_one({"phone": phone})
        clinic = (row.get("clinic_name") or row.get("name") or "").strip()
        name = (row.get("name") or clinic).strip()
        city = (row.get("city") or "").strip()
        address = (row.get("address") or "").strip()
        specialty = (row.get("specialty") or "all").strip() or "all"
        services = row.get("services") or []
        if not isinstance(services, list):
            services = []
        hours = row.get("available_hours")
        rating = float(row.get("rating") or 0)
        rating_count = int(row.get("reviews_count") or 0)
        experience = int(row.get("experience_years") or 0)
        email = row.get("email")
        sources = ", ".join(row.get("sources") or [])
        bio_bits = [
            "عيادة مدرجة من مصادر عامة موثّقة (دليل Petsy سوريا).",
            f"المصادر: {sources}" if sources else None,
            f"ساعات العمل: {hours}" if hours else None,
        ]
        bio = " ".join(b for b in bio_bits if b)

        patch = {
            "name": name,
            "clinic_name": clinic,
            "specialty": specialty if specialty != "all" else "طب بيطري عام",
            "specialties": services or ["عام"],
            "experience_years": experience,
            "phone": phone,
            "email": email,
            "city": city,
            "location_text": address,
            "pet_types_supported": ["all"],
            "rating_avg": rating,
            "rating_count": rating_count,
            "available_hours": hours,
            "services": services,
            "bio": bio,
            "consultation_note": "البيانات من دليل عام؛ يُفضّل تأكيد الموعد بالاتصال قبل الزيارة.",
            "status": "active",
            "verified": True,
            "is_public": True,
            "verification_notes": "Imported from verified_vets.json (public listings).",
            "updated_at": now,
            "latitude": row.get("latitude"),
            "longitude": row.get("longitude"),
            "source_import": "syria_research_2026_11_09",
        }

        if existing:
            if args.dry_run:
                print(f"UPDATE {phone} {name}")
            else:
                await db.vet_profiles.update_one({"id": existing["id"]}, {"$set": patch})
            updated += 1
            continue

        # Create a directory-backed vet user (no login password usable by default).
        user_id = str(uuid.uuid4())
        profile_id = str(uuid.uuid4())
        user_email = f"directory.{slugify(clinic)}.{phone[-4:]}@users.petsy.company"
        user_doc = {
            "id": user_id,
            "email": user_email,
            "name": name,
            "phone": phone,
            "city": city,
            "password_hash": None,
            "is_verified": True,
            "is_admin": False,
            "role": "vet",
            "language": "ar",
            "created_at": now,
            "directory_import": True,
        }
        profile_doc = {
            "id": profile_id,
            "user_id": user_id,
            "created_at": now,
            **patch,
        }

        if args.dry_run:
            print(f"INSERT {phone} {name} ({city})")
        else:
            # Avoid email collision if re-run with different phone formatting.
            if await db.users.find_one({"email": user_email}):
                user_email = f"directory.{slugify(clinic)}.{uuid.uuid4().hex[:6]}@users.petsy.company"
                user_doc["email"] = user_email
            await db.users.insert_one(user_doc)
            await db.vet_profiles.insert_one(profile_doc)
        inserted += 1

    public = await db.vet_profiles.count_documents(
        {"status": "active", "verified": True, "is_public": True}
    )
    print(
        json.dumps(
            {
                "candidates": len(candidates),
                "inserted": inserted,
                "updated": updated,
                "skipped": skipped,
                "public_active_now": public,
                "dry_run": args.dry_run,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    asyncio.run(main())
