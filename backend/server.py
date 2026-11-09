from fastapi import FastAPI, APIRouter, HTTPException, Depends, status, UploadFile, File, WebSocket, WebSocketDisconnect, Body, Request, Query
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.encoders import jsonable_encoder
from fastapi.staticfiles import StaticFiles
from dotenv import load_dotenv
from starlette.middleware.cors import CORSMiddleware
from starlette.responses import JSONResponse
from motor.motor_asyncio import AsyncIOMotorClient
import asyncio
import httpx
import os
import time
import logging
from pathlib import Path
from pydantic import BaseModel, Field, EmailStr, field_validator, model_validator
from typing import List, Optional, Dict, Set, Any
import uuid
from datetime import datetime, timedelta
import bcrypt
import jwt
import random
import re
import secrets
import hmac
import base64
import smtplib
from email.message import EmailMessage
from email.utils import formataddr
from html import escape as html_escape

ROOT_DIR = Path(__file__).parent
load_dotenv(ROOT_DIR / '.env')


def env_flag(name: str, default: bool = False) -> bool:
    return os.environ.get(name, str(default)).strip().lower() in {"1", "true", "yes", "on"}


ENVIRONMENT = os.environ.get("ENVIRONMENT", "development").strip().lower()
IS_PRODUCTION = ENVIRONMENT == "production"

# MongoDB connection
mongo_url = os.environ['MONGO_URL']
client = AsyncIOMotorClient(mongo_url)
db = client[os.environ.get('DB_NAME', 'petsy_db')]

# JWT Configuration
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_DAYS = 30

# Secrets that shipped in source control or public docs must never be usable.
KNOWN_WEAK_SECRETS = {
    "petsy-secret-key-2025",
    "change-me-in-local-env",
    "changeme",
    "secret",
}


def _load_jwt_secret() -> str:
    value = (os.environ.get("JWT_SECRET") or "").strip()
    if not value:
        raise RuntimeError(
            "JWT_SECRET is not set. Generate one with: python -c \"import secrets; print(secrets.token_urlsafe(48))\""
        )
    if value in KNOWN_WEAK_SECRETS or len(value) < 32:
        message = "JWT_SECRET is weak or a known default value; it must be a random string of at least 32 characters."
        if IS_PRODUCTION:
            raise RuntimeError(message)
        logging.getLogger(__name__).warning("%s Continuing because ENVIRONMENT=%s.", message, ENVIRONMENT)
    return value


SECRET_KEY = _load_jwt_secret()

# Returning verification/reset codes in API responses is a dev-only convenience.
ALLOW_INSECURE_AUTH_CODE_RESPONSE = env_flag("ALLOW_INSECURE_AUTH_CODE_RESPONSE") and not IS_PRODUCTION

# The seed endpoint creates a known-password admin, so it stays off unless opted in.
SEED_ENABLED = env_flag("SEED_ENABLED") and not IS_PRODUCTION
SEED_ADMIN_EMAIL = os.environ.get("SEED_ADMIN_EMAIL", "admin@petsy.com").strip()
SEED_ADMIN_PASSWORD = os.environ.get("SEED_ADMIN_PASSWORD", "").strip()

ALLOWED_ORIGINS = [o.strip() for o in os.environ.get("ALLOWED_ORIGINS", "").split(",") if o.strip()]
if not ALLOWED_ORIGINS:
    if IS_PRODUCTION:
        raise RuntimeError("ALLOWED_ORIGINS must list the exact frontend origins when ENVIRONMENT=production.")
    ALLOWED_ORIGINS = [
        "http://localhost:3000",
        "http://localhost:8081",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:8081",
    ]

# Create the main app
app = FastAPI(title="Petsy API", version="1.0.0")

# Create a router with the /api prefix
api_router = APIRouter(prefix="/api")

security = HTTPBearer()
security_optional = HTTPBearer(auto_error=False)

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# ========================= RATE LIMITING =========================

# In-process sliding window. Adequate for a single uvicorn worker; move the
# counters to Redis before scaling horizontally or the limits become per-worker.
_rate_limit_hits: Dict[str, List[float]] = {}
_RATE_LIMIT_MAX_KEYS = 20000


def client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def rate_limit(bucket: str, limit: int, window_seconds: int):
    """Reject a caller that exceeds `limit` requests per `window_seconds`."""

    async def _guard(request: Request) -> None:
        now = time.monotonic()
        key = f"{bucket}:{client_ip(request)}"
        hits = [t for t in _rate_limit_hits.get(key, []) if now - t < window_seconds]

        if len(hits) >= limit:
            retry_after = int(window_seconds - (now - hits[0])) + 1
            _rate_limit_hits[key] = hits
            raise HTTPException(
                status_code=429,
                detail=error_detail("RATE_LIMITED", "Too many requests. Please try again later."),
                headers={"Retry-After": str(retry_after)},
            )

        hits.append(now)
        _rate_limit_hits[key] = hits

        if len(_rate_limit_hits) > _RATE_LIMIT_MAX_KEYS:
            for stale_key in [k for k, v in _rate_limit_hits.items() if not v or now - v[-1] > window_seconds]:
                _rate_limit_hits.pop(stale_key, None)

    return _guard


# ========================= REALTIME CHAT (WEBSOCKET) =========================

class ChatConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, Set[WebSocket]] = {}

    async def connect(self, user_id: str, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.setdefault(user_id, set()).add(websocket)

    def disconnect(self, user_id: str, websocket: WebSocket):
        if user_id in self.active_connections:
            self.active_connections[user_id].discard(websocket)
            if not self.active_connections[user_id]:
                del self.active_connections[user_id]

    def is_online(self, user_id: str) -> bool:
        return user_id in self.active_connections and len(self.active_connections[user_id]) > 0

    def online_user_ids(self) -> List[str]:
        return list(self.active_connections.keys())

    async def send_user_event(self, user_id: str, event: Dict[str, Any]):
        sockets = list(self.active_connections.get(user_id, set()))
        stale: List[WebSocket] = []
        encoded_event = jsonable_encoder(event)
        for ws in sockets:
            try:
                await ws.send_json(encoded_event)
            except Exception:
                stale.append(ws)
        for ws in stale:
            self.disconnect(user_id, ws)

    async def broadcast_event(self, event: Dict[str, Any]):
        users = list(self.active_connections.keys())
        for uid in users:
            await self.send_user_event(uid, event)

chat_ws_manager = ChatConnectionManager()

async def notify_conversation_participants(conversation_id: str, event_type: str, payload: Dict[str, Any]):
    conversation = await db.conversations.find_one({"id": conversation_id})
    if not conversation:
        return
    participants = conversation.get("participants", [])
    event = {
        "type": event_type,
        "conversation_id": conversation_id,
        "payload": payload,
        "timestamp": datetime.utcnow().isoformat(),
    }
    for user_id in participants:
        await chat_ws_manager.send_user_event(user_id, event)

async def user_is_conversation_participant(user_id: str, conversation_id: str) -> bool:
    conversation = await db.conversations.find_one({"id": conversation_id, "participants": user_id})
    return conversation is not None

async def create_notification(user_id: str, title: str, body: str, notif_type: str = "system", data: Optional[dict] = None):
    if not user_id:
        return
    await db.notifications.insert_one({
        "id": str(uuid.uuid4()),
        "user_id": user_id,
        "title": title,
        "body": body,
        "type": notif_type,
        "data": data or {},
        "is_read": False,
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow(),
    })
    spawn_background(send_push_to_user(user_id, title, body, notif_type, data or {}))

async def create_notifications_for_admins(title: str, body: str, notif_type: str = "admin", data: Optional[dict] = None):
    admins = await db.users.find({"$or": [{"is_admin": True}, {"role": "admin"}]}).to_list(500)
    for admin in admins:
        await create_notification(admin.get("id"), title, body, notif_type, data)

# ========================= PUSH (FCM HTTP v1) =========================

FCM_SERVICE_ACCOUNT_FILE = os.environ.get("FCM_SERVICE_ACCOUNT_FILE", "").strip()
FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
PUSH_TOKENS_PER_USER = 10
_fcm_credentials = None
_fcm_lock = asyncio.Lock()
_background_tasks: Set[asyncio.Task] = set()

PUSH_DEFAULT_ROUTES = {
    "adoption": "/adoption-requests",
    "appointment": "/appointments",
    "friend_request": "/friends",
}
PUSH_CHANNELS = {"chat_message": "petsy_messages", "appointment": "petsy_appointments"}


def spawn_background(coro) -> None:
    """Run a coroutine without blocking the request; failures are logged, not raised."""
    task = asyncio.create_task(coro)
    _background_tasks.add(task)

    def _done(t: asyncio.Task) -> None:
        _background_tasks.discard(t)
        if not t.cancelled() and t.exception():
            logger.error("Background task failed: %r", t.exception())

    task.add_done_callback(_done)


async def _fcm_auth() -> Optional[tuple]:
    global _fcm_credentials
    if not FCM_SERVICE_ACCOUNT_FILE:
        return None
    async with _fcm_lock:
        if _fcm_credentials is None:
            from google.oauth2 import service_account
            _fcm_credentials = service_account.Credentials.from_service_account_file(
                FCM_SERVICE_ACCOUNT_FILE, scopes=[FCM_SCOPE]
            )
        if not _fcm_credentials.valid:
            from google.auth.transport.requests import Request as GoogleAuthRequest
            await asyncio.to_thread(_fcm_credentials.refresh, GoogleAuthRequest())
        return _fcm_credentials.token, _fcm_credentials.project_id


def _push_text_ar(notif_type: str, data: dict) -> Optional[tuple]:
    pet = data.get("pet_name") or ""
    who = data.get("from_user_name") or ""
    status = data.get("status")
    when = f"{data.get('date', '')} الساعة {data.get('time', '')}"
    texts = {
        ("adoption", "requested"): ("طلب تبنٍّ جديد", f"{who} يريد تبنّي {pet}"),
        ("adoption", "closed"): ("تم تبنّي الحيوان", f"وجد {pet} بيتًا مع عائلة أخرى"),
        ("adoption", "accepted"): ("تم قبول طلب التبني", f"تم قبول طلبك لتبنّي {pet}"),
        ("adoption", "declined"): ("تم رفض طلب التبني", f"تم رفض طلبك لتبنّي {pet}"),
        ("appointment", "requested"): ("طلب موعد جديد", f"{who} حجز موعدًا في {when}"),
        ("appointment", "confirmed"): ("تم قبول الموعد", f"تم قبول موعدك في {when}"),
        ("appointment", "cancelled"): ("تم رفض الموعد", f"رفضت العيادة موعدك في {when}"),
        ("appointment", "completed"): ("اكتملت الزيارة", f"تم تسجيل زيارتك في {when} كمكتملة"),
        ("friend_request", "pending"): ("طلب صداقة جديد", f"{who} أرسل لك طلب صداقة"),
        ("friend_request", "accepted"): ("تم قبول طلب الصداقة", f"قبل {who} طلب صداقتك"),
        ("friend_request", "rejected"): ("تحديث طلب الصداقة", f"رفض {who} طلب صداقتك"),
    }
    if (notif_type, status) in texts:
        return texts[(notif_type, status)]
    generic = {
        "care_request": "تم تحديث طلب الرعاية",
        "marketplace": "تحديث إعلانك في السوق",
        "role_request": "تحديث طلب الصلاحية",
        "vet_profile": "تحديث ملف الطبيب البيطري",
        "admin": "إشعار إداري",
    }
    if notif_type == "push_test":
        return "Petsy", "تم إرسال إشعار تجريبي"
    if notif_type in generic:
        return generic[notif_type], "افتح التطبيق لعرض التفاصيل"
    return None


async def _send_fcm(token: str, title: str, body: str, data: Dict[str, str], channel: Optional[str], tag: Optional[str]) -> None:
    auth = await _fcm_auth()
    if not auth:
        return
    access_token, project_id = auth
    android_notification = {k: v for k, v in {"channel_id": channel, "tag": tag}.items() if v}
    message = {
        "message": {
            "token": token,
            "notification": {"title": title[:200], "body": body[:500]},
            "data": data,
            "android": {"priority": "high", "notification": android_notification},
            "apns": {"payload": {"aps": {"sound": "default"}}},
        }
    }
    async with httpx.AsyncClient(timeout=10) as http:
        resp = await http.post(
            f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send",
            json=message,
            headers={"Authorization": f"Bearer {access_token}"},
        )
    if resp.status_code == 200:
        return
    text = resp.text
    if resp.status_code == 404 or "UNREGISTERED" in text or ("INVALID_ARGUMENT" in text and "registration token" in text):
        await db.device_tokens.delete_one({"token": token})
        logger.info("Removed stale FCM token")
        return
    logger.warning("FCM send failed (%s): %s", resp.status_code, text[:300])


async def send_push_to_user(
    user_id: str,
    title: str,
    body: str,
    notif_type: str,
    data: dict,
    texts_by_lang: Optional[Dict[str, tuple]] = None,
    tag: Optional[str] = None,
) -> None:
    """Deliver an FCM notification to every registered device of a user, in each device's language."""
    if not FCM_SERVICE_ACCOUNT_FILE or not user_id:
        return
    settings = await db.user_settings.find_one({"user_id": user_id}, {"push_notifications": 1})
    if settings and settings.get("push_notifications") is False:
        return
    devices = await db.device_tokens.find({"user_id": user_id, "provider": "fcm"}).sort("updated_at", -1).to_list(PUSH_TOKENS_PER_USER)
    if not devices:
        return

    payload = {k: str(v) for k, v in data.items() if isinstance(v, (str, int, float, bool))}
    payload["type"] = notif_type
    payload.setdefault("route", PUSH_DEFAULT_ROUTES.get(notif_type, "/notifications"))
    channel = PUSH_CHANNELS.get(notif_type)

    sends = []
    for device in devices:
        lang = device.get("language") or "en"
        localized = (texts_by_lang or {}).get(lang)
        if localized is None and lang == "ar" and texts_by_lang is None:
            localized = _push_text_ar(notif_type, data)
        push_title, push_body = localized or (title, body)
        sends.append(_send_fcm(device["token"], push_title, push_body, payload, channel, tag))
    results = await asyncio.gather(*sends, return_exceptions=True)
    for result in results:
        if isinstance(result, Exception):
            logger.warning("FCM send error: %r", result)


async def get_friend_ids_set(user_id: str) -> Set[str]:
    rows = await db.friendships.find({"users": user_id}).to_list(5000)
    result: Set[str] = set()
    for fr in rows:
        for uid in fr.get("users", []):
            if uid and uid != user_id:
                result.add(uid)
    return result

async def audit_admin_action(admin_user: dict, action: str, target_type: str, target_id: Optional[str] = None, payload: Optional[dict] = None):
    try:
        await db.admin_audit_logs.insert_one({
            "id": str(uuid.uuid4()),
            "admin_user_id": admin_user.get("id"),
            "admin_email": admin_user.get("email"),
            "action": action,
            "target_type": target_type,
            "target_id": target_id,
            "payload": payload or {},
            "created_at": datetime.utcnow(),
        })
    except Exception as e:
        logger.warning(f"Failed to write admin audit log: {e}")

# ========================= MODELS =========================

# User Models
class UserBase(BaseModel):
    email: EmailStr
    name: str
    phone: Optional[str] = None
    date_of_birth: Optional[str] = None
    city: Optional[str] = None
    bio: Optional[str] = None
    avatar: Optional[str] = None
    language: str = "en"

class UserCreate(BaseModel):
    email: EmailStr
    name: str
    password: str
    phone: Optional[str] = None

class UserLogin(BaseModel):
    email: EmailStr
    password: str


class SocialLoginRequest(BaseModel):
    provider: str = Field(pattern="^(google|facebook|instagram)$")
    provider_user_id: str = Field(min_length=1, max_length=128)
    email: Optional[EmailStr] = None
    name: Optional[str] = Field(default=None, max_length=120)
    avatar: Optional[str] = Field(default=None, max_length=1024)
    access_token: Optional[str] = Field(default=None, max_length=8192)


class ForgotPasswordRequest(BaseModel):
    email: EmailStr

class ResetPasswordRequest(BaseModel):
    email: EmailStr
    code: str
    new_password: str

class ResendVerificationRequest(BaseModel):
    email: EmailStr

class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str

class DeleteAccountRequest(BaseModel):
    password: Optional[str] = None

class User(UserBase):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    username: Optional[str] = None
    user_code: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    is_verified: bool = False
    is_admin: bool = False
    role: str = "user"  # user, admin
    verification_code: Optional[str] = None
    reset_code: Optional[str] = None
    reset_code_expires_at: Optional[datetime] = None

class UserResponse(BaseModel):
    id: str
    email: str
    name: str
    username: Optional[str] = None
    user_code: Optional[str] = None
    phone: Optional[str] = None
    city: Optional[str] = None
    bio: Optional[str] = None
    avatar: Optional[str] = None
    language: str
    is_verified: bool
    is_admin: bool = False
    role: str = "user"
    created_at: datetime

class UserUpdate(BaseModel):
    name: Optional[str] = None
    phone: Optional[str] = None
    date_of_birth: Optional[str] = None
    city: Optional[str] = None
    bio: Optional[str] = None
    avatar: Optional[str] = None
    language: Optional[str] = None

# Pet Models
GUARD_ROLES = {"home", "facility", "police", "military", "personal_protection"}
SELLER_TYPES = {"individual", "kennel", "security_company", "agency"}
TRAINER_CATEGORIES = {"obedience", "guard", "puppy", "agility", "behavior", "service_dog"}
TRAINER_PET_TYPES = {"dog", "cat", "bird", "rabbit", "other", "all"}


class PetBase(BaseModel):
    name: str
    species: str  # dog, cat, bird, etc.
    breed: Optional[str] = None
    age: Optional[str] = None
    gender: str  # male, female
    color: Optional[str] = None
    weight: Optional[float] = None
    description: Optional[str] = None
    image: Optional[str] = None
    status: str = "owned"  # owned, for_sale, for_adoption, lost, found
    # companion (default) | guard — used for guard-dog sale listings
    purpose: Optional[str] = None
    # home | facility | police | military | personal_protection
    guard_role: Optional[str] = None
    # ISO-ish country code: SY, AE, TR, JO, EG, IQ, LB, SA, QA, KW, OM, BH, other
    country: Optional[str] = None
    # individual | kennel | security_company | agency
    seller_type: Optional[str] = None
    price: Optional[float] = None
    currency: Optional[str] = None
    location: Optional[str] = None
    vaccinated: bool = False
    neutered: bool = False

class PetCreate(PetBase):
    pass

class Pet(PetBase):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    owner_id: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
    likes: int = 0
    views: int = 0

class PetUpdate(BaseModel):
    name: Optional[str] = None
    species: Optional[str] = None
    breed: Optional[str] = None
    age: Optional[str] = None
    gender: Optional[str] = None
    color: Optional[str] = None
    weight: Optional[float] = None
    description: Optional[str] = None
    image: Optional[str] = None
    status: Optional[str] = None
    purpose: Optional[str] = None
    guard_role: Optional[str] = None
    country: Optional[str] = None
    seller_type: Optional[str] = None
    price: Optional[float] = None
    currency: Optional[str] = None
    location: Optional[str] = None
    vaccinated: Optional[bool] = None
    neutered: Optional[bool] = None


class TrainerCreate(BaseModel):
    name: str
    title: Optional[str] = None
    categories: List[str] = []
    pet_types: List[str] = []
    experience_years: int = 0
    phone: Optional[str] = None
    city: Optional[str] = None
    country: Optional[str] = None
    location_text: Optional[str] = None
    bio: Optional[str] = None
    image_url: Optional[str] = None
    languages: List[str] = []
    price_from: Optional[float] = None
    currency: Optional[str] = "USD"
    serves_international: bool = False


class Trainer(TrainerCreate):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: Optional[str] = None
    rating_avg: float = 0.0
    rating_count: int = 0
    is_public: bool = True
    status: str = "active"
    verified: bool = True
    verification_notes: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

# Pet Health Record
# Veterinarian Models
class VetBase(BaseModel):
    name: str
    specialty: str  # dogs, cats, birds, all
    experience_years: int
    phone: str
    email: Optional[str] = None
    clinic_name: str
    address: str
    city: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    rating: float = 0.0
    reviews_count: int = 0
    image: Optional[str] = None
    available_hours: Optional[str] = None
    services: List[str] = []

class Vet(VetBase):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    created_at: datetime = Field(default_factory=datetime.utcnow)

# Product Models (Shop)
class ProductBase(BaseModel):
    name: str
    category: str  # food, medicine, toys, cages, shampoo, accessories
    description: Optional[str] = None
    price: float
    original_price: Optional[float] = None
    image: Optional[str] = None
    brand: Optional[str] = None
    pet_type: str  # dog, cat, bird, all
    in_stock: bool = True
    quantity: int = 0
    rating: float = 0.0

class Product(ProductBase):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    created_at: datetime = Field(default_factory=datetime.utcnow)

# Emergency Contact Models
class EmergencyContact(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    name: str
    type: str  # vet, clinic, rescue, shelter
    phone: str
    address: Optional[str] = None
    city: str
    is_24_hours: bool = False
    notes: Optional[str] = None

# Message Models
class MessageBase(BaseModel):
    receiver_id: str
    subject: str
    content: str
    pet_id: Optional[str] = None

class Message(MessageBase):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    sender_id: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
    is_read: bool = False

# Lost & Found
class LostFoundPost(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str
    type: str  # lost, found
    pet_species: str
    breed: Optional[str] = None
    color: Optional[str] = None
    description: str
    last_seen_location: str
    last_seen_date: str
    contact_phone: str
    image: Optional[str] = None
    lat: Optional[float] = Field(default=None, ge=-90, le=90)
    lng: Optional[float] = Field(default=None, ge=-180, le=180)
    status: str = "active"  # active, resolved
    resolved_at: Optional[datetime] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)

class LostFoundCreate(BaseModel):
    type: str
    pet_species: str
    breed: Optional[str] = None
    color: Optional[str] = None
    description: str
    last_seen_location: str
    last_seen_date: str
    contact_phone: str
    image: Optional[str] = None
    lat: Optional[float] = Field(default=None, ge=-90, le=90)
    lng: Optional[float] = Field(default=None, ge=-180, le=180)

# Community Post
class CommunityPost(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str
    user_name: str
    user_avatar: Optional[str] = None
    type: str  # question, story, tip, sponsorship
    title: str
    content: str
    image: Optional[str] = None
    likes: int = 0
    comments_count: int = 0
    created_at: datetime = Field(default_factory=datetime.utcnow)

class CommunityPostCreate(BaseModel):
    type: str
    title: str
    content: str
    image: Optional[str] = None

# Appointment
class Appointment(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str
    vet_id: str
    pet_id: Optional[str] = None
    date: str
    time: str
    reason: str
    status: str = "pending"  # pending, confirmed, completed, cancelled
    notes: Optional[str] = None
    # Always the current booking fee: payments charge APPOINTMENT_BOOKING_FEE, not a stored value.
    fee: float = Field(default_factory=lambda: APPOINTMENT_BOOKING_FEE)
    payment_method: Optional[str] = None
    payment_status: str = "unpaid"  # unpaid, pay_at_clinic, pending, paid
    payment_id: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)

class AppointmentCreate(BaseModel):
    vet_id: str
    pet_id: Optional[str] = None
    date: str
    time: str
    reason: str
    notes: Optional[str] = None

# Favorite
class Favorite(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str
    pet_id: str
    created_at: datetime = Field(default_factory=datetime.utcnow)

# Cart Item
class CartItem(BaseModel):
    product_id: str
    quantity: int = 1
    name: str
    price: float
    image: Optional[str] = None

# Order Models
class OrderItem(BaseModel):
    product_id: str
    name: str
    price: float
    quantity: int
    image: Optional[str] = None
    seller_user_id: Optional[str] = None

class Order(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str
    items: List[OrderItem]
    total: float
    status: str = "pending"  # pending, confirmed, shipped, delivered, cancelled
    shipping_address: str
    shipping_city: str
    shipping_phone: str
    payment_method: str = "cash_on_delivery"
    notes: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)

class OrderCreate(BaseModel):
    items: List[OrderItem]
    total: float
    shipping_address: str
    shipping_city: str
    shipping_phone: str
    payment_method: str = "cash_on_delivery"
    notes: Optional[str] = None
    points_used: int = 0  # Loyalty points to redeem

# Payment Models
class PaymentMethod(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str
    type: str  # stripe, paypal, shamcash
    card_last_four: Optional[str] = None
    card_brand: Optional[str] = None  # visa, mastercard
    is_default: bool = False
    created_at: datetime = Field(default_factory=datetime.utcnow)

class PaymentIntent(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str
    amount: float
    currency: str = "USD"
    payment_method: str  # stripe, paypal, shamcash, cash_on_delivery
    status: str = "pending"  # pending, processing, succeeded, failed, cancelled
    order_id: Optional[str] = None
    appointment_id: Optional[str] = None
    sponsorship_id: Optional[str] = None
    stripe_payment_intent_id: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)

SUPPORTED_PAYMENT_METHODS = {"stripe", "paypal", "shamcash", "cash_on_delivery"}


class PaymentRequest(BaseModel):
    """The client picks what to pay for and how, never the amount.

    Raw card data is deliberately absent: card details must go straight from the
    client to the payment provider's SDK so this server stays out of PCI scope.
    """
    payment_method: str
    order_id: Optional[str] = None
    appointment_id: Optional[str] = None
    sponsorship_id: Optional[str] = None
    points_to_use: int = Field(default=0, ge=0, le=1000000)

    @field_validator("payment_method")
    @classmethod
    def validate_method(cls, v: str) -> str:
        method = (v or "").strip().lower()
        if method not in SUPPORTED_PAYMENT_METHODS:
            raise ValueError(f"Unsupported payment method. Allowed: {', '.join(sorted(SUPPORTED_PAYMENT_METHODS))}")
        return method

    @model_validator(mode="after")
    def validate_single_target(self):
        targets = [self.order_id, self.appointment_id, self.sponsorship_id]
        if sum(1 for t in targets if t) != 1:
            raise ValueError("Provide exactly one of order_id, appointment_id or sponsorship_id")
        return self

# Loyalty Points Models
class LoyaltyPoints(BaseModel):
    user_id: str
    total_points: int = 0
    lifetime_points: int = 0
    tier: str = "bronze"  # bronze, silver, gold, platinum

class PointsTransaction(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str
    points: int  # positive for earned, negative for redeemed
    transaction_type: str  # earned, redeemed, bonus, expired
    description: str
    reference_id: Optional[str] = None  # order_id, appointment_id, etc.
    created_at: datetime = Field(default_factory=datetime.utcnow)

# Conversation & Chat
class ChatMessage(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    conversation_id: str
    sender_id: str
    content: str = ""
    image_url: Optional[str] = None
    reply_to_message_id: Optional[str] = None
    reply_to_content: Optional[str] = None
    reply_to_sender_id: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    is_read: bool = False

class Conversation(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    participants: List[str]  # user IDs
    pet_id: Optional[str] = None
    last_message: Optional[str] = None
    last_message_time: Optional[datetime] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)

class ConversationCreate(BaseModel):
    other_user_id: str
    pet_id: Optional[str] = None
    initial_message: str

# Map Location
class MapLocation(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    name: str
    type: str  # vet, clinic, shelter, pet_shop, park
    address: str
    city: str
    latitude: float
    longitude: float
    phone: Optional[str] = None
    rating: float = 0.0
    is_open_now: bool = False
    hours: Optional[str] = None
    image: Optional[str] = None

# Token Response
class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse

# ========================= HELPERS =========================

def error_detail(code: str, message: str) -> dict:
    """Standard API error payload.

    Frontend can use `code` for i18n, and display `message` as fallback.
    """
    return {"code": code, "message": message}

def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

def verify_password(password: str, hashed: str) -> bool:
    return bcrypt.checkpw(password.encode('utf-8'), hashed.encode('utf-8'))

def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(days=ACCESS_TOKEN_EXPIRE_DAYS)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def generate_verification_code() -> str:
    """Six digits from a CSPRNG: `random` is predictable and 4 digits is brute-forceable."""
    return f"{secrets.randbelow(1000000):06d}"


def codes_match(expected: Optional[str], provided: Optional[str]) -> bool:
    if not expected or not provided:
        return False
    return hmac.compare_digest(str(expected), str(provided).strip())

def normalize_username(value: str) -> str:
    clean = ''.join(ch for ch in (value or '').lower() if ch.isalnum() or ch in ['_', '.'])
    return clean[:24]

def generate_user_code(user_id: str) -> str:
    suffix = (user_id or '').replace('-', '')[-6:].upper()
    return f"PET-{suffix}"

def smtp_is_configured() -> bool:
    return bool(
        os.environ.get("SMTP_HOST")
        and os.environ.get("SMTP_PORT")
        and os.environ.get("SMTP_USERNAME")
        and os.environ.get("SMTP_PASSWORD")
        and os.environ.get("SMTP_FROM_EMAIL")
    )

def send_email_smtp(to_email: str, subject: str, body: str, html: Optional[str] = None) -> None:
    host = os.environ.get("SMTP_HOST")
    port = int(os.environ.get("SMTP_PORT", "587"))
    username = os.environ.get("SMTP_USERNAME")
    password = os.environ.get("SMTP_PASSWORD")
    from_email = os.environ.get("SMTP_FROM_EMAIL")
    from_name = os.environ.get("SMTP_FROM_NAME", "Petsy")

    if not all([host, port, username, password, from_email]):
        raise RuntimeError("SMTP is not fully configured")

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = formataddr((from_name, from_email))
    msg["To"] = to_email
    msg.set_content(body)
    if html:
        msg.add_alternative(html, subtype="html")

    # Port 465 speaks TLS from the first byte; other ports upgrade with STARTTLS.
    if port == 465:
        with smtplib.SMTP_SSL(host, port, timeout=20) as server:
            server.login(username, password)
            server.send_message(msg)
    else:
        with smtplib.SMTP(host, port, timeout=20) as server:
            server.starttls()
            server.login(username, password)
            server.send_message(msg)


AUTH_EMAIL_TEXT = {
    "verify": {
        "subject": "رمز التحقق من Petsy | Your Petsy verification code",
        "ar_title": "رمز التحقق من حسابك",
        "ar_body": "أدخل هذا الرمز في التطبيق لتفعيل حسابك.",
        "en_title": "Your verification code",
        "en_body": "Enter this code in the app to verify your account.",
    },
    "reset": {
        "subject": "رمز إعادة تعيين كلمة المرور | Your Petsy password reset code",
        "ar_title": "إعادة تعيين كلمة المرور",
        "ar_body": "أدخل هذا الرمز في التطبيق لتعيين كلمة مرور جديدة. ينتهي خلال 15 دقيقة.",
        "en_title": "Reset your password",
        "en_body": "Enter this code in the app to set a new password. It expires in 15 minutes.",
    },
}


async def send_auth_code_email(to_email: str, kind: str, code: str) -> None:
    t = AUTH_EMAIL_TEXT[kind]
    footer_ar = "إذا لم تطلب هذا الرمز، تجاهل هذه الرسالة."
    footer_en = "If you didn't request this code, you can ignore this email."
    text = (
        f"{t['ar_title']}\n{t['ar_body']}\n\n{code}\n\n{footer_ar}\n\n"
        f"---\n\n{t['en_title']}\n{t['en_body']}\n\n{code}\n\n{footer_en}\n"
    )
    safe_code = html_escape(code)
    code_box = (
        '<div style="font-size:30px;font-weight:700;letter-spacing:8px;color:#E8590C;'
        'background:#FFF4EC;border-radius:12px;padding:14px 0;text-align:center;margin:16px 0" dir="ltr">'
        f"{safe_code}</div>"
    )
    html = f"""<!doctype html><html><body style="margin:0;background:#F7F3EF;font-family:Tahoma,Arial,sans-serif">
<div style="max-width:480px;margin:24px auto;background:#fff;border-radius:16px;padding:24px">
<div style="font-size:22px;font-weight:700;color:#E8590C;text-align:center;margin-bottom:8px">Petsy</div>
<div dir="rtl" style="text-align:right">
<h2 style="margin:8px 0;color:#222">{t['ar_title']}</h2><p style="color:#555;line-height:1.7">{t['ar_body']}</p>
{code_box}<p style="color:#999;font-size:12px">{footer_ar}</p></div>
<hr style="border:none;border-top:1px solid #eee;margin:20px 0">
<div dir="ltr" style="text-align:left">
<h2 style="margin:8px 0;color:#222">{t['en_title']}</h2><p style="color:#555;line-height:1.6">{t['en_body']}</p>
{code_box}<p style="color:#999;font-size:12px">{footer_en}</p></div>
</div></body></html>"""
    await asyncio.to_thread(send_email_smtp, to_email, t["subject"], text, html)

async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)) -> dict:
    try:
        token = credentials.credentials
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token")
        user = await db.users.find_one({"id": user_id})
        if not user:
            raise HTTPException(status_code=401, detail="User not found")
        return user
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")

async def get_current_user_optional(credentials: Optional[HTTPAuthorizationCredentials] = Depends(security_optional)) -> Optional[dict]:
    if not credentials:
        return None
    try:
        token = credentials.credentials
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = payload.get("sub")
        if not user_id:
            return None
        return await db.users.find_one({"id": user_id})
    except Exception:
        return None

ALLOWED_ROLES = {"user", "admin", "vet", "market_owner", "care_clinic"}
VET_PROFILE_STATUSES = {"draft", "pending_verification", "active", "suspended", "rejected"}
VET_PET_TYPES = {"dogs", "cats", "birds", "all"}

async def get_admin_user(current_user: dict = Depends(get_current_user)) -> dict:
    """Verify user has admin privileges"""
    if not current_user.get("is_admin", False) and current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")
    return current_user

def require_roles(*roles: str):
    async def _guard(current_user: dict = Depends(get_current_user)) -> dict:
        role = (current_user.get("role") or "user").strip()
        if role not in roles and not current_user.get("is_admin", False):
            raise HTTPException(status_code=403, detail="Access denied for this role")
        return current_user
    return _guard


def _vet_profile_defaults(user: Optional[dict] = None) -> dict:
    user = user or {}
    return {
        "name": user.get("name") or "",
        "specialty": "",
        "experience_years": 0,
        "phone": user.get("phone") or "",
        "city": user.get("city") or "",
        "location_text": "",
        "image_url": user.get("avatar") or "",
        "pet_types_supported": [],
        "rating_avg": 0,
        "rating_count": 0,
        "is_public": False,
        "status": "draft",
        "verified": False,
        "verification_notes": None,
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow(),
    }


def _normalize_pet_types(values: Any) -> List[str]:
    if not isinstance(values, list):
        return []
    out: List[str] = []
    for v in values:
        item = str(v or "").strip().lower()
        if item in VET_PET_TYPES and item not in out:
            out.append(item)
    return out


def _serialize_doc(row: Optional[dict]) -> Optional[dict]:
    if not row:
        return None
    return {k: v for k, v in row.items() if k != "_id"}


async def ensure_vet_profile(user_id: str, *, user: Optional[dict] = None) -> dict:
    if not user_id:
        raise HTTPException(status_code=400, detail="user_id is required")

    existing = await db.vet_profiles.find_one({"user_id": user_id})
    if existing:
        patch = {"updated_at": datetime.utcnow()}
        if not existing.get("name") and user and user.get("name"):
            patch["name"] = user.get("name")
        if not existing.get("phone") and user and user.get("phone"):
            patch["phone"] = user.get("phone")
        if not existing.get("city") and user and user.get("city"):
            patch["city"] = user.get("city")
        if patch:
            await db.vet_profiles.update_one({"id": existing["id"]}, {"$set": patch})
            existing.update(patch)
        return existing

    user = user or await db.users.find_one({"id": user_id}) or {}
    legacy = await db.vets.find_one({"$or": [{"user_id": user_id}, {"id": user_id}, {"email": user.get("email")}]})

    row = {
        "id": str(uuid.uuid4()),
        "user_id": user_id,
        **_vet_profile_defaults(user),
    }

    if legacy:
        row.update({
            "name": legacy.get("name") or row["name"],
            "specialty": legacy.get("specialty") or row["specialty"],
            "experience_years": int(legacy.get("experience_years") or legacy.get("experience") or 0),
            "phone": legacy.get("phone") or row["phone"],
            "city": legacy.get("city") or row["city"],
            "location_text": legacy.get("address") or legacy.get("location") or row["location_text"],
            "image_url": legacy.get("image") or row["image_url"],
            "pet_types_supported": _normalize_pet_types(legacy.get("pet_types_supported") or ([legacy.get("specialty")] if legacy.get("specialty") else [])),
            "rating_avg": float(legacy.get("rating_avg") if legacy.get("rating_avg") is not None else legacy.get("rating") or 0),
            "rating_count": int(legacy.get("rating_count") if legacy.get("rating_count") is not None else legacy.get("reviews_count") or 0),
            "is_public": bool(legacy.get("is_public", False)),
            "status": legacy.get("status") if legacy.get("status") in VET_PROFILE_STATUSES else "draft",
            "verified": bool(legacy.get("verified", False)),
        })

    await db.vet_profiles.insert_one(row)
    return row

# ========================= REALTIME ROUTES =========================

async def get_user_from_token(token: str) -> Optional[dict]:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = payload.get("sub")
        if not user_id:
            return None
        return await db.users.find_one({"id": user_id})
    except Exception:
        return None

@app.websocket("/ws/chat")
async def chat_websocket(websocket: WebSocket):
    token = websocket.query_params.get("token")
    if not token:
        await websocket.close(code=1008)
        return

    user = await get_user_from_token(token)
    if not user:
        await websocket.close(code=1008)
        return

    user_id = user["id"]
    await chat_ws_manager.connect(user_id, websocket)

    # announce online presence + initial state
    await chat_ws_manager.broadcast_event({
        "type": "presence_update",
        "payload": {"user_id": user_id, "is_online": True}
    })

    try:
        await websocket.send_json({
            "type": "connected",
            "user_id": user_id,
            "payload": {"online_user_ids": chat_ws_manager.online_user_ids()}
        })

        while True:
            message = await websocket.receive_json()
            event_type = message.get("type")
            conversation_id = message.get("conversation_id")

            if event_type == "ping":
                await websocket.send_json({"type": "pong"})
                continue

            if event_type in {"typing", "read"}:
                if not conversation_id or not await user_is_conversation_participant(user_id, conversation_id):
                    continue

            if event_type == "typing":
                await notify_conversation_participants(
                    conversation_id,
                    "typing",
                    {
                        "user_id": user_id,
                        "is_typing": bool(message.get("is_typing", False))
                    },
                )
            elif event_type == "read":
                await db.chat_messages.update_many(
                    {"conversation_id": conversation_id, "sender_id": {"$ne": user_id}, "is_read": False},
                    {"$set": {"is_read": True}},
                )
                await notify_conversation_participants(
                    conversation_id,
                    "messages_read",
                    {"reader_id": user_id},
                )

    except WebSocketDisconnect:
        chat_ws_manager.disconnect(user_id, websocket)
        await chat_ws_manager.broadcast_event({
            "type": "presence_update",
            "payload": {"user_id": user_id, "is_online": chat_ws_manager.is_online(user_id)}
        })
    except Exception:
        chat_ws_manager.disconnect(user_id, websocket)
        await chat_ws_manager.broadcast_event({
            "type": "presence_update",
            "payload": {"user_id": user_id, "is_online": chat_ws_manager.is_online(user_id)}
        })

DEFAULT_USER_SETTINGS = {
    "push_notifications": True,
    "dark_mode": False,
    "location_services": True,
    "email_updates": True,
    "chat_sound": True,
    "chat_preview": True,
    "allow_friend_requests": "everyone",  # everyone | nobody
    "allow_direct_messages": "everyone",  # everyone | friends_only
    "language": "en",
    "muted_conversation_ids": [],
}
MAX_MUTED_CONVERSATIONS = 500

# ========================= AUTH ROUTES =========================

@api_router.post("/auth/signup", response_model=dict, dependencies=[Depends(rate_limit("signup", 5, 3600))])
async def signup(user_data: UserCreate):
    existing = await db.users.find_one({"email": user_data.email})
    if existing:
        raise HTTPException(status_code=400, detail=error_detail("AUTH_EMAIL_EXISTS", "Email already registered"))
    
    verification_code = generate_verification_code()

    base_username = normalize_username(user_data.name) or f"user{random.randint(1000, 9999)}"
    username = base_username
    i = 1
    while await db.users.find_one({"username": username}):
        i += 1
        username = f"{base_username}{i}"

    user = User(
        email=user_data.email,
        name=user_data.name,
        username=username,
        phone=user_data.phone,
        verification_code=verification_code
    )
    user.user_code = generate_user_code(user.id)
    user_dict = user.dict()
    user_dict["password_hash"] = hash_password(user_data.password)
    
    await db.users.insert_one(user_dict)
    logger.info(f"User registered: {user.id}")

    if smtp_is_configured():
        try:
            await send_auth_code_email(user.email, "verify", verification_code)
            return {"message": "User created. Verification code sent to email.", "user_id": user.id}
        except Exception as e:
            logger.error(f"SMTP send failed on signup: {e}")
            if ALLOW_INSECURE_AUTH_CODE_RESPONSE:
                # Explicitly opt-in dev fallback only
                return {"message": "User created. Email sending failed; using demo code.", "user_id": user.id, "verification_code": verification_code}
            return {"message": "User created. Email delivery failed. Please retry resend verification.", "user_id": user.id}

    if ALLOW_INSECURE_AUTH_CODE_RESPONSE:
        return {"message": "User created. Please verify your account.", "user_id": user.id, "verification_code": verification_code}

    return {"message": "User created. Please verify your account.", "user_id": user.id}

@api_router.post(
    "/auth/resend-verification",
    response_model=dict,
    dependencies=[Depends(rate_limit("resend_verification", 5, 900))],
)
async def resend_verification(req: ResendVerificationRequest):
    user = await db.users.find_one({"email": req.email})
    if not user:
        return {"message": "If that email exists, a verification code has been generated."}

    if user.get("is_verified", False):
        return {"message": "Account is already verified."}

    verification_code = generate_verification_code()
    await db.users.update_one(
        {"id": user["id"]},
        {"$set": {"verification_code": verification_code}},
    )

    if smtp_is_configured():
        try:
            await send_auth_code_email(req.email, "verify", verification_code)
            return {"message": "Verification code sent to email."}
        except Exception as e:
            logger.error(f"SMTP send failed on resend verification: {e}")

    if ALLOW_INSECURE_AUTH_CODE_RESPONSE:
        return {
            "message": "Verification code generated.",
            "verification_code": verification_code,
        }

    return {"message": "Verification code generated. If email delivery is configured, check your inbox."}

@api_router.post(
    "/auth/verify",
    response_model=TokenResponse,
    dependencies=[Depends(rate_limit("verify", 10, 900))],
)
async def verify_account(user_id: str, code: str):
    user = await db.users.find_one({"id": user_id})
    if not user:
        raise HTTPException(status_code=404, detail=error_detail("AUTH_USER_NOT_FOUND", "User not found"))

    if not codes_match(user.get("verification_code"), code):
        raise HTTPException(status_code=400, detail=error_detail("AUTH_INVALID_VERIFICATION_CODE", "Invalid verification code"))

    await db.users.update_one({"id": user_id}, {"$set": {"is_verified": True, "verification_code": None}})
    
    token = create_access_token({"sub": user["id"]})
    user["is_verified"] = True
    return TokenResponse(
        access_token=token,
        user=UserResponse(**user)
    )

@api_router.post(
    "/auth/forgot-password",
    response_model=dict,
    dependencies=[Depends(rate_limit("forgot_password", 5, 900))],
)
async def forgot_password(req: ForgotPasswordRequest):
    user = await db.users.find_one({"email": req.email})

    # Always return success-like message to avoid email enumeration
    if not user:
        return {"message": "If that email exists, a reset code has been generated."}

    reset_code = generate_verification_code()
    expires_at = datetime.utcnow() + timedelta(minutes=15)
    await db.users.update_one(
        {"id": user["id"]},
        {"$set": {"reset_code": reset_code, "reset_code_expires_at": expires_at}},
    )

    if smtp_is_configured():
        try:
            await send_auth_code_email(req.email, "reset", reset_code)
            return {
                "message": "If that email exists, a reset code has been sent.",
                "expires_at": expires_at.isoformat(),
            }
        except Exception as e:
            logger.error(f"SMTP send failed on forgot password: {e}")

    if ALLOW_INSECURE_AUTH_CODE_RESPONSE:
        # Explicitly opt-in dev fallback: return code directly
        return {
            "message": "Password reset code generated.",
            "reset_code": reset_code,
            "expires_at": expires_at.isoformat(),
        }

    return {
        "message": "If that email exists, a reset code has been generated.",
        "expires_at": expires_at.isoformat(),
    }

@api_router.post(
    "/auth/reset-password",
    response_model=dict,
    dependencies=[Depends(rate_limit("reset_password", 10, 900))],
)
async def reset_password(req: ResetPasswordRequest):
    # Every failure path returns the same error so the endpoint cannot be used
    # to discover which emails are registered.
    invalid = HTTPException(
        status_code=400,
        detail=error_detail("AUTH_INVALID_RESET_CODE", "Invalid or expired reset code"),
    )

    user = await db.users.find_one({"email": req.email})
    if not user:
        raise invalid

    code = user.get("reset_code")
    exp = user.get("reset_code_expires_at")
    if not code or not exp:
        raise invalid

    if not codes_match(code, req.code):
        raise invalid

    if isinstance(exp, str):
        try:
            exp = datetime.fromisoformat(exp)
        except Exception:
            exp = None

    if not exp or exp < datetime.utcnow():
        raise invalid

    await db.users.update_one(
        {"id": user["id"]},
        {
            "$set": {"password_hash": hash_password(req.new_password)},
            "$unset": {"reset_code": "", "reset_code_expires_at": ""},
        },
    )

    return {"message": "Password reset successful"}

@api_router.post(
    "/auth/login",
    response_model=TokenResponse,
    dependencies=[Depends(rate_limit("login", 10, 300))],
)
async def login(credentials: UserLogin):
    user = await db.users.find_one({"email": credentials.email})
    if not user:
        raise HTTPException(status_code=401, detail=error_detail("AUTH_INVALID_CREDENTIALS", "Invalid credentials"))

    if not verify_password(credentials.password, user.get("password_hash", "")):
        raise HTTPException(status_code=401, detail=error_detail("AUTH_INVALID_CREDENTIALS", "Invalid credentials"))

    if not user.get("is_verified", False):
        raise HTTPException(status_code=403, detail=error_detail("AUTH_NOT_VERIFIED", "Please verify your account before login"))

    user = await _ensure_user_identity_fields(user)
    token = create_access_token({"sub": user["id"]})
    return TokenResponse(
        access_token=token,
        user=UserResponse(**user)
    )


# Accepted OAuth client IDs for Google ID-token audience (Web + Android), comma-separated.
GOOGLE_CLIENT_IDS = {
    cid.strip()
    for cid in os.environ.get("GOOGLE_CLIENT_IDS", "").split(",")
    if cid.strip()
}
FACEBOOK_APP_ID = os.environ.get("FACEBOOK_APP_ID", "").strip()
FACEBOOK_APP_SECRET = os.environ.get("FACEBOOK_APP_SECRET", "").strip()
# Instagram Login for consumers goes through the same Meta app (Facebook Login / Instagram product).
INSTAGRAM_APP_ID = os.environ.get("INSTAGRAM_APP_ID", FACEBOOK_APP_ID).strip()
INSTAGRAM_APP_SECRET = os.environ.get("INSTAGRAM_APP_SECRET", FACEBOOK_APP_SECRET).strip()


async def _ensure_user_identity_fields(user: dict) -> dict:
    patch = {}
    if not user.get("username"):
        base = normalize_username(user.get("name") or "user") or f"user{random.randint(1000, 9999)}"
        candidate = base
        i = 1
        while await db.users.find_one({"username": candidate, "id": {"$ne": user["id"]}}):
            i += 1
            candidate = f"{base}{i}"
        patch["username"] = candidate
    if not user.get("user_code"):
        patch["user_code"] = generate_user_code(user["id"])
    if patch:
        await db.users.update_one({"id": user["id"]}, {"$set": patch})
        user.update(patch)
    return user


async def _unique_username(seed: str) -> str:
    base = normalize_username(seed) or f"user{random.randint(1000, 9999)}"
    candidate = base
    i = 1
    while await db.users.find_one({"username": candidate}):
        i += 1
        candidate = f"{base}{i}"
    return candidate


def _verify_google_id_token(token: str) -> dict:
    """Validate a Google ID token and return a normalized identity. Raises ValueError on failure."""
    if not GOOGLE_CLIENT_IDS:
        raise ValueError("not_configured")
    if not token:
        raise ValueError("missing_token")
    try:
        from google.auth.transport import requests as google_requests
        from google.oauth2 import id_token as google_id_token

        claims = google_id_token.verify_oauth2_token(token, google_requests.Request(), audience=None)
    except Exception as e:
        logger.warning("Google ID token verification failed: %s", e)
        raise ValueError("invalid_token") from e
    if claims.get("aud") not in GOOGLE_CLIENT_IDS:
        raise ValueError("bad_audience")
    if claims.get("iss") not in {"accounts.google.com", "https://accounts.google.com"}:
        raise ValueError("bad_issuer")
    sub = claims.get("sub")
    if not sub:
        raise ValueError("missing_sub")
    return {
        "provider_user_id": str(sub),
        "email": (claims.get("email") or "").strip().lower() or None,
        "email_verified": bool(claims.get("email_verified", False)),
        "name": (claims.get("name") or "").strip() or None,
        "avatar": (claims.get("picture") or "").strip() or None,
    }


async def _verify_facebook_access_token(token: str, *, app_id: str, app_secret: str, provider: str) -> dict:
    """Validate a Meta access token with debug_token + /me. Raises ValueError on failure."""
    if not app_id or not app_secret:
        raise ValueError("not_configured")
    if not token:
        raise ValueError("missing_token")
    app_token = f"{app_id}|{app_secret}"
    async with httpx.AsyncClient(timeout=12) as http:
        debug = await http.get(
            "https://graph.facebook.com/debug_token",
            params={"input_token": token, "access_token": app_token},
        )
        if debug.status_code != 200:
            logger.warning("%s debug_token failed (%s): %s", provider, debug.status_code, debug.text[:200])
            raise ValueError("invalid_token")
        payload = debug.json().get("data") or {}
        if not payload.get("is_valid"):
            raise ValueError("invalid_token")
        if str(payload.get("app_id") or "") != app_id:
            raise ValueError("bad_audience")
        user_id = str(payload.get("user_id") or "")
        if not user_id:
            raise ValueError("missing_sub")

        me = await http.get(
            "https://graph.facebook.com/me",
            params={
                "fields": "id,name,email,picture.type(large)",
                "access_token": token,
            },
        )
        if me.status_code != 200:
            logger.warning("%s /me failed (%s): %s", provider, me.status_code, me.text[:200])
            raise ValueError("invalid_token")
        profile = me.json()
    if str(profile.get("id") or "") != user_id:
        raise ValueError("invalid_token")
    picture = profile.get("picture")
    avatar = None
    if isinstance(picture, dict):
        avatar = ((picture.get("data") or {}).get("url") or "").strip() or None
    email = (profile.get("email") or "").strip().lower() or None
    return {
        "provider_user_id": user_id,
        "email": email,
        # Facebook only returns email when granted; treat a returned email as verified.
        "email_verified": bool(email),
        "name": (profile.get("name") or "").strip() or None,
        "avatar": avatar,
    }


async def _verify_instagram_access_token(token: str) -> dict:
    """
    Validate an Instagram user access token (Instagram API with Instagram Login).
    Falls back to Facebook token verification when the client used Facebook Login for Instagram.
    """
    if INSTAGRAM_APP_ID and INSTAGRAM_APP_SECRET and INSTAGRAM_APP_ID != FACEBOOK_APP_ID:
        # Dedicated Instagram app credentials — try Instagram Graph first.
        try:
            async with httpx.AsyncClient(timeout=12) as http:
                me = await http.get(
                    "https://graph.instagram.com/me",
                    params={"fields": "id,username,account_type", "access_token": token},
                )
                if me.status_code == 200:
                    profile = me.json()
                    ig_id = str(profile.get("id") or "")
                    if ig_id:
                        username = (profile.get("username") or "").strip()
                        return {
                            "provider_user_id": ig_id,
                            "email": None,
                            "email_verified": False,
                            "name": username or None,
                            "avatar": None,
                        }
        except Exception as e:
            logger.warning("Instagram Graph /me failed: %s", e)
    # Consumer Instagram Login in Petsy uses Facebook Login on the same Meta app.
    return await _verify_facebook_access_token(
        token,
        app_id=INSTAGRAM_APP_ID or FACEBOOK_APP_ID,
        app_secret=INSTAGRAM_APP_SECRET or FACEBOOK_APP_SECRET,
        provider="instagram",
    )


async def _verify_social_identity(provider: str, token: str) -> dict:
    if provider == "google":
        return await asyncio.to_thread(_verify_google_id_token, token)
    if provider == "facebook":
        return await _verify_facebook_access_token(
            token, app_id=FACEBOOK_APP_ID, app_secret=FACEBOOK_APP_SECRET, provider="facebook"
        )
    if provider == "instagram":
        return await _verify_instagram_access_token(token)
    raise ValueError("unsupported")


@api_router.post(
    "/auth/social",
    response_model=TokenResponse,
    dependencies=[Depends(rate_limit("social_login", 20, 300))],
)
async def social_login(data: SocialLoginRequest):
    """Create or sign in a user via a verified social identity (Google / Facebook / Instagram)."""
    provider = data.provider
    try:
        identity = await _verify_social_identity(provider, data.access_token or "")
    except ValueError as e:
        code = str(e)
        if code == "not_configured":
            raise HTTPException(
                status_code=503,
                detail=error_detail("AUTH_SOCIAL_NOT_CONFIGURED", f"{provider} sign-in is not configured on the server"),
            )
        if code == "unsupported":
            raise HTTPException(
                status_code=501,
                detail=error_detail("AUTH_SOCIAL_UNSUPPORTED", f"{provider} sign-in is not available yet"),
            )
        raise HTTPException(
            status_code=401,
            detail=error_detail("AUTH_SOCIAL_INVALID_TOKEN", f"Invalid {provider} token"),
        )

    provider_user_id = str(identity["provider_user_id"])
    if data.provider_user_id and data.provider_user_id != provider_user_id:
        raise HTTPException(
            status_code=401,
            detail=error_detail("AUTH_SOCIAL_INVALID_TOKEN", f"{provider} user id does not match the token"),
        )

    email = (identity.get("email") or (str(data.email) if data.email else "") or "").strip().lower()
    email_verified = bool(identity.get("email_verified")) or (provider == "google" and bool(email))
    # Client-provided email is only a hint; never mark it verified unless the provider confirmed it.
    if not identity.get("email") and data.email:
        email_verified = False
    name = (
        identity.get("name")
        or data.name
        or (email.split("@")[0] if email else f"{provider.title()} User")
    ).strip()[:120]
    avatar = (identity.get("avatar") or data.avatar or "").strip()[:1024] or None

    user = await db.users.find_one({f"social_providers.{provider}": provider_user_id})
    if not user and email:
        user = await db.users.find_one({"email": email})

    placeholder_names = {"Google User", "Facebook User", "Instagram User", "Petsy User"}
    if user:
        patch: Dict[str, Any] = {f"social_providers.{provider}": provider_user_id, "is_verified": True}
        if avatar and not user.get("avatar"):
            patch["avatar"] = avatar
        if name and (not user.get("name") or user.get("name") in placeholder_names):
            patch["name"] = name
        if email and not user.get("email"):
            patch["email"] = email
        await db.users.update_one({"id": user["id"]}, {"$set": patch})
        user.update(patch)
        providers = dict(user.get("social_providers") or {})
        providers[provider] = provider_user_id
        user["social_providers"] = providers
        user.pop(f"social_providers.{provider}", None)
    else:
        if not email:
            # Instagram often has no email — synthesize a stable private placeholder the user can change later.
            if provider == "instagram":
                email = f"ig_{provider_user_id}@users.petsy.company"
                email_verified = True
            else:
                raise HTTPException(
                    status_code=400,
                    detail=error_detail(
                        "AUTH_SOCIAL_EMAIL_REQUIRED",
                        f"A verified {provider} email is required to create an account",
                    ),
                )
        elif not email_verified and provider != "instagram":
            raise HTTPException(
                status_code=400,
                detail=error_detail(
                    "AUTH_SOCIAL_EMAIL_REQUIRED",
                    f"A verified {provider} email is required to create an account",
                ),
            )
        username = await _unique_username(name)
        user_obj = User(
            email=email,
            name=name,
            username=username,
            avatar=avatar,
            is_verified=True,
            language="ar",
        )
        user_obj.user_code = generate_user_code(user_obj.id)
        user = user_obj.dict()
        user["social_providers"] = {provider: provider_user_id}
        user["password_hash"] = None
        await db.users.insert_one(user)
        logger.info("Social user created via %s: %s", provider, user_obj.id)

    user = await _ensure_user_identity_fields(user)
    token = create_access_token({"sub": user["id"]})
    return TokenResponse(access_token=token, user=UserResponse(**user))

@api_router.get("/auth/me", response_model=UserResponse)
async def get_me(current_user: dict = Depends(get_current_user)):
    patch = {}
    if not current_user.get("username"):
        base = normalize_username(current_user.get("name") or "user") or f"user{random.randint(1000,9999)}"
        candidate = base
        i = 1
        while await db.users.find_one({"username": candidate, "id": {"$ne": current_user["id"]}}):
            i += 1
            candidate = f"{base}{i}"
        patch["username"] = candidate
    if not current_user.get("user_code"):
        patch["user_code"] = generate_user_code(current_user["id"])
    if patch:
        await db.users.update_one({"id": current_user["id"]}, {"$set": patch})
        current_user.update(patch)
    return UserResponse(**current_user)

@api_router.put("/auth/update", response_model=UserResponse)
async def update_profile(update_data: UserUpdate, current_user: dict = Depends(get_current_user)):
    update_dict = {k: v for k, v in update_data.dict().items() if v is not None}
    if update_dict:
        await db.users.update_one({"id": current_user["id"]}, {"$set": update_dict})
    updated = await db.users.find_one({"id": current_user["id"]})
    return UserResponse(**updated)

@api_router.post('/auth/change-password')
async def change_password(payload: ChangePasswordRequest, current_user: dict = Depends(get_current_user)):
    if not verify_password(payload.current_password, current_user.get('password_hash', '')):
        raise HTTPException(status_code=400, detail='Current password is incorrect')
    if len(payload.new_password or '') < 6:
        raise HTTPException(status_code=400, detail='New password must be at least 6 characters')
    await db.users.update_one({"id": current_user["id"]}, {"$set": {"password_hash": hash_password(payload.new_password)}})
    return {"message": "Password changed successfully"}

@api_router.post('/auth/delete-account')
async def delete_account(payload: DeleteAccountRequest, current_user: dict = Depends(get_current_user)):
    if current_user.get('password_hash'):
        if not payload.password or not verify_password(payload.password, current_user.get('password_hash', '')):
            raise HTTPException(status_code=400, detail='Password is required to delete account')

    uid = current_user['id']
    await db.users.delete_one({"id": uid})
    await db.pets.delete_many({"owner_id": uid})
    await db.comments.delete_many({"user_id": uid})
    await db.community.delete_many({"user_id": uid})
    await db.conversations.delete_many({"participants": uid})
    await db.chat_messages.delete_many({"sender_id": uid})
    await db.favorites.delete_many({"user_id": uid})
    await db.friend_requests.delete_many({"$or": [{"from_user_id": uid}, {"to_user_id": uid}]})
    await db.friendships.delete_many({"users": uid})
    await db.user_settings.delete_many({"user_id": uid})
    await db.blocked_users.delete_many({"$or": [{"user_id": uid}, {"blocked_user_id": uid}]})
    await db.community_post_notifications.delete_many({"user_id": uid})
    await db.community_reports.delete_many({"reported_by": uid})
    await db.notifications.delete_many({"user_id": uid})
    return {"message": "Account deleted"}

@api_router.get('/user-settings')
async def get_user_settings(current_user: dict = Depends(get_current_user)):
    row = await db.user_settings.find_one({"user_id": current_user["id"]})
    if not row:
        row = {"user_id": current_user["id"], **DEFAULT_USER_SETTINGS}
        await db.user_settings.insert_one({**row, "created_at": datetime.utcnow(), "updated_at": datetime.utcnow()})
    return {k: row.get(k, DEFAULT_USER_SETTINGS.get(k)) for k in DEFAULT_USER_SETTINGS.keys()}

@api_router.put('/user-settings')
async def update_user_settings(data: dict, current_user: dict = Depends(get_current_user)):
    allowed = set(DEFAULT_USER_SETTINGS.keys())
    patch = {k: v for k, v in (data or {}).items() if k in allowed}
    if not patch:
        return await get_user_settings(current_user)

    if "allow_friend_requests" in patch:
        value = str(patch["allow_friend_requests"] or "").strip().lower()
        if value not in {"everyone", "nobody"}:
            raise HTTPException(status_code=400, detail="allow_friend_requests must be everyone or nobody")
        patch["allow_friend_requests"] = value

    if "allow_direct_messages" in patch:
        value = str(patch["allow_direct_messages"] or "").strip().lower()
        if value not in {"everyone", "friends_only"}:
            raise HTTPException(status_code=400, detail="allow_direct_messages must be everyone or friends_only")
        patch["allow_direct_messages"] = value

    if "muted_conversation_ids" in patch:
        ids = patch["muted_conversation_ids"]
        if not isinstance(ids, list) or not all(isinstance(i, str) and 0 < len(i) <= 64 for i in ids):
            raise HTTPException(status_code=400, detail="muted_conversation_ids must be a list of conversation ids")
        patch["muted_conversation_ids"] = list(dict.fromkeys(ids))[:MAX_MUTED_CONVERSATIONS]

    await db.user_settings.update_one(
        {"user_id": current_user["id"]},
        {"$set": {**patch, "updated_at": datetime.utcnow()}, "$setOnInsert": {"created_at": datetime.utcnow()}},
        upsert=True,
    )
    row = await db.user_settings.find_one({"user_id": current_user["id"]})
    return {k: row.get(k, DEFAULT_USER_SETTINGS.get(k)) for k in DEFAULT_USER_SETTINGS.keys()}

@api_router.get('/notifications')
async def get_my_notifications(
    unread_only: bool = False,
    notif_type: Optional[str] = None,
    limit: int = 20,
    offset: int = 0,
    current_user: dict = Depends(get_current_user)
):
    query: dict = {"user_id": current_user["id"]}
    if unread_only:
        query["is_read"] = False
    if notif_type and notif_type != "all":
        query["type"] = notif_type

    safe_limit = max(1, min(limit, 100))
    safe_offset = max(0, offset)
    rows = await db.notifications.find(query).sort("created_at", -1).skip(safe_offset).limit(safe_limit).to_list(safe_limit)
    total = await db.notifications.count_documents(query)
    return {
        "items": [{k: v for k, v in row.items() if k != "_id"} for row in rows],
        "total": total,
        "limit": safe_limit,
        "offset": safe_offset,
        "has_more": safe_offset + len(rows) < total,
    }

@api_router.get('/notifications/unread-count')
async def get_unread_notifications_count(current_user: dict = Depends(get_current_user)):
    count = await db.notifications.count_documents({"user_id": current_user["id"], "is_read": False})
    return {"count": count}


@api_router.get('/inbox/badges')
async def get_inbox_badges(current_user: dict = Depends(get_current_user)):
    notifications = await db.notifications.count_documents({"user_id": current_user["id"], "is_read": False})
    friend_requests = await db.friend_requests.count_documents({
        "to_user_id": current_user["id"],
        "status": "pending",
    })
    conv_ids = [
        c.get("id")
        for c in await db.conversations.find({"participants": current_user["id"]}, {"id": 1}).to_list(500)
        if c.get("id")
    ]
    messages = 0
    if conv_ids:
        messages = await db.chat_messages.count_documents({
            "conversation_id": {"$in": conv_ids},
            "sender_id": {"$ne": current_user["id"]},
            "is_read": False,
        })
    return {
        "notifications": notifications,
        "friend_requests": friend_requests,
        "messages": messages,
    }


@api_router.put('/notifications/{notification_id}/read')
async def mark_notification_read(notification_id: str, current_user: dict = Depends(get_current_user)):
    await db.notifications.update_one(
        {"id": notification_id, "user_id": current_user["id"]},
        {"$set": {"is_read": True, "updated_at": datetime.utcnow()}},
    )
    return {"success": True}

@api_router.put('/notifications/read-all')
async def mark_all_notifications_read(current_user: dict = Depends(get_current_user)):
    await db.notifications.update_many(
        {"user_id": current_user["id"], "is_read": False},
        {"$set": {"is_read": True, "updated_at": datetime.utcnow()}},
    )
    return {"success": True}

@api_router.delete('/notifications/clear-all')
async def clear_all_notifications(current_user: dict = Depends(get_current_user)):
    await db.notifications.delete_many({"user_id": current_user["id"]})
    return {"success": True}

# ========================= PET ROUTES =========================

def _normalize_pet_purpose(purpose: Optional[str]) -> Optional[str]:
    value = (purpose or '').strip().lower() or None
    if value and value not in {'companion', 'guard'}:
        raise HTTPException(status_code=400, detail='purpose must be companion or guard')
    return value


def _normalize_guard_role(role: Optional[str]) -> Optional[str]:
    value = (role or '').strip().lower() or None
    if value and value not in GUARD_ROLES:
        raise HTTPException(status_code=400, detail=f'guard_role must be one of: {", ".join(sorted(GUARD_ROLES))}')
    return value


def _normalize_seller_type(seller_type: Optional[str]) -> Optional[str]:
    value = (seller_type or '').strip().lower() or None
    if value and value not in SELLER_TYPES:
        raise HTTPException(status_code=400, detail=f'seller_type must be one of: {", ".join(sorted(SELLER_TYPES))}')
    return value


def _normalize_country(country: Optional[str]) -> Optional[str]:
    value = (country or '').strip().upper() or None
    if not value:
        return None
    if len(value) > 8:
        raise HTTPException(status_code=400, detail='country code too long')
    return value


def _normalize_currency(currency: Optional[str]) -> Optional[str]:
    value = (currency or '').strip().upper() or None
    if value and len(value) > 8:
        raise HTTPException(status_code=400, detail='currency code too long')
    return value


def _sanitize_pet_listing_fields(payload: dict) -> dict:
    payload['purpose'] = _normalize_pet_purpose(payload.get('purpose'))
    payload['guard_role'] = _normalize_guard_role(payload.get('guard_role'))
    payload['seller_type'] = _normalize_seller_type(payload.get('seller_type'))
    payload['country'] = _normalize_country(payload.get('country'))
    payload['currency'] = _normalize_currency(payload.get('currency'))
    if payload.get('purpose') != 'guard':
        payload['guard_role'] = None
        payload['seller_type'] = None
    return payload


@api_router.post("/pets", response_model=Pet)
async def create_pet(pet_data: PetCreate, current_user: dict = Depends(get_current_user)):
    payload = _sanitize_pet_listing_fields(pet_data.dict())
    pet = Pet(**payload, owner_id=current_user["id"])
    await db.pets.insert_one(pet.dict())
    return pet

@api_router.get("/pets", response_model=List[Pet])
async def get_pets(
    status: Optional[str] = None,
    species: Optional[str] = None,
    city: Optional[str] = None,
    gender: Optional[str] = None,
    purpose: Optional[str] = None,
    guard_role: Optional[str] = None,
    country: Optional[str] = None,
    seller_type: Optional[str] = None,
    limit: int = 50,
    skip: int = 0
):
    query = {}
    if status:
        query["status"] = status
    if species:
        query["species"] = species
    if city:
        query["location"] = {"$regex": city, "$options": "i"}
    if gender:
        query["gender"] = gender
    if purpose:
        purpose_val = purpose.strip().lower()
        if purpose_val not in {'companion', 'guard'}:
            raise HTTPException(status_code=400, detail='purpose must be companion or guard')
        query["purpose"] = purpose_val
    if guard_role:
        query["guard_role"] = _normalize_guard_role(guard_role)
    if country:
        query["country"] = _normalize_country(country)
    if seller_type:
        query["seller_type"] = _normalize_seller_type(seller_type)
    
    pets = await db.pets.find(query).skip(skip).limit(limit).to_list(limit)
    return [Pet(**pet) for pet in pets]

@api_router.get("/pets/my", response_model=List[Pet])
async def get_my_pets(current_user: dict = Depends(get_current_user)):
    pets = await db.pets.find({"owner_id": current_user["id"]}).to_list(100)
    return [Pet(**pet) for pet in pets]

@api_router.get("/pets/{pet_id}", response_model=Pet)
async def get_pet(pet_id: str):
    pet = await db.pets.find_one({"id": pet_id})
    if not pet:
        raise HTTPException(status_code=404, detail="Pet not found")
    # Increment views
    await db.pets.update_one({"id": pet_id}, {"$inc": {"views": 1}})
    return Pet(**pet)

@api_router.put("/pets/{pet_id}", response_model=Pet)
async def update_pet(pet_id: str, pet_data: PetUpdate, current_user: dict = Depends(get_current_user)):
    pet = await db.pets.find_one({"id": pet_id, "owner_id": current_user["id"]})
    if not pet:
        raise HTTPException(status_code=404, detail="Pet not found or not authorized")
    
    update_dict = {k: v for k, v in pet_data.dict().items() if v is not None}
    if update_dict:
        merged = {
            "purpose": update_dict.get("purpose", pet.get("purpose")),
            "guard_role": update_dict.get("guard_role", pet.get("guard_role")),
            "seller_type": update_dict.get("seller_type", pet.get("seller_type")),
            "country": update_dict.get("country", pet.get("country")),
            "currency": update_dict.get("currency", pet.get("currency")),
        }
        cleaned = _sanitize_pet_listing_fields(merged)
        for key in ("purpose", "guard_role", "seller_type", "country", "currency"):
            if key in update_dict or key in ("purpose", "guard_role", "seller_type"):
                update_dict[key] = cleaned.get(key)
        await db.pets.update_one({"id": pet_id}, {"$set": update_dict})
    
    updated = await db.pets.find_one({"id": pet_id})
    return Pet(**updated)

@api_router.delete("/pets/{pet_id}")
async def delete_pet(pet_id: str, current_user: dict = Depends(get_current_user)):
    result = await db.pets.delete_one({"id": pet_id, "owner_id": current_user["id"]})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Pet not found or not authorized")
    return {"message": "Pet deleted"}


def _normalize_trainer_categories(values: Any) -> List[str]:
    if not isinstance(values, list):
        return []
    out: List[str] = []
    for v in values:
        item = str(v or "").strip().lower()
        if item in TRAINER_CATEGORIES and item not in out:
            out.append(item)
    return out


def _normalize_trainer_pet_types(values: Any) -> List[str]:
    if not isinstance(values, list):
        return []
    out: List[str] = []
    for v in values:
        item = str(v or "").strip().lower()
        if item in TRAINER_PET_TYPES and item not in out:
            out.append(item)
    return out


@api_router.get("/trainers")
async def get_trainers(
    q: Optional[str] = None,
    city: Optional[str] = None,
    country: Optional[str] = None,
    category: Optional[str] = None,
    pet_type: Optional[str] = None,
    international: Optional[bool] = None,
    limit: int = Query(50, ge=1, le=200),
):
    query: dict = {"status": "active", "verified": True, "is_public": True}
    if q:
        qv = str(q).strip()
        if qv:
            query["$or"] = [
                {"name": {"$regex": qv, "$options": "i"}},
                {"title": {"$regex": qv, "$options": "i"}},
                {"bio": {"$regex": qv, "$options": "i"}},
            ]
    if city:
        query["city"] = {"$regex": str(city).strip(), "$options": "i"}
    if country:
        query["country"] = _normalize_country(country)
    if category:
        cat = str(category).strip().lower()
        if cat not in TRAINER_CATEGORIES:
            raise HTTPException(status_code=400, detail="invalid trainer category")
        query["categories"] = cat
    if pet_type:
        pt = str(pet_type).strip().lower()
        if pt not in TRAINER_PET_TYPES:
            raise HTTPException(status_code=400, detail="invalid pet_type")
        query.setdefault("$and", []).append({"$or": [{"pet_types": pt}, {"pet_types": "all"}]})
    if international is True:
        query["serves_international"] = True

    rows = await db.trainers.find(query).sort([("rating_avg", -1), ("rating_count", -1), ("updated_at", -1)]).to_list(limit)
    return [_serialize_doc(r) for r in rows]


@api_router.get("/trainers/me")
async def get_my_trainer_application(current_user: dict = Depends(get_current_user)):
    row = await db.trainers.find_one({"user_id": current_user["id"]}, sort=[("updated_at", -1), ("created_at", -1)])
    if not row:
        raise HTTPException(status_code=404, detail="No trainer application")
    return _serialize_doc(row)


@api_router.get("/trainers/{trainer_id}")
async def get_trainer(trainer_id: str):
    row = await db.trainers.find_one({"id": trainer_id, "status": "active", "verified": True, "is_public": True})
    if not row:
        raise HTTPException(status_code=404, detail="Trainer not found")
    return _serialize_doc(row)


@api_router.post("/trainers", response_model=Trainer)
async def create_trainer(data: TrainerCreate, current_user: dict = Depends(get_current_user)):
    existing = await db.trainers.find_one({"user_id": current_user["id"]}, sort=[("updated_at", -1), ("created_at", -1)])
    if existing and existing.get("status") == "pending_verification":
        raise HTTPException(
            status_code=409,
            detail=error_detail("TRAINER_PENDING", "You already have a trainer application under review"),
        )
    if existing and existing.get("status") == "active" and existing.get("verified"):
        raise HTTPException(
            status_code=409,
            detail=error_detail("TRAINER_EXISTS", "You already have an approved trainer profile"),
        )

    name = str(data.name or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="name is required")
    categories = _normalize_trainer_categories(data.categories)
    if not categories:
        raise HTTPException(status_code=400, detail="at least one category is required")

    trainer = Trainer(
        **{
            **data.model_dump(),
            "name": name,
            "categories": categories,
            "pet_types": _normalize_trainer_pet_types(data.pet_types) or ["dog"],
            "country": _normalize_country(data.country),
            "currency": _normalize_currency(data.currency) or "USD",
            "languages": [str(x).strip().lower() for x in (data.languages or []) if str(x).strip()][:8],
            "experience_years": max(0, int(data.experience_years or 0)),
        },
        user_id=current_user["id"],
        verified=False,
        status="pending_verification",
        is_public=False,
        verification_notes=None,
    )

    if existing and existing.get("status") == "rejected":
        patch = trainer.model_dump()
        patch["id"] = existing["id"]
        patch["created_at"] = existing.get("created_at") or patch.get("created_at")
        patch["verification_notes"] = None
        await db.trainers.update_one({"id": existing["id"]}, {"$set": patch})
        trainer = Trainer.model_validate(patch)
    else:
        await db.trainers.insert_one(trainer.model_dump())

    await create_notifications_for_admins(
        "Trainer application pending",
        f"{current_user.get('name') or name} submitted a trainer listing for review.",
        "trainer_verification",
        {
            "trainer_id": trainer.id,
            "user_id": current_user["id"],
            "status": "pending_verification",
            "route": "/admin/trainer-applications",
        },
    )
    return trainer


@api_router.get("/admin/trainers")
async def get_admin_trainers(
    status: Optional[str] = Query(None),
    admin_user: dict = Depends(get_admin_user),
):
    query: dict = {}
    if status:
        query["status"] = str(status).strip().lower()
    rows = await db.trainers.find(query).sort("updated_at", -1).to_list(1000)
    return [_serialize_doc(r) for r in rows]


@api_router.put("/admin/trainers/{trainer_id}")
async def review_admin_trainer(trainer_id: str, data: dict, admin_user: dict = Depends(get_admin_user)):
    row = await db.trainers.find_one({"id": trainer_id})
    if not row:
        raise HTTPException(status_code=404, detail="Trainer not found")

    action = str((data or {}).get("action") or "").strip().lower()
    notes = (data or {}).get("verification_notes")
    update: dict = {"updated_at": datetime.utcnow()}

    if action == "approve":
        update.update({"status": "active", "verified": True, "is_public": True})
    elif action == "reject":
        note = str(notes or "").strip()
        if not note:
            raise HTTPException(status_code=400, detail="verification_notes are required for reject")
        update.update(
            {
                "status": "rejected",
                "verified": False,
                "is_public": False,
                "verification_notes": note,
            }
        )
    else:
        raise HTTPException(status_code=400, detail="Invalid action")

    await db.trainers.update_one({"id": trainer_id}, {"$set": update})
    await create_notification(
        row.get("user_id"),
        "Trainer application update",
        (
            "Your trainer listing was approved and is now public."
            if action == "approve"
            else f"Your trainer listing was rejected. {str(notes or '').strip()}"
        ),
        "trainer_verification",
        {"trainer_id": trainer_id, "action": action, "status": update["status"]},
    )
    await audit_admin_action(admin_user, "review_trainer", "trainer", trainer_id, {"action": action, **update})
    updated = await db.trainers.find_one({"id": trainer_id})
    return _serialize_doc(updated)


class AdoptionRequestCreate(BaseModel):
    message: str


class AdoptionRequestAction(BaseModel):
    action: str  # accept / decline (pet owner), withdraw (requester)


ADOPTION_MESSAGE_MIN = 20
ADOPTION_MESSAGE_MAX = 600


async def _enrich_adoption_requests(rows: List[dict]) -> List[dict]:
    pet_ids = list({r["pet_id"] for r in rows})
    user_ids = list({r["owner_id"] for r in rows} | {r["requester_id"] for r in rows})
    pets = {
        p["id"]: p
        async for p in db.pets.find({"id": {"$in": pet_ids}}, {"_id": 0, "id": 1, "name": 1, "species": 1, "image": 1, "status": 1})
    }
    users = {u["id"]: u async for u in db.users.find({"id": {"$in": user_ids}}, {"_id": 0, "id": 1, "name": 1, "city": 1})}
    out = []
    for r in rows:
        r = {k: v for k, v in r.items() if k != "_id"}
        pet = pets.get(r["pet_id"], {})
        owner = users.get(r["owner_id"], {})
        requester = users.get(r["requester_id"], {})
        out.append({
            **r,
            "pet_name": pet.get("name"),
            "pet_species": pet.get("species"),
            "pet_image": pet.get("image"),
            "pet_status": pet.get("status"),
            "owner_name": owner.get("name"),
            "requester_name": requester.get("name"),
            "requester_city": requester.get("city"),
        })
    return out


@api_router.post("/pets/{pet_id}/adoption-requests")
async def create_adoption_request(pet_id: str, data: AdoptionRequestCreate, current_user: dict = Depends(get_current_user)):
    pet = await db.pets.find_one({"id": pet_id})
    if not pet:
        raise HTTPException(status_code=404, detail="Pet not found")
    if pet.get("owner_id") == current_user["id"]:
        raise HTTPException(status_code=400, detail=error_detail("OWN_PET", "You can't adopt your own pet"))
    if pet.get("status") != "for_adoption":
        raise HTTPException(status_code=409, detail=error_detail("PET_NOT_AVAILABLE", "This pet is no longer up for adoption"))
    message = (data.message or "").strip()
    if len(message) < ADOPTION_MESSAGE_MIN:
        raise HTTPException(status_code=400, detail=error_detail("MESSAGE_TOO_SHORT", "Tell the owner a bit more about yourself"))
    if await db.adoption_requests.find_one({"pet_id": pet_id, "requester_id": current_user["id"], "status": "pending"}):
        raise HTTPException(status_code=409, detail=error_detail("ALREADY_REQUESTED", "You already have a pending request for this pet"))

    now = datetime.utcnow()
    row = {
        "id": str(uuid.uuid4()),
        "pet_id": pet_id,
        "owner_id": pet["owner_id"],
        "requester_id": current_user["id"],
        "message": message[:ADOPTION_MESSAGE_MAX],
        "status": "pending",
        "created_at": now,
        "updated_at": now,
    }
    await db.adoption_requests.insert_one(dict(row))
    requester_name = current_user.get("name") or "Someone"
    await create_notification(
        pet["owner_id"],
        "New adoption request",
        f"{requester_name} wants to adopt {pet.get('name')}.",
        "adoption",
        {
            "request_id": row["id"],
            "pet_id": pet_id,
            "status": "requested",
            "pet_name": pet.get("name"),
            "from_user_name": requester_name,
            "route": "/adoption-requests?tab=incoming",
        },
    )
    return (await _enrich_adoption_requests([row]))[0]


@api_router.get("/pets/{pet_id}/my-adoption-request")
async def get_my_adoption_request(pet_id: str, current_user: dict = Depends(get_current_user)):
    """The caller's most recent request for this pet, or null."""
    rows = await db.adoption_requests.find({"pet_id": pet_id, "requester_id": current_user["id"]}).sort("created_at", -1).to_list(1)
    return (await _enrich_adoption_requests(rows))[0] if rows else None


@api_router.get("/adoption-requests")
async def list_adoption_requests(
    role: str = Query("incoming", pattern="^(incoming|sent)$"),
    current_user: dict = Depends(get_current_user),
):
    field = "owner_id" if role == "incoming" else "requester_id"
    rows = await db.adoption_requests.find({field: current_user["id"]}).sort("created_at", -1).to_list(200)
    return await _enrich_adoption_requests(rows)


@api_router.put("/adoption-requests/{request_id}")
async def update_adoption_request(request_id: str, data: AdoptionRequestAction, current_user: dict = Depends(get_current_user)):
    action = (data.action or "").strip().lower()
    row = await db.adoption_requests.find_one({"id": request_id})
    if not row:
        raise HTTPException(status_code=404, detail="Request not found")
    is_owner = row["owner_id"] == current_user["id"]
    is_requester = row["requester_id"] == current_user["id"]
    if (action in ("accept", "decline") and not is_owner) or (action == "withdraw" and not is_requester):
        raise HTTPException(status_code=404, detail="Request not found")
    if action not in ("accept", "decline", "withdraw"):
        raise HTTPException(status_code=400, detail="Unknown action")
    if row.get("status") != "pending":
        raise HTTPException(status_code=409, detail=f"This request is already {row.get('status')}")

    pet = await db.pets.find_one({"id": row["pet_id"]}) or {}
    now = datetime.utcnow()
    new_status = {"accept": "accepted", "decline": "declined", "withdraw": "withdrawn"}[action]

    if action == "accept":
        if pet.get("status") != "for_adoption":
            raise HTTPException(status_code=409, detail=error_detail("PET_NOT_AVAILABLE", "This pet is no longer up for adoption"))
        await db.pets.update_one({"id": row["pet_id"]}, {"$set": {"status": "adopted", "adopted_by": row["requester_id"]}})
        others = await db.adoption_requests.find(
            {"pet_id": row["pet_id"], "status": "pending", "id": {"$ne": request_id}}
        ).to_list(200)
        if others:
            await db.adoption_requests.update_many(
                {"id": {"$in": [o["id"] for o in others]}},
                {"$set": {"status": "declined", "closed_reason": "adopted", "updated_at": now}},
            )
        for other in others:
            await create_notification(
                other["requester_id"],
                "Pet adopted",
                f"{pet.get('name')} has found a home with another family.",
                "adoption",
                {"request_id": other["id"], "pet_id": row["pet_id"], "status": "closed", "pet_name": pet.get("name"), "route": "/adoption-requests?tab=sent"},
            )

    await db.adoption_requests.update_one({"id": request_id}, {"$set": {"status": new_status, "updated_at": now}})
    if action in ("accept", "decline"):
        await create_notification(
            row["requester_id"],
            "Adoption request accepted" if action == "accept" else "Adoption request declined",
            f"Your request to adopt {pet.get('name')} was {new_status}.",
            "adoption",
            {
                "request_id": request_id,
                "pet_id": row["pet_id"],
                "status": new_status,
                "pet_name": pet.get("name"),
                "from_user_name": current_user.get("name"),
                "route": "/adoption-requests?tab=sent",
            },
        )
    updated = await db.adoption_requests.find_one({"id": request_id})
    return (await _enrich_adoption_requests([updated]))[0]


@api_router.post("/pets/{pet_id}/like")
async def like_pet(pet_id: str, current_user: dict = Depends(get_current_user)):
    pet = await db.pets.find_one({"id": pet_id})
    if not pet:
        raise HTTPException(status_code=404, detail="Pet not found")
    
    # Check if already favorited
    existing = await db.favorites.find_one({"user_id": current_user["id"], "pet_id": pet_id})
    if existing:
        # Unlike
        await db.favorites.delete_one({"id": existing["id"]})
        await db.pets.update_one({"id": pet_id}, {"$inc": {"likes": -1}})
        return {"liked": False}
    else:
        # Like
        favorite = Favorite(user_id=current_user["id"], pet_id=pet_id)
        await db.favorites.insert_one(favorite.dict())
        await db.pets.update_one({"id": pet_id}, {"$inc": {"likes": 1}})
        return {"liked": True}

@api_router.get("/pets/{pet_id}/like")
async def get_pet_like(pet_id: str, current_user: dict = Depends(get_current_user)):
    liked = await db.favorites.find_one({"user_id": current_user["id"], "pet_id": pet_id}) is not None
    return {"liked": liked}

@api_router.get("/favorites/pets", response_model=List[Pet])
async def get_favorite_pets_legacy(current_user: dict = Depends(get_current_user)):
    favorites = await db.favorites.find({"user_id": current_user["id"]}).sort("created_at", -1).to_list(100)
    pet_ids = [f.get("pet_id") for f in favorites if f.get("pet_id")]
    pets = {p["id"]: p for p in await db.pets.find({"id": {"$in": pet_ids}}).to_list(100)}
    return [Pet(**pets[pid]) for pid in pet_ids if pid in pets]

# ========================= VETS =========================

@api_router.get("/vets")
async def get_vets(
    q: Optional[str] = None,
    city: Optional[str] = None,
    pet_type: Optional[str] = None,
    sort: Optional[str] = "top_rated",
):
    query: dict = {"status": "active", "verified": True, "is_public": True}
    if q:
        qv = str(q).strip()
        if qv:
            query["$or"] = [
                {"name": {"$regex": qv, "$options": "i"}},
                {"specialty": {"$regex": qv, "$options": "i"}},
            ]
    if city:
        query["city"] = {"$regex": str(city).strip(), "$options": "i"}
    if pet_type and str(pet_type).strip().lower() in VET_PET_TYPES:
        pt = str(pet_type).strip().lower()
        query.setdefault("$and", []).append({"$or": [{"pet_types_supported": pt}, {"pet_types_supported": "all"}]})

    sort_key = (sort or "top_rated").strip().lower()
    sort_clause = [("rating_avg", -1), ("rating_count", -1), ("updated_at", -1)]
    if sort_key == "nearest":
        sort_clause = [("city", 1), ("rating_avg", -1), ("updated_at", -1)]

    vets = await db.vet_profiles.find(query).sort(sort_clause).to_list(200)

    legacy_q: dict = {"status": "active", "verified": True, "is_public": True}
    if city:
        legacy_q["city"] = {"$regex": str(city).strip(), "$options": "i"}
    if q:
        qv = str(q).strip()
        if qv:
            legacy_q["$or"] = [
                {"name": {"$regex": qv, "$options": "i"}},
                {"specialty": {"$regex": qv, "$options": "i"}},
            ]
    legacy_rows = await db.vets.find(legacy_q).to_list(200)

    seen_user_ids = {v.get("user_id") for v in vets if v.get("user_id")}
    for lv in legacy_rows:
        if lv.get("user_id") and lv.get("user_id") in seen_user_ids:
            continue

        raw_exp = lv.get("experience_years") if lv.get("experience_years") is not None else lv.get("experience")
        try:
            experience_years = int(raw_exp) if raw_exp not in (None, "") else 0
        except Exception:
            experience_years = 0

        raw_rating_avg = lv.get("rating_avg") if lv.get("rating_avg") is not None else lv.get("rating")
        try:
            rating_avg = float(raw_rating_avg) if raw_rating_avg not in (None, "") else 0.0
        except Exception:
            rating_avg = 0.0

        raw_rating_count = lv.get("rating_count") if lv.get("rating_count") is not None else lv.get("reviews_count")
        try:
            rating_count = int(raw_rating_count) if raw_rating_count not in (None, "") else 0
        except Exception:
            rating_count = 0

        vets.append({
            "id": f"legacy-{lv.get('id')}",
            "user_id": lv.get("user_id") or lv.get("id"),
            "name": lv.get("name") or "",
            "specialty": lv.get("specialty") or "",
            "experience_years": experience_years,
            "phone": lv.get("phone") or "",
            "city": lv.get("city") or "",
            "location_text": lv.get("address") or lv.get("location") or "",
            "image_url": lv.get("image") or "",
            "pet_types_supported": _normalize_pet_types(lv.get("pet_types_supported") or []),
            "rating_avg": rating_avg,
            "rating_count": rating_count,
            "is_public": True,
            "status": "active",
            "verified": True,
        })

    return [_serialize_doc(v) for v in vets]

@api_router.get("/vets/{vet_id}/booked-slots")
async def get_vet_booked_slots(vet_id: str, start: str, days: int = Query(14, ge=1, le=90)):
    """Taken date/time pairs for the booking screen; deliberately carries no booker details."""
    try:
        first = datetime.strptime(start, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid start date")
    last = first + timedelta(days=days - 1)
    rows = await db.appointments.find(
        {
            "vet_id": vet_id,
            "date": {"$gte": first.isoformat(), "$lte": last.isoformat()},
            "status": {"$ne": "cancelled"},
        },
        {"_id": 0, "date": 1, "time": 1},
    ).to_list(2000)
    return [{"date": r.get("date"), "time": r.get("time")} for r in rows]

@api_router.get("/vets/{vet_id}")
async def get_vet(vet_id: str):
    vet = await db.vet_profiles.find_one({"id": vet_id, "status": "active", "verified": True, "is_public": True})
    if vet:
        return _serialize_doc(vet)

    legacy = await db.vets.find_one({"id": vet_id, "status": "active", "verified": True, "is_public": True})
    if not legacy:
        raise HTTPException(status_code=404, detail="Vet not found")
    return _serialize_doc(legacy)


@api_router.get("/vet-profile/me")
async def get_my_vet_profile(current_user: dict = Depends(require_roles("vet"))):
    profile = await ensure_vet_profile(current_user["id"], user=current_user)
    return _serialize_doc(profile)


@api_router.put("/vet-profile/me")
async def update_my_vet_profile(data: dict, current_user: dict = Depends(require_roles("vet"))):
    profile = await ensure_vet_profile(current_user["id"], user=current_user)

    allowed = {"name", "specialty", "experience_years", "phone", "city", "location_text", "image_url", "pet_types_supported"}
    patch = {k: v for k, v in (data or {}).items() if k in allowed}

    if "experience_years" in patch:
        try:
            patch["experience_years"] = max(0, int(patch["experience_years"]))
        except Exception:
            raise HTTPException(status_code=400, detail="experience_years must be a number")

    if "pet_types_supported" in patch:
        patch["pet_types_supported"] = _normalize_pet_types(patch.get("pet_types_supported"))

    if profile.get("status") in {"rejected", "draft"}:
        patch["status"] = "draft"

    patch["updated_at"] = datetime.utcnow()
    await db.vet_profiles.update_one({"id": profile["id"]}, {"$set": patch})
    updated = await db.vet_profiles.find_one({"id": profile["id"]})
    return _serialize_doc(updated)


@api_router.post("/vet-profile/me/submit")
async def submit_my_vet_profile(current_user: dict = Depends(require_roles("vet"))):
    profile = await ensure_vet_profile(current_user["id"], user=current_user)

    if profile.get("status") == "suspended":
        raise HTTPException(status_code=400, detail="Profile suspended. Contact admin.")

    was_pending = profile.get("status") == "pending_verification"

    required_fields = ["name", "specialty", "experience_years", "phone", "city"]
    missing = [k for k in required_fields if not profile.get(k)]
    if not profile.get("pet_types_supported"):
        missing.append("pet_types_supported")
    if missing:
        raise HTTPException(status_code=400, detail=f"Missing required fields: {', '.join(missing)}")

    patch = {
        "status": "pending_verification",
        "verified": False,
        "is_public": False,
        "updated_at": datetime.utcnow(),
    }
    await db.vet_profiles.update_one({"id": profile["id"]}, {"$set": patch})

    submit_verb = "resubmitted" if was_pending else "submitted"
    await create_notifications_for_admins(
        "Vet profile verification required",
        f"{current_user.get('name') or 'Vet'} {submit_verb} profile for verification.",
        "vet_profile_verification",
        {
            "profile_id": profile["id"],
            "user_id": current_user["id"],
            "status": "pending_verification",
            "route": "/admin/vet-profiles",
        },
    )

    updated = await db.vet_profiles.find_one({"id": profile["id"]})
    return _serialize_doc(updated)

# ========================= APPOINTMENTS =========================

@api_router.post("/appointments", response_model=Appointment)
async def create_appointment(apt: AppointmentCreate, current_user: dict = Depends(get_current_user)):
    try:
        day = datetime.strptime(apt.date, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date")
    if day < datetime.utcnow().date() - timedelta(days=1):
        raise HTTPException(status_code=400, detail=error_detail("PAST_DATE", "Cannot book a past date"))
    taken = await db.appointments.find_one({
        "vet_id": apt.vet_id,
        "date": apt.date,
        "time": apt.time,
        "status": {"$ne": "cancelled"},
    })
    if taken:
        raise HTTPException(status_code=409, detail=error_detail("SLOT_TAKEN", "This time slot is already booked"))
    appointment = Appointment(**apt.dict(), user_id=current_user["id"])
    await db.appointments.insert_one(appointment.dict())
    vet_profile = await db.vet_profiles.find_one({"id": apt.vet_id}, {"user_id": 1})
    if vet_profile:
        await create_notification(
            vet_profile.get("user_id"),
            "New appointment request",
            f"{current_user.get('name', 'A pet owner')} booked {apt.date} at {apt.time}.",
            "appointment",
            {
                "appointment_id": appointment.id,
                "status": "requested",
                "date": apt.date,
                "time": apt.time,
                "from_user_name": current_user.get("name"),
                "route": "/vet/appointments",
            },
        )
    return appointment

@api_router.get("/appointments", response_model=List[Appointment])
async def get_appointments(current_user: dict = Depends(get_current_user)):
    appointments = await db.appointments.find({
        "$or": [
            {"user_id": current_user["id"]},
            {"vet_id": current_user["id"]}
        ]
    }).sort("created_at", -1).to_list(100)
    return [Appointment(**a) for a in appointments]

@api_router.get("/appointments/{appointment_id}")
async def get_appointment(appointment_id: str, current_user: dict = Depends(get_current_user)):
    appointment = await db.appointments.find_one({
        "id": appointment_id,
        "$or": [
            {"user_id": current_user["id"]},
            {"vet_id": current_user["id"]}
        ]
    })
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")
    return Appointment(**appointment)

class AppointmentConfirm(BaseModel):
    payment_method: str


@api_router.post("/appointments/{appointment_id}/confirm", response_model=Appointment)
async def confirm_appointment(
    appointment_id: str,
    data: AppointmentConfirm,
    current_user: dict = Depends(get_current_user),
):
    """Choose how a booking's fee is paid."""
    appointment = await db.appointments.find_one({"id": appointment_id, "user_id": current_user["id"]})
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")
    if appointment.get("status") == "cancelled":
        raise HTTPException(status_code=400, detail="Appointment is cancelled")
    if appointment.get("payment_status") in ("pending", "paid"):
        raise HTTPException(status_code=409, detail="Appointment is already paid")

    method = (data.payment_method or "").strip().lower()
    if method not in SUPPORTED_PAYMENT_METHODS:
        raise HTTPException(status_code=400, detail="Unsupported payment method")
    # Status stays the vet's call (pending -> confirmed); this only settles how the fee is paid.
    update = {"payment_method": method}
    if method == "cash_on_delivery":
        # Paid in person; no payment record until the clinic collects the money.
        update["payment_status"] = "pay_at_clinic"
    else:
        result = await process_payment(
            PaymentRequest(payment_method=method, appointment_id=appointment_id),
            current_user,
        )
        update["payment_id"] = result["payment_id"]
        update["payment_status"] = "paid" if result["status"] == "succeeded" else "pending"

    await db.appointments.update_one({"id": appointment_id}, {"$set": update})
    return Appointment(**{**appointment, **update})


async def _vet_profile_ids(user_id: str) -> List[str]:
    rows = await db.vet_profiles.find({"user_id": user_id}, {"id": 1}).to_list(20)
    return [r["id"] for r in rows if r.get("id")]


@api_router.get("/vet/appointments")
async def get_vet_appointments(current_user: dict = Depends(require_roles("vet"))):
    """Bookings made with the caller's vet profile, with the pet and owner names a clinic needs."""
    profile_ids = await _vet_profile_ids(current_user["id"])
    if not profile_ids:
        return []
    rows = await db.appointments.find({"vet_id": {"$in": profile_ids}}).sort([("date", 1), ("time", 1)]).to_list(500)
    owner_ids = list({r.get("user_id") for r in rows if r.get("user_id")})
    pet_ids = list({r.get("pet_id") for r in rows if r.get("pet_id")})
    owners = {u["id"]: u for u in await db.users.find({"id": {"$in": owner_ids}}, {"id": 1, "name": 1}).to_list(500)}
    pets = {p["id"]: p for p in await db.pets.find({"id": {"$in": pet_ids}}, {"id": 1, "name": 1, "species": 1}).to_list(500)}
    result = []
    for r in rows:
        item = Appointment(**r).dict()
        item["owner_name"] = owners.get(r.get("user_id"), {}).get("name")
        pet = pets.get(r.get("pet_id")) or {}
        item["pet_name"] = pet.get("name")
        item["pet_species"] = pet.get("species")
        result.append(item)
    return result


class VetAppointmentAction(BaseModel):
    action: str  # accept, decline, complete


_VET_TRANSITIONS = {
    "accept": ({"pending"}, "confirmed", "Appointment accepted", "Your appointment on {date} at {time} was accepted."),
    "decline": ({"pending", "confirmed"}, "cancelled", "Appointment declined", "Your appointment on {date} at {time} was declined by the clinic."),
    "complete": ({"confirmed"}, "completed", "Visit completed", "Your visit on {date} at {time} is marked as completed."),
}


@api_router.put("/vet/appointments/{appointment_id}")
async def update_vet_appointment(
    appointment_id: str,
    data: VetAppointmentAction,
    current_user: dict = Depends(require_roles("vet")),
):
    transition = _VET_TRANSITIONS.get((data.action or "").strip().lower())
    if not transition:
        raise HTTPException(status_code=400, detail="Unknown action")
    allowed_from, new_status, title, body = transition

    profile_ids = await _vet_profile_ids(current_user["id"])
    appointment = await db.appointments.find_one({"id": appointment_id, "vet_id": {"$in": profile_ids}})
    if not appointment:
        raise HTTPException(status_code=404, detail="Appointment not found")
    if appointment.get("status") not in allowed_from:
        raise HTTPException(status_code=409, detail=f"Cannot {data.action} a {appointment.get('status')} appointment")

    update = {"status": new_status}
    if new_status == "cancelled":
        update["cancelled_by"] = "vet"
    if new_status == "completed" and appointment.get("payment_status", "unpaid") in ("unpaid", "pay_at_clinic"):
        # The fee is collected at the clinic during the visit.
        update["payment_status"] = "paid"
        update["payment_method"] = appointment.get("payment_method") or "cash_on_delivery"
    await db.appointments.update_one({"id": appointment_id}, {"$set": update})
    await create_notification(
        appointment.get("user_id"),
        title,
        body.format(date=appointment.get("date"), time=appointment.get("time")),
        "appointment",
        {
            "appointment_id": appointment_id,
            "status": new_status,
            "date": appointment.get("date"),
            "time": appointment.get("time"),
            "route": "/appointments",
        },
    )
    return Appointment(**{**appointment, **update})


@api_router.put("/appointments/{appointment_id}/cancel")
async def cancel_appointment(appointment_id: str, current_user: dict = Depends(get_current_user)):
    result = await db.appointments.update_one(
        {"id": appointment_id, "user_id": current_user["id"]},
        {"$set": {"status": "cancelled"}}
    )
    if result.modified_count == 0:
        raise HTTPException(status_code=404, detail="Appointment not found")
    return {"message": "Appointment cancelled"}

# ========================= CART =========================

class CartItemAdd(BaseModel):
    product_id: str
    name: str
    price: float
    quantity: int = 1
    image: Optional[str] = None

class CartItemUpdate(BaseModel):
    quantity: int

@api_router.get("/cart")
async def get_cart(current_user: dict = Depends(get_current_user)):
    cart = await db.carts.find_one({"user_id": current_user["id"]})
    if not cart:
        return {"items": [], "total": 0}
    
    total = sum(item["price"] * item["quantity"] for item in cart.get("items", []))
    return {"items": cart.get("items", []), "total": total}

@api_router.post("/cart/add")
async def add_to_cart(item: CartItemAdd, current_user: dict = Depends(get_current_user)):
    cart = await db.carts.find_one({"user_id": current_user["id"]})
    
    if not cart:
        # Create new cart
        cart = {
            "user_id": current_user["id"],
            "items": [item.dict()],
            "created_at": datetime.utcnow()
        }
        await db.carts.insert_one(cart)
    else:
        # Check if item already in cart
        existing_item = next(
            (i for i in cart.get("items", []) if i["product_id"] == item.product_id),
            None
        )
        
        if existing_item:
            # Update quantity
            await db.carts.update_one(
                {"user_id": current_user["id"], "items.product_id": item.product_id},
                {"$inc": {"items.$.quantity": item.quantity}}
            )
        else:
            # Add new item
            await db.carts.update_one(
                {"user_id": current_user["id"]},
                {"$push": {"items": item.dict()}}
            )
    
    return {"message": "Item added to cart"}

@api_router.put("/cart/update/{product_id}")
async def update_cart_item(product_id: str, update_data: CartItemUpdate, current_user: dict = Depends(get_current_user)):
    if update_data.quantity <= 0:
        # Remove item if quantity is 0 or less
        await db.carts.update_one(
            {"user_id": current_user["id"]},
            {"$pull": {"items": {"product_id": product_id}}}
        )
        return {"message": "Item removed from cart"}
    
    result = await db.carts.update_one(
        {"user_id": current_user["id"], "items.product_id": product_id},
        {"$set": {"items.$.quantity": update_data.quantity}}
    )
    
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Item not found in cart")
    
    return {"message": "Cart updated"}

@api_router.delete("/cart/remove/{product_id}")
async def remove_from_cart(product_id: str, current_user: dict = Depends(get_current_user)):
    result = await db.carts.update_one(
        {"user_id": current_user["id"]},
        {"$pull": {"items": {"product_id": product_id}}}
    )
    
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Cart not found")
    
    return {"message": "Item removed from cart"}

@api_router.delete("/cart/clear")
async def clear_cart(current_user: dict = Depends(get_current_user)):
    await db.carts.update_one(
        {"user_id": current_user["id"]},
        {"$set": {"items": []}}
    )
    return {"message": "Cart cleared"}

# ========================= ORDERS (SHOP CHECKOUT) =========================

async def resolve_catalog_item(product_id: str) -> Optional[dict]:
    """Look up an orderable item by id in the shop catalog, then the marketplace."""
    product = await db.products.find_one({"id": product_id})
    if product:
        return {
            "name": product.get("name"),
            "price": float(product.get("price") or 0),
            "image": product.get("image"),
            "seller_user_id": None,
            "in_stock": product.get("in_stock", True) is not False,
        }
    listing = await db.marketplace_listings.find_one({"id": product_id})
    if listing:
        return {
            "name": listing.get("title"),
            "price": float(listing.get("price") or 0),
            "image": listing.get("image"),
            "seller_user_id": listing.get("user_id"),
        }
    return None


@api_router.post("/orders", response_model=Order)
async def create_order(order_data: OrderCreate, current_user: dict = Depends(get_current_user)):
    if not order_data.items:
        raise HTTPException(status_code=400, detail="Order must contain at least one item")

    # Prices and totals are re-derived from the catalog; the client only chooses
    # what and how many, never how much it costs.
    enriched_items = []
    server_total = 0.0
    for item in order_data.items:
        if item.quantity < 1 or item.quantity > 100:
            raise HTTPException(status_code=400, detail="Invalid quantity")

        catalog_item = await resolve_catalog_item(item.product_id)
        if not catalog_item:
            raise HTTPException(status_code=400, detail=f"Product not available: {item.product_id}")
        if not catalog_item.get("in_stock", True):
            raise HTTPException(status_code=400, detail=f"Out of stock: {catalog_item['name']}")

        server_total += catalog_item["price"] * item.quantity
        enriched_items.append(OrderItem(
            product_id=item.product_id,
            name=catalog_item["name"],
            price=catalog_item["price"],
            quantity=item.quantity,
            image=catalog_item["image"],
            seller_user_id=catalog_item["seller_user_id"],
        ))

    order_payload = order_data.dict(exclude={"items", "total", "points_used"})
    order = Order(
        **order_payload,
        items=[i.dict() for i in enriched_items],
        total=round(server_total, 2),
        user_id=current_user["id"],
    )
    await db.orders.insert_one(order.dict())
    return order

@api_router.get("/orders", response_model=List[Order])
async def get_orders(current_user: dict = Depends(get_current_user)):
    orders = await db.orders.find({"user_id": current_user["id"]}).sort("created_at", -1).to_list(100)
    return [Order(**o) for o in orders]

@api_router.get("/orders/sales", response_model=List[Order])
async def get_sales_orders(current_user: dict = Depends(get_current_user)):
    orders = await db.orders.find({"items": {"$elemMatch": {"seller_user_id": current_user["id"]}}}).sort("created_at", -1).to_list(200)
    return [Order(**o) for o in orders]

@api_router.get("/orders/{order_id}")
async def get_order(order_id: str, current_user: dict = Depends(get_current_user)):
    order = await db.orders.find_one({"id": order_id, "user_id": current_user["id"]})
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return Order(**order)

# ========================= CONVERSATIONS (CHAT) =========================

@api_router.post("/conversations")
async def create_conversation(data: ConversationCreate, current_user: dict = Depends(get_current_user)):
    # Basic validation
    if data.other_user_id == current_user["id"]:
        raise HTTPException(status_code=400, detail="Cannot start a conversation with yourself")

    initial_message = (data.initial_message or "").strip()
    if not initial_message:
        raise HTTPException(status_code=400, detail="Initial message cannot be empty")

    # Verify other user exists
    other_user = await db.users.find_one({"id": data.other_user_id})
    if not other_user:
        raise HTTPException(status_code=404, detail="Recipient user not found")

    blocked = await db.blocked_users.find_one({"$or": [
        {"user_id": current_user["id"], "blocked_user_id": data.other_user_id},
        {"user_id": data.other_user_id, "blocked_user_id": current_user["id"]},
    ]})
    if blocked:
        raise HTTPException(status_code=403, detail="Cannot message this user")

    # Check if 1:1 conversation already exists (exactly two participants)
    existing = await db.conversations.find_one({
        "participants": {"$all": [current_user["id"], data.other_user_id]},
        "$expr": {"$eq": [{"$size": "$participants"}, 2]}
    })

    if existing:
        # Add message to existing conversation
        chat_msg = ChatMessage(
            conversation_id=existing["id"],
            sender_id=current_user["id"],
            content=initial_message
        )
        await db.chat_messages.insert_one(chat_msg.dict())
        await db.conversations.update_one(
            {"id": existing["id"]},
            {"$set": {"last_message": initial_message, "last_message_time": datetime.utcnow()}}
        )

        await notify_conversation_participants(
            existing["id"],
            "new_message",
            {"message": chat_msg.dict(), "is_new_conversation": False},
        )
        await notify_conversation_participants(existing["id"], "conversations_updated", {})

        return {"conversation_id": existing["id"], "is_new": False}

    other_settings = await db.user_settings.find_one({"user_id": data.other_user_id})
    direct_policy = (other_settings or {}).get("allow_direct_messages", "everyone")
    if direct_policy == "friends_only":
        is_friend = await db.friendships.find_one({"users": {"$all": [current_user["id"], data.other_user_id]}})
        if not is_friend:
            raise HTTPException(
                status_code=403,
                detail=error_detail("DM_FRIENDS_ONLY", "This user accepts messages from friends only"),
            )

    # Create new conversation
    conversation = Conversation(
        participants=[current_user["id"], data.other_user_id],
        pet_id=data.pet_id,
        last_message=initial_message,
        last_message_time=datetime.utcnow()
    )
    await db.conversations.insert_one(conversation.dict())

    # Add initial message
    chat_msg = ChatMessage(
        conversation_id=conversation.id,
        sender_id=current_user["id"],
        content=initial_message
    )
    await db.chat_messages.insert_one(chat_msg.dict())

    await notify_conversation_participants(
        conversation.id,
        "new_message",
        {"message": chat_msg.dict(), "is_new_conversation": True},
    )
    await notify_conversation_participants(conversation.id, "conversations_updated", {})

    return {"conversation_id": conversation.id, "is_new": True}

@api_router.get("/conversations")
async def get_conversations(current_user: dict = Depends(get_current_user)):
    conversations = await db.conversations.find({
        "participants": current_user["id"]
    }).sort("last_message_time", -1).to_list(100)
    
    # Enrich with user info
    result = []
    for conv in conversations:
        other_candidates = [p for p in conv.get("participants", []) if p != current_user["id"]]
        other_user_id = other_candidates[0] if other_candidates else None
        other_user = await db.users.find_one({"id": other_user_id}) if other_user_id else None
        
        # Get unread count
        unread = await db.chat_messages.count_documents({
            "conversation_id": conv["id"],
            "sender_id": {"$ne": current_user["id"]},
            "is_read": False
        })
        
        latest = await db.chat_messages.find_one({"conversation_id": conv["id"]}, sort=[("created_at", -1)])

        # Create a clean dict without MongoDB ObjectId
        clean_conv = {
            "id": conv["id"],
            "participants": conv["participants"],
            "pet_id": conv.get("pet_id"),
            "last_message": conv.get("last_message"),
            "last_message_time": conv.get("last_message_time"),
            "created_at": conv["created_at"],
            "other_user": {
                "id": other_user["id"] if other_user else None,
                "name": other_user["name"] if other_user else "Unknown",
                "avatar": other_user.get("avatar") if other_user else None,
                "is_online": chat_ws_manager.is_online(other_user["id"]) if other_user else False,
            },
            "unread_count": unread,
            "last_message_sender_id": latest.get("sender_id") if latest else None,
            "last_message_is_read": bool(latest.get("is_read")) if latest else False,
        }
        result.append(clean_conv)
    
    return result

async def _friend_exclusion_sets(current_user_id: str):
    blocked_rows = await db.blocked_users.find({"$or": [{"user_id": current_user_id}, {"blocked_user_id": current_user_id}]}).to_list(5000)
    blocked_ids = set()
    for row in blocked_rows:
        if row.get("user_id") == current_user_id:
            blocked_ids.add(row.get("blocked_user_id"))
        if row.get("blocked_user_id") == current_user_id:
            blocked_ids.add(row.get("user_id"))

    outgoing = await db.friend_requests.find({"from_user_id": current_user_id, "status": "pending"}).to_list(500)
    incoming = await db.friend_requests.find({"to_user_id": current_user_id, "status": "pending"}).to_list(500)
    outgoing_set = {r.get("to_user_id") for r in outgoing if r.get("to_user_id")}
    incoming_set = {r.get("from_user_id") for r in incoming if r.get("from_user_id")}
    my_friend_ids = await get_friend_ids_set(current_user_id)
    exclude = {current_user_id} | blocked_ids | my_friend_ids | outgoing_set | incoming_set
    return blocked_ids, outgoing_set, incoming_set, my_friend_ids, exclude


def _haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    from math import radians, sin, cos, asin, sqrt
    r = 6371.0
    dlat = radians(lat2 - lat1)
    dlng = radians(lng2 - lng1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlng / 2) ** 2
    return 2 * r * asin(sqrt(a))


@api_router.get('/friends/activity')
async def friends_activity(
    lat: Optional[float] = None,
    lng: Optional[float] = None,
    radius_km: float = 25,
    limit: int = 40,
    current_user: dict = Depends(get_current_user),
):
    limit = max(1, min(limit, 80))
    radius_km = max(1.0, min(radius_km, 100.0))
    friend_ids = await get_friend_ids_set(current_user["id"])
    friend_list = list(friend_ids)

    items = []
    if friend_list:
        community_posts = await db.community.find({"user_id": {"$in": friend_list}}).sort("created_at", -1).to_list(60)
        for p in community_posts:
            clean = {k: v for k, v in p.items() if k != "_id"}
            items.append({
                "kind": "community",
                "created_at": clean.get("created_at"),
                "nearby_km": None,
                "user_id": clean.get("user_id"),
                "community": clean,
                "lost_found": None,
            })

        lost_posts = await db.lost_found.find({
            "user_id": {"$in": friend_list},
            "status": {"$ne": "resolved"},
        }).sort("created_at", -1).to_list(60)
        for p in lost_posts:
            clean = {k: v for k, v in p.items() if k != "_id"}
            nearby_km = None
            if lat is not None and lng is not None and clean.get("lat") is not None and clean.get("lng") is not None:
                try:
                    nearby_km = round(_haversine_km(float(lat), float(lng), float(clean["lat"]), float(clean["lng"])), 1)
                except Exception:
                    nearby_km = None
            items.append({
                "kind": "lost_found",
                "created_at": clean.get("created_at"),
                "nearby_km": nearby_km,
                "user_id": clean.get("user_id"),
                "community": None,
                "lost_found": clean,
            })

    if lat is not None and lng is not None:
        nearby_candidates = await db.lost_found.find({
            "status": {"$ne": "resolved"},
            "lat": {"$ne": None},
            "lng": {"$ne": None},
        }).sort("created_at", -1).to_list(120)
        seen_ids = {
            (it.get("lost_found") or {}).get("id")
            for it in items
            if it.get("kind") == "lost_found"
        }
        for p in nearby_candidates:
            clean = {k: v for k, v in p.items() if k != "_id"}
            pid = clean.get("id")
            if pid in seen_ids:
                continue
            try:
                dist = _haversine_km(float(lat), float(lng), float(clean["lat"]), float(clean["lng"]))
            except Exception:
                continue
            if dist > radius_km:
                continue
            items.append({
                "kind": "lost_found",
                "created_at": clean.get("created_at"),
                "nearby_km": round(dist, 1),
                "user_id": clean.get("user_id"),
                "community": None,
                "lost_found": clean,
                "is_nearby": True,
            })

    def _sort_key(it):
        ts = it.get("created_at") or datetime.min
        return ts if isinstance(ts, datetime) else datetime.min

    items.sort(key=_sort_key, reverse=True)
    items = items[:limit]

    user_ids = list({it.get("user_id") for it in items if it.get("user_id")})
    users = await db.users.find({"id": {"$in": user_ids}}).to_list(len(user_ids) or 1)
    umap = {u.get("id"): u for u in users}

    result = []
    for it in items:
        uid = it.get("user_id")
        u = umap.get(uid) or {}
        community = it.get("community")
        if community is not None:
            community = {
                **community,
                "comments_count": community.get("comments_count") or community.get("comments") or 0,
                "user_name": community.get("user_name") or u.get("name") or "Unknown",
                "user_avatar": community.get("user_avatar") or u.get("avatar"),
            }
        result.append({
            "kind": it["kind"],
            "created_at": it.get("created_at"),
            "nearby_km": it.get("nearby_km"),
            "is_nearby": bool(it.get("is_nearby")),
            "user": {
                "id": uid,
                "name": u.get("name") or "Unknown",
                "avatar": u.get("avatar"),
                "username": u.get("username"),
            },
            "community": community,
            "lost_found": it.get("lost_found"),
        })
    return result


@api_router.get('/friends/lookup')
async def lookup_friend_by_code(code: str = '', current_user: dict = Depends(get_current_user)):
    raw = (code or '').strip().upper()
    if len(raw) < 3:
        raise HTTPException(status_code=400, detail='Invalid invite code')

    candidates = {raw}
    if raw.startswith('PET-'):
        candidates.add(raw[4:])
    else:
        candidates.add(f'PET-{raw}')

    user = await db.users.find_one({"user_code": {"$in": list(candidates)}})
    if not user:
        for candidate in list(candidates):
            user = await db.users.find_one({"user_code": {"$regex": f"^{re.escape(candidate)}$", "$options": "i"}})
            if user:
                break
    if not user:
        raise HTTPException(status_code=404, detail=error_detail("INVITE_NOT_FOUND", "Invite code not found"))

    uid = user.get("id")
    if uid == current_user["id"]:
        raise HTTPException(status_code=400, detail=error_detail("INVITE_SELF", "Cannot invite yourself"))

    _, outgoing_set, incoming_set, my_friend_ids, _ = await _friend_exclusion_sets(current_user["id"])
    target_friend_ids = await get_friend_ids_set(uid)
    mutual_count = len(my_friend_ids.intersection(target_friend_ids))
    return {
        "id": uid,
        "name": user.get("name"),
        "avatar": user.get("avatar"),
        "username": user.get("username") or normalize_username(user.get("name") or "user"),
        "user_code": user.get("user_code") or generate_user_code(uid or ""),
        "city": user.get("city"),
        "mutual_count": mutual_count,
        "friendship_status": "friends" if uid in my_friend_ids else (
            "outgoing_pending" if uid in outgoing_set else (
                "incoming_pending" if uid in incoming_set else "none"
            )
        ),
    }


@api_router.get('/friends/suggestions')
async def friend_suggestions(limit: int = 20, current_user: dict = Depends(get_current_user)):
    limit = max(1, min(limit, 40))
    _, outgoing_set, incoming_set, my_friend_ids, exclude = await _friend_exclusion_sets(current_user["id"])

    mutual_scores: Dict[str, int] = {}
    for friend_id in list(my_friend_ids)[:200]:
        for other_id in await get_friend_ids_set(friend_id):
            if other_id in exclude:
                continue
            mutual_scores[other_id] = mutual_scores.get(other_id, 0) + 1

    me = await db.users.find_one({"id": current_user["id"]})
    my_city = (me or {}).get("city") or ""
    city_ids: Set[str] = set()
    if my_city.strip():
        city_users = await db.users.find({
            "city": {"$regex": f"^{re.escape(my_city.strip())}$", "$options": "i"},
            "id": {"$nin": list(exclude)},
        }).limit(60).to_list(60)
        city_ids = {u.get("id") for u in city_users if u.get("id")}

    ranked_ids = sorted(mutual_scores.keys(), key=lambda uid: mutual_scores[uid], reverse=True)
    for uid in city_ids:
        if uid not in mutual_scores:
            ranked_ids.append(uid)

    ranked_ids = ranked_ids[:limit]
    if not ranked_ids:
        return []

    users = await db.users.find({"id": {"$in": ranked_ids}}).to_list(limit)
    umap = {u.get("id"): u for u in users}
    result = []
    for uid in ranked_ids:
        u = umap.get(uid)
        if not u:
            continue
        mutual = mutual_scores.get(uid, 0)
        reason = "mutual" if mutual > 0 else "city"
        result.append({
            "id": uid,
            "name": u.get("name"),
            "avatar": u.get("avatar"),
            "username": u.get("username") or normalize_username(u.get("name") or "user"),
            "user_code": u.get("user_code") or generate_user_code(uid or ""),
            "city": u.get("city"),
            "mutual_count": mutual,
            "suggestion_reason": reason,
            "friendship_status": "outgoing_pending" if uid in outgoing_set else (
                "incoming_pending" if uid in incoming_set else "none"
            ),
        })
    return result


@api_router.get('/friends/search')
async def search_users_for_friends(q: str = '', current_user: dict = Depends(get_current_user)):
    keyword = (q or '').strip()
    if len(keyword) < 2:
        return []

    blocked_ids, outgoing_set, incoming_set, my_friend_ids, _ = await _friend_exclusion_sets(current_user["id"])

    regex_query = {
        "$or": [
            {"name": {"$regex": keyword, "$options": "i"}},
            {"username": {"$regex": keyword, "$options": "i"}},
            {"user_code": {"$regex": keyword, "$options": "i"}},
        ],
        "id": {"$ne": current_user["id"], "$nin": list(blocked_ids)}
    }
    users = await db.users.find(regex_query).limit(30).to_list(30)

    result = []
    for u in users:
        uid = u.get("id")
        target_friend_ids = await get_friend_ids_set(uid)
        mutual_count = len(my_friend_ids.intersection(target_friend_ids))
        result.append({
            "id": uid,
            "name": u.get("name"),
            "avatar": u.get("avatar"),
            "username": u.get("username") or normalize_username(u.get("name") or "user"),
            "user_code": u.get("user_code") or generate_user_code(uid or ""),
            "mutual_count": mutual_count,
            "friendship_status": "friends" if uid in my_friend_ids else (
                "outgoing_pending" if uid in outgoing_set else (
                    "incoming_pending" if uid in incoming_set else "none"
                )
            )
        })
    return result

@api_router.get('/friends')
async def get_friends(current_user: dict = Depends(get_current_user)):
    rows = await db.friendships.find({"users": current_user["id"]}).sort("created_at", -1).to_list(2000)
    friend_ids = []
    for fr in rows:
        for uid in fr.get("users", []):
            if uid != current_user["id"]:
                friend_ids.append(uid)
    if not friend_ids:
        return []
    users = await db.users.find({"id": {"$in": friend_ids}}).to_list(2000)
    umap = {u.get("id"): u for u in users}
    my_friend_ids = await get_friend_ids_set(current_user["id"])
    result = []
    for uid in friend_ids:
        target_friend_ids = await get_friend_ids_set(uid)
        mutual_count = len(my_friend_ids.intersection(target_friend_ids))
        result.append({
            "id": uid,
            "name": umap.get(uid, {}).get("name", "Unknown"),
            "avatar": umap.get(uid, {}).get("avatar"),
            "username": umap.get(uid, {}).get("username") or normalize_username(umap.get(uid, {}).get("name") or "user"),
            "user_code": umap.get(uid, {}).get("user_code") or generate_user_code(uid),
            "mutual_count": mutual_count,
            "is_online": chat_ws_manager.is_online(uid),
        })
    return result

@api_router.get('/friends/requests')
async def get_friend_requests(current_user: dict = Depends(get_current_user)):
    incoming = await db.friend_requests.find({"to_user_id": current_user["id"], "status": "pending"}).sort("created_at", -1).to_list(300)
    outgoing = await db.friend_requests.find({"from_user_id": current_user["id"], "status": "pending"}).sort("created_at", -1).to_list(300)

    incoming_user_ids = [r.get("from_user_id") for r in incoming if r.get("from_user_id")]
    outgoing_user_ids = [r.get("to_user_id") for r in outgoing if r.get("to_user_id")]
    users = await db.users.find({"id": {"$in": list(set(incoming_user_ids + outgoing_user_ids))}}).to_list(1000)
    umap = {u.get("id"): u for u in users}

    return {
        "incoming": [{
            "id": r.get("id"),
            "message": r.get("message"),
            "created_at": r.get("created_at"),
            "user": {
                "id": r.get("from_user_id"),
                "name": umap.get(r.get("from_user_id"), {}).get("name", "Unknown"),
                "avatar": umap.get(r.get("from_user_id"), {}).get("avatar"),
                "username": umap.get(r.get("from_user_id"), {}).get("username") or normalize_username(umap.get(r.get("from_user_id"), {}).get("name") or "user"),
                "user_code": umap.get(r.get("from_user_id"), {}).get("user_code") or generate_user_code(r.get("from_user_id") or ""),
            }
        } for r in incoming],
        "outgoing": [{
            "id": r.get("id"),
            "message": r.get("message"),
            "created_at": r.get("created_at"),
            "user": {
                "id": r.get("to_user_id"),
                "name": umap.get(r.get("to_user_id"), {}).get("name", "Unknown"),
                "avatar": umap.get(r.get("to_user_id"), {}).get("avatar"),
                "username": umap.get(r.get("to_user_id"), {}).get("username") or normalize_username(umap.get(r.get("to_user_id"), {}).get("name") or "user"),
                "user_code": umap.get(r.get("to_user_id"), {}).get("user_code") or generate_user_code(r.get("to_user_id") or ""),
            }
        } for r in outgoing]
    }

@api_router.post('/friends/requests')
async def send_friend_request(payload: dict, current_user: dict = Depends(get_current_user)):
    target_user_id = payload.get('target_user_id')
    if not target_user_id or target_user_id == current_user['id']:
        raise HTTPException(status_code=400, detail='Invalid target user')

    target = await db.users.find_one({'id': target_user_id})
    if not target:
        raise HTTPException(status_code=404, detail='User not found')

    blocked = await db.blocked_users.find_one({"$or": [
        {"user_id": current_user["id"], "blocked_user_id": target_user_id},
        {"user_id": target_user_id, "blocked_user_id": current_user["id"]}
    ]})
    if blocked:
        raise HTTPException(status_code=403, detail='Cannot send request to this user')

    target_settings = await db.user_settings.find_one({"user_id": target_user_id})
    allow_requests = (target_settings or {}).get("allow_friend_requests", "everyone")
    if allow_requests == "nobody":
        raise HTTPException(status_code=403, detail='This user is not accepting friend requests')

    existing_friend = await db.friendships.find_one({"users": {"$all": [current_user["id"], target_user_id]}})
    if existing_friend:
        return {"success": True, "status": "already_friends"}

    existing = await db.friend_requests.find_one({
        "from_user_id": current_user["id"],
        "to_user_id": target_user_id,
        "status": "pending"
    })
    if existing:
        return {"success": True, "status": "pending", "request_id": existing.get("id")}

    reverse = await db.friend_requests.find_one({
        "from_user_id": target_user_id,
        "to_user_id": current_user["id"],
        "status": "pending"
    })
    if reverse:
        # auto-accept reverse request
        await db.friend_requests.update_one({"id": reverse.get("id")}, {"$set": {"status": "accepted", "updated_at": datetime.utcnow()}})
        await db.friendships.insert_one({
            "id": str(uuid.uuid4()),
            "users": [current_user["id"], target_user_id],
            "created_at": datetime.utcnow(),
        })
        return {"success": True, "status": "friends"}

    row = {
        "id": str(uuid.uuid4()),
        "from_user_id": current_user["id"],
        "to_user_id": target_user_id,
        "message": (payload.get('message') or '').strip() or None,
        "status": "pending",
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow(),
    }
    await db.friend_requests.insert_one(row)
    sender_name = current_user.get("name") or "Someone"
    await create_notification(
        target_user_id,
        "New friend request",
        f"{sender_name} sent you a friend request.",
        "friend_request",
        {
            "route": "/friends",
            "request_id": row["id"],
            "status": "pending",
            "from_user_id": current_user["id"],
            "from_user_name": sender_name,
            "action": "incoming",
        },
    )
    return {"success": True, "status": "pending", "request_id": row["id"]}

@api_router.put('/friends/requests/{request_id}')
async def review_friend_request(request_id: str, payload: dict, current_user: dict = Depends(get_current_user)):
    action = (payload.get('action') or '').strip().lower()
    if action not in {'accept', 'reject'}:
        raise HTTPException(status_code=400, detail='Invalid action')

    req = await db.friend_requests.find_one({"id": request_id, "to_user_id": current_user["id"], "status": "pending"})
    if not req:
        raise HTTPException(status_code=404, detail='Friend request not found')

    new_status = 'accepted' if action == 'accept' else 'rejected'
    await db.friend_requests.update_one({"id": request_id}, {"$set": {"status": new_status, "updated_at": datetime.utcnow()}})

    if action == 'accept':
        existing_friend = await db.friendships.find_one({"users": {"$all": [current_user["id"], req.get("from_user_id")]}})
        if not existing_friend:
            await db.friendships.insert_one({
                "id": str(uuid.uuid4()),
                "users": [current_user["id"], req.get("from_user_id")],
                "created_at": datetime.utcnow(),
            })

    actor_name = current_user.get("name") or "User"
    await create_notification(
        req.get("from_user_id"),
        "Friend request update",
        f"{actor_name} {new_status} your friend request.",
        "friend_request",
        {
            "route": "/friends",
            "request_id": request_id,
            "status": new_status,
            "from_user_id": current_user["id"],
            "from_user_name": actor_name,
            "action": "update",
        },
    )

    return {"success": True, "status": new_status}


@api_router.delete('/friends/requests/{request_id}')
async def cancel_friend_request(request_id: str, current_user: dict = Depends(get_current_user)):
    req = await db.friend_requests.find_one({
        "id": request_id,
        "from_user_id": current_user["id"],
        "status": "pending",
    })
    if not req:
        raise HTTPException(status_code=404, detail='Friend request not found')

    await db.friend_requests.update_one(
        {"id": request_id},
        {"$set": {"status": "cancelled", "updated_at": datetime.utcnow()}},
    )
    return {"success": True, "status": "cancelled"}


@api_router.get('/friends/blocked')
async def get_blocked_users_in_friends(current_user: dict = Depends(get_current_user)):
    rows = await db.blocked_users.find({"user_id": current_user["id"]}).sort("created_at", -1).to_list(1000)
    ids = [r.get("blocked_user_id") for r in rows if r.get("blocked_user_id")]
    users = await db.users.find({"id": {"$in": ids}}).to_list(1000)
    umap = {u.get("id"): u for u in users}
    return [{
        "id": uid,
        "name": umap.get(uid, {}).get("name", "Unknown"),
        "avatar": umap.get(uid, {}).get("avatar"),
        "username": umap.get(uid, {}).get("username") or normalize_username(umap.get(uid, {}).get("name") or "user"),
        "user_code": umap.get(uid, {}).get("user_code") or generate_user_code(uid),
    } for uid in ids]

@api_router.delete('/friends/{target_user_id}')
async def unfriend_user(target_user_id: str, current_user: dict = Depends(get_current_user)):
    if target_user_id == current_user['id']:
        raise HTTPException(status_code=400, detail='Cannot unfriend yourself')

    deleted = await db.friendships.delete_many({"users": {"$all": [current_user["id"], target_user_id]}})
    await db.friend_requests.delete_many({"$or": [
        {"from_user_id": current_user["id"], "to_user_id": target_user_id},
        {"from_user_id": target_user_id, "to_user_id": current_user["id"]},
    ]})
    if deleted.deleted_count == 0:
        raise HTTPException(status_code=404, detail='Friendship not found')
    return {"success": True}


@api_router.post('/friends/{target_user_id}/block')
async def block_user_in_friends(target_user_id: str, current_user: dict = Depends(get_current_user)):
    if target_user_id == current_user['id']:
        raise HTTPException(status_code=400, detail='Cannot block yourself')

    target = await db.users.find_one({"id": target_user_id})
    if not target:
        raise HTTPException(status_code=404, detail='User not found')

    existing = await db.blocked_users.find_one({"user_id": current_user["id"], "blocked_user_id": target_user_id})
    if not existing:
        await db.blocked_users.insert_one({
            "id": str(uuid.uuid4()),
            "user_id": current_user["id"],
            "blocked_user_id": target_user_id,
            "created_at": datetime.utcnow(),
        })

    await db.friend_requests.delete_many({"$or": [
        {"from_user_id": current_user["id"], "to_user_id": target_user_id},
        {"from_user_id": target_user_id, "to_user_id": current_user["id"]},
    ]})
    await db.friendships.delete_many({"users": {"$all": [current_user["id"], target_user_id]}})
    return {"success": True}

@api_router.delete('/friends/{target_user_id}/block')
async def unblock_user_in_friends(target_user_id: str, current_user: dict = Depends(get_current_user)):
    await db.blocked_users.delete_one({"user_id": current_user["id"], "blocked_user_id": target_user_id})
    return {"success": True}

@api_router.post('/friends/report')
async def report_user_in_friends(payload: dict, current_user: dict = Depends(get_current_user)):
    target_user_id = payload.get('target_user_id')
    reason = (payload.get('reason') or 'abuse').strip()
    notes = payload.get('notes')
    if not target_user_id or target_user_id == current_user['id']:
        raise HTTPException(status_code=400, detail='Invalid target user')

    target = await db.users.find_one({"id": target_user_id})
    if not target:
        raise HTTPException(status_code=404, detail='User not found')

    await db.friend_reports.insert_one({
        "id": str(uuid.uuid4()),
        "reported_by": current_user["id"],
        "target_user_id": target_user_id,
        "reason": reason,
        "notes": notes,
        "status": "open",
        "created_at": datetime.utcnow(),
    })
    await create_notifications_for_admins(
        "User reported",
        f"{current_user.get('name', 'User')} reported a user profile.",
        "admin",
        {"route": "/admin/users", "target_user_id": target_user_id}
    )
    return {"success": True}

@api_router.get('/admin/friend-reports')
async def get_friend_reports_admin(target_user_id: Optional[str] = None, status: Optional[str] = None, admin_user: dict = Depends(get_admin_user)):
    query: dict = {}
    if target_user_id:
        query["target_user_id"] = target_user_id
    if status:
        query["status"] = status
    rows = await db.friend_reports.find(query).sort("created_at", -1).to_list(1000)
    uids = list({r.get("reported_by") for r in rows if r.get("reported_by")} | {r.get("target_user_id") for r in rows if r.get("target_user_id")})
    users = await db.users.find({"id": {"$in": uids}}).to_list(2000)
    umap = {u.get("id"): u for u in users}
    result = []
    for r in rows:
        result.append({
            "id": r.get("id"),
            "reason": r.get("reason"),
            "notes": r.get("notes"),
            "status": r.get("status", "open"),
            "created_at": r.get("created_at"),
            "reported_by": {
                "id": r.get("reported_by"),
                "name": umap.get(r.get("reported_by"), {}).get("name", "Unknown"),
                "email": umap.get(r.get("reported_by"), {}).get("email"),
            },
            "target_user": {
                "id": r.get("target_user_id"),
                "name": umap.get(r.get("target_user_id"), {}).get("name", "Unknown"),
                "email": umap.get(r.get("target_user_id"), {}).get("email"),
            },
            "reviewed_at": r.get("reviewed_at"),
            "reviewed_by": r.get("reviewed_by"),
        })
    return result

@api_router.put('/admin/friend-reports/{report_id}')
async def review_friend_report_admin(report_id: str, payload: dict, admin_user: dict = Depends(get_admin_user)):
    action = (payload.get('action') or '').strip().lower()  # resolve|reject|block_target
    if action not in {'resolve', 'reject', 'block_target'}:
        raise HTTPException(status_code=400, detail='Invalid action')

    report = await db.friend_reports.find_one({"id": report_id})
    if not report:
        raise HTTPException(status_code=404, detail='Report not found')

    status_val = 'resolved' if action in {'resolve', 'block_target'} else 'rejected'

    if action == 'block_target':
        target_user_id = report.get('target_user_id')
        reporter_id = report.get('reported_by')
        if target_user_id and reporter_id:
            existing = await db.blocked_users.find_one({"user_id": reporter_id, "blocked_user_id": target_user_id})
            if not existing:
                await db.blocked_users.insert_one({
                    "id": str(uuid.uuid4()),
                    "user_id": reporter_id,
                    "blocked_user_id": target_user_id,
                    "created_at": datetime.utcnow(),
                })

    await db.friend_reports.update_one(
        {"id": report_id},
        {"$set": {
            "status": status_val,
            "review_action": action,
            "reviewed_at": datetime.utcnow(),
            "reviewed_by": admin_user.get("id"),
        }}
    )
    await audit_admin_action(admin_user, "review_friend_report", "friend_report", report_id, {"action": action, "status": status_val})
    return {"success": True, "status": status_val}

@api_router.post('/conversations/direct/{other_user_id}')
async def start_direct_conversation(other_user_id: str, current_user: dict = Depends(get_current_user)):
    if other_user_id == current_user['id']:
        raise HTTPException(status_code=400, detail='Cannot chat with yourself')

    blocked = await db.blocked_users.find_one({"$or": [
        {"user_id": current_user["id"], "blocked_user_id": other_user_id},
        {"user_id": other_user_id, "blocked_user_id": current_user["id"]},
    ]})
    if blocked:
        raise HTTPException(status_code=403, detail='Cannot message this user')

    is_friend = await db.friendships.find_one({"users": {"$all": [current_user["id"], other_user_id]}})
    if not is_friend:
        raise HTTPException(status_code=403, detail='You can only chat with friends')

    other_user = await db.users.find_one({"id": other_user_id})
    if not other_user:
        raise HTTPException(status_code=404, detail='User not found')

    existing = await db.conversations.find_one({
        "participants": {"$all": [current_user["id"], other_user_id]},
        "$expr": {"$eq": [{"$size": "$participants"}, 2]}
    })
    if existing:
        return {"conversation_id": existing["id"], "is_new": False}

    conversation = Conversation(
        participants=[current_user["id"], other_user_id],
        pet_id=None,
        last_message=None,
        last_message_time=datetime.utcnow(),
    )
    await db.conversations.insert_one(conversation.dict())
    await notify_conversation_participants(conversation.id, "conversations_updated", {})
    return {"conversation_id": conversation.id, "is_new": True}

@api_router.get("/conversations/{conversation_id}/messages")
async def get_chat_messages(conversation_id: str, current_user: dict = Depends(get_current_user)):
    # Verify user is participant
    conversation = await db.conversations.find_one({
        "id": conversation_id,
        "participants": current_user["id"]
    })
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")

    # Mark messages as read
    read_result = await db.chat_messages.update_many(
        {"conversation_id": conversation_id, "sender_id": {"$ne": current_user["id"]}, "is_read": False},
        {"$set": {"is_read": True}}
    )

    if read_result.modified_count > 0:
        await notify_conversation_participants(
            conversation_id,
            "messages_read",
            {"reader_id": current_user["id"]},
        )

    messages = await db.chat_messages.find({"conversation_id": conversation_id}).sort("created_at", -1).to_list(CHAT_HISTORY_LIMIT)
    messages.reverse()

    # Enrich conversation with the other user's display name/avatar
    other_user_id = None
    for pid in (conversation.get("participants") or []):
        if pid != current_user.get("id"):
            other_user_id = pid
            break
    other_user = None
    if other_user_id:
        row = await db.users.find_one({"id": other_user_id})
        if row:
            other_user = {
                "id": row.get("id"),
                "name": row.get("name") or row.get("username") or "User",
                "avatar": row.get("avatar"),
                "is_online": chat_ws_manager.is_online(other_user_id),
            }

    # Return object form; frontend supports both array and object.
    return {
        "conversation": {
            "id": conversation.get("id"),
            "other_user": other_user,
        },
        "messages": [ChatMessage(**m) for m in messages],
    }

@api_router.post("/conversations/{conversation_id}/read")
async def mark_conversation_read(conversation_id: str, current_user: dict = Depends(get_current_user)):
    conversation = await db.conversations.find_one({
        "id": conversation_id,
        "participants": current_user["id"]
    })
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")

    read_result = await db.chat_messages.update_many(
        {"conversation_id": conversation_id, "sender_id": {"$ne": current_user["id"]}, "is_read": False},
        {"$set": {"is_read": True}}
    )

    if read_result.modified_count > 0:
        await notify_conversation_participants(
            conversation_id,
            "messages_read",
            {"reader_id": current_user["id"]},
        )

    return {"updated": int(read_result.modified_count)}

CHAT_MESSAGE_MAX_LENGTH = 4000
CHAT_HISTORY_LIMIT = 200
PHOTO_PREVIEW = "📷"


async def _participant_conversation(conversation_id: str, user_id: str) -> dict:
    conversation = await db.conversations.find_one({"id": conversation_id, "participants": user_id})
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")
    return conversation


async def _refresh_last_message(conversation_id: str):
    latest = await db.chat_messages.find_one({"conversation_id": conversation_id}, sort=[("created_at", -1)])
    await db.conversations.update_one(
        {"id": conversation_id},
        {"$set": {
            "last_message": ((latest.get("content") or "").strip() or PHOTO_PREVIEW) if latest else None,
            "last_message_time": latest.get("created_at") if latest else None,
        }},
    )


@api_router.post("/conversations/{conversation_id}/messages")
async def send_chat_message(
    conversation_id: str,
    content: str = "",
    image_url: Optional[str] = None,
    reply_to_message_id: Optional[str] = None,
    current_user: dict = Depends(get_current_user),
):
    await _participant_conversation(conversation_id, current_user["id"])

    clean_content = (content or "").strip()
    clean_image = (image_url or "").strip() or None
    if not clean_content and not clean_image:
        raise HTTPException(status_code=400, detail="Message content cannot be empty")
    if len(clean_content) > CHAT_MESSAGE_MAX_LENGTH:
        raise HTTPException(status_code=400, detail=error_detail("MESSAGE_TOO_LONG", "Message is too long"))
    if clean_image and not _valid_media_url(clean_image):
        raise HTTPException(status_code=400, detail=error_detail("INVALID_IMAGE", "Invalid image"))

    reply_fields = {}
    if reply_to_message_id:
        original = await db.chat_messages.find_one({"id": reply_to_message_id, "conversation_id": conversation_id})
        if original:
            reply_fields = {
                "reply_to_message_id": original["id"],
                "reply_to_content": (original.get("content") or "")[:300],
                "reply_to_sender_id": original.get("sender_id"),
            }

    chat_msg = ChatMessage(
        conversation_id=conversation_id,
        sender_id=current_user["id"],
        content=clean_content,
        image_url=clean_image,
        **reply_fields,
    )
    await db.chat_messages.insert_one(chat_msg.dict())

    await db.conversations.update_one(
        {"id": conversation_id},
        {"$set": {"last_message": clean_content or PHOTO_PREVIEW, "last_message_time": chat_msg.created_at}}
    )

    await notify_conversation_participants(
        conversation_id,
        "new_message",
        {"message": chat_msg.dict(), "is_new_conversation": False},
    )
    await notify_conversation_participants(conversation_id, "conversations_updated", {})
    spawn_background(_push_chat_message(conversation_id, current_user, chat_msg))

    return chat_msg


async def _push_chat_message(conversation_id: str, sender: dict, msg: "ChatMessage") -> None:
    conversation = await db.conversations.find_one({"id": conversation_id}, {"participants": 1})
    recipients = [uid for uid in (conversation or {}).get("participants", []) if uid and uid != sender["id"]]
    if not recipients:
        return
    settings_rows = await db.user_settings.find(
        {"user_id": {"$in": recipients}}, {"user_id": 1, "muted_conversation_ids": 1, "chat_preview": 1}
    ).to_list(len(recipients))
    settings = {row["user_id"]: row for row in settings_rows}
    sender_name = sender.get("name") or "Petsy"
    for uid in recipients:
        row = settings.get(uid, {})
        if conversation_id in (row.get("muted_conversation_ids") or []):
            continue
        if row.get("chat_preview", True):
            preview = msg.content or None
            texts = {
                "ar": (sender_name, preview or "📷 صورة"),
                "en": (sender_name, preview or "📷 Photo"),
            }
        else:
            texts = {"ar": (sender_name, "رسالة جديدة"), "en": (sender_name, "New message")}
        await send_push_to_user(
            uid,
            texts["en"][0],
            texts["en"][1],
            "chat_message",
            {"conversation_id": conversation_id, "route": f"/chat/{conversation_id}"},
            texts_by_lang=texts,
            tag=f"chat_{conversation_id}",
        )


@api_router.delete("/conversations/{conversation_id}/messages/{message_id}")
async def delete_chat_message(conversation_id: str, message_id: str, current_user: dict = Depends(get_current_user)):
    await _participant_conversation(conversation_id, current_user["id"])
    result = await db.chat_messages.delete_one(
        {"id": message_id, "conversation_id": conversation_id, "sender_id": current_user["id"]}
    )
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Message not found")
    await _refresh_last_message(conversation_id)
    await notify_conversation_participants(conversation_id, "message_deleted", {"message_id": message_id})
    await notify_conversation_participants(conversation_id, "conversations_updated", {})
    return {"deleted": True}


@api_router.delete("/conversations/{conversation_id}")
async def delete_conversation(conversation_id: str, current_user: dict = Depends(get_current_user)):
    await _participant_conversation(conversation_id, current_user["id"])
    # Notify before deleting: participants are looked up from the conversation document.
    await notify_conversation_participants(conversation_id, "conversation_deleted", {"conversation_id": conversation_id})
    await db.chat_messages.delete_many({"conversation_id": conversation_id})
    await db.conversations.delete_one({"id": conversation_id})
    return {"deleted": True}

# ========================= DEVICES =========================

class DeviceRegistration(BaseModel):
    token: str = Field(min_length=8, max_length=4096)
    platform: str = Field(pattern="^(android|ios|web)$")
    provider: str = Field(default="local", pattern="^(local|fcm)$")
    language: str = Field(default="en", pattern="^(ar|en)$")


@api_router.post("/devices/register")
async def register_device(data: DeviceRegistration, current_user: dict = Depends(get_current_user)):
    now = datetime.utcnow()
    await db.device_tokens.update_one(
        {"token": data.token},
        {
            "$set": {
                "user_id": current_user["id"],
                "platform": data.platform,
                "provider": data.provider,
                "language": data.language,
                "updated_at": now,
            },
            "$setOnInsert": {"id": str(uuid.uuid4()), "created_at": now},
        },
        upsert=True,
    )
    return {"registered": True}


class DeviceUnregistration(BaseModel):
    token: str = Field(min_length=8, max_length=4096)


@api_router.post("/devices/unregister")
async def unregister_device(data: DeviceUnregistration, current_user: dict = Depends(get_current_user)):
    result = await db.device_tokens.delete_one({"token": data.token, "user_id": current_user["id"]})
    return {"unregistered": result.deleted_count > 0}


@api_router.post("/notifications/push-test", dependencies=[Depends(rate_limit("push_test", 10, 3600))])
async def push_test(current_user: dict = Depends(get_current_user)):
    await create_notification(current_user["id"], "Petsy", "Test notification", "push_test")
    return {"sent": True}

# ========================= UPLOADS =========================

UPLOAD_DIR = ROOT_DIR / "uploads"
UPLOAD_DIR.mkdir(exist_ok=True)
UPLOAD_MAX_BYTES = 8 * 1024 * 1024
UPLOAD_FORMATS = {"JPEG": "jpg", "PNG": "png", "WEBP": "webp", "GIF": "gif"}
UPLOAD_URL_PATTERN = re.compile(r"^/uploads/[a-f0-9]{32}\.(jpg|png|webp|gif)$")


@api_router.post("/uploads", dependencies=[Depends(rate_limit("upload", 60, 3600))])
async def upload_image(file: UploadFile = File(...), current_user: dict = Depends(get_current_user)):
    data = await file.read(UPLOAD_MAX_BYTES + 1)
    if len(data) > UPLOAD_MAX_BYTES:
        raise HTTPException(status_code=413, detail=error_detail("FILE_TOO_LARGE", "Image is larger than 8 MB"))
    try:
        from PIL import Image
        from io import BytesIO

        with Image.open(BytesIO(data)) as image:
            fmt = image.format
            image.verify()
    except Exception:
        raise HTTPException(status_code=400, detail=error_detail("INVALID_IMAGE", "File is not a supported image"))
    ext = UPLOAD_FORMATS.get(fmt or "")
    if not ext:
        raise HTTPException(status_code=400, detail=error_detail("INVALID_IMAGE", "File is not a supported image"))
    name = f"{uuid.uuid4().hex}.{ext}"
    (UPLOAD_DIR / name).write_bytes(data)
    return {"url": f"/uploads/{name}"}


def _valid_media_url(url: str) -> bool:
    return bool(UPLOAD_URL_PATTERN.match(url)) or (url.startswith("https://") and len(url) <= 2048)

# ========================= MAP LOCATIONS =========================

@api_router.get("/map-locations", response_model=List[MapLocation])
async def get_map_locations(
    type: Optional[str] = None,
    city: Optional[str] = None,
    lat: Optional[float] = None,
    lng: Optional[float] = None,
    radius_km: float = 50
):
    query = {}
    if type:
        query["type"] = type
    if city:
        query["city"] = {"$regex": city, "$options": "i"}
    
    locations = await db.map_locations.find(query).to_list(100)
    return [MapLocation(**loc) for loc in locations]

# ========================= PRODUCTS (SHOP) =========================

@api_router.get("/products", response_model=List[Product])
async def get_products(
    category: Optional[str] = None,
    pet_type: Optional[str] = None,
    limit: int = 50,
    skip: int = 0
):
    query = {}
    if category:
        query["category"] = category
    if pet_type:
        query["pet_type"] = pet_type
    
    products = await db.products.find(query).skip(skip).limit(limit).to_list(limit)
    return [Product(**p) for p in products]

@api_router.get("/products/{product_id}", response_model=Product)
async def get_product(product_id: str):
    product = await db.products.find_one({"id": product_id})
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    return Product(**product)

# ========================= EMERGENCY CONTACTS =========================

@api_router.get("/emergency-contacts", response_model=List[EmergencyContact])
async def get_emergency_contacts(city: Optional[str] = None):
    query = {}
    if city:
        query["city"] = {"$regex": city, "$options": "i"}
    contacts = await db.emergency_contacts.find(query).to_list(100)
    return [EmergencyContact(**c) for c in contacts]

# ========================= MESSAGES =========================

@api_router.post("/messages", response_model=Message)
async def send_message(msg: MessageBase, current_user: dict = Depends(get_current_user)):
    message = Message(**msg.dict(), sender_id=current_user["id"])
    await db.messages.insert_one(message.dict())
    return message

@api_router.get("/messages", response_model=List[Message])
async def get_messages(current_user: dict = Depends(get_current_user)):
    messages = await db.messages.find({
        "$or": [
            {"sender_id": current_user["id"]},
            {"receiver_id": current_user["id"]}
        ]
    }).sort("created_at", -1).to_list(100)
    return [Message(**m) for m in messages]

@api_router.put("/messages/{message_id}/read")
async def mark_message_read(message_id: str, current_user: dict = Depends(get_current_user)):
    await db.messages.update_one(
        {"id": message_id, "receiver_id": current_user["id"]},
        {"$set": {"is_read": True}}
    )
    return {"message": "Marked as read"}

# ========================= LOST & FOUND =========================

@api_router.post("/lost-found", response_model=LostFoundPost)
async def create_lost_found(post: LostFoundCreate, current_user: dict = Depends(get_current_user)):
    lost_found = LostFoundPost(**post.dict(), user_id=current_user["id"])
    await db.lost_found.insert_one(lost_found.dict())
    return lost_found

@api_router.get("/lost-found", response_model=List[LostFoundPost])
async def get_lost_found(type: Optional[str] = None, status: str = "active"):
    query = {"status": status}
    if type:
        query["type"] = type
    posts = await db.lost_found.find(query).sort("created_at", -1).to_list(100)
    return [LostFoundPost(**p) for p in posts]

@api_router.put("/lost-found/{post_id}/resolve", response_model=LostFoundPost)
async def resolve_lost_found(post_id: str, current_user: dict = Depends(get_current_user)):
    post = await db.lost_found.find_one({"id": post_id})
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    if post.get("user_id") != current_user["id"]:
        raise HTTPException(status_code=403, detail="Only the author can resolve this post")
    if post.get("status") != "resolved":
        now = datetime.utcnow()
        await db.lost_found.update_one({"id": post_id}, {"$set": {"status": "resolved", "resolved_at": now}})
        post.update(status="resolved", resolved_at=now)
    return LostFoundPost(**post)

@api_router.get("/lost-found/{post_id}", response_model=LostFoundPost)
async def get_lost_found_by_id(post_id: str):
    post = await db.lost_found.find_one({"id": post_id})
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    return LostFoundPost(**post)

# ========================= COMMUNITY =========================

@api_router.post("/community", response_model=CommunityPost)
async def create_community_post(post: CommunityPostCreate, current_user: dict = Depends(get_current_user)):
    community_post = CommunityPost(
        **post.dict(),
        user_id=current_user["id"],
        user_name=current_user["name"],
        user_avatar=current_user.get("avatar")
    )
    await db.community.insert_one(community_post.dict())
    return community_post

@api_router.get("/users/{user_id}/public")
async def get_public_user_profile(user_id: str, current_user: Optional[dict] = Depends(get_current_user_optional)):
    user = await db.users.find_one({"id": user_id})
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    posts_count = await db.community.count_documents({"user_id": user_id})
    is_blocked = False
    is_self = False
    friendship_status = "none"
    incoming_request_id = None
    mutual_count = 0
    friends_count = len(await get_friend_ids_set(user_id))
    if current_user:
        is_self = current_user["id"] == user_id
        my_friend_ids = await get_friend_ids_set(current_user["id"])
        target_friend_ids = await get_friend_ids_set(user_id)
        if not is_self:
            mutual_count = len(my_friend_ids.intersection(target_friend_ids))
            blocked = await db.blocked_users.find_one({
                "user_id": current_user["id"],
                "blocked_user_id": user_id,
            })
            is_blocked = bool(blocked)
            if user_id in my_friend_ids:
                friendship_status = "friends"
            else:
                outgoing = await db.friend_requests.find_one({
                    "from_user_id": current_user["id"],
                    "to_user_id": user_id,
                    "status": "pending",
                })
                incoming = await db.friend_requests.find_one({
                    "from_user_id": user_id,
                    "to_user_id": current_user["id"],
                    "status": "pending",
                })
                if outgoing:
                    friendship_status = "outgoing_pending"
                elif incoming:
                    friendship_status = "incoming_pending"
                    incoming_request_id = incoming.get("id")

    return {
        "id": user["id"],
        "name": user.get("name") or "Unknown",
        "username": user.get("username"),
        "user_code": user.get("user_code"),
        "city": user.get("city"),
        "bio": user.get("bio"),
        "avatar": user.get("avatar"),
        "role": user.get("role") or "user",
        "is_verified": bool(user.get("is_verified")),
        "created_at": user.get("created_at"),
        "posts_count": posts_count,
        "friends_count": friends_count,
        "mutual_count": mutual_count,
        "is_blocked": is_blocked,
        "is_self": is_self,
        "friendship_status": friendship_status,
        "incoming_request_id": incoming_request_id,
    }


@api_router.get("/community", response_model=List[CommunityPost])
async def get_community_posts(
    type: Optional[str] = None,
    user_id: Optional[str] = None,
    limit: int = 50,
    current_user: Optional[dict] = Depends(get_current_user_optional),
):
    query = {}
    if type:
        query["type"] = type
    if user_id:
        query["user_id"] = user_id

    # Hide posts from blocked users for the current user (unless viewing a specific author).
    if current_user and not user_id:
        blocked_rows = await db.blocked_users.find({"user_id": current_user["id"]}).to_list(1000)
        blocked_ids = [r.get("blocked_user_id") for r in blocked_rows if r.get("blocked_user_id")]
        if blocked_ids:
            query["user_id"] = {"$nin": blocked_ids}

    posts = await db.community.find(query).sort("created_at", -1).limit(limit).to_list(limit)

    enriched = []
    for p in posts:
      clean = {k: v for k, v in p.items() if k != "_id"}
      comments_count = await db.comments.count_documents({"post_id": clean.get("id")})
      clean["comments_count"] = comments_count
      clean["comments"] = comments_count
      enriched.append(CommunityPost(**clean))

    return enriched

@api_router.get("/community/post/{post_id}", response_model=CommunityPost)
async def get_community_post_by_id(post_id: str):
    post = await db.community.find_one({"id": post_id})
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    clean = {k: v for k, v in post.items() if k != "_id"}
    comments_count = await db.comments.count_documents({"post_id": clean.get("id")})
    clean["comments_count"] = comments_count
    clean["comments"] = comments_count
    return CommunityPost(**clean)

@api_router.post("/community/{post_id}/like")
async def like_community_post(post_id: str, current_user: dict = Depends(get_current_user)):
    await db.community.update_one({"id": post_id}, {"$inc": {"likes": 1}})
    return {"message": "Liked"}

@api_router.post("/community/{post_id}/report")
async def report_community_post(post_id: str, data: dict = {}, current_user: dict = Depends(get_current_user)):
    post = await db.community.find_one({"id": post_id})
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    row = {
        "id": str(uuid.uuid4()),
        "post_id": post_id,
        "reported_by": current_user["id"],
        "post_owner_id": post.get("user_id"),
        "reason": data.get("reason", "inappropriate"),
        "notes": data.get("notes"),
        "created_at": datetime.utcnow(),
    }
    await db.community_reports.insert_one(row)
    return {"message": "Report submitted"}

@api_router.post("/community/users/{target_user_id}/block")
async def block_community_user(target_user_id: str, current_user: dict = Depends(get_current_user)):
    if target_user_id == current_user["id"]:
        raise HTTPException(status_code=400, detail="Cannot block yourself")

    existing = await db.blocked_users.find_one({"user_id": current_user["id"], "blocked_user_id": target_user_id})
    if not existing:
        await db.blocked_users.insert_one({
            "id": str(uuid.uuid4()),
            "user_id": current_user["id"],
            "blocked_user_id": target_user_id,
            "created_at": datetime.utcnow(),
        })
    return {"message": "User blocked"}

@api_router.delete("/community/users/{target_user_id}/block")
async def unblock_community_user(target_user_id: str, current_user: dict = Depends(get_current_user)):
    await db.blocked_users.delete_one({"user_id": current_user["id"], "blocked_user_id": target_user_id})
    return {"message": "User unblocked"}

@api_router.get("/community/blocked-users")
async def get_blocked_users(current_user: dict = Depends(get_current_user)):
    rows = await db.blocked_users.find({"user_id": current_user["id"]}).sort("created_at", -1).to_list(1000)
    result = []
    for r in rows:
        uid = r.get("blocked_user_id")
        u = await db.users.find_one({"id": uid})
        result.append({
            "user_id": uid,
            "name": (u or {}).get("name", "Unknown"),
            "avatar": (u or {}).get("avatar"),
            "blocked_at": r.get("created_at"),
        })
    return result

@api_router.post("/community/{post_id}/notify")
async def enable_post_notifications(post_id: str, current_user: dict = Depends(get_current_user)):
    existing = await db.community_post_notifications.find_one({"user_id": current_user["id"], "post_id": post_id})
    if not existing:
        await db.community_post_notifications.insert_one({
            "id": str(uuid.uuid4()),
            "user_id": current_user["id"],
            "post_id": post_id,
            "created_at": datetime.utcnow(),
        })
    return {"message": "Notifications enabled"}

@api_router.delete("/community/{post_id}/notify")
async def disable_post_notifications(post_id: str, current_user: dict = Depends(get_current_user)):
    await db.community_post_notifications.delete_one({"user_id": current_user["id"], "post_id": post_id})
    return {"message": "Notifications disabled"}

@api_router.get("/community/notifications/subscriptions")
async def get_notification_subscriptions(current_user: dict = Depends(get_current_user)):
    rows = await db.community_post_notifications.find({"user_id": current_user["id"]}).to_list(2000)
    return [r.get("post_id") for r in rows if r.get("post_id")]

# ========================= COMMUNITY COMMENTS =========================

class CommentCreate(BaseModel):
    content: str
    parent_comment_id: Optional[str] = None

class Comment(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    post_id: str
    user_id: str
    user_name: str
    user_avatar: Optional[str] = None
    content: str
    likes: int = 0
    parent_comment_id: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)

@api_router.post("/community/{post_id}/comments")
async def create_comment(post_id: str, comment: CommentCreate, current_user: dict = Depends(get_current_user)):
    new_comment = Comment(
        post_id=post_id,
        user_id=current_user["id"],
        user_name=current_user["name"],
        user_avatar=current_user.get("avatar"),
        content=comment.content,
        parent_comment_id=comment.parent_comment_id
    )
    await db.comments.insert_one(new_comment.dict())
    await db.community.update_one({"id": post_id}, {"$inc": {"comments": 1}})
    return new_comment

@api_router.get("/community/{post_id}/comments", response_model=List[Comment])
async def get_comments(post_id: str):
    comments = await db.comments.find({"post_id": post_id}).sort("created_at", 1).to_list(300)
    return [Comment(**{k: v for k, v in c.items() if k != "_id"}) for c in comments]

@api_router.post('/community/comments/{comment_id}/like')
async def like_comment(comment_id: str, current_user: dict = Depends(get_current_user)):
    result = await db.comments.update_one({'id': comment_id}, {'$inc': {'likes': 1}})
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail='Comment not found')
    return {'message': 'Comment liked'}

# ========================= HEALTH RECORDS =========================

class HealthRecordCreate(BaseModel):
    pet_id: str
    record_type: str  # vaccination, vet_visit, medication, weight, other
    title: str
    description: Optional[str] = None
    date: str
    vet_name: Optional[str] = None
    clinic_name: Optional[str] = None
    next_due_date: Optional[str] = None
    notes: Optional[str] = None
    attachments: Optional[List[str]] = []
    appointment_id: Optional[str] = None

class HealthRecord(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    pet_id: str
    user_id: Optional[str] = None
    record_type: str
    title: str
    description: Optional[str] = None
    date: str
    vet_name: Optional[str] = None
    clinic_name: Optional[str] = None
    next_due_date: Optional[str] = None
    notes: Optional[str] = None
    attachments: List[str] = []
    appointment_id: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)


async def _owned_pet(pet_id: str, user_id: str) -> dict:
    pet = await db.pets.find_one({"id": pet_id, "owner_id": user_id})
    if not pet:
        raise HTTPException(status_code=404, detail="Pet not found")
    return pet


@api_router.post("/health-records", response_model=HealthRecord)
async def create_health_record(record: HealthRecordCreate, current_user: dict = Depends(get_current_user)):
    await _owned_pet(record.pet_id, current_user["id"])
    if record.appointment_id:
        appointment = await db.appointments.find_one({"id": record.appointment_id, "user_id": current_user["id"]})
        if not appointment:
            raise HTTPException(status_code=404, detail="Appointment not found")
    health_record = HealthRecord(**record.dict(exclude={"attachments"}), attachments=record.attachments or [], user_id=current_user["id"])
    await db.health_records.insert_one(health_record.dict())
    return health_record

@api_router.get("/health-records/{pet_id}", response_model=List[HealthRecord])
async def get_health_records(pet_id: str, current_user: dict = Depends(get_current_user)):
    await _owned_pet(pet_id, current_user["id"])
    records = await db.health_records.find({"pet_id": pet_id}).sort("date", -1).to_list(200)
    return [HealthRecord(**r) for r in records]

@api_router.delete("/health-records/{record_id}")
async def delete_health_record(record_id: str, current_user: dict = Depends(get_current_user)):
    record = await db.health_records.find_one({"id": record_id})
    if not record or not await db.pets.find_one({"id": record.get("pet_id"), "owner_id": current_user["id"]}):
        raise HTTPException(status_code=404, detail="Record not found")
    await db.health_records.delete_one({"id": record_id})
    return {"message": "Record deleted"}

# ========================= FAVORITES =========================

FAVORITE_ITEM_TYPES = {"product"}  # pets are favorited through /pets/{id}/like


def _check_favorite_type(item_type: str):
    if item_type not in FAVORITE_ITEM_TYPES:
        raise HTTPException(status_code=400, detail="Unsupported favorite type")


@api_router.get("/favorites/{item_type}/{item_id}")
async def get_favorite_state(item_type: str, item_id: str, current_user: dict = Depends(get_current_user)):
    _check_favorite_type(item_type)
    existing = await db.favorites.find_one({"user_id": current_user["id"], "item_type": item_type, "item_id": item_id})
    return {"is_favorite": existing is not None}


@api_router.post("/favorites/{item_type}/{item_id}")
async def add_favorite(item_type: str, item_id: str, current_user: dict = Depends(get_current_user)):
    """Add a product to favorites."""
    _check_favorite_type(item_type)
    if not await db.products.find_one({"id": item_id}):
        raise HTTPException(status_code=404, detail="Product not found")
    favorite = {
        "id": str(uuid.uuid4()),
        "user_id": current_user["id"],
        "item_type": item_type,
        "item_id": item_id,
        "created_at": datetime.utcnow()
    }
    # Check if already favorited
    existing = await db.favorites.find_one({
        "user_id": current_user["id"],
        "item_type": item_type,
        "item_id": item_id
    })
    if existing:
        return {"message": "Already in favorites", "is_favorite": True}
    
    await db.favorites.insert_one(favorite)
    return {"message": "Added to favorites", "is_favorite": True}

@api_router.delete("/favorites/{item_type}/{item_id}")
async def remove_favorite(item_type: str, item_id: str, current_user: dict = Depends(get_current_user)):
    _check_favorite_type(item_type)
    await db.favorites.delete_one({
        "user_id": current_user["id"],
        "item_type": item_type,
        "item_id": item_id
    })
    return {"message": "Removed from favorites", "is_favorite": False}

@api_router.get("/favorites")
async def get_favorites(item_type: Optional[str] = None, current_user: dict = Depends(get_current_user)):
    # Read all user favorites then normalize legacy/new shapes
    raw_favorites = await db.favorites.find({"user_id": current_user["id"]}).sort("created_at", -1).to_list(100)

    result = []
    for fav in raw_favorites:
        normalized_type = fav.get("item_type")
        normalized_id = fav.get("item_id")

        # Legacy compatibility
        if not normalized_type:
            if fav.get("pet_id"):
                normalized_type = "pet"
                normalized_id = fav.get("pet_id")
            elif fav.get("product_id"):
                normalized_type = "product"
                normalized_id = fav.get("product_id")

        if not normalized_type or not normalized_id:
            continue

        if item_type and normalized_type != item_type:
            continue

        if normalized_type == "pet":
            item = await db.pets.find_one({"id": normalized_id})
        else:
            item = await db.products.find_one({"id": normalized_id})

        if item:
            fav_clean = {k: v for k, v in fav.items() if k != "_id"}
            item_clean = {k: v for k, v in item.items() if k != "_id"}
            result.append({
                **fav_clean,
                "item_type": normalized_type,
                "item_id": normalized_id,
                "item": item_clean,
            })
    return result

# ========================= SPONSORSHIP =========================

class SponsorshipCreate(BaseModel):
    pet_id: str
    amount: float
    message: Optional[str] = None
    is_anonymous: bool = False
    is_recurring: bool = False

class Sponsorship(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    pet_id: str
    user_id: str
    user_name: Optional[str] = None
    amount: float
    message: Optional[str] = None
    is_anonymous: bool = False
    is_recurring: bool = False
    status: str = "pending"  # pending, completed, cancelled
    created_at: datetime = Field(default_factory=datetime.utcnow)

class MarketplaceListingCreate(BaseModel):
    title: str
    description: str
    category: str  # pets, accessories, services
    price: float
    location: str
    image: Optional[str] = None
    pet_type: Optional[str] = None
    condition: Optional[str] = None

class MarketplaceListing(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str
    user_name: str
    user_avatar: Optional[str] = None
    title: str
    description: str
    category: str
    price: float
    location: str
    image: Optional[str] = None
    pet_type: Optional[str] = None
    condition: Optional[str] = None
    status: str = "active"  # active, sold, archived
    created_at: datetime = Field(default_factory=datetime.utcnow)

@api_router.post("/sponsorships")
async def create_sponsorship(sponsorship: SponsorshipCreate, current_user: dict = Depends(get_current_user)):
    new_sponsorship = Sponsorship(
        **sponsorship.dict(),
        user_id=current_user["id"],
        user_name=None if sponsorship.is_anonymous else current_user["name"]
    )
    await db.sponsorships.insert_one(new_sponsorship.dict())
    
    # Update pet's sponsorship total
    await db.pets.update_one(
        {"id": sponsorship.pet_id},
        {"$inc": {"total_sponsorship": sponsorship.amount}}
    )
    return new_sponsorship

@api_router.get("/sponsorships/pet/{pet_id}")
async def get_pet_sponsorships(pet_id: str, current_user: dict = Depends(get_current_user)):
    pet = await db.pets.find_one({"id": pet_id})
    all_for_pet = await db.sponsorships.find({"pet_id": pet_id}).sort("created_at", -1).to_list(100)

    # Pet owner can inspect full lifecycle.
    if pet and pet.get("owner_id") == current_user["id"]:
        visible = all_for_pet[:50]
    else:
        # Other viewers: completed sponsorships + viewer's own entries.
        visible = [
            s for s in all_for_pet
            if s.get("status") == "completed" or s.get("user_id") == current_user["id"]
        ][:50]

    sanitized = []
    for s in visible:
        row = dict(s)
        row.pop("_id", None)
        sanitized.append(Sponsorship(**row))
    return sanitized

@api_router.get("/sponsorships/my")
async def get_my_sponsorships(current_user: dict = Depends(get_current_user)):
    sponsorships = await db.sponsorships.find({"user_id": current_user["id"]}).sort("created_at", -1).to_list(100)
    return [Sponsorship(**s) for s in sponsorships]

@api_router.put("/sponsorships/{sponsorship_id}/status")
async def update_sponsorship_status(sponsorship_id: str, data: dict, current_user: dict = Depends(get_current_user)):
    new_status = (data or {}).get("status")
    if new_status not in {"pending", "completed", "cancelled"}:
        raise HTTPException(status_code=400, detail="Invalid sponsorship status")

    sponsorship = await db.sponsorships.find_one({"id": sponsorship_id})
    if not sponsorship:
        raise HTTPException(status_code=404, detail="Sponsorship not found")

    pet = await db.pets.find_one({"id": sponsorship.get("pet_id")})
    is_owner = pet and pet.get("owner_id") == current_user["id"]
    is_sponsor = sponsorship.get("user_id") == current_user["id"]
    if not (is_owner or is_sponsor or current_user.get("is_admin")):
        raise HTTPException(status_code=403, detail="Not allowed to update this sponsorship")

    await db.sponsorships.update_one({"id": sponsorship_id}, {"$set": {"status": new_status}})
    updated = await db.sponsorships.find_one({"id": sponsorship_id})
    return Sponsorship(**updated)

# ========================= MARKETPLACE =========================

@api_router.post("/marketplace/listings", response_model=MarketplaceListing)
async def create_marketplace_listing(payload: MarketplaceListingCreate, current_user: dict = Depends(get_current_user)):
    listing = MarketplaceListing(
        **payload.dict(),
        user_id=current_user["id"],
        user_name=current_user.get("name", "User"),
        user_avatar=current_user.get("avatar")
    )
    await db.marketplace_listings.insert_one(listing.dict())
    return listing

@api_router.get("/marketplace/listings", response_model=List[MarketplaceListing])
async def get_marketplace_listings(
    category: Optional[str] = None,
    q: Optional[str] = None,
    city: Optional[str] = None,
    min_price: Optional[float] = None,
    max_price: Optional[float] = None,
    current_user: Optional[dict] = Depends(get_current_user_optional),
):
    query: dict = {"status": {"$in": ["active", "sold"]}}
    if category and category != "all":
        query["category"] = category
    if city:
        query["location"] = {"$regex": city, "$options": "i"}
    if min_price is not None or max_price is not None:
        rng = {}
        if min_price is not None:
            rng["$gte"] = min_price
        if max_price is not None:
            rng["$lte"] = max_price
        query["price"] = rng

    if current_user:
        blocked_rows = await db.blocked_users.find({"user_id": current_user["id"]}).to_list(1000)
        blocked_ids = [r.get("blocked_user_id") for r in blocked_rows if r.get("blocked_user_id")]
        if blocked_ids:
            query["user_id"] = {"$nin": blocked_ids}

    rows = await db.marketplace_listings.find(query).sort("created_at", -1).to_list(200)

    if q:
        ql = q.lower().strip()
        rows = [
            r for r in rows
            if ql in f"{r.get('title','')} {r.get('description','')} {r.get('location','')}".lower()
        ]

    clean_rows = [{k: v for k, v in r.items() if k != "_id"} for r in rows]
    return [MarketplaceListing(**r) for r in clean_rows]

@api_router.get("/marketplace/listings/my", response_model=List[MarketplaceListing])
async def get_my_marketplace_listings(current_user: dict = Depends(get_current_user)):
    rows = await db.marketplace_listings.find({"user_id": current_user["id"]}).sort("created_at", -1).to_list(200)
    clean_rows = [{k: v for k, v in r.items() if k != "_id"} for r in rows]
    return [MarketplaceListing(**r) for r in clean_rows]

@api_router.get("/marketplace/listings/{listing_id}", response_model=MarketplaceListing)
async def get_marketplace_listing_by_id(listing_id: str):
    row = await db.marketplace_listings.find_one({"id": listing_id})
    if not row:
        raise HTTPException(status_code=404, detail="Listing not found")
    clean_row = {k: v for k, v in row.items() if k != "_id"}
    return MarketplaceListing(**clean_row)

@api_router.put("/marketplace/listings/{listing_id}", response_model=MarketplaceListing)
async def update_marketplace_listing(listing_id: str, payload: MarketplaceListingCreate, current_user: dict = Depends(get_current_user)):
    row = await db.marketplace_listings.find_one({"id": listing_id})
    if not row:
        raise HTTPException(status_code=404, detail="Listing not found")
    if row.get("user_id") != current_user["id"]:
        raise HTTPException(status_code=403, detail="Not allowed")

    update_data = payload.dict()
    await db.marketplace_listings.update_one(
        {"id": listing_id},
        {"$set": {**update_data, "updated_at": datetime.utcnow()}}
    )
    updated = await db.marketplace_listings.find_one({"id": listing_id})
    return MarketplaceListing(**{k: v for k, v in updated.items() if k != "_id"})

@api_router.put("/marketplace/listings/{listing_id}/status")
async def set_marketplace_listing_status(listing_id: str, data: dict = {}, current_user: dict = Depends(get_current_user)):
    row = await db.marketplace_listings.find_one({"id": listing_id})
    if not row:
        raise HTTPException(status_code=404, detail="Listing not found")
    if row.get("user_id") != current_user["id"]:
        raise HTTPException(status_code=403, detail="Not allowed")

    status = data.get("status", "active")
    if status not in ["active", "sold", "archived"]:
        raise HTTPException(status_code=400, detail="Invalid status")

    await db.marketplace_listings.update_one(
        {"id": listing_id},
        {"$set": {"status": status, "updated_at": datetime.utcnow()}}
    )
    return {"message": "Status updated", "status": status}

@api_router.delete("/marketplace/listings/{listing_id}")
async def delete_marketplace_listing(listing_id: str, current_user: dict = Depends(get_current_user)):
    row = await db.marketplace_listings.find_one({"id": listing_id})
    if not row:
        raise HTTPException(status_code=404, detail="Listing not found")
    if row.get("user_id") != current_user["id"]:
        raise HTTPException(status_code=403, detail="Not allowed")

    await db.marketplace_listings.delete_one({"id": listing_id})
    return {"message": "Listing deleted"}

@api_router.post("/marketplace/listings/{listing_id}/report")
async def report_marketplace_listing(listing_id: str, data: dict = {}, current_user: dict = Depends(get_current_user)):
    row = await db.marketplace_listings.find_one({"id": listing_id})
    if not row:
        raise HTTPException(status_code=404, detail="Listing not found")

    await db.marketplace_reports.insert_one({
        "id": str(uuid.uuid4()),
        "listing_id": listing_id,
        "reported_by": current_user["id"],
        "listing_owner_id": row.get("user_id"),
        "reason": data.get("reason", "inappropriate"),
        "notes": data.get("notes"),
        "created_at": datetime.utcnow(),
    })
    return {"message": "Report submitted"}

# ========================= CARE REQUESTS / ROLE MODULES =========================

@api_router.post("/care-requests")
async def create_care_request(data: dict, current_user: dict = Depends(get_current_user)):
    now = datetime.utcnow()
    row = {
        "id": str(uuid.uuid4()),
        "pet_id": data.get("pet_id"),
        "title": data.get("title", "Care Request"),
        "description": data.get("description"),
        "location": data.get("location"),
        "priority": data.get("priority", "normal"),
        "status": "pending",  # pending, accepted, in_progress, completed, cancelled
        "requested_by": current_user["id"],
        "requested_by_name": current_user.get("name"),
        "assigned_vet_id": None,
        "assigned_clinic_id": None,
        "created_at": now,
        "updated_at": now,
    }
    await db.care_requests.insert_one(row)
    await db.care_request_events.insert_one({
        "id": str(uuid.uuid4()),
        "request_id": row["id"],
        "actor_id": current_user["id"],
        "actor_name": current_user.get("name"),
        "actor_role": current_user.get("role", "user"),
        "event_type": "created",
        "status": "pending",
        "notes": row.get("description"),
        "created_at": now,
    })
    await create_notifications_for_admins(
        "New care request",
        f"{current_user.get('name', 'User')} submitted a care request.",
        "care_request",
        {"request_id": row["id"], "route": "/clinic-care-management"}
    )
    return {k: v for k, v in row.items() if k != "_id"}

@api_router.get("/vet/care-requests")
async def get_vet_care_requests(
    status: Optional[str] = None,
    current_user: dict = Depends(require_roles("vet"))
):
    query: dict = {"$or": [{"assigned_vet_id": None}, {"assigned_vet_id": current_user["id"]}]}
    if status:
        query["status"] = status
    rows = await db.care_requests.find(query).sort("created_at", -1).to_list(200)
    return [{k: v for k, v in r.items() if k != "_id"} for r in rows]

@api_router.put("/vet/care-requests/{request_id}")
async def update_vet_care_request(request_id: str, data: dict, current_user: dict = Depends(require_roles("vet"))):
    existing = await db.care_requests.find_one({"id": request_id})
    if not existing:
        raise HTTPException(status_code=404, detail="Care request not found")

    # A vet may only touch unassigned requests or their own; otherwise one vet
    # could read and overwrite another vet's case, including medical notes.
    assigned_vet_id = existing.get("assigned_vet_id")
    if assigned_vet_id and assigned_vet_id != current_user["id"] and not current_user.get("is_admin", False):
        raise HTTPException(status_code=403, detail="This care request is assigned to another vet")

    updates = {"updated_at": datetime.utcnow()}
    action = data.get("action")
    event_type = action or "status_update"
    if action == "accept":
        updates.update({"status": "accepted", "assigned_vet_id": current_user["id"]})
    elif action == "start":
        updates.update({"status": "in_progress", "assigned_vet_id": current_user["id"]})
    elif action == "complete":
        vet_notes = data.get("vet_notes")
        diagnosis = data.get("diagnosis")
        prescription = data.get("prescription")
        if not diagnosis or not str(diagnosis).strip() or not prescription or not str(prescription).strip():
            raise HTTPException(status_code=400, detail="Diagnosis and prescription are required to complete the case")
        updates.update({
            "status": "completed",
            "assigned_vet_id": current_user["id"],
            "vet_notes": vet_notes,
            "diagnosis": diagnosis,
            "prescription": prescription,
        })

        # Sync completion into pet health timeline when pet exists
        pet_id = existing.get("pet_id")
        if pet_id:
            pet = await db.pets.find_one({"id": pet_id})
            if pet:
                merged_notes = "\n".join([
                    f"Diagnosis: {diagnosis}" if diagnosis else "",
                    f"Prescription: {prescription}" if prescription else "",
                    f"Notes: {vet_notes}" if vet_notes else "",
                ]).strip()
                await db.health_records.insert_one({
                    "id": str(uuid.uuid4()),
                    "pet_id": pet_id,
                    "user_id": pet.get("owner_id"),
                    "record_type": "vet_visit",
                    "title": existing.get("title") or "Care Request Visit",
                    "description": existing.get("description") or "Care request was completed by vet",
                    "date": datetime.utcnow().strftime("%Y-%m-%d"),
                    "vet_name": current_user.get("name"),
                    "clinic_name": data.get("clinic_name") or existing.get("clinic_name"),
                    "notes": merged_notes,
                    "attachments": [],
                    "created_at": datetime.utcnow(),
                })
    elif data.get("status"):
        updates["status"] = data.get("status")

    await db.care_requests.update_one({"id": request_id}, {"$set": updates})
    await db.care_request_events.insert_one({
        "id": str(uuid.uuid4()),
        "request_id": request_id,
        "actor_id": current_user["id"],
        "actor_name": current_user.get("name"),
        "actor_role": current_user.get("role", "vet"),
        "event_type": event_type,
        "status": updates.get("status", existing.get("status")),
        "notes": data.get("vet_notes") or data.get("notes") or data.get("diagnosis"),
        "created_at": datetime.utcnow(),
    })

    row = await db.care_requests.find_one({"id": request_id})
    if row:
        await create_notification(
            row.get("requested_by"),
            "Care request updated",
            f"Your care request is now {row.get('status', 'updated')}.",
            "care_request",
            {"request_id": request_id, "status": row.get("status"), "route": "/clinic-care-management"}
        )
    return {k: v for k, v in row.items() if k != "_id"} if row else {"success": True}

@api_router.get("/clinic/care-requests")
async def get_clinic_care_requests(current_user: dict = Depends(require_roles("care_clinic"))):
    rows = await db.care_requests.find({}).sort("created_at", -1).to_list(300)
    return [{k: v for k, v in r.items() if k != "_id"} for r in rows]

@api_router.get("/clinic/vets")
async def get_clinic_vets(current_user: dict = Depends(require_roles("care_clinic"))):
    users = await db.users.find({"role": "vet"}).to_list(300)
    return [
        {
            "id": u.get("id"),
            "name": u.get("name"),
            "email": u.get("email"),
            "city": u.get("city"),
        }
        for u in users
    ]

@api_router.put("/clinic/care-requests/{request_id}")
async def update_clinic_care_request(request_id: str, data: dict, current_user: dict = Depends(require_roles("care_clinic"))):
    updates = {
        "updated_at": datetime.utcnow(),
        "assigned_clinic_id": current_user["id"],
    }
    if data.get("status"):
      updates["status"] = data.get("status")
    if data.get("assigned_vet_id"):
      updates["assigned_vet_id"] = data.get("assigned_vet_id")
    if data.get("clinic_notes") is not None:
      updates["clinic_notes"] = data.get("clinic_notes")

    await db.care_requests.update_one({"id": request_id}, {"$set": updates})
    await db.care_request_events.insert_one({
        "id": str(uuid.uuid4()),
        "request_id": request_id,
        "actor_id": current_user["id"],
        "actor_name": current_user.get("name"),
        "actor_role": current_user.get("role", "care_clinic"),
        "event_type": "clinic_update",
        "status": updates.get("status"),
        "notes": data.get("clinic_notes") or (f"assigned_vet_id={data.get('assigned_vet_id')}" if data.get("assigned_vet_id") else None),
        "created_at": datetime.utcnow(),
    })

    row = await db.care_requests.find_one({"id": request_id})
    if row:
        await create_notification(
            row.get("requested_by"),
            "Clinic updated your care request",
            f"Clinic updated your request to {row.get('status', 'updated')}.",
            "care_request",
            {"request_id": request_id, "status": row.get("status"), "route": "/clinic-care-management"}
        )
        if row.get("assigned_vet_id"):
            await create_notification(
                row.get("assigned_vet_id"),
                "Assigned to care request",
                "A clinic assigned you to a care request.",
                "care_request",
                {"request_id": request_id, "route": "/vet-care-requests"}
            )
    return {k: v for k, v in row.items() if k != "_id"} if row else {"success": True}

@api_router.get("/care-requests/{request_id}/timeline")
async def get_care_request_timeline(request_id: str, current_user: dict = Depends(get_current_user)):
    req = await db.care_requests.find_one({"id": request_id})
    if not req:
        raise HTTPException(status_code=404, detail="Care request not found")

    # basic access: requester, assigned vet/clinic, or admin
    uid = current_user["id"]
    if not current_user.get("is_admin", False) and current_user.get("role") != "admin":
        allowed = {
            req.get("requested_by"),
            req.get("assigned_vet_id"),
            req.get("assigned_clinic_id"),
        }
        if uid not in allowed:
            raise HTTPException(status_code=403, detail="Access denied")

    events = await db.care_request_events.find({"request_id": request_id}).sort("created_at", 1).to_list(300)
    return [{k: v for k, v in e.items() if k != "_id"} for e in events]

@api_router.get("/market-owner/overview")
async def get_market_owner_overview(current_user: dict = Depends(require_roles("market_owner"))):
    listings = await db.marketplace_listings.find({"user_id": current_user["id"]}).sort("created_at", -1).to_list(500)
    total = len(listings)
    active = len([l for l in listings if l.get("status") == "active"])
    sold = len([l for l in listings if l.get("status") == "sold"])
    revenue = sum(float(l.get("price", 0) or 0) for l in listings if l.get("status") == "sold")
    clean = [{k: v for k, v in l.items() if k != "_id"} for l in listings[:50]]
    return {
        "total_listings": total,
        "active_listings": active,
        "sold_listings": sold,
        "estimated_revenue": revenue,
        "recent_listings": clean,
    }

# ========================= PET TRACKING (PETSY TAG) =========================

class PetTagCreate(BaseModel):
    pet_id: str
    tag_code: str

class PetTag(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    tag_code: str
    pet_id: str
    owner_id: str
    is_active: bool = True
    last_scanned: Optional[datetime] = None
    last_location: Optional[str] = None
    scan_count: int = 0
    created_at: datetime = Field(default_factory=datetime.utcnow)

class TagScan(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    tag_code: str
    pet_id: str
    scanner_name: Optional[str] = None
    scanner_phone: Optional[str] = None
    location: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    message: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)

@api_router.post("/pet-tags")
async def register_pet_tag(tag: PetTagCreate, current_user: dict = Depends(get_current_user)):
    # Verify pet belongs to user
    pet = await db.pets.find_one({"id": tag.pet_id, "owner_id": current_user["id"]})
    if not pet:
        raise HTTPException(status_code=404, detail="Pet not found")

    normalized_code = (tag.tag_code or '').strip().upper()
    if not normalized_code:
        raise HTTPException(status_code=400, detail='Tag code is required')

    # If this pet already has a tag, replace it with the new code
    existing_pet_tag = await db.pet_tags.find_one({"pet_id": tag.pet_id, "owner_id": current_user["id"]})

    # Check if tag code already exists globally
    existing_code = await db.pet_tags.find_one({"tag_code": normalized_code})
    if existing_code and existing_code.get('owner_id') != current_user['id']:
        raise HTTPException(status_code=400, detail="Tag code already registered")

    # Reactivate existing code for same owner
    if existing_code and existing_code.get('owner_id') == current_user['id']:
        await db.pet_tags.update_one(
            {"id": existing_code["id"]},
            {"$set": {"pet_id": tag.pet_id, "is_active": True}}
        )
        updated = await db.pet_tags.find_one({"id": existing_code["id"]})
        return {**updated, "message": "Tag activated"}

    new_tag = PetTag(
        tag_code=normalized_code,
        pet_id=tag.pet_id,
        owner_id=current_user["id"],
        is_active=True,
    )

    # remove old tag row if pet already had one
    if existing_pet_tag:
        await db.pet_tags.delete_one({"id": existing_pet_tag["id"]})

    await db.pet_tags.insert_one(new_tag.dict())
    return {**new_tag.dict(), "message": "Tag registered and activated"}

@api_router.get("/pet-tags/{pet_id}")
async def get_pet_tag(pet_id: str, current_user: dict = Depends(get_current_user)):
    tag = await db.pet_tags.find_one({"pet_id": pet_id, "owner_id": current_user["id"]})
    if not tag:
        return None
    return {k: v for k, v in tag.items() if k != '_id'}

@api_router.put('/pet-tags/{pet_id}/status')
async def set_pet_tag_status(pet_id: str, data: dict = Body(default={}), current_user: dict = Depends(get_current_user)):
    tag = await db.pet_tags.find_one({"pet_id": pet_id, "owner_id": current_user["id"]})
    if not tag:
        raise HTTPException(status_code=404, detail='Tag not found')
    is_active = bool(data.get('is_active', True))
    await db.pet_tags.update_one({"id": tag["id"]}, {"$set": {"is_active": is_active}})
    updated = await db.pet_tags.find_one({"id": tag["id"]})
    return {k: v for k, v in updated.items() if k != '_id'}

@api_router.get("/pet-tags/scan/{tag_code}")
async def scan_pet_tag(tag_code: str):
    """Public endpoint - anyone can scan a tag"""
    tag_code = tag_code.upper()
    tag = await db.pet_tags.find_one({"tag_code": tag_code, "is_active": True})
    if not tag:
        raise HTTPException(status_code=404, detail="Tag not found or inactive")
    
    pet = await db.pets.find_one({"id": tag["pet_id"]})
    owner = await db.users.find_one({"id": tag["owner_id"]})
    
    # Increment scan count
    await db.pet_tags.update_one(
        {"tag_code": tag_code},
        {"$inc": {"scan_count": 1}, "$set": {"last_scanned": datetime.utcnow()}}
    )
    
    return {
        "pet": {
            "name": pet["name"] if pet else "Unknown",
            "species": pet.get("species") if pet else None,
            "breed": pet.get("breed") if pet else None,
            "image": pet.get("image") if pet else None,
            "description": pet.get("description") if pet else None,
        },
        "owner": {
            "name": owner["name"] if owner else "Unknown",
            "phone": owner.get("phone") if owner else None,
            "city": owner.get("city") if owner else None,
        },
        "tag": {k: v for k, v in tag.items() if k != '_id'}
    }

@api_router.post("/pet-tags/scan/{tag_code}/report")
async def report_tag_scan(tag_code: str, data: dict = Body(default={})):
    """Report a found pet via tag scan"""
    tag = await db.pet_tags.find_one({"tag_code": tag_code.upper()})
    if not tag:
        raise HTTPException(status_code=404, detail="Tag not found")

    scan = TagScan(
        tag_code=tag_code.upper(),
        pet_id=tag["pet_id"],
        scanner_name=data.get('scanner_name'),
        scanner_phone=data.get('scanner_phone'),
        location=data.get('location'),
        latitude=data.get('latitude'),
        longitude=data.get('longitude'),
        message=data.get('message')
    )
    await db.tag_scans.insert_one(scan.dict())
    
    # Update tag with last location
    await db.pet_tags.update_one(
        {"tag_code": tag_code.upper()},
        {"$set": {"last_location": data.get('location'), "last_scanned": datetime.utcnow()}}
    )
    
    return {"message": "Scan reported successfully", "scan_id": scan.id}

@api_router.get("/pet-tags/{pet_id}/scans")
async def get_tag_scans(pet_id: str, current_user: dict = Depends(get_current_user)):
    """Get scan history for a pet's tag"""
    tag = await db.pet_tags.find_one({"pet_id": pet_id, "owner_id": current_user["id"]})
    if not tag:
        raise HTTPException(status_code=404, detail="Tag not found")
    
    scans = await db.tag_scans.find({"pet_id": pet_id}).sort("created_at", -1).to_list(50)
    return [{k: v for k, v in s.items() if k != '_id'} for s in scans]

# ========================= AI ASSISTANT =========================

@api_router.post("/ai/assistant", dependencies=[Depends(rate_limit("ai_assistant", 20, 300))])
async def ai_assistant(query: str, context: Optional[str] = None, current_user: dict = Depends(get_current_user)):
    """
    AI assistant endpoint with graceful fallback.
    - Preferred: emergentintegrations + EMERGENT_LLM_KEY (optional, not in requirements)
    - Fallback: local rule-based pet-care helper (never fails with 500 for missing AI deps)
    """
    if len(query or "") > 2000:
        raise HTTPException(status_code=400, detail="Query too long")

    def fallback_pet_reply(user_query: str) -> str:
        q = (user_query or "").lower()

        emergency_keywords = ["poison", "blood", "seizure", "can't breathe", "can’t breathe", "not breathing", "hit by car"]
        if any(k in q for k in emergency_keywords):
            return (
                "⚠️ This sounds urgent. Please contact the nearest emergency vet immediately. "
                "Keep your pet warm and calm, and avoid giving any medication unless a vet instructs you."
            )

        if "food" in q or "diet" in q or "eat" in q:
            return (
                "For food planning: choose species-specific food, split meals by age, keep clean water always available, "
                "and avoid sudden food changes. If you share pet type + age, I can give a precise plan."
            )

        if "name" in q:
            return "Name ideas: Luna, Milo, Bella, Max, Coco. Tell me pet gender/species and I’ll suggest a better custom list."

        if "breed" in q or "adopt" in q:
            return (
                "I can recommend a breed based on your home size, activity level, and experience. "
                "Share these 3 details and I’ll suggest the best matches."
            )

        return (
            "I can help with pet care, food, behavior, breed suggestions, and basic symptom guidance. "
            "For serious symptoms, always visit a licensed vet immediately."
        )

    try:
        from emergentintegrations.llm.chat import LlmChat, UserMessage

        api_key = os.environ.get('EMERGENT_LLM_KEY')
        if not api_key:
            # graceful fallback if key is not configured
            return {"response": fallback_pet_reply(query), "query": query, "mode": "fallback"}

        system_message = """You are Petsy AI Assistant, a friendly and knowledgeable pet care expert.
You help users with:
- Pet breed recommendations based on their lifestyle
- Pet name suggestions
- Food and nutrition advice based on pet age and species
- Basic symptom detection and health advice (always recommend visiting a vet for serious issues)
- General pet care tips

Be concise, helpful, and always prioritize pet welfare. If symptoms sound serious, always recommend professional veterinary care.
Respond in the same language the user asks in (Arabic or English)."""

        chat = LlmChat(
            api_key=api_key,
            session_id=f"petsy-{current_user['id']}-{datetime.utcnow().strftime('%Y%m%d')}",
            system_message=system_message,
        ).with_model("openai", "gpt-4o")

        user_message = UserMessage(text=query)
        response = await chat.send_message(user_message)

        return {"response": response, "query": query, "mode": "llm"}

    except Exception as e:
        logger.warning(f"AI Assistant fallback activated: {e}")
        return {"response": fallback_pet_reply(query), "query": query, "mode": "fallback"}

# ========================= SEED DATA =========================

@api_router.post("/seed", dependencies=[Depends(rate_limit("seed", 5, 3600))])
async def seed_data():
    """Seed demo data. Disabled unless SEED_ENABLED=true and never available in production."""
    if not SEED_ENABLED:
        # 404 rather than 403 so the endpoint is not discoverable when disabled.
        raise HTTPException(status_code=404, detail="Not Found")

    admin_created = False
    existing_admin = await db.users.find_one({"email": SEED_ADMIN_EMAIL})
    if not existing_admin:
        if len(SEED_ADMIN_PASSWORD) < 12:
            logger.warning(
                "Skipping seed admin creation: set SEED_ADMIN_PASSWORD to at least 12 characters to create %s.",
                SEED_ADMIN_EMAIL,
            )
        else:
            admin_user = {
                "id": str(uuid.uuid4()),
                "email": SEED_ADMIN_EMAIL,
                "name": "Admin User",
                "phone": "+963900000000",
                "password_hash": hash_password(SEED_ADMIN_PASSWORD),
                "is_verified": True,
                "is_admin": True,
                "role": "admin",
                "language": "en",
                "created_at": datetime.utcnow(),
            }
            await db.users.insert_one(admin_user)
            admin_created = True
            logger.info("Seed admin created: %s", SEED_ADMIN_EMAIL)


    # Seed Vets
    vets_data = [
        {
            "name": "Dr. Ahmad Hassan",
            "specialty": "all",
            "experience_years": 15,
            "phone": "+963912345678",
            "clinic_name": "Damascus Pet Care",
            "address": "Mezzeh, Damascus",
            "city": "Damascus",
            "rating": 4.8,
            "reviews_count": 124,
            "services": ["checkup", "vaccination", "surgery", "dental"],
            "available_hours": "9:00 AM - 6:00 PM"
        },
        {
            "name": "Dr. Layla Nouri",
            "specialty": "cats",
            "experience_years": 10,
            "phone": "+963923456789",
            "clinic_name": "Feline Friends Clinic",
            "address": "Malki, Damascus",
            "city": "Damascus",
            "rating": 4.9,
            "reviews_count": 89,
            "services": ["checkup", "vaccination", "grooming"],
            "available_hours": "10:00 AM - 8:00 PM"
        },
        {
            "name": "Dr. Omar Khalil",
            "specialty": "dogs",
            "experience_years": 12,
            "phone": "+963934567890",
            "clinic_name": "Canine Care Center",
            "address": "Aleppo City Center",
            "city": "Aleppo",
            "rating": 4.7,
            "reviews_count": 156,
            "services": ["checkup", "vaccination", "surgery", "emergency"],
            "available_hours": "24/7 Emergency"
        }
    ]
    
    for vet in vets_data:
        existing = await db.vets.find_one({"name": vet["name"]})
        if not existing:
            await db.vets.insert_one(Vet(**vet).dict())
    
    # Seed Products
    products_data = [
        {"name": "Premium Dog Food", "category": "food", "price": 25.99, "pet_type": "dog", "brand": "Royal Canin", "in_stock": True, "quantity": 50, "rating": 4.5},
        {"name": "Cat Wet Food Pack", "category": "food", "price": 15.99, "pet_type": "cat", "brand": "Whiskas", "in_stock": True, "quantity": 100, "rating": 4.3},
        {"name": "Dog Chew Toy", "category": "toys", "price": 8.99, "pet_type": "dog", "in_stock": True, "quantity": 30, "rating": 4.7},
        {"name": "Cat Scratching Post", "category": "toys", "price": 29.99, "pet_type": "cat", "in_stock": True, "quantity": 20, "rating": 4.6},
        {"name": "Pet Shampoo", "category": "shampoo", "price": 12.99, "pet_type": "all", "brand": "Pet Head", "in_stock": True, "quantity": 45, "rating": 4.4},
        {"name": "Dog Collar - Medium", "category": "accessories", "price": 14.99, "pet_type": "dog", "in_stock": True, "quantity": 60, "rating": 4.2},
        {"name": "Cat Litter Box", "category": "accessories", "price": 35.99, "pet_type": "cat", "in_stock": True, "quantity": 25, "rating": 4.5},
        {"name": "Bird Cage - Large", "category": "cages", "price": 89.99, "pet_type": "bird", "in_stock": True, "quantity": 10, "rating": 4.8},
        {"name": "Flea Medicine", "category": "medicine", "price": 19.99, "pet_type": "all", "brand": "Frontline", "in_stock": True, "quantity": 80, "rating": 4.6},
        {"name": "Pet Vitamins", "category": "medicine", "price": 24.99, "pet_type": "all", "in_stock": True, "quantity": 40, "rating": 4.4}
    ]
    
    for product in products_data:
        existing = await db.products.find_one({"name": product["name"]})
        if not existing:
            await db.products.insert_one(Product(**product).dict())
    
    # Seed Emergency Contacts
    emergency_data = [
        {"name": "24/7 Pet Emergency Damascus", "type": "clinic", "phone": "+963911111111", "city": "Damascus", "is_24_hours": True, "address": "Mezzeh Highway"},
        {"name": "Animal Rescue Syria", "type": "rescue", "phone": "+963922222222", "city": "Damascus", "is_24_hours": False},
        {"name": "Aleppo Animal Shelter", "type": "shelter", "phone": "+963933333333", "city": "Aleppo", "is_24_hours": False},
        {"name": "Dr. Emergency Vet Line", "type": "vet", "phone": "+963944444444", "city": "Damascus", "is_24_hours": True}
    ]
    
    for contact in emergency_data:
        existing = await db.emergency_contacts.find_one({"name": contact["name"]})
        if not existing:
            await db.emergency_contacts.insert_one(EmergencyContact(**contact).dict())
    
    # Seed Sample Pets for Adoption
    sample_pets = [
        {"name": "Max", "species": "dog", "breed": "Golden Retriever", "age": "2 years", "gender": "male", "status": "for_adoption", "location": "Damascus", "vaccinated": True, "description": "Friendly and playful golden retriever looking for a loving home."},
        {"name": "Luna", "species": "cat", "breed": "Persian", "age": "1 year", "gender": "female", "status": "for_adoption", "location": "Damascus", "vaccinated": True, "description": "Beautiful Persian cat, very calm and affectionate."},
        {"name": "Rocky", "species": "dog", "breed": "German Shepherd", "age": "3 years", "gender": "male", "status": "for_sale", "price": 150, "location": "Aleppo", "vaccinated": True, "description": "Well-trained German Shepherd, great guard dog."},
        {"name": "Milo", "species": "cat", "breed": "Siamese", "age": "6 months", "gender": "male", "status": "for_adoption", "location": "Damascus", "vaccinated": False, "description": "Playful Siamese kitten, loves to play with toys."},
        {"name": "Bella", "species": "dog", "breed": "Husky", "age": "1.5 years", "gender": "female", "status": "for_sale", "price": 200, "location": "Homs", "vaccinated": True, "description": "Gorgeous Husky with blue eyes, needs an active family."}
    ]
    
    for pet in sample_pets:
        existing = await db.pets.find_one({"name": pet["name"], "breed": pet.get("breed")})
        if not existing:
            pet_obj = Pet(**pet, owner_id="system")
            await db.pets.insert_one(pet_obj.dict())
    
    # Seed Map Locations
    map_locations_data = [
        {"name": "Damascus Pet Care Center", "type": "vet", "address": "Mezzeh, Damascus", "city": "Damascus", "latitude": 33.5138, "longitude": 36.2765, "phone": "+963912345678", "rating": 4.8, "is_open_now": True, "hours": "9:00 AM - 9:00 PM"},
        {"name": "Feline Friends Clinic", "type": "clinic", "address": "Malki, Damascus", "city": "Damascus", "latitude": 33.5200, "longitude": 36.2900, "phone": "+963923456789", "rating": 4.9, "is_open_now": True, "hours": "10:00 AM - 8:00 PM"},
        {"name": "Happy Paws Pet Shop", "type": "pet_shop", "address": "Abu Rummaneh, Damascus", "city": "Damascus", "latitude": 33.5180, "longitude": 36.2850, "phone": "+963955555555", "rating": 4.5, "is_open_now": True, "hours": "10:00 AM - 10:00 PM"},
        {"name": "Syria Animal Shelter", "type": "shelter", "address": "Daraya Road, Damascus", "city": "Damascus", "latitude": 33.4800, "longitude": 36.2400, "phone": "+963922222222", "rating": 4.7, "is_open_now": False, "hours": "9:00 AM - 5:00 PM"},
        {"name": "Pet Paradise Store", "type": "pet_shop", "address": "Sha'lan, Damascus", "city": "Damascus", "latitude": 33.5120, "longitude": 36.2920, "phone": "+963966666666", "rating": 4.3, "is_open_now": True, "hours": "11:00 AM - 11:00 PM"},
        {"name": "Al-Jahez Park", "type": "park", "address": "Al-Jahez St, Damascus", "city": "Damascus", "latitude": 33.5050, "longitude": 36.3000, "rating": 4.6, "is_open_now": True, "hours": "6:00 AM - 10:00 PM"},
        {"name": "Aleppo Vet Hospital", "type": "vet", "address": "City Center, Aleppo", "city": "Aleppo", "latitude": 36.2021, "longitude": 37.1343, "phone": "+963934567890", "rating": 4.7, "is_open_now": True, "hours": "24/7"},
        {"name": "Homs Pet Clinic", "type": "clinic", "address": "Central Homs", "city": "Homs", "latitude": 34.7324, "longitude": 36.7137, "phone": "+963945678901", "rating": 4.4, "is_open_now": True, "hours": "8:00 AM - 6:00 PM"},
    ]
    
    for loc in map_locations_data:
        existing = await db.map_locations.find_one({"name": loc["name"]})
        if not existing:
            await db.map_locations.insert_one(MapLocation(**loc).dict())

    return {"message": "Seed data created successfully", "admin_created": admin_created}

# ========================= PAYMENT ENDPOINTS =========================

STRIPE_SECRET_KEY = os.environ.get('STRIPE_SECRET_KEY', '').strip()
STRIPE_PUBLISHABLE_KEY = os.environ.get('STRIPE_PUBLISHABLE_KEY', '').strip()

POINTS_PER_DOLLAR = 1
POINTS_PER_DOLLAR_REDEEMED = 100  # 100 points = $1 discount
APPOINTMENT_BOOKING_FEE = float(os.environ.get("APPOINTMENT_BOOKING_FEE", "5"))

# Without provider credentials a payment can only be simulated. Simulation is a
# development affordance and must never run in production, where it would mean
# handing out goods for free.
PAYMENTS_SIMULATION_ENABLED = env_flag("PAYMENTS_SIMULATION_ENABLED", not IS_PRODUCTION) and not IS_PRODUCTION


@api_router.get("/payments/config")
async def get_payment_config():
    """Get payment configuration for frontend"""
    return {
        "stripe_publishable_key": STRIPE_PUBLISHABLE_KEY,
        "supported_methods": sorted(SUPPORTED_PAYMENT_METHODS),
        "currency": "USD",
        "points_per_dollar": POINTS_PER_DOLLAR,
        "points_redemption_rate": POINTS_PER_DOLLAR_REDEEMED,
        "appointment_booking_fee": APPOINTMENT_BOOKING_FEE,
        "simulation_mode": PAYMENTS_SIMULATION_ENABLED,
    }


async def resolve_payment_amount(payment: PaymentRequest, user_id: str) -> tuple[float, str]:
    """Derive the authoritative amount from stored records owned by the caller."""
    if payment.order_id:
        order = await db.orders.find_one({"id": payment.order_id, "user_id": user_id})
        if not order:
            raise HTTPException(status_code=404, detail="Order not found")
        return round(float(order.get("total") or 0), 2), "order"

    if payment.appointment_id:
        appointment = await db.appointments.find_one({"id": payment.appointment_id, "user_id": user_id})
        if not appointment:
            raise HTTPException(status_code=404, detail="Appointment not found")
        return round(APPOINTMENT_BOOKING_FEE, 2), "appointment"

    sponsorship = await db.sponsorships.find_one({"id": payment.sponsorship_id, "user_id": user_id})
    if not sponsorship:
        raise HTTPException(status_code=404, detail="Sponsorship not found")
    return round(float(sponsorship.get("amount") or 0), 2), "sponsorship"


async def existing_settled_payment(payment: PaymentRequest) -> Optional[dict]:
    """Block a second charge against a target that is already paid or in flight."""
    target = {
        "order_id": payment.order_id,
        "appointment_id": payment.appointment_id,
        "sponsorship_id": payment.sponsorship_id,
    }
    query = {k: v for k, v in target.items() if v}
    query["status"] = {"$in": ["pending", "succeeded"]}
    return await db.payments.find_one(query)


@api_router.post("/payments/process", dependencies=[Depends(rate_limit("payments", 20, 300))])
async def process_payment(payment: PaymentRequest, current_user: dict = Depends(get_current_user)):
    """Create a payment for an existing order, appointment or sponsorship."""
    user_id = current_user["id"]

    gross_amount, target_type = await resolve_payment_amount(payment, user_id)
    if gross_amount <= 0:
        raise HTTPException(status_code=400, detail="Nothing to pay for this item")

    duplicate = await existing_settled_payment(payment)
    if duplicate:
        raise HTTPException(status_code=409, detail="A payment already exists for this item")

    if payment.payment_method != "cash_on_delivery" and not PAYMENTS_SIMULATION_ENABLED:
        if not STRIPE_SECRET_KEY:
            raise HTTPException(
                status_code=503,
                detail="Online payments are not configured. Set STRIPE_SECRET_KEY or use cash on delivery.",
            )
        raise HTTPException(
            status_code=503,
            detail="Payment gateway integration is pending. Use cash on delivery.",
        )

    # Cap redemption so points can never exceed the amount owed.
    max_redeemable = int(gross_amount * POINTS_PER_DOLLAR_REDEEMED)
    points_to_use = min(payment.points_to_use, max_redeemable)
    points_discount = round(points_to_use / POINTS_PER_DOLLAR_REDEEMED, 2)
    final_amount = round(max(0.0, gross_amount - points_discount), 2)

    payment_id = str(uuid.uuid4())

    # Conditional update: the balance check and the debit happen in one atomic
    # operation, so concurrent requests cannot spend the same points twice.
    if points_to_use > 0:
        debited = await db.users.update_one(
            {"id": user_id, "loyalty_points": {"$gte": points_to_use}},
            {"$inc": {"loyalty_points": -points_to_use}},
        )
        if debited.modified_count == 0:
            raise HTTPException(status_code=400, detail="Insufficient loyalty points")

        await db.points_transactions.insert_one({
            "id": str(uuid.uuid4()),
            "user_id": user_id,
            "points": -points_to_use,
            "transaction_type": "redeemed",
            "description": f"Redeemed {points_to_use} points for ${points_discount:.2f} discount",
            "reference_id": payment_id,
            "created_at": datetime.utcnow(),
        })

    is_settled = payment.payment_method == "cash_on_delivery"

    await db.payments.insert_one({
        "id": payment_id,
        "user_id": user_id,
        "amount": final_amount,
        "original_amount": gross_amount,
        "payment_method": payment.payment_method,
        "status": "succeeded" if is_settled else "pending",
        "target_type": target_type,
        "order_id": payment.order_id,
        "appointment_id": payment.appointment_id,
        "sponsorship_id": payment.sponsorship_id,
        "points_used": points_to_use,
        "points_earned": 0,
        "simulated": PAYMENTS_SIMULATION_ENABLED and not is_settled,
        "created_at": datetime.utcnow(),
    })

    result = {
        "success": True,
        "payment_id": payment_id,
        "amount": final_amount,
        "original_amount": gross_amount,
        "points_used": points_to_use,
        "points_discount": points_discount,
        "method": payment.payment_method,
        "status": "succeeded" if is_settled else "pending",
    }

    if is_settled:
        # Loyalty points are only minted once money is actually collected.
        await credit_purchase_points(user_id, payment_id, final_amount)
        result["points_earned"] = int(final_amount * POINTS_PER_DOLLAR)
        result["message"] = "Cash on delivery confirmed"
    else:
        result["message"] = "Payment initiated. Awaiting provider confirmation."

    return result


async def credit_purchase_points(user_id: str, payment_id: str, amount: float) -> int:
    """Award loyalty points once, guarded by a unique transaction reference."""
    points_earned = int(amount * POINTS_PER_DOLLAR)
    if points_earned <= 0:
        return 0

    already = await db.points_transactions.find_one({"reference_id": payment_id, "transaction_type": "earned"})
    if already:
        return 0

    await db.points_transactions.insert_one({
        "id": str(uuid.uuid4()),
        "user_id": user_id,
        "points": points_earned,
        "transaction_type": "earned",
        "description": f"Earned {points_earned} points from purchase",
        "reference_id": payment_id,
        "created_at": datetime.utcnow(),
    })
    await db.users.update_one(
        {"id": user_id},
        {"$inc": {"loyalty_points": points_earned, "lifetime_points": points_earned}},
    )
    await db.payments.update_one({"id": payment_id}, {"$set": {"points_earned": points_earned}})
    return points_earned


async def settle_payment(payment_id: str, confirmed_by: str) -> dict:
    payment = await db.payments.find_one({"id": payment_id})
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")

    if payment.get("status") == "succeeded":
        return {"success": True, "message": "Payment already confirmed"}

    await db.payments.update_one(
        {"id": payment_id},
        {"$set": {"status": "succeeded", "confirmed_at": datetime.utcnow(), "confirmed_by": confirmed_by}},
    )
    await credit_purchase_points(payment["user_id"], payment_id, float(payment.get("amount") or 0))
    return {"success": True, "message": "Payment confirmed"}


@api_router.post("/payments/{payment_id}/confirm")
async def confirm_payment_admin(payment_id: str, admin_user: dict = Depends(get_admin_user)):
    """Manually settle a payment.

    Users must never confirm their own payments: only the provider (via webhook)
    or an operator who verified the transfer can mark money as received.
    """
    result = await settle_payment(payment_id, confirmed_by=f"admin:{admin_user['id']}")
    await audit_admin_action(admin_user, "confirm_payment", "payment", payment_id)
    return result

@api_router.get("/payments/history")
async def get_payment_history(current_user: dict = Depends(get_current_user)):
    """Get user's payment history"""
    payments = await db.payments.find({"user_id": current_user["id"]}).sort("created_at", -1).to_list(50)
    return [
        {
            "id": p.get("id"),
            "amount": p.get("amount"),
            "payment_method": p.get("payment_method"),
            "status": p.get("status"),
            "created_at": p.get("created_at"),
            "order_id": p.get("order_id"),
            "points_used": p.get("points_used", 0),
            "points_earned": p.get("points_earned", 0),
        }
        for p in payments
    ]

# ========================= LOYALTY POINTS ENDPOINTS =========================

@api_router.get("/loyalty/points")
async def get_loyalty_points(current_user: dict = Depends(get_current_user)):
    """Get user's loyalty points balance and tier"""
    user = await db.users.find_one({"id": current_user["id"]})
    total_points = user.get("loyalty_points", 0)
    lifetime_points = user.get("lifetime_points", 0)
    
    # Calculate tier based on lifetime points
    if lifetime_points >= 5000:
        tier = "platinum"
        tier_multiplier = 2.0
    elif lifetime_points >= 2000:
        tier = "gold"
        tier_multiplier = 1.5
    elif lifetime_points >= 500:
        tier = "silver"
        tier_multiplier = 1.25
    else:
        tier = "bronze"
        tier_multiplier = 1.0
    
    # Calculate points value in dollars
    points_value = total_points / 100
    
    return {
        "total_points": total_points,
        "lifetime_points": lifetime_points,
        "tier": tier,
        "tier_multiplier": tier_multiplier,
        "points_value": points_value,
        "points_to_next_tier": {
            "bronze": max(0, 500 - lifetime_points),
            "silver": max(0, 2000 - lifetime_points),
            "gold": max(0, 5000 - lifetime_points),
        }.get(tier, 0)
    }

@api_router.get("/loyalty/transactions")
async def get_points_transactions(current_user: dict = Depends(get_current_user)):
    """Get user's points transaction history"""
    transactions = await db.points_transactions.find(
        {"user_id": current_user["id"]}
    ).sort("created_at", -1).to_list(50)
    
    return [
        {
            "id": t.get("id"),
            "points": t.get("points"),
            "transaction_type": t.get("transaction_type"),
            "description": t.get("description"),
            "created_at": t.get("created_at"),
        }
        for t in transactions
    ]

class BonusPointsRequest(BaseModel):
    user_id: str
    points: int = Field(gt=0, le=100000)
    description: str = Field(min_length=1, max_length=280)


@api_router.post("/loyalty/bonus")
async def award_bonus_points(
    req: BonusPointsRequest,
    admin_user: dict = Depends(get_admin_user),
):
    """Award bonus points to a user. Admin only: points are redeemable for money."""
    target = await db.users.find_one({"id": req.user_id})
    if not target:
        raise HTTPException(status_code=404, detail=error_detail("AUTH_USER_NOT_FOUND", "User not found"))

    await db.users.update_one(
        {"id": req.user_id},
        {
            "$inc": {
                "loyalty_points": req.points,
                "lifetime_points": req.points
            }
        }
    )

    await db.points_transactions.insert_one({
        "id": str(uuid.uuid4()),
        "user_id": req.user_id,
        "points": req.points,
        "transaction_type": "bonus",
        "description": req.description,
        "granted_by": admin_user["id"],
        "created_at": datetime.utcnow()
    })

    await audit_admin_action(admin_user, "award_bonus_points", "user", req.user_id, {"points": req.points})

    return {"success": True, "points_awarded": req.points, "user_id": req.user_id}

# ========================= ADMIN ENDPOINTS =========================

@api_router.get("/admin/stats")
async def get_admin_stats(admin_user: dict = Depends(get_admin_user)):
    """Get dashboard statistics"""
    try:
        users_count = await db.users.count_documents({})
        pets_count = await db.pets.count_documents({})
        orders_count = await db.orders.count_documents({})
        appointments_count = await db.appointments.count_documents({})
        products_count = await db.products.count_documents({})
        vets_count = await db.vet_profiles.count_documents({})
        
        # Calculate revenue
        orders = await db.orders.find({}).to_list(1000)
        revenue = sum(order.get("total", 0) for order in orders)
        
        pending_orders = await db.orders.count_documents({"status": "pending"})
        open_marketplace_reports = await db.marketplace_reports.count_documents({})
        pending_role_requests = await db.role_requests.count_documents({"status": "pending"})
        open_friend_reports = await db.friend_reports.count_documents({"status": "open"})
        
        # Recent activity
        recent_orders = await db.orders.find({}).sort("created_at", -1).limit(5).to_list(5)
        recent_users = await db.users.find({}).sort("created_at", -1).limit(5).to_list(5)
        
        # Monthly stats for charts
        from datetime import datetime, timedelta
        now = datetime.utcnow()
        monthly_stats = []
        for i in range(6):
            month_start = (now - timedelta(days=30*i)).replace(day=1, hour=0, minute=0, second=0, microsecond=0)
            month_end = (month_start + timedelta(days=32)).replace(day=1)
            month_orders = await db.orders.count_documents({
                "created_at": {"$gte": month_start, "$lt": month_end}
            })
            month_revenue_data = await db.orders.find({
                "created_at": {"$gte": month_start, "$lt": month_end}
            }).to_list(1000)
            month_revenue = sum(o.get("total", 0) for o in month_revenue_data)
            monthly_stats.append({
                "month": month_start.strftime("%b"),
                "orders": month_orders,
                "revenue": month_revenue
            })
        
        return {
            "users": users_count,
            "pets": pets_count,
            "orders": orders_count,
            "appointments": appointments_count,
            "products": products_count,
            "vets": vets_count,
            "revenue": revenue,
            "pendingOrders": pending_orders,
            "openMarketplaceReports": open_marketplace_reports,
            "pendingRoleRequests": pending_role_requests,
            "openFriendReports": open_friend_reports,
            "monthlyStats": list(reversed(monthly_stats)),
            "recentOrders": [{"id": o.get("id"), "total": o.get("total", 0), "status": o.get("status")} for o in recent_orders],
            "recentUsers": [{"id": u.get("id"), "name": u.get("name"), "email": u.get("email")} for u in recent_users],
        }
    except Exception as e:
        logger.error(f"Admin stats error: {str(e)}")
        return {
            "users": 0, "pets": 0, "orders": 0, "appointments": 0,
            "products": 0, "vets": 0, "revenue": 0, "pendingOrders": 0,
            "openMarketplaceReports": 0, "pendingRoleRequests": 0, "openFriendReports": 0,
            "monthlyStats": [], "recentOrders": [], "recentUsers": [],
        }

@api_router.get("/admin/users")
async def get_all_users(admin_user: dict = Depends(get_admin_user)):
    """Get all users for admin"""
    users = await db.users.find({}).to_list(1000)
    user_ids = [u.get("id") for u in users if u.get("id")]

    # friend report counts per target user
    pipeline = [
        {"$group": {"_id": "$target_user_id", "count": {"$sum": 1}, "open_count": {"$sum": {"$cond": [{"$eq": ["$status", "open"]}, 1, 0]}}}},
    ]
    report_rows = await db.friend_reports.aggregate(pipeline).to_list(2000)
    report_map = {r.get("_id"): r for r in report_rows}

    blocked_rows = await db.blocked_users.find({"user_id": admin_user["id"], "blocked_user_id": {"$in": user_ids}}).to_list(2000)
    blocked_set = {r.get("blocked_user_id") for r in blocked_rows}

    return [
        {
            "id": u.get("id"),
            "name": u.get("name"),
            "email": u.get("email"),
            "phone": u.get("phone"),
            "city": u.get("city"),
            "is_verified": u.get("is_verified", False),
            "is_admin": u.get("is_admin", False),
            "role": u.get("role", "user"),
            "created_at": u.get("created_at"),
            "loyalty_points": u.get("loyalty_points", 0),
            "friend_reports_count": (report_map.get(u.get("id")) or {}).get("count", 0),
            "friend_reports_open_count": (report_map.get(u.get("id")) or {}).get("open_count", 0),
            "is_blocked_by_admin": u.get("id") in blocked_set,
        }
        for u in users
    ]

class AdminUserUpdate(BaseModel):
    """Explicit allowlist: a raw dict let an admin overwrite password_hash, id or loyalty_points."""
    name: Optional[str] = Field(default=None, max_length=120)
    phone: Optional[str] = Field(default=None, max_length=32)
    username: Optional[str] = Field(default=None, max_length=24)
    city: Optional[str] = Field(default=None, max_length=120)
    role: Optional[str] = None
    is_verified: Optional[bool] = None
    language: Optional[str] = Field(default=None, max_length=8)


@api_router.put("/admin/users/{user_id}")
async def update_user_admin(user_id: str, data: AdminUserUpdate, admin_user: dict = Depends(get_admin_user)):
    """Update user (admin)"""
    updates = data.dict(exclude_unset=True, exclude_none=True)

    if "role" in updates:
        role = str(updates["role"]).strip()
        if role not in ALLOWED_ROLES:
            raise HTTPException(status_code=400, detail=f"Invalid role. Allowed: {', '.join(sorted(ALLOWED_ROLES))}")
        updates["role"] = role
        updates["is_admin"] = role == "admin"

    if not updates:
        raise HTTPException(status_code=400, detail="No updatable fields provided")

    if "username" in updates:
        normalized = normalize_username(updates["username"])
        if not normalized:
            raise HTTPException(status_code=400, detail="Invalid username")
        taken = await db.users.find_one({"username": normalized, "id": {"$ne": user_id}})
        if taken:
            raise HTTPException(status_code=400, detail="Username already taken")
        updates["username"] = normalized

    result = await db.users.update_one({"id": user_id}, {"$set": updates})
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail=error_detail("AUTH_USER_NOT_FOUND", "User not found"))

    await audit_admin_action(admin_user, "update_user", "user", user_id, updates)
    return {"success": True}

@api_router.delete("/admin/users/{user_id}")
async def delete_user_admin(user_id: str, admin_user: dict = Depends(get_admin_user)):
    """Delete user (admin)"""
    await db.users.delete_one({"id": user_id})
    await audit_admin_action(admin_user, "delete_user", "user", user_id)
    return {"success": True}

@api_router.post("/admin/users/{user_id}/make-admin")
async def make_user_admin(user_id: str, admin_user: dict = Depends(get_admin_user)):
    """Promote user to admin"""
    await db.users.update_one({"id": user_id}, {"$set": {"is_admin": True, "role": "admin"}})
    await audit_admin_action(admin_user, "make_admin", "user", user_id)
    return {"success": True}

@api_router.post("/admin/users/{user_id}/remove-admin")
async def remove_user_admin(user_id: str, admin_user: dict = Depends(get_admin_user)):
    """Remove admin privileges from user"""
    await db.users.update_one({"id": user_id}, {"$set": {"is_admin": False, "role": "user"}})
    await audit_admin_action(admin_user, "remove_admin", "user", user_id)
    return {"success": True}


@api_router.get("/admin/users/{user_id}/auth-fields")
async def get_user_auth_fields_admin(user_id: str, admin_user: dict = Depends(get_admin_user)):
    """Get auth-related fields for debugging/testing (admin only)."""
    u = await db.users.find_one({"id": user_id})
    if not u:
        raise HTTPException(status_code=404, detail=error_detail("AUTH_USER_NOT_FOUND", "User not found"))
    return {
        "id": u.get("id"),
        "email": u.get("email"),
        "is_verified": u.get("is_verified", False),
        "is_admin": u.get("is_admin", False),
        "role": u.get("role", "user"),
        "verification_code": u.get("verification_code"),
        "reset_code": u.get("reset_code"),
        "reset_code_expires_at": u.get("reset_code_expires_at"),
    }


class AdminAuthFieldsPatch(BaseModel):
    verification_code: Optional[str] = None
    reset_code: Optional[str] = None
    reset_code_expires_minutes: Optional[int] = None
    clear_reset: Optional[bool] = None
    clear_verification: Optional[bool] = None


@api_router.put("/admin/users/{user_id}/auth-fields")
async def update_user_auth_fields_admin(user_id: str, patch: AdminAuthFieldsPatch, admin_user: dict = Depends(get_admin_user)):
    """Update auth-related fields for debugging/testing (admin only)."""
    u = await db.users.find_one({"id": user_id})
    if not u:
        raise HTTPException(status_code=404, detail=error_detail("AUTH_USER_NOT_FOUND", "User not found"))

    update: dict = {}

    if patch.clear_verification:
        update["verification_code"] = None
    elif patch.verification_code is not None:
        code = str(patch.verification_code).strip()
        update["verification_code"] = code or None

    if patch.clear_reset:
        update["reset_code"] = None
        update["reset_code_expires_at"] = None
    else:
        if patch.reset_code is not None:
            rc = str(patch.reset_code).strip()
            update["reset_code"] = rc or None
        if patch.reset_code_expires_minutes is not None:
            mins = max(1, min(int(patch.reset_code_expires_minutes), 60 * 24 * 30))
            update["reset_code_expires_at"] = datetime.utcnow() + timedelta(minutes=mins)

    if not update:
        return {"success": True, "updated": {}}

    await db.users.update_one({"id": user_id}, {"$set": update})
    await audit_admin_action(admin_user, "update_user_auth_fields", "user", user_id, update)
    return {"success": True, "updated": update}

@api_router.post('/admin/users/{user_id}/block')
async def block_user_admin(user_id: str, admin_user: dict = Depends(get_admin_user)):
    if user_id == admin_user.get('id'):
        raise HTTPException(status_code=400, detail='Cannot block yourself')
    existing = await db.blocked_users.find_one({"user_id": admin_user["id"], "blocked_user_id": user_id})
    if not existing:
        await db.blocked_users.insert_one({
            "id": str(uuid.uuid4()),
            "user_id": admin_user["id"],
            "blocked_user_id": user_id,
            "created_at": datetime.utcnow(),
        })
    await audit_admin_action(admin_user, "block_user", "user", user_id)
    return {"success": True}

@api_router.delete('/admin/users/{user_id}/block')
async def unblock_user_admin(user_id: str, admin_user: dict = Depends(get_admin_user)):
    await db.blocked_users.delete_one({"user_id": admin_user["id"], "blocked_user_id": user_id})
    await audit_admin_action(admin_user, "unblock_user", "user", user_id)
    return {"success": True}

@api_router.get("/admin/marketplace/listings")
async def get_marketplace_listings_admin(admin_user: dict = Depends(get_admin_user)):
    rows = await db.marketplace_listings.find({}).sort("created_at", -1).to_list(1000)
    return [{k: v for k, v in r.items() if k != "_id"} for r in rows]

@api_router.get("/admin/marketplace/reports")
async def get_marketplace_reports_admin(admin_user: dict = Depends(get_admin_user)):
    rows = await db.marketplace_reports.find({}).sort("created_at", -1).to_list(1000)
    return [{k: v for k, v in r.items() if k != "_id"} for r in rows]

@api_router.put("/admin/marketplace/listings/{listing_id}/status")
async def set_marketplace_listing_status_admin(listing_id: str, data: dict, admin_user: dict = Depends(get_admin_user)):
    status = data.get("status", "active")
    if status not in ["active", "sold", "archived"]:
        raise HTTPException(status_code=400, detail="Invalid status")
    listing = await db.marketplace_listings.find_one({"id": listing_id})
    await db.marketplace_listings.update_one({"id": listing_id}, {"$set": {"status": status, "updated_at": datetime.utcnow()}})
    if listing and listing.get("user_id"):
        await create_notification(
            listing.get("user_id"),
            "Marketplace listing update",
            f"Your listing status is now {status}.",
            "marketplace",
            {"listing_id": listing_id, "status": status, "route": "/my-marketplace-listings"}
        )
    await audit_admin_action(admin_user, "set_marketplace_listing_status", "marketplace_listing", listing_id, {"status": status})
    return {"success": True}

@api_router.post("/role-requests")
async def create_role_request(data: dict, current_user: dict = Depends(get_current_user)):
    target_role = str(data.get("target_role") or "").strip()
    if target_role not in {"vet", "market_owner", "care_clinic"}:
        raise HTTPException(status_code=400, detail="Invalid target role")

    existing = await db.role_requests.find_one({
        "user_id": current_user["id"],
        "target_role": target_role,
        "status": "pending"
    })
    if existing:
        return {"message": "Request already pending", "id": existing.get("id")}

    row = {
        "id": str(uuid.uuid4()),
        "user_id": current_user["id"],
        "user_name": current_user.get("name"),
        "user_email": current_user.get("email"),
        "target_role": target_role,
        "reason": data.get("reason"),
        "status": "pending",
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow(),
    }
    await db.role_requests.insert_one(row)
    await create_notifications_for_admins(
        "New role request",
        f"{current_user.get('name', 'User')} requested role: {target_role}",
        "role_request",
        {"request_id": row["id"], "target_role": target_role, "route": "/admin/role-requests"}
    )
    return {k: v for k, v in row.items() if k != "_id"}

@api_router.get("/role-requests/my")
async def get_my_role_requests(current_user: dict = Depends(get_current_user)):
    rows = await db.role_requests.find({"user_id": current_user["id"]}).sort("created_at", -1).to_list(200)
    return [{k: v for k, v in r.items() if k != "_id"} for r in rows]

@api_router.get("/admin/role-requests")
async def get_role_requests_admin(admin_user: dict = Depends(get_admin_user)):
    rows = await db.role_requests.find({}).sort("created_at", -1).to_list(1000)
    return [{k: v for k, v in r.items() if k != "_id"} for r in rows]

@api_router.put("/admin/role-requests/{request_id}")
async def handle_role_request_admin(request_id: str, data: dict, admin_user: dict = Depends(get_admin_user)):
    req = await db.role_requests.find_one({"id": request_id})
    if not req:
        raise HTTPException(status_code=404, detail="Role request not found")

    action = data.get("action")  # approve|reject
    if action not in {"approve", "reject"}:
        raise HTTPException(status_code=400, detail="Invalid action")

    if action == "approve":
        role = req.get("target_role", "user")
        if role not in ALLOWED_ROLES:
            raise HTTPException(status_code=400, detail="Invalid role in request")
        await db.users.update_one({"id": req.get("user_id")}, {"$set": {"role": role, "is_admin": role == "admin"}})

        if role == "vet":
            approved_user = await db.users.find_one({"id": req.get("user_id")})
            profile = await ensure_vet_profile(req.get("user_id"), user=approved_user)
            await db.vet_profiles.update_one(
                {"id": profile["id"]},
                {"$set": {
                    "status": "pending_verification",
                    "verified": False,
                    "is_public": False,
                    "updated_at": datetime.utcnow(),
                }},
            )

    new_status = "approved" if action == "approve" else "rejected"
    await db.role_requests.update_one(
        {"id": request_id},
        {"$set": {"status": new_status, "updated_at": datetime.utcnow(), "reviewed_by": admin_user["id"]}}
    )

    await create_notification(
        req.get("user_id"),
        "Role request update",
        f"Your request for {req.get('target_role')} was {new_status}.",
        "role_request",
        {"request_id": request_id, "status": new_status, "target_role": req.get("target_role"), "route": "/my-role-requests"}
    )
    await audit_admin_action(admin_user, "review_role_request", "role_request", request_id, {"action": action, "status": new_status})
    return {"success": True}

@api_router.get('/admin/audit-logs')
async def get_admin_audit_logs(
    limit: int = 200,
    q: Optional[str] = None,
    action: Optional[str] = None,
    from_date: Optional[str] = None,
    to_date: Optional[str] = None,
    admin_user: dict = Depends(get_admin_user)
):
    query: dict = {}

    if action and action != 'all':
        query['action'] = action

    if q:
        qv = str(q).strip()
        if qv:
            query['$or'] = [
                {"action": {"$regex": qv, "$options": "i"}},
                {"target_type": {"$regex": qv, "$options": "i"}},
                {"target_id": {"$regex": qv, "$options": "i"}},
                {"admin_email": {"$regex": qv, "$options": "i"}},
            ]

    date_query: dict = {}
    if from_date:
        try:
            date_query['$gte'] = datetime.fromisoformat(str(from_date))
        except Exception:
            pass
    if to_date:
        try:
            # inclusive day if YYYY-MM-DD provided
            to_dt = datetime.fromisoformat(str(to_date))
            if len(str(to_date)) == 10:
                to_dt = to_dt + timedelta(days=1)
            date_query['$lt'] = to_dt
        except Exception:
            pass
    if date_query:
        query['created_at'] = date_query

    rows = await db.admin_audit_logs.find(query).sort("created_at", -1).limit(max(1, min(limit, 1000))).to_list(1000)
    return [{k: v for k, v in r.items() if k != "_id"} for r in rows]

@api_router.get("/admin/orders")
async def get_all_orders_admin(admin_user: dict = Depends(get_admin_user)):
    """Get all orders for admin"""
    orders = await db.orders.find({}).sort("created_at", -1).to_list(1000)
    result = []
    for order in orders:
        user = await db.users.find_one({"id": order.get("user_id")})
        result.append({
            "id": order.get("id"),
            "user_id": order.get("user_id"),
            "user_name": user.get("name") if user else "Unknown",
            "items": order.get("items", []),
            "total": order.get("total", 0),
            "status": order.get("status", "pending"),
            "payment_method": order.get("payment_method"),
            "shipping_address": order.get("shipping_address"),
            "shipping_city": order.get("shipping_city"),
            "created_at": order.get("created_at"),
        })
    return result

@api_router.put("/admin/orders/{order_id}")
async def update_order_admin(order_id: str, data: dict, admin_user: dict = Depends(get_admin_user)):
    """Update order status (admin)"""
    await db.orders.update_one({"id": order_id}, {"$set": data})
    return {"success": True}

@api_router.get("/admin/products")
async def get_all_products_admin(admin_user: dict = Depends(get_admin_user)):
    """Get all products for admin"""
    products = await db.products.find({}).to_list(1000)
    return [
        {
            "id": p.get("id"),
            "name": p.get("name"),
            "description": p.get("description"),
            "price": p.get("price"),
            "category": p.get("category"),
            "stock": p.get("stock", 0),
            "image_url": p.get("image_url"),
            "is_active": p.get("is_active", True),
        }
        for p in products
    ]

@api_router.post("/admin/products")
async def create_product_admin(data: dict, admin_user: dict = Depends(get_admin_user)):
    """Create new product (admin)"""
    product = {
        "id": str(uuid.uuid4()),
        **data,
        "created_at": datetime.utcnow(),
    }
    await db.products.insert_one(product)
    return product

@api_router.put("/admin/products/{product_id}")
async def update_product_admin(product_id: str, data: dict, admin_user: dict = Depends(get_admin_user)):
    """Update product (admin)"""
    await db.products.update_one({"id": product_id}, {"$set": data})
    return {"success": True}

@api_router.delete("/admin/products/{product_id}")
async def delete_product_admin(product_id: str, admin_user: dict = Depends(get_admin_user)):
    """Delete product (admin)"""
    await db.products.delete_one({"id": product_id})
    return {"success": True}

@api_router.get("/admin/appointments")
async def get_all_appointments_admin(admin_user: dict = Depends(get_admin_user)):
    """Get all appointments for admin"""
    appointments = await db.appointments.find({}).sort("date", -1).to_list(1000)
    return appointments

@api_router.get("/admin/vets")
async def get_all_vets_admin(admin_user: dict = Depends(get_admin_user)):
    """Legacy admin vets endpoint: returns vet profiles joined with user"""
    rows = await db.vet_profiles.find({}).sort("updated_at", -1).to_list(1000)
    user_ids = [r.get("user_id") for r in rows if r.get("user_id")]
    users = await db.users.find({"id": {"$in": user_ids}}).to_list(1000)
    user_map = {u.get("id"): u for u in users}
    out = []
    for r in rows:
        u = user_map.get(r.get("user_id"), {})
        out.append({
            **_serialize_doc(r),
            "user_email": u.get("email"),
            "user_name": u.get("name"),
            "user_role": u.get("role"),
            "user_is_verified": u.get("is_verified", False),
        })
    return out


@api_router.get("/admin/vet-profiles")
async def get_admin_vet_profiles(
    status: Optional[str] = None,
    q: Optional[str] = None,
    city: Optional[str] = None,
    admin_user: dict = Depends(get_admin_user),
):
    query: dict = {}
    if status and status in VET_PROFILE_STATUSES:
        query["status"] = status
    if city:
        query["city"] = {"$regex": str(city).strip(), "$options": "i"}
    if q:
        qv = str(q).strip()
        if qv:
            query["$or"] = [
                {"name": {"$regex": qv, "$options": "i"}},
                {"specialty": {"$regex": qv, "$options": "i"}},
                {"city": {"$regex": qv, "$options": "i"}},
            ]

    rows = await db.vet_profiles.find(query).sort("updated_at", -1).to_list(1000)
    user_ids = [r.get("user_id") for r in rows if r.get("user_id")]
    users = await db.users.find({"id": {"$in": user_ids}}).to_list(1000)
    user_map = {u.get("id"): u for u in users}

    blocked_rows = await db.blocked_users.find({"user_id": admin_user["id"], "blocked_user_id": {"$in": user_ids}}).to_list(2000)
    blocked_set = {r.get("blocked_user_id") for r in blocked_rows}

    out = []
    for r in rows:
        u = user_map.get(r.get("user_id"), {})
        out.append({
            **_serialize_doc(r),
            "user": {
                "id": u.get("id"),
                "name": u.get("name"),
                "email": u.get("email"),
                "role": u.get("role"),
                "is_verified": u.get("is_verified", False),
                "is_blocked_by_admin": u.get("id") in blocked_set,
            },
        })
    return out


@api_router.put("/admin/vet-profiles/{profile_id}")
async def update_admin_vet_profile(profile_id: str, data: dict, admin_user: dict = Depends(get_admin_user)):
    profile = await db.vet_profiles.find_one({"id": profile_id})
    if not profile:
        raise HTTPException(status_code=404, detail="Vet profile not found")

    action = str(data.get("action") or "").strip().lower()
    notes = data.get("verification_notes")
    update: dict = {"updated_at": datetime.utcnow()}

    if action == "approve":
        update.update({"status": "active", "verified": True})
    elif action == "reject":
        note = str(notes or "").strip()
        if not note:
            raise HTTPException(status_code=400, detail="verification_notes are required for reject")
        update.update({"status": "rejected", "verified": False, "is_public": False, "verification_notes": note})
    elif action == "suspend":
        update.update({"status": "suspended", "is_public": False})
    elif action == "activate":
        if not profile.get("verified"):
            raise HTTPException(status_code=400, detail="Cannot activate unverified profile")
        update.update({"status": "active"})
    elif action == "set_public":
        is_public = bool(data.get("is_public", False))
        if is_public and (profile.get("status") != "active" or not profile.get("verified")):
            raise HTTPException(status_code=400, detail="Only verified active profiles can be public")
        update.update({"is_public": is_public})
    else:
        raise HTTPException(status_code=400, detail="Invalid action")

    if notes is not None and action != "reject":
        update["verification_notes"] = str(notes).strip() or None

    await db.vet_profiles.update_one({"id": profile_id}, {"$set": update})

    await create_notification(
        profile.get("user_id"),
        "Vet profile update",
        f"Your vet profile status is now {update.get('status', profile.get('status'))}.",
        "vet_profile",
        {"profile_id": profile_id, "action": action},
    )
    await audit_admin_action(admin_user, "review_vet_profile", "vet_profile", profile_id, {"action": action, **update})

    updated = await db.vet_profiles.find_one({"id": profile_id})
    return _serialize_doc(updated)

@api_router.get("/admin/community")
async def get_all_posts_admin(admin_user: dict = Depends(get_admin_user)):
    """Get all community posts for admin"""
    posts = await db.community_posts.find({}).sort("created_at", -1).to_list(1000)
    return posts

@api_router.delete("/admin/community/{post_id}")
async def delete_post_admin(post_id: str, admin_user: dict = Depends(get_admin_user)):
    """Delete community post (admin)"""
    await db.community_posts.delete_one({"id": post_id})
    return {"success": True}

@api_router.get("/admin/payments")
async def get_all_payments_admin(admin_user: dict = Depends(get_admin_user)):
    """Get all payments for admin"""
    payments = await db.payments.find({}).sort("created_at", -1).to_list(1000)
    return payments

@api_router.get("/admin/sponsorships")
async def get_all_sponsorships_admin(admin_user: dict = Depends(get_admin_user)):
    """Get all sponsorships for admin"""
    sponsorships = await db.sponsorships.find({}).sort("created_at", -1).to_list(1000)
    return sponsorships

@api_router.get("/admin/locations")
async def get_all_locations_admin(admin_user: dict = Depends(get_admin_user)):
    """Get all map locations for admin"""
    locations = await db.map_locations.find({}).to_list(1000)
    return locations

@api_router.post("/admin/locations")
async def create_location_admin(data: dict, admin_user: dict = Depends(get_admin_user)):
    """Create map location (admin)"""
    location = {
        "id": str(uuid.uuid4()),
        **data,
    }
    await db.map_locations.insert_one(location)
    return location

@api_router.put("/admin/locations/{location_id}")
async def update_location_admin(location_id: str, data: dict, admin_user: dict = Depends(get_admin_user)):
    """Update map location (admin)"""
    await db.map_locations.update_one({"id": location_id}, {"$set": data})
    return {"success": True}

@api_router.delete("/admin/locations/{location_id}")
async def delete_location_admin(location_id: str, admin_user: dict = Depends(get_admin_user)):
    """Delete map location (admin)"""
    await db.map_locations.delete_one({"id": location_id})
    return {"success": True}

# ========================= MAIN ROUTES =========================

@api_router.get("/")
async def root():
    return {"message": "Welcome to Petsy API", "version": "1.0.0"}

@api_router.get("/health")
async def health_check():
    """Report database reachability so load balancers can drain a broken instance."""
    try:
        await client.admin.command("ping")
        db_ok = True
    except Exception as e:
        logger.error("Health check database ping failed: %s", e)
        db_ok = False

    payload = {
        "status": "healthy" if db_ok else "degraded",
        "database": "up" if db_ok else "down",
        "environment": ENVIRONMENT,
        "timestamp": datetime.utcnow().isoformat(),
    }
    if not db_ok:
        return JSONResponse(status_code=503, content=payload)
    return payload

# Include the router
app.include_router(api_router)
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")


# Indexes that back the hot query paths and enforce the uniqueness the code assumes.
INDEXES: Dict[str, List[tuple]] = {
    "users": [
        ("role", 1),
        ("created_at", -1),
        ("social_providers.google", 1),
        ("social_providers.facebook", 1),
        ("social_providers.instagram", 1),
    ],
    "pets": [("owner_id", 1)],
    "health_records": [("pet_id", 1)],
    "notifications": [("user_id", 1), ("created_at", -1)],
    "orders": [("user_id", 1), ("created_at", -1)],
    "payments": [("user_id", 1), ("created_at", -1)],
    "points_transactions": [("user_id", 1), ("created_at", -1)],
    "appointments": [("user_id", 1), ("date", 1)],
    "care_requests": [("assigned_vet_id", 1), ("status", 1)],
    "conversations": [("participants", 1), ("updated_at", -1)],
    "chat_messages": [("conversation_id", 1), ("created_at", 1)],
    "community": [("created_at", -1)],
    "comments": [("post_id", 1), ("created_at", 1)],
    "marketplace_listings": [("created_at", -1)],
    "favorites": [("user_id", 1)],
    "friendships": [("user_id", 1)],
    "blocked_users": [("user_id", 1)],
    "device_tokens": [("user_id", 1), ("provider", 1)],
}

UNIQUE_INDEXES: Dict[str, List[str]] = {
    "users": ["email", "username", "id"],
    "pets": ["id"],
    "orders": ["id"],
    "payments": ["id"],
    "device_tokens": ["token"],
}


@app.on_event("startup")
async def ensure_indexes():
    for collection, fields in UNIQUE_INDEXES.items():
        for field in fields:
            try:
                await db[collection].create_index(field, unique=True, sparse=True)
            except Exception as e:
                logger.warning("Could not create unique index %s.%s: %s", collection, field, e)

    for collection, keys in INDEXES.items():
        try:
            await db[collection].create_index(list(keys))
        except Exception as e:
            logger.warning("Could not create index on %s %s: %s", collection, keys, e)

    logger.info("Startup complete. environment=%s simulation_payments=%s seed_enabled=%s",
                ENVIRONMENT, PAYMENTS_SIMULATION_ENABLED, SEED_ENABLED)

app.add_middleware(
    CORSMiddleware,
    allow_credentials=True,
    allow_origins=ALLOWED_ORIGINS,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept", "Accept-Language"],
)

@app.on_event("shutdown")
async def shutdown_db_client():
    client.close()
