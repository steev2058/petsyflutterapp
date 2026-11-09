#!/usr/bin/env python3
"""Fill Petsy with rich DEMO data so every feature can be exercised.

Idempotent via demo_seed=True / email prefixes. Does NOT delete real Aleef/directory data.
Default password for all demo accounts: DemoPetsy2026!
Primary tester (gets friends + chats): mustafa.joha001@gmail.com if present.
"""
from __future__ import annotations

import asyncio
import os
import uuid
from datetime import datetime, timedelta, timezone

import bcrypt
from motor.motor_asyncio import AsyncIOMotorClient

DEMO_PASSWORD = "DemoPetsy2026!"
DEMO_TAG = "demo_playground_2026_11"

# Stable Unsplash pet/product photos (free CDN)
IMG = {
    "dog1": "https://images.unsplash.com/photo-1552053831-71594a27632d?w=800&q=80",
    "dog2": "https://images.unsplash.com/photo-1587300003388-59208cc962c0?w=800&q=80",
    "dog3": "https://images.unsplash.com/photo-1517849845537-4d257902454a?w=800&q=80",
    "cat1": "https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba?w=800&q=80",
    "cat2": "https://images.unsplash.com/photo-1574158622682-e40e69881006?w=800&q=80",
    "cat3": "https://images.unsplash.com/photo-1592194996308-7b43878e84a6?w=800&q=80",
    "bird": "https://images.unsplash.com/photo-1552728089-57bdde30beb3?w=800&q=80",
    "food": "https://images.unsplash.com/photo-1589924691995-400dc9dac191?w=800&q=80",
    "toy": "https://images.unsplash.com/photo-1535294435445-d7249524ef2e?w=800&q=80",
    "litter": "https://images.unsplash.com/photo-1548199973-03cce0bbc87b?w=800&q=80",
    "shampoo": "https://images.unsplash.com/photo-1620916567796-1c3c1f0f0f0f?w=800&q=80",  # may 404 — use safer
    "collar": "https://images.unsplash.com/photo-1601758228041-f3b2795255f1?w=800&q=80",
    "cage": "https://images.unsplash.com/photo-1450778869180-41d0601e046e?w=800&q=80",
    "meds": "https://images.unsplash.com/photo-1584308666744-24d5c474f2ae?w=800&q=80",
    "community1": "https://images.unsplash.com/photo-1548198611-0f4a4c3f0f0f?w=800&q=80",
    "park": "https://images.unsplash.com/photo-1548199973-03cce0bbc87b?w=800&q=80",
    "avatar1": "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&q=80",
    "avatar2": "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&q=80",
    "avatar3": "https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=200&q=80",
    "avatar4": "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=200&q=80",
    "avatar5": "https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=200&q=80",
}

# Fix shaky shampoo URL
IMG["shampoo"] = "https://images.unsplash.com/photo-1556228578-0d85b1a4d571?w=800&q=80"
IMG["community1"] = "https://images.unsplash.com/photo-1450778869180-41d0601e046e?w=800&q=80"
IMG["community2"] = "https://images.unsplash.com/photo-1587300003388-59208cc962c0?w=800&q=80"
IMG["community3"] = "https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba?w=800&q=80"
IMG["lost"] = "https://images.unsplash.com/photo-1574158622682-e40e69881006?w=800&q=80"
IMG["found"] = "https://images.unsplash.com/photo-1517849845537-4d257902454a?w=800&q=80"


def now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def uid() -> str:
    return str(uuid.uuid4())


