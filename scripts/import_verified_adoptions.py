#!/usr/bin/env python3
"""Import verified Syria adoption listings; unpublish fake seed pets."""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import urlopen, Request

from motor.motor_asyncio import AsyncIOMotorClient

FAKE_ADOPTION_NAMES = {"Max", "Luna", "Milo", "قطة الاختبار", "Rocky", "Bella"}


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
    if digits.startswith("0"):
        return f"+963{digits[1:]}"
    return f"+{digits}"


def download_image(url: str, dest: Path) -> bool:
    try:
        req = Request(url, headers={"User-Agent": "PetsyImporter/1.0"})
        with urlopen(req, timeout=40) as resp:
            dest.write_bytes(resp.read())
        return dest.stat().st_size > 1000
    except Exception as exc:
        print(f"image_download_failed {url}: {exc}")
        return False


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--json",
        default=str(Path(__file__).resolve().parents[1] / "data/syria_research/verified_adoptions.json"),
    )
    parser.add_argument("--uploads-dir", default="/opt/petsy/backend/uploads")
    parser.add_argument("--public-base", default="https://petsy.company/uploads")  # FastAPI StaticFiles mount
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    data = json.loads(Path(args.json).read_text(encoding="utf-8"))
    rows = [r for r in (data.get("adoptions") or []) if r.get("confidence") == "high"]
    db = AsyncIOMotorClient(os.environ["MONGO_URL"])[os.environ.get("DB_NAME", "petsy")]
    now = utcnow()
    uploads = Path(args.uploads_dir)
    uploads.mkdir(parents=True, exist_ok=True)

    fake_q = {
        "$or": [
            {"name": {"$in": list(FAKE_ADOPTION_NAMES)}},
            {"description": {"$regex": "looking for a loving home", "$options": "i"}},
            {"owner_id": {"$exists": True}, "name": {"$in": ["Max", "Luna", "Milo"]}},
        ],
        "status": {"$in": ["for_adoption", "for_sale", "owned"]},
    }
    fake_n = await db.pets.count_documents({"name": {"$in": list(FAKE_ADOPTION_NAMES)}})
    print(f"fake_named_pets={fake_n}")
    if not args.dry_run and fake_n:
        res = await db.pets.update_many(
            {"name": {"$in": list(FAKE_ADOPTION_NAMES)}},
            {"$set": {"status": "owned", "updated_at": now, "import_note": "Unpublished seed/demo pet"}},
        )
        print(f"fake_unpublished={res.modified_count}")

    inserted = updated = 0
    for row in rows:
        ext = row.get("external_id") or row.get("source")
        phone = norm_phone(row.get("contact_phone"))
        existing = await db.pets.find_one({"external_id": ext}) if ext else None
        if not existing and phone:
            existing = await db.pets.find_one(
                {"status": "for_adoption", "description": {"$regex": re.escape(phone[-8:])}}
            )

        image_url = None
        images = row.get("images") or []
        if images and not args.dry_run:
            fname = f"adoption_{re.sub(r'[^a-zA-Z0-9]+', '_', str(ext))[:48]}.jpg"
            dest = uploads / fname
            if download_image(images[0], dest):
                image_url = f"{args.public_base.rstrip('/')}/{fname}"
            else:
                image_url = images[0]
        elif images:
            image_url = images[0]

        # Ensure directory owner user for in-app adoption requests.
        owner_email = f"adoption.{re.sub(r'[^a-z0-9]+', '', (phone or 'x')[-8:])}@users.petsy.company"
        owner = await db.users.find_one({"email": owner_email})
        if not owner:
            owner_id = str(uuid.uuid4())
            owner = {
                "id": owner_id,
                "email": owner_email,
                "name": row.get("contact_name") or "صاحب التبني",
                "phone": phone,
                "city": row.get("location") or "دمشق",
                "password_hash": None,
                "is_verified": True,
                "is_admin": False,
                "role": "user",
                "language": "ar",
                "created_at": now,
                "directory_import": True,
            }
            if not args.dry_run:
                await db.users.insert_one(owner)
        owner_id = owner["id"]

        pet_doc = {
            "name": row.get("name") or "للتبني",
            "species": (row.get("species") or "cat").lower(),
            "breed": row.get("breed"),
            "age": row.get("age"),
            "gender": (row.get("gender") or "female").lower(),
            "color": row.get("color"),
            "weight": None,
            "description": row.get("description") or "",
            "image": image_url,
            "status": "for_adoption",
            "price": None,
            "location": row.get("location") or "دمشق",
            "vaccinated": bool(row.get("vaccinated")),
            "neutered": bool(row.get("neutered")),
            "owner_id": owner_id,
            "likes": 0,
            "views": 0,
            "external_id": ext,
            "source_url": row.get("source"),
            "contact_phone": phone,
            "source_import": "syria_research_adoptions_2026_11_09",
            "updated_at": now,
        }

        if existing:
            if args.dry_run:
                print(f"UPDATE {ext}")
            else:
                await db.pets.update_one({"id": existing["id"]}, {"$set": pet_doc})
            updated += 1
        else:
            pet_doc["id"] = str(uuid.uuid4())
            pet_doc["created_at"] = now
            if args.dry_run:
                print(f"INSERT {pet_doc['name']} {pet_doc['location']} {image_url}")
            else:
                await db.pets.insert_one(pet_doc)
            inserted += 1

    adoption_n = await db.pets.count_documents({"status": "for_adoption"})
    print(
        json.dumps(
            {
                "candidates": len(rows),
                "inserted": inserted,
                "updated": updated,
                "for_adoption_now": adoption_n,
                "dry_run": args.dry_run,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    asyncio.run(main())
