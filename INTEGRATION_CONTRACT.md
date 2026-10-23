# RAISE Smart Market Ecosystem — Shared Integration Contract

**Version:** 2.0.0  
**Scope:** Drivesystem (ESP32), RAISE (Pi Kiosk), raise-cloud (Backend/Edge Functions), raise-smart-market (Fleet Portal)

---

## 1. System Architecture & Component Roles

| Component | Role | Network Identity | Primary Communications |
|---|---|---|---|
| **Drivesystem** | Motor controller & chassis safety | Serial (115200 baud) / Hardware GPIO | Joystick inputs, E-stop, IR proximity, Motor PWM |
| **RAISE Kiosk** | Self-checkout customer station | Client with Kiosk Device Key (`x-kiosk-key`) | Calls `raise-cloud/functions/v1/kiosk` |
| **raise-cloud** | Authoritative database & business rules | REST / PostgreSQL / Deno Edge Functions | Row-Level Security, HMAC signatures, server pricing |
| **raise-smart-market**| Fleet manager & Anti-theft monitor | Browser Client (Admin & Tablet Simulator) | Supabase client + Realtime channel subscriptions |

---

## 2. Shared Database Entities & Schema

All applications must align with the PostgreSQL schema managed by `raise-cloud`:

### `public.products` (Authoritative Store Catalog)
```sql
id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
barcode TEXT UNIQUE NOT NULL CHECK (barcode ~ '^[0-9]{6,14}$'),
title TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
brand TEXT NOT NULL DEFAULT '',
category TEXT NOT NULL DEFAULT 'General',
price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
weight_grams NUMERIC(10, 2) NOT NULL DEFAULT 100.00 CHECK (weight_grams >= 0),
image_url TEXT NOT NULL DEFAULT '',
stock INTEGER CHECK (stock IS NULL OR stock >= 0),
active BOOLEAN NOT NULL DEFAULT true,
created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
```
*Note for frontends:* Frontends may display `title` as `name`.

### `public.trolleys` (IoT Fleet & Scale Telemetry)
```sql
id TEXT PRIMARY KEY,                       -- e.g. 'TRL-DEL-101'
battery_level INTEGER NOT NULL DEFAULT 100 CHECK (battery_level BETWEEN 0 AND 100),
status TEXT NOT NULL DEFAULT 'idle' CHECK (status IN ('idle', 'verified', 'mismatch', 'charging')),
customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
current_customer_name TEXT,
current_customer_phone TEXT,
items_count INTEGER NOT NULL DEFAULT 0 CHECK (items_count >= 0),
total_amount NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (total_amount >= 0),
measured_weight NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (measured_weight >= 0),
expected_weight NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (expected_weight >= 0),
security_alert TEXT,
last_item_scanned TEXT,
locked BOOLEAN NOT NULL DEFAULT false,
updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
```

### `public.orders`
```sql
id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
number BIGINT NOT NULL UNIQUE DEFAULT nextval('public.order_number_seq'),
customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
kiosk_id UUID REFERENCES public.kiosks(id) ON DELETE SET NULL,
trolley_id TEXT REFERENCES public.trolleys(id) ON DELETE SET NULL,
status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'cancelled')),
item_count INTEGER NOT NULL DEFAULT 0,
total NUMERIC(10, 2) NOT NULL DEFAULT 0 CHECK (total >= 0),
points_earned INTEGER NOT NULL DEFAULT 0,
created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
paid_at TIMESTAMPTZ
```

### `public.order_items`
```sql
id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
barcode TEXT NOT NULL,
title TEXT NOT NULL,
unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),
qty INTEGER NOT NULL CHECK (qty > 0),
estimated BOOLEAN NOT NULL DEFAULT false
```

---

## 3. Authentication & Security Contracts

### A. Customer Pass QR (`RAISE2` Token)
* Format: `RAISE2.<pass_id>.<signature>`
  * `<pass_id>`: 10 Crockford Base32 characters (`[0-9A-Z]{10}`)
  * `<signature>`: 22 base64url characters generated via `HMAC-SHA256(PASS_SECRET, "RAISE2." + pass_id)`
* Properties:
  * Static: Can be printed or displayed on any phone screen.
  * Tamper-proof: Secret never leaves Edge Functions; invalid signatures rejected with HTTP 400.
  * Anonymous: Contains no names, phone numbers, or balances.

### B. Kiosk Device Authentication
* Kiosks provisioned with a random 24-byte base64url token.
* Database stores only `sha256(raw_key)`.
* Requests passed in header: `x-kiosk-key: <device_key>`.
* Edge Function verifies SHA-256 against `public.kiosks` and ensures `active = true`.

### C. NFC Card Identification
* Physical cards read by PN532 or Web NFC.
* Stored and looked up strictly as `sha256("raise-nfc:" + uid.toLowerCase())`.
* Plaintext card UIDs are never stored in the database.

---

## 4. API Endpoints (`functions/v1/kiosk`)

### `heartbeat`
* **Request:** `{ "action": "heartbeat", "info": { "version": "...", "stage": "..." } }`
* **Response:** `{ "ok": true, "name": "Kiosk #1" }`

### `identify`
* **Request:** `{ "action": "identify", "pass": "<token>" }` OR `{ "action": "identify", "card": "<hash>" }`
* **Response:** `{ "customer": { "id": "...", "name": "...", "points": 120, "has_card": true }, "token": "..." }`

### `checkout`
* **Request:**
  ```json
  {
    "action": "checkout",
    "customer_id": "uuid-optional",
    "pass": "token-optional",
    "items": [
      { "barcode": "8901058023800", "qty": 2, "price": 112 },
      { "barcode": "4006381333931", "qty": 1, "price": 50, "title": "Unlisted Pen" }
    ]
  }
  ```
* **Security Rule:** Server queries `products` table by barcode and uses the database price. If a barcode is unlisted, the client's estimated price is capped at ₹5000 and marked `estimated: true`.
* **Response:** `{ "order": { "id": "...", "number": 1005, "total": 274.00, "status": "pending", "items": [...] } }`

### `paid`
* **Request:** `{ "action": "paid", "order_id": "uuid" }`
* **Idempotency Rule:** If order is already `paid`, returns existing order with `points: 0` without duplicate updates.
* **Loyalty Rule:** Server credits `floor(total * 0.1)` points directly to `customers.points`.
* **Response:** `{ "order": { "status": "paid", "paid_at": "..." }, "points": 27, "balance": 147 }`

---

## 5. Anti-Theft & Weight Mismatch Contract

1. **Scale Sensitivity:** Default tolerance is $\pm 150\text{ g}$.
2. **Detection Logic:**
   $$\Delta W = W_{\text{measured}} - W_{\text{expected}}$$
   * $|\Delta W| \le 150\text{ g}$: Status is `verified`, wheels unlocked.
   * $\Delta W > 150\text{ g}$: Status is `mismatch`, alert flagged, wheels locked (unscanned item placed in cart).
   * $\Delta W < -150\text{ g}$: Status is `mismatch`, alert flagged, wheels locked (item removed without scanning).
3. **Resolution:** Floor attendant verifies cart contents and triggers `resolveTrolleyAlert(trolleyId)`, which re-calibrates the scale tare and unlocks the wheels.
