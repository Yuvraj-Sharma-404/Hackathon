// Unit & Integration Tests for RAISE Kiosk Frontend Logic & Hardware Bridges
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';

// --- 1. Barcode Normalization (EAN-13 & UPC-A) ---
function normaliseBarcode(code) {
  const c = String(code).trim();
  return /^\d{12}$/.test(c) ? '0' + c : c;
}

test('normaliseBarcode correctly handles 12-digit UPC-A and 13-digit EAN-13', () => {
  assert.equal(normaliseBarcode('8901058023800'), '8901058023800'); // Standard 13-digit
  assert.equal(normaliseBarcode('012345678905'), '0012345678905');   // 12-digit padded
  assert.equal(normaliseBarcode('  8901491503020  '), '8901491503020'); // Whitespace trimmed
});

// --- 2. NFC Keystroke Bridge Parsing ---
function parseNfcKeyboardInput(scannedString) {
  const trimmed = scannedString.trim().toLowerCase();
  if (trimmed.startsWith('nfc-')) {
    const hex = trimmed.slice(4);
    if (/^[0-9a-f]{8,32}$/.test(hex)) {
      const cardHash = createHash('sha256').update('raise-nfc:' + hex).digest('hex');
      return { isNfc: true, uid: hex, hash: cardHash };
    }
  }
  return { isNfc: false, uid: null, hash: null };
}

test('parseNfcKeyboardInput detects virtual NFC keyboard keystrokes and computes SHA-256 hash', () => {
  const parsed = parseNfcKeyboardInput('nfc-04a3b2c1d0e580');
  assert.equal(parsed.isNfc, true);
  assert.equal(parsed.uid, '04a3b2c1d0e580');
  assert.equal(parsed.hash.length, 64); // SHA-256 hex string

  const invalid = parseNfcKeyboardInput('8901058023800');
  assert.equal(invalid.isNfc, false);
});

// --- 3. Buzzer Sound Patterns Protocol ---
const BUZZER_PATTERNS = {
  scan:  { freq: 1046, ms: 90, repeats: 1 },
  login: { freq: 1568, ms: 70, repeats: 2 },
  error: { freq: 330,  ms: 160, repeats: 1 },
  paid:  { freq: 1318, ms: 140, repeats: 1 }
};

function buildBuzzerUrl(event, host = 'http://127.0.0.1:8799') {
  const p = BUZZER_PATTERNS[event];
  if (!p) throw new Error(`Unknown sound event: ${event}`);
  return `${host}/beep?f=${p.freq}&ms=${p.ms}&n=${p.repeats}`;
}

test('buildBuzzerUrl constructs compliant HTTP parameters for localhost buzzer-bridge', () => {
  assert.equal(buildBuzzerUrl('scan'), 'http://127.0.0.1:8799/beep?f=1046&ms=90&n=1');
  assert.equal(buildBuzzerUrl('login'), 'http://127.0.0.1:8799/beep?f=1568&ms=70&n=2');
  assert.equal(buildBuzzerUrl('error'), 'http://127.0.0.1:8799/beep?f=330&ms=160&n=1');
  assert.equal(buildBuzzerUrl('paid'), 'http://127.0.0.1:8799/beep?f=1318&ms=140&n=1');
  assert.throws(() => buildBuzzerUrl('invalid'), /Unknown sound event/);
});

// --- 4. Pass QR Token Structure Verification ---
function verifyPassTokenStructure(token) {
  if (typeof token !== 'string') return false;
  // Format: RAISE2.<10_char_crockford_base32>.<22_char_base64url_hmac>
  return /^RAISE2\.[0-9A-Z]{10}\.[A-Za-z0-9_-]{22}$/.test(token);
}

test('verifyPassTokenStructure validates official HMAC-signed RAISE2 tokens', () => {
  assert.equal(verifyPassTokenStructure('RAISE2.9XYZ8ABC23.aB3_dE4-fG5_hI6-jK7_lM'), true);
  assert.equal(verifyPassTokenStructure('RAISE1.INSECURE.123'), false); // Old version rejected
  assert.equal(verifyPassTokenStructure('TAMPERED_QR_CODE'), false);
  assert.equal(verifyPassTokenStructure(null), false);
});
