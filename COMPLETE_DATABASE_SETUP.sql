-- ============================================================================
-- RAISE SMART MARKET & SELF-CHECKOUT KIOSK — MASTER DATABASE SETUP
-- Target: Supabase PostgreSQL (Project ref: ievqvubwmynousijplik)
-- ============================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. PRODUCTS TABLE (Source of truth for store inventory, prices & scale weights)
CREATE TABLE IF NOT EXISTS public.products (
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
);

-- 3. SMART TROLLEYS TABLE (IoT Fleet telemetry & Anti-Theft scale monitoring)
CREATE TABLE IF NOT EXISTS public.trolleys (
    id TEXT PRIMARY KEY,
    battery_level INTEGER NOT NULL DEFAULT 100 CHECK (battery_level BETWEEN 0 AND 100),
    status TEXT NOT NULL DEFAULT 'idle' CHECK (status IN ('idle', 'verified', 'mismatch', 'charging')),
    customer_id UUID,
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
);

-- 4. ORDERS & ORDER ITEMS TABLE (Immutable transaction record)
CREATE SEQUENCE IF NOT EXISTS public.order_number_seq START 1001;

CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    number BIGINT NOT NULL UNIQUE DEFAULT nextval('public.order_number_seq'),
    customer_id UUID,
    kiosk_id UUID,
    trolley_id TEXT REFERENCES public.trolleys(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'cancelled')),
    item_count INTEGER NOT NULL DEFAULT 0,
    total NUMERIC(10, 2) NOT NULL DEFAULT 0 CHECK (total >= 0),
    points_earned INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    paid_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
    barcode TEXT NOT NULL,
    title TEXT NOT NULL,
    unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),
    qty INTEGER NOT NULL CHECK (qty > 0),
    estimated BOOLEAN NOT NULL DEFAULT false
);

-- 5. ENABLE ROW-LEVEL SECURITY (Never disabled in production)
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trolleys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

-- 6. PUBLIC ACCESS POLICIES
DROP POLICY IF EXISTS "catalog is public" ON public.products;
CREATE POLICY "catalog is public" ON public.products FOR SELECT USING (active = true);

DROP POLICY IF EXISTS "trolleys readable by store" ON public.trolleys;
CREATE POLICY "trolleys readable by store" ON public.trolleys FOR SELECT USING (true);

DROP POLICY IF EXISTS "trolleys updatable by fleet" ON public.trolleys;
CREATE POLICY "trolleys updatable by fleet" ON public.trolleys FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "orders read own" ON public.orders;
CREATE POLICY "orders read own" ON public.orders FOR SELECT USING (true);

DROP POLICY IF EXISTS "orders insert" ON public.orders;
CREATE POLICY "orders insert" ON public.orders FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "orders update" ON public.orders;
CREATE POLICY "orders update" ON public.orders FOR UPDATE USING (true) WITH CHECK (true);

-- 7. ENABLE REALTIME REPLICATION (For live trolley tracking)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'trolleys'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.trolleys;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'orders'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'products'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.products;
  END IF;
END $$;

-- 8. SEED INITIAL PRODUCTS (Store inventory with anti-theft scale weights)
INSERT INTO public.products (barcode, title, brand, category, price, weight_grams, image_url, stock, active)
VALUES
    ('8901030383786', 'Amul Taaza Milk 500ml', 'Amul', 'Dairy', 28.00, 520.00, 'https://images.unsplash.com/photo-1550583724-b2692b85b150?auto=format&fit=crop&q=80&w=200', 120, true),
    ('8901491101837', 'Lays Classic Salted 50g', 'Lays', 'Snacks', 20.00, 52.00, 'https://images.unsplash.com/photo-1566478989037-eec170784d0b?auto=format&fit=crop&q=80&w=200', 85, true),
    ('8901058852271', 'Tata Salt 1kg', 'Tata', 'Pantry', 28.00, 1010.00, 'https://images.unsplash.com/photo-1518110925495-5fe2fda0442c?auto=format&fit=crop&q=80&w=200', 60, true),
    ('8901725181222', 'Britannia Good Day 100g', 'Britannia', 'Bakery', 30.00, 105.00, 'https://images.unsplash.com/photo-1558961363-fa8fdf82db35?auto=format&fit=crop&q=80&w=200', 150, true),
    ('8901063012646', 'Parle-G Gold 1kg', 'Parle', 'Bakery', 120.00, 1020.00, 'https://images.unsplash.com/photo-1509440159596-0249088772ff?auto=format&fit=crop&q=80&w=200', 40, true),
    ('8901207010116', 'Nescafe Classic 50g', 'Nescafe', 'Beverages', 170.00, 160.00, 'https://images.unsplash.com/photo-1514432324607-a09d9b4aefdd?auto=format&fit=crop&q=80&w=200', 90, true),
    ('8901030825279', 'Maggi 2-Minute Noodles 70g', 'Nestle', 'Packaged Food', 14.00, 72.00, 'https://images.unsplash.com/photo-1612927601601-6638404737ce?auto=format&fit=crop&q=80&w=200', 200, true),
    ('8901030775284', 'Cadbury Dairy Milk 130g', 'Cadbury', 'Snacks', 105.00, 135.00, 'https://images.unsplash.com/photo-1549007994-cb92caebd54b?auto=format&fit=crop&q=80&w=200', 75, true)
ON CONFLICT (barcode) DO UPDATE SET
    title = EXCLUDED.title,
    brand = EXCLUDED.brand,
    category = EXCLUDED.category,
    price = EXCLUDED.price,
    weight_grams = EXCLUDED.weight_grams,
    image_url = EXCLUDED.image_url,
    stock = EXCLUDED.stock,
    active = EXCLUDED.active;

-- 9. SEED INITIAL SMART TROLLEYS FLEET
INSERT INTO public.trolleys (id, battery_level, status, current_customer_name, current_customer_phone, items_count, total_amount, measured_weight, expected_weight, locked)
VALUES
    ('TR-101', 94, 'verified', 'Aarav Patel', '+91 98765 43210', 4, 385.00, 1684.00, 1684.00, false),
    ('TR-102', 28, 'mismatch', 'Priya Sharma', '+91 98234 56789', 2, 120.00, 680.00, 540.00, true),
    ('TR-103', 88, 'idle', NULL, NULL, 0, 0.00, 0.00, 0.00, false),
    ('TR-104', 15, 'charging', NULL, NULL, 0, 0.00, 0.00, 0.00, true)
ON CONFLICT (id) DO UPDATE SET
    battery_level = EXCLUDED.battery_level,
    status = EXCLUDED.status,
    current_customer_name = EXCLUDED.current_customer_name,
    current_customer_phone = EXCLUDED.current_customer_phone,
    items_count = EXCLUDED.items_count,
    total_amount = EXCLUDED.total_amount,
    measured_weight = EXCLUDED.measured_weight,
    expected_weight = EXCLUDED.expected_weight,
    locked = EXCLUDED.locked;
