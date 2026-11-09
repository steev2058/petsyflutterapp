#!/usr/bin/env python3
"""Seed professional international guard-dog listings + pet trainers."""
from __future__ import annotations

import asyncio
import os
import uuid
from datetime import datetime, timezone

from motor.motor_asyncio import AsyncIOMotorClient

TAG = "demo_guard_training_2026_11"

IMG = {
    "gsd": "https://images.unsplash.com/photo-1568572933382-74d440642117?w=800&q=80",
    "malo": "https://images.unsplash.com/photo-1587300003388-59208cc962c0?w=800&q=80",
    "rott": "https://images.unsplash.com/photo-1567752881298-894bb81f9379?w=800&q=80",
    "dob": "https://images.unsplash.com/photo-1517849845537-4d257902454a?w=800&q=80",
    "cane": "https://images.unsplash.com/photo-1552053831-71594a27632d?w=800&q=80",
    "t1": "https://images.unsplash.com/photo-1559839734-2b71ea197ec2?w=400&q=80",
    "t2": "https://images.unsplash.com/photo-1560250097-0b93528c311a?w=400&q=80",
    "t3": "https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=400&q=80",
    "t4": "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=400&q=80",
}


def uid() -> str:
    return str(uuid.uuid4())


def now():
    return datetime.now(timezone.utc).replace(tzinfo=None)


