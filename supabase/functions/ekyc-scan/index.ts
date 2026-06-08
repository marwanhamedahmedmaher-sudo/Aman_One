// ============================================================================
// ekyc-scan — server-side OCR / eKYC proxy for the Aman ID-scan flow
// ============================================================================
// PRODUCTION SEAM. The Flutter app (EdgeFunctionEkycService) POSTs
//   { "image_base64": "<jpeg/png bytes, base64>" }
// to this function. This function forwards the image to the COMPANY eKYC
// vendor (e.g. Valify) and returns the extracted Egyptian National ID fields
// in the exact shape EkycResult.fromJson() expects:
//
//   {
//     "full_name":    "محمد أحمد علي",
//     "national_id":  "29001010100013",
//     "address":      "١٥ شارع جمال عبد الناصر، مدينة نصر، القاهرة",
//     "birth_date":   "1990-01-01",
//     "governorate":  "القاهرة",
//     "gender":       "ذكر",
//     "confidence":   { "full_name": 0.97, "national_id": 0.99, "address": 0.9 }
//   }
//
// WHY A SERVER PROXY (do not OCR on the device):
//   1. The vendor API key stays in this function's secrets, never in the APK.
//      ->  supabase secrets set EKYC_API_KEY=... EKYC_VENDOR_URL=...
//   2. One PDPL chokepoint: decide here whether the ID image is retained or
//      discarded after extraction (data minimisation — see TODO below).
//   3. Vendor swap = edit this one file; the app never changes.
//
// ACTIVATE IN THE APP:  --dart-define=EKYC_ENDPOINT=ekyc-scan
// DEPLOY:               supabase functions deploy ekyc-scan
// ============================================================================

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const VENDOR_URL = Deno.env.get("EKYC_VENDOR_URL") ?? "";
const VENDOR_KEY = Deno.env.get("EKYC_API_KEY") ?? "";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "POST only" }, 405);
  }

  let body: { image_base64?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }

  const imageBase64 = body.image_base64;
  if (!imageBase64 || imageBase64.length < 100) {
    return json({ error: "image_base64 is required" }, 400);
  }

  // --------------------------------------------------------------------------
  // TODO(tech-team): call the company eKYC vendor here and map its response to
  // the EkycResult shape above. Sketch:
  //
  //   const vendorRes = await fetch(VENDOR_URL, {
  //     method: "POST",
  //     headers: {
  //       "Authorization": `Bearer ${VENDOR_KEY}`,
  //       "Content-Type": "application/json",
  //     },
  //     body: JSON.stringify({ image: imageBase64, doc_type: "egypt_national_id" }),
  //   });
  //   if (!vendorRes.ok) return json({ error: "vendor error" }, 502);
  //   const v = await vendorRes.json();
  //   return json(mapVendorToEkyc(v), 200);
  //
  // DATA MINIMISATION (PDPL): do NOT persist `imageBase64`. Extract fields,
  // return them, let the image fall out of scope. If KYC later requires the
  // image, store it in a RLS-protected bucket with an explicit retention
  // policy — that is a deliberate decision, not a default.
  // --------------------------------------------------------------------------

  // Until the vendor is wired, return a deterministic, trigger-valid mock so
  // the full round-trip is verifiable end-to-end the moment EKYC_ENDPOINT is
  // set. (The emulator demo uses the in-app MockEkycService and never calls
  // this function — this branch only matters once you flip to the live path.)
  if (!VENDOR_URL || !VENDOR_KEY) {
    return json(mockResult(), 200);
  }

  return json({ error: "eKYC vendor not wired — see TODO in index.ts" }, 501);
});

function mockResult() {
  return {
    full_name: "محمد أحمد علي",
    national_id: "29001010100013", // century 2, 1990-01-01, gov 01 (Cairo)
    address: "١٥ شارع جمال عبد الناصر، مدينة نصر، القاهرة",
    birth_date: "1990-01-01",
    governorate: "القاهرة",
    gender: "ذكر",
    confidence: { full_name: 0.97, national_id: 0.99, address: 0.9 },
  };
}

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}
