// ============================================================================
// ekyc-scan — server-side OCR / eKYC proxy for the Aman document-scan flow
// ============================================================================
// PRODUCTION SEAM. The Flutter app (EdgeFunctionEkycService) POSTs
//   { "image_base64": "<jpeg/png bytes, base64>", "doc_type": "<type>" }
// where doc_type is one of:
//   national_id        -> Egyptian National ID  (EkycResult shape)
//   passport           -> foreign passport      (PassportResult shape)
//   commercial_register-> commercial register   (DocOcrResult { fields })
//   tax_card           -> tax card              (DocOcrResult { fields })
//
// This function forwards the image to the COMPANY eKYC vendor (e.g. Valify) and
// returns the extracted fields. For the National ID the shape EkycResult.fromJson()
// expects is:
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

  let body: { image_base64?: string; doc_type?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }

  const imageBase64 = body.image_base64;
  if (!imageBase64 || imageBase64.length < 100) {
    return json({ error: "image_base64 is required" }, 400);
  }

  const docType = body.doc_type ?? "national_id";

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
  //     body: JSON.stringify({ image: imageBase64, doc_type: docType }),
  //   });
  //   if (!vendorRes.ok) return json({ error: "vendor error" }, 502);
  //   const v = await vendorRes.json();
  //   return json(mapVendorToEkyc(v, docType), 200);
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
    return json(mockResult(docType), 200);
  }

  return json({ error: "eKYC vendor not wired — see TODO in index.ts" }, 501);
});

// Deterministic, trigger-valid mocks per document type. Shapes match the
// Flutter result parsers: EkycResult / PassportResult / DocOcrResult.
function mockResult(docType: string) {
  switch (docType) {
    case "passport":
      return {
        full_name: "أحمد خالد المنصور",
        full_name_en: "Ahmed Khaled Almansour",
        passport_number: "A12345678",
        nationality: "سوري",
        birth_date: "1988-05-12",
        expiry_date: "2030-05-11",
        gender: "ذكر",
        confidence: { passport_number: 0.98, nationality: 0.95 },
      };
    case "commercial_register":
      return {
        fields: { commercial_reg: "123456", company_name: "شركة النور للتجارة" },
        confidence: { commercial_reg: 0.96 },
      };
    case "tax_card":
      return {
        fields: { tax_card: "456789123" },
        confidence: { tax_card: 0.96 },
      };
    case "national_id":
    default:
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
}

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}