async def main() -> None:
    db = AsyncIOMotorClient(os.environ["MONGO_URL"])[os.environ.get("DB_NAME", "petsy")]
    ts = now()

    # Drop previous demo guard tags from both seed waves
    await db.pets.delete_many({"demo_seed": {"$in": [TAG, "demo_guard_dogs_2026_11"]}})
    await db.trainers.delete_many({"demo_seed": TAG})

    owners = []
    for email in [
        "demo.nour@petsy.app",
        "demo.rami@petsy.app",
        "demo.omar@petsy.app",
        "demo.lina@petsy.app",
        "demo.shop@petsy.app",
    ]:
        u = await db.users.find_one({"email": email})
        if u:
            owners.append(u)
    if not owners:
        owners = [await db.users.find_one({})]

    dogs = [
        ("شبح", "German Shepherd", "سنتان", "male", "دمشق", "SY", "home", "kennel", 2500000, "SYP", IMG["gsd"], "مدرب حماية منزل وفلل، أوامر عربية."),
        ("رعد", "Rottweiler", "3 سنوات", "male", "حلب", "SY", "facility", "security_company", 3200000, "SYP", IMG["rott"], "حراسة منشآت ومستودعات — تدريب ليلي."),
        ("فهد", "Malinois", "سنة ونصف", "male", "دبي", "AE", "police", "agency", 18000, "AED", IMG["malo"], "مالي نوى بمواصفات أمنية/شرطة، جاهز للتسليم."),
        ("نايت", "Doberman", "سنتان", "male", "الرياض", "SA", "personal_protection", "kennel", 22000, "SAR", IMG["dob"], "حماية شخصية للشخصيات والمواكب."),
        ("أطلس", "Cane Corso", "سنتان", "male", "إسطنبول", "TR", "facility", "kennel", 4500, "USD", IMG["cane"], "حراسة مواقع صناعية — تدريب أوروبي."),
        ("كابتن", "German Shepherd", "4 سنوات", "male", "عمّان", "JO", "military", "agency", 9000, "USD", IMG["gsd"], "خلفية K9 عسكرية سابقة، مناسب للوحدات الأمنية."),
        ("ليث", "Malinois", "سنتان", "male", "القاهرة", "EG", "police", "security_company", 7000, "USD", IMG["malo"], "تدريب كشف ومطاردة وفق برامج أمنية."),
        ("فارس", "Rottweiler", "سنة ونصف", "male", "بيروت", "LB", "home", "individual", 3500, "USD", IMG["rott"], "حراسة منزلية مع عائلة، اجتماعي ومنضبط."),
    ]

    for i, (name, breed, age, gender, city, country, role, seller, price, currency, image, desc) in enumerate(dogs):
        owner = owners[i % len(owners)]
        await db.pets.insert_one(
            {
                "id": uid(),
                "owner_id": owner["id"],
                "name": name,
                "species": "dog",
                "breed": breed,
                "age": age,
                "gender": gender,
                "description": f"{desc}\n\n[عرض احترافي تجريبي — {TAG}]",
                "image": image,
                "status": "for_sale",
                "purpose": "guard",
                "guard_role": role,
                "country": country,
                "seller_type": seller,
                "price": float(price),
                "currency": currency,
                "location": city,
                "vaccinated": True,
                "neutered": False,
                "likes": 3 + i,
                "views": 20 + i * 4,
                "created_at": ts,
                "demo_seed": TAG,
            }
        )

    trainers = [
        {
            "name": "أحمد منصور",
            "title": "مدرب طاعة وسلوك — دمشق",
            "categories": ["obedience", "puppy", "behavior"],
            "pet_types": ["dog", "cat"],
            "experience_years": 8,
            "phone": "+963991200001",
            "city": "دمشق",
            "country": "SY",
            "bio": "برامج طاعة منزلية وإصلاح سلوك للكلاب والقطط. جلسات فردية وجماعية.",
            "image_url": IMG["t1"],
            "languages": ["ar", "en"],
            "price_from": 150000,
            "currency": "SYP",
            "serves_international": False,
            "rating_avg": 4.8,
            "rating_count": 42,
        },
        {
            "name": "K9 Shield Academy",
            "title": "تدريب حراسة وشرطة — دبي",
            "categories": ["guard", "service_dog", "obedience"],
            "pet_types": ["dog"],
            "experience_years": 15,
            "phone": "+971501234567",
            "city": "دبي",
            "country": "AE",
            "bio": "أكاديمية متخصصة بكلاب الحماية والوحدات الأمنية. برامج للشركات والجهات الرسمية.",
            "image_url": IMG["t2"],
            "languages": ["ar", "en"],
            "price_from": 2500,
            "currency": "AED",
            "serves_international": True,
            "rating_avg": 4.9,
            "rating_count": 120,
        },
        {
            "name": "Sara Al-Najjar",
            "title": "سلوك حيوانات أليفة — عمّان",
            "categories": ["behavior", "puppy", "obedience"],
            "pet_types": ["dog", "cat", "rabbit"],
            "experience_years": 6,
            "phone": "+962791234567",
            "city": "عمّان",
            "country": "JO",
            "bio": "استشارات سلوك عن بُعد وحضورياً. خبرة مع القلق والعدوانية والتدريب الإيجابي.",
            "image_url": IMG["t3"],
            "languages": ["ar", "en"],
            "price_from": 40,
            "currency": "USD",
            "serves_international": True,
            "rating_avg": 4.7,
            "rating_count": 65,
        },
        {
            "name": "Elite Canine TR",
            "title": "رشاقة وحراسة — إسطنبول",
            "categories": ["agility", "guard", "obedience"],
            "pet_types": ["dog"],
            "experience_years": 11,
            "phone": "+905551112233",
            "city": "إسطنبول",
            "country": "TR",
            "bio": "معسكرات تدريب دولية لكلاب العمل والحراسة مع شهادات تقييم.",
            "image_url": IMG["t4"],
            "languages": ["tr", "en", "ar"],
            "price_from": 80,
            "currency": "USD",
            "serves_international": True,
            "rating_avg": 4.6,
            "rating_count": 88,
        },
        {
            "name": "نورة الخطيب",
            "title": "تدريب جراء وقطط — الرياض",
            "categories": ["puppy", "obedience", "behavior"],
            "pet_types": ["dog", "cat"],
            "experience_years": 5,
            "phone": "+966501112233",
            "city": "الرياض",
            "country": "SA",
            "bio": "تأسيس الجراء والقطط المنزلية بأسلوب إيجابي مناسب للعائلات.",
            "image_url": IMG["t3"],
            "languages": ["ar"],
            "price_from": 200,
            "currency": "SAR",
            "serves_international": False,
            "rating_avg": 4.5,
            "rating_count": 31,
        },
    ]

    for i, t in enumerate(trainers):
        owner = owners[i % len(owners)]
        await db.trainers.insert_one(
            {
                "id": uid(),
                "user_id": owner["id"],
                **t,
                "location_text": t["city"],
                "is_public": True,
                "status": "active",
                "verified": True,
                "created_at": ts,
                "updated_at": ts,
                "demo_seed": TAG,
            }
        )

    print(
        {
            "guard_dogs": await db.pets.count_documents({"demo_seed": TAG, "purpose": "guard"}),
            "trainers": await db.trainers.count_documents({"demo_seed": TAG}),
        }
    )


if __name__ == "__main__":
    asyncio.run(main())
