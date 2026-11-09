#!/usr/bin/env python3
"""Seed demo guard dogs for sale (purpose=guard, status=for_sale)."""
from __future__ import annotations

import asyncio
import os
import uuid
from datetime import datetime, timezone

from motor.motor_asyncio import AsyncIOMotorClient

TAG = "demo_guard_dogs_2026_11"
IMG = {
    "gsd": "https://images.unsplash.com/photo-1568572933382-74d440642117?w=800&q=80",
    "rott": "https://images.unsplash.com/photo-1567752881298-894bb81f9379?w=800&q=80",
    "malo": "https://images.unsplash.com/photo-1587300003388-59208cc962c0?w=800&q=80",
    "cane": "https://images.unsplash.com/photo-1552053831-71594a27632d?w=800&q=80",
    "dob": "https://images.unsplash.com/photo-1517849845537-4d257902454a?w=800&q=80",
}


async def main() -> None:
    db = AsyncIOMotorClient(os.environ["MONGO_URL"])[os.environ.get("DB_NAME", "petsy")]
    ts = datetime.now(timezone.utc).replace(tzinfo=None)
    await db.pets.delete_many({"demo_seed": TAG})

    owners = []
    for email in [
        "demo.nour@petsy.app",
        "demo.rami@petsy.app",
        "demo.omar@petsy.app",
        "demo.lina@petsy.app",
    ]:
        u = await db.users.find_one({"email": email})
        if u:
            owners.append(u)
    if not owners:
        owners = [await db.users.find_one({})]

    dogs = [
        ("شبح", "German Shepherd", "سنتان", "male", "دمشق", 2500000, IMG["gsd"], "مدرب حراسة وحماية منزل، يستجيب للأوامر بالعربية."),
        ("رعد", "Rottweiler", "3 سنوات", "male", "حلب", 3200000, IMG["rott"], "كلب حراسة قوي، معتاد على الحراسة الليلية."),
        ("فهد", "Malinois", "سنة ونصف", "male", "دمشق", 4500000, IMG["malo"], "مالي نوى مدرّب، مناسب للمنشآت والحراسة الشخصية."),
        ("لونا حارسة", "Cane Corso", "سنتان", "female", "حمص", 2800000, IMG["cane"], "كورسو هادئة مع العائلة وحازمة مع الغرباء."),
        ("نايت", "Doberman", "سنتان", "male", "اللاذقية", 3000000, IMG["dob"], "دوبيرمان سريع الاستجابة، لقاحات كاملة."),
    ]
    for i, (name, breed, age, gender, loc, price, image, desc) in enumerate(dogs):
        owner = owners[i % len(owners)]
        await db.pets.insert_one(
            {
                "id": str(uuid.uuid4()),
                "owner_id": owner["id"],
                "name": name,
                "species": "dog",
                "breed": breed,
                "age": age,
                "gender": gender,
                "description": f"{desc}\n\n[عرض تجريبي لكلاب الحراسة]",
                "image": image,
                "status": "for_sale",
                "purpose": "guard",
                "price": float(price),
                "location": loc,
                "vaccinated": True,
                "neutered": False,
                "likes": 2 + i,
                "views": 10 + i * 3,
                "created_at": ts,
                "demo_seed": TAG,
            }
        )

    n = await db.pets.count_documents({"status": "for_sale", "purpose": "guard", "species": "dog"})
    print({"guard_for_sale": n})


if __name__ == "__main__":
    asyncio.run(main())