async def upsert_user(db, *, email: str, name: str, phone: str, city: str, avatar: str | None = None) -> dict:
    existing = await db.users.find_one({"email": email})
    if existing:
        await db.users.update_one(
            {"id": existing["id"]},
            {
                "$set": {
                    "name": name,
                    "phone": phone,
                    "city": city,
                    "avatar": avatar,
                    "is_verified": True,
                    "password_hash": hash_password(DEMO_PASSWORD),
                    "demo_seed": DEMO_TAG,
                    "updated_at": now(),
                }
            },
        )
        existing = await db.users.find_one({"id": existing["id"]})
        return existing

    user = {
        "id": uid(),
        "email": email,
        "name": name,
        "username": email.split("@")[0].replace(".", "_")[:20],
        "phone": phone,
        "city": city,
        "avatar": avatar,
        "password_hash": hash_password(DEMO_PASSWORD),
        "is_verified": True,
        "is_admin": False,
        "role": "user",
        "language": "ar",
        "created_at": now(),
        "demo_seed": DEMO_TAG,
    }
    await db.users.insert_one(user)
    await db.user_settings.update_one(
        {"user_id": user["id"]},
        {
            "$set": {
                "user_id": user["id"],
                "push_notifications": True,
                "allow_friend_requests": "everyone",
                "allow_direct_messages": "everyone",
                "chat_sound": True,
                "chat_preview": True,
                "language": "ar",
                "updated_at": now(),
                "created_at": now(),
            }
        },
        upsert=True,
    )
    return user


async def replace_demo(db, collection: str, docs: list[dict]):
    await db[collection].delete_many({"demo_seed": DEMO_TAG})
    if docs:
        await db[collection].insert_many(docs)


async def main() -> None:
    db = AsyncIOMotorClient(os.environ["MONGO_URL"])[os.environ.get("DB_NAME", "petsy")]
    ts = now()

    # ---- Users ----
    demo_people = [
        ("demo.nour@petsy.app", "نور الحسن", "+963991100001", "دمشق", IMG["avatar1"]),
        ("demo.rami@petsy.app", "رامي خليل", "+963991100002", "دمشق", IMG["avatar2"]),
        ("demo.lina@petsy.app", "لينا العلي", "+963991100003", "حلب", IMG["avatar3"]),
        ("demo.omar@petsy.app", "عمر صالح", "+963991100004", "حمص", IMG["avatar4"]),
        ("demo.sara@petsy.app", "سارة دياب", "+963991100005", "اللاذقية", IMG["avatar5"]),
        ("demo.shop@petsy.app", "متجر بيتسي التجريبي", "+963991100099", "دمشق", None),
    ]
    users = []
    for email, name, phone, city, avatar in demo_people:
        users.append(await upsert_user(db, email=email, name=name, phone=phone, city=city, avatar=avatar))
    by_email = {u["email"]: u for u in users}
    nour, rami, lina, omar, sara, shop = [by_email[e] for e, *_ in demo_people]

    primary = await db.users.find_one({"email": "mustafa.joha001@gmail.com"})
    friend_targets = [nour, rami, lina, omar, sara]
    if primary:
        # friendships with primary tester
        await db.friendships.delete_many({"demo_seed": DEMO_TAG})
        for other in friend_targets:
            await db.friendships.insert_one(
                {
                    "id": uid(),
                    "users": [primary["id"], other["id"]],
                    "created_at": ts,
                    "demo_seed": DEMO_TAG,
                }
            )
        # one pending request from a stranger-ish (omar already friend — use shop)
        await db.friend_requests.delete_many({"demo_seed": DEMO_TAG})
        await db.friend_requests.insert_one(
            {
                "id": uid(),
                "from_user_id": shop["id"],
                "to_user_id": primary["id"],
                "message": "مرحباً! حساب تجريبي لمتجر Petsy — اقبلني لتجربة طلبات الصداقة",
                "status": "pending",
                "created_at": ts,
                "updated_at": ts,
                "demo_seed": DEMO_TAG,
            }
        )

    # Also friend among demos
    for a, b in [(nour, rami), (nour, lina), (rami, omar), (lina, sara)]:
        exists = await db.friendships.find_one({"users": {"$all": [a["id"], b["id"]]}})
        if not exists:
            await db.friendships.insert_one(
                {"id": uid(), "users": [a["id"], b["id"]], "created_at": ts, "demo_seed": DEMO_TAG}
            )

    # ---- Products (replace previous image-less English seed names if present) ----
    products = [
        ("طعام كلاب بريميوم 3كغ", "food", "dog", "Royal Canin", 185000, 210000, IMG["food"], 40),
        ("طعام قطط رطب ×12", "food", "cat", "Whiskas", 95000, None, IMG["food"], 80),
        ("لعبة مضغ للكلاب", "toys", "dog", "Kong", 45000, None, IMG["toy"], 30),
        ("عمود خدش للقطط", "toys", "cat", "Petsy", 120000, 140000, IMG["toy"], 18),
        ("شامبو حيوانات لطيف", "shampoo", "all", "Pet Head", 38000, None, IMG["shampoo"], 50),
        ("طوق كلاب متوسط", "accessories", "dog", "Flexi", 55000, None, IMG["collar"], 60),
        ("صندوق رمل قطط", "accessories", "cat", "Petsy", 75000, None, IMG["litter"], 25),
        ("قفص طيور كبير", "cages", "bird", "Petsy", 220000, None, IMG["cage"], 8),
        ("دواء براغيث", "medicine", "all", "Frontline", 65000, None, IMG["meds"], 70),
        ("فيتامينات حيوانات", "medicine", "all", "PetVit", 48000, None, IMG["meds"], 35),
        ("رمل قطط 10لتر", "accessories", "cat", "Ever Clean", 52000, None, IMG["litter"], 45),
        ("حزام مشي كلاب", "accessories", "dog", "Flexi", 42000, None, IMG["collar"], 28),
    ]
    await db.products.delete_many({"demo_seed": DEMO_TAG})
    # Patch older English seed products that have no image
    legacy_images = [IMG["food"], IMG["toy"], IMG["litter"], IMG["collar"], IMG["meds"], IMG["cage"], IMG["shampoo"]]
    legacy = await db.products.find({"$or": [{"image": None}, {"image": ""}]}).to_list(100)
    for i, p in enumerate(legacy):
        await db.products.update_one(
            {"id": p["id"]},
            {"$set": {"image": legacy_images[i % len(legacy_images)], "updated_at": ts}},
        )

    for name, cat, pet, brand, price, original, image, qty in products:
        doc = {
            "id": uid(),
            "name": name,
            "category": cat,
            "description": f"منتج تجريبي للاختبار — {name}. مناسب لتجربة المتجر والسلة والدفع عند الاستلام.",
            "price": float(price),
            "original_price": float(original) if original else None,
            "image": image,
            "brand": brand,
            "pet_type": pet,
            "in_stock": True,
            "quantity": qty,
            "rating": 4.5,
            "created_at": ts,
            "demo_seed": DEMO_TAG,
        }
        await db.products.insert_one(doc)

    # ---- Adoption / owned pets ----
    await db.pets.delete_many({"demo_seed": DEMO_TAG})
    adoption_pets = [
        ("ماكس", "dog", "Golden Retriever", "سنتان", "male", "دمشق", IMG["dog1"], nour, True, "ودود ومرِح، معتاد على الأطفال."),
        ("لونا", "cat", "Persian", "سنة", "female", "دمشق", IMG["cat1"], rami, True, "هادئة وتحب الحضن، ملقّحة بالكامل."),
        ("روكي", "dog", "German Shepherd", "3 سنوات", "male", "حلب", IMG["dog2"], lina, True, "مدرب جيداً، يحتاج عائلة نشيطة."),
        ("ميلو", "cat", "Siamese", "6 أشهر", "male", "دمشق", IMG["cat2"], omar, False, "صغير لعوب ويحب الألعاب."),
        ("بيلا", "dog", "Husky", "سنة ونصف", "female", "حمص", IMG["dog3"], sara, True, "عيون زرقاء، تحتاج مساحة للركض."),
        ("كوكي", "cat", "بلدي", "8 أشهر", "female", "اللاذقية", IMG["cat3"], nour, True, "أنقذت من الشارع وتعافت."),
        ("بيبو", "bird", "ببغاء", "سنتان", "male", "دمشق", IMG["bird"], rami, False, "يردد كلمات بسيطة، يحتاج قفص واسع."),
    ]
    pet_ids = {}
    for name, species, breed, age, gender, loc, image, owner, vacc, desc in adoption_pets:
        pid = uid()
        pet_ids[name] = pid
        await db.pets.insert_one(
            {
                "id": pid,
                "owner_id": owner["id"],
                "name": name,
                "species": species,
                "breed": breed,
                "age": age,
                "gender": gender,
                "color": None,
                "weight": None,
                "description": f"{desc}\n\n[بيانات تجريبية — {DEMO_TAG}]",
                "image": image,
                "status": "for_adoption",
                "price": None,
                "location": loc,
                "vaccinated": vacc,
                "neutered": False,
                "likes": 3,
                "views": 12,
                "created_at": ts - timedelta(hours=len(pet_ids)),
                "demo_seed": DEMO_TAG,
            }
        )

    # Guard dogs for sale
    guard_dogs = [
        ("شبح", "German Shepherd", "سنتان", "male", "دمشق", 2500000, IMG["dog2"], nour, "مدرب حراسة وحماية منزل."),
        ("رعد", "Rottweiler", "3 سنوات", "male", "حلب", 3200000, IMG["dog1"], rami, "كلب حراسة قوي للحراسة الليلية."),
        ("فهد", "Malinois", "سنة ونصف", "male", "دمشق", 4500000, IMG["dog3"], omar, "مالي نوى مدرّب للمنشآت."),
        ("نايت", "Doberman", "سنتان", "male", "اللاذقية", 3000000, IMG["dog1"], lina, "دوبيرمان سريع الاستجابة."),
    ]
    for name, breed, age, gender, loc, price, image, owner, desc in guard_dogs:
        await db.pets.insert_one(
            {
                "id": uid(),
                "owner_id": owner["id"],
                "name": name,
                "species": "dog",
                "breed": breed,
                "age": age,
                "gender": gender,
                "description": f"{desc}\n\n[بيانات تجريبية — {DEMO_TAG}]",
                "image": image,
                "status": "for_sale",
                "purpose": "guard",
                "price": float(price),
                "location": loc,
                "vaccinated": True,
                "neutered": False,
                "likes": 4,
                "views": 15,
                "created_at": ts,
                "demo_seed": DEMO_TAG,
            }
        )

    # Owned pets for primary user (health / my pets)
    if primary:
        for name, species, breed, age, gender, image in [
            ("شموس", "cat", "شيرازي", "3 سنوات", "female", IMG["cat1"]),
            ("زين", "dog", "هجين", "4 سنوات", "male", IMG["dog1"]),
        ]:
            await db.pets.insert_one(
                {
                    "id": uid(),
                    "owner_id": primary["id"],
                    "name": name,
                    "species": species,
                    "breed": breed,
                    "age": age,
                    "gender": gender,
                    "description": "حيوانك التجريبي لتجربة سجل الصحة ومواعيدي.",
                    "image": image,
                    "status": "owned",
                    "location": "دمشق",
                    "vaccinated": True,
                    "neutered": True,
                    "likes": 0,
                    "views": 0,
                    "created_at": ts,
                    "demo_seed": DEMO_TAG,
                }
            )

    # ---- Lost & found ----
    await db.lost_found.delete_many({"demo_seed": DEMO_TAG})
    lost_docs = [
        {
            "id": uid(),
            "user_id": nour["id"],
            "type": "lost",
            "pet_species": "cat",
            "breed": "بلدي",
            "color": "برتقالي",
            "description": "قطة برتقالية ضاعت قرب المزة. عليها طوق أحمر. [تجريبي]",
            "last_seen_location": "دمشق — المزة فيلات غربية",
            "last_seen_date": (ts - timedelta(days=1)).date().isoformat(),
            "contact_phone": nour["phone"],
            "image": IMG["lost"],
            "lat": 33.505,
            "lng": 36.258,
            "status": "active",
            "created_at": ts - timedelta(days=1),
            "demo_seed": DEMO_TAG,
        },
        {
            "id": uid(),
            "user_id": rami["id"],
            "type": "found",
            "pet_species": "dog",
            "breed": "هجين",
            "color": "أسود",
            "description": "كلب صغير أسود وجدناه قرب باب توما، وديع. [تجريبي]",
            "last_seen_location": "دمشق — باب توما",
            "last_seen_date": ts.date().isoformat(),
            "contact_phone": rami["phone"],
            "image": IMG["found"],
            "lat": 33.512,
            "lng": 36.315,
            "status": "active",
            "created_at": ts,
            "demo_seed": DEMO_TAG,
        },
        {
            "id": uid(),
            "user_id": lina["id"],
            "type": "lost",
            "pet_species": "dog",
            "breed": "هسكي",
            "color": "رمادي",
            "description": "ضاع في سيف الدولة بحلب. يستجيب لاسم نمر. [تجريبي]",
            "last_seen_location": "حلب — سيف الدولة",
            "last_seen_date": (ts - timedelta(days=2)).date().isoformat(),
            "contact_phone": lina["phone"],
            "image": IMG["dog3"],
            "lat": 36.20,
            "lng": 37.15,
            "status": "active",
            "created_at": ts - timedelta(days=2),
            "demo_seed": DEMO_TAG,
        },
    ]
    await db.lost_found.insert_many(lost_docs)

    # ---- Community ----
    await db.community.delete_many({"demo_seed": DEMO_TAG})
    posts = [
        (nour, "story", "أول نزهة لشموس في الحديقة 🐾", "اليوم طلعت مع قطتي وكانت مرتاحة مع الناس. أي نصائح لنزهة أول مرة؟", IMG["community1"]),
        (rami, "tip", "نصيحة: انتقال تدريجي للطعام", "لما تغيّروا نوع الأكل، اخلطوا القديم مع الجديد على أسبوع حتى ما يصير إسهال.", None),
        (lina, "question", "وين أفضل عيادة بحلب للطوارئ؟", "كلبي تعبان فجأة بالليل — أي عيادة بتفتح متأخر؟", None),
        (omar, "story", "تبني ناجح بعد أسبوعين ❤️", "أخذنا ميلو من التطبيق وصار جزء من العيلة. شكراً Petsy!", IMG["community3"]),
        (sara, "tip", "تنظيف الأذن بأمان", "لا تدخلوا أعواد قطن بعمق. استخدموا محلول بيطري وبقطعة شاش فقط.", IMG["community2"]),
        (nour, "question", "هل الرمل المعطّر مضر؟", "قطتي تعطس من الرمل المعطّر — شو بديل منيح ورخيص بدمشق؟", None),
        (rami, "sponsorship", "حملة طعام لملجأ محلي", "نجمع أكياس طعام جاف لـ 20 كلب هذا الأسبوع. من يحب يساهم؟", IMG["food"]),
        (lina, "story", "تدريب الجرو على المشى", "أول أسبوع كان صعب، بعدين صار يمشي جنب الساق. الصبر أهم شي.", IMG["dog2"]),
    ]
    for i, (user, ptype, title, content, image) in enumerate(posts):
        await db.community.insert_one(
            {
                "id": uid(),
                "user_id": user["id"],
                "user_name": user["name"],
                "user_avatar": user.get("avatar"),
                "type": ptype,
                "title": title,
                "content": content + f"\n\n[منشور تجريبي]",
                "image": image,
                "likes": 5 + i,
                "comments_count": i % 3,
                "comments": [],
                "created_at": ts - timedelta(hours=i * 5),
                "demo_seed": DEMO_TAG,
            }
        )

    # ---- Conversations + messages ----
    await db.conversations.delete_many({"demo_seed": DEMO_TAG})
    await db.chat_messages.delete_many({"demo_seed": DEMO_TAG})
    chat_pairs = []
    if primary:
        chat_pairs = [
            (primary, nour, ["مرحبا نور! شفتِ منشور التبني", "أيوا ماكس لسا متاح 🐶", "تمام بدي أزور هالأسبوع"]),
            (primary, rami, ["شلونك رامي؟", "تمام، في عندي قطة للتبني لونا", "أرسلتلك التفاصيل بالتطبيق"]),
            (primary, lina, ["أهلا من حلب", "مرحبا! في عيادة قريبة بتنصح فيها؟", "جرّب د. يامن خشان"]),
        ]
    chat_pairs += [
        (nour, rami, ["صباح الخير", "صباح النور! رايحين الحديقة؟", "يلا الساعة 5"]),
        (lina, sara, ["وصل الطعم؟", "أيوا والقطط فرحت 😍"]),
    ]
    for a, b, lines in chat_pairs:
        cid = uid()
        msgs = []
        t0 = ts - timedelta(minutes=30)
        for idx, text in enumerate(lines):
            sender = a["id"] if idx % 2 == 0 else b["id"]
            mid = uid()
            created = t0 + timedelta(minutes=idx * 3)
            msgs.append(
                {
                    "id": mid,
                    "conversation_id": cid,
                    "sender_id": sender,
                    "content": text,
                    "image_url": None,
                    "created_at": created,
                    "is_read": idx < len(lines) - 1,
                    "demo_seed": DEMO_TAG,
                }
            )
        await db.conversations.insert_one(
            {
                "id": cid,
                "participants": [a["id"], b["id"]],
                "pet_id": pet_ids.get("ماكس") if a == (primary or nour) and b == nour else None,
                "last_message": lines[-1],
                "last_message_time": msgs[-1]["created_at"],
                "created_at": t0,
                "demo_seed": DEMO_TAG,
            }
        )
        await db.chat_messages.insert_many(msgs)

    # ---- Notifications for primary ----
    if primary:
        await db.notifications.delete_many({"demo_seed": DEMO_TAG, "user_id": primary["id"]})
        notifs = [
            ("friend_request", "طلب صداقة جديد", "متجر بيتسي التجريبي أرسل لك طلب صداقة"),
            ("message", "رسالة جديدة", "نور الحسن: أيوا ماكس لسا متاح 🐶"),
            ("system", "مرحباً بتجربة Petsy", "هذه إشعارات تجريبية لتجربة الشاشة"),
            ("adoption", "اهتمام بحيوانك", "شخص مهتم بتبني — بيانات تجريبية"),
        ]
        for i, (ntype, title, body) in enumerate(notifs):
            await db.notifications.insert_one(
                {
                    "id": uid(),
                    "user_id": primary["id"],
                    "title": title,
                    "body": body,
                    "type": ntype,
                    "data": {},
                    "is_read": False,
                    "created_at": ts - timedelta(minutes=i * 10),
                    "updated_at": ts,
                    "demo_seed": DEMO_TAG,
                }
            )

    # ---- Appointments sample for primary with a public vet ----
    if primary:
        vet = await db.vet_profiles.find_one({"status": "active", "verified": True, "is_public": True})
        if vet:
            await db.appointments.delete_many({"demo_seed": DEMO_TAG})
            day = (ts + timedelta(days=2)).date().isoformat()
            await db.appointments.insert_one(
                {
                    "id": uid(),
                    "user_id": primary["id"],
                    "vet_id": vet["id"],
                    "pet_id": None,
                    "date": day,
                    "time": "16:00",
                    "reason": "فحص دوري (موعد تجريبي)",
                    "status": "confirmed",
                    "notes": "بيانات تجريبية",
                    "fee": 5,
                    "payment_status": "pay_at_clinic",
                    "created_at": ts,
                    "demo_seed": DEMO_TAG,
                }
            )

    summary = {
        "demo_password": DEMO_PASSWORD,
        "demo_users": [e for e, *_ in demo_people],
        "primary_linked": bool(primary),
        "products": await db.products.count_documents({"demo_seed": DEMO_TAG}),
        "pets_adoption": await db.pets.count_documents({"demo_seed": DEMO_TAG, "status": "for_adoption"}),
        "community": await db.community.count_documents({"demo_seed": DEMO_TAG}),
        "lost_found": await db.lost_found.count_documents({"demo_seed": DEMO_TAG}),
        "friendships": await db.friendships.count_documents({"demo_seed": DEMO_TAG}),
        "conversations": await db.conversations.count_documents({"demo_seed": DEMO_TAG}),
        "chat_messages": await db.chat_messages.count_documents({"demo_seed": DEMO_TAG}),
        "notifications": await db.notifications.count_documents({"demo_seed": DEMO_TAG}),
    }
    print(summary)


if __name__ == "__main__":
    asyncio.run(main())
