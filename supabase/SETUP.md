# ReceiptIQ — Supabase & API setup (beginner-friendly)

The app already runs **offline** with local storage and sample data. Follow
these steps only when you're ready to turn on the cloud + real AI scanning.
Nothing here touches your code — you just create accounts and paste keys into
the `.env` file.

---

## 1. Create the Supabase project
1. Go to https://supabase.com and sign up (free).
2. Click **New project**. Pick a name (e.g. `receiptiq`), a strong database
   password, and the region closest to your users (e.g. EU/London for Kenya).
3. Wait ~2 minutes for it to provision.

## 2. Run the database schema
1. In the Supabase dashboard, open **SQL Editor** (left sidebar) → **New query**.
2. Open the file `supabase/schema.sql` from this project, copy ALL of it, paste
   into the editor, and click **Run**.
3. You should see "Success. No rows returned." This created the tables
   (`receipts`, `line_items`, `budgets`, `businesses`), security rules (RLS),
   and the private `receipts` storage bucket.

## 3. Enable anonymous sign-in
The app signs users in anonymously so each device gets its own private data.
1. Dashboard → **Authentication** → **Providers** (or **Sign In / Providers**).
2. Find **Anonymous** and toggle it **ON**. Save.

> Later, you can add email/Google sign-in; the data already links to a user id.

## 4. Get your project URL + anon key
1. Dashboard → **Project Settings** (gear) → **API**.
2. Copy the **Project URL** and the **anon public** key.

## 5. Get the AI keys (for real scanning)
- **Google Vision (OCR):** https://console.cloud.google.com → create a project →
  enable **Cloud Vision API** → **Credentials** → **Create API key**. Make sure
  billing is enabled on the Google Cloud project.
- **OpenAI (extraction):** https://platform.openai.com → **API keys** →
  **Create new secret key**. Add a little billing credit.

## 6. Fill in the `.env` file
Open `.env` in the project root and set:

```
SUPABASE_URL=https://YOUR-PROJECT.supabase.co
SUPABASE_ANON_KEY=YOUR-ANON-PUBLIC-KEY
GOOGLE_VISION_API_KEY=YOUR-GOOGLE-VISION-KEY
OPENAI_API_KEY=YOUR-OPENAI-KEY
OPENAI_MODEL=gpt-4o-mini
DEFAULT_CURRENCY=KES
```

Save the file. (`.env` is gitignored, so your keys never get committed.)

## 7. Run the app
In your terminal (with a device/emulator running):

```
flutter run
```

- If Supabase keys are present, the app stores receipts in the cloud and
  uploads images to Storage automatically.
- If AI keys are present, scanning reads + understands receipts for real.
- If anything is missing, the app falls back to local storage / manual entry,
  so it always works.

---

## How it behaves
- **No keys:** local storage + seeded sample data + manual receipt entry.
- **Supabase keys only:** cloud storage, no auto-scan (manual entry still works).
- **All keys:** full experience — scan → OCR → AI extraction → cloud save.

## 8. Scan / AI Edge Functions

OCR and AI extraction run **server-side** — `GOOGLE_VISION_API_KEY` and
`OPENAI_API_KEY` are **never** in the Flutter app binary.

### 8a. Set secrets (Supabase dashboard → Edge Functions → Manage secrets)

| Secret | Where to get it |
|--------|----------------|
| `GOOGLE_VISION_API_KEY` | [Google Cloud Console](https://console.cloud.google.com) → APIs & Services → Credentials → Create API key. Enable **Cloud Vision API** on the project. |
| `OPENAI_API_KEY` | [OpenAI platform](https://platform.openai.com) → API keys → Create new secret key |
| `OPENAI_MODEL` | Optional — defaults to `gpt-4o-mini` |

### 8b. Create the ocr-temp Storage bucket
Re-run `supabase/schema.sql` in the SQL editor — it creates the `ocr-temp`
bucket and its RLS policies automatically.

### 8c. Deploy the scan Edge Functions
```bash
supabase functions deploy scan/ocr
supabase functions deploy scan/extract
supabase functions deploy scan/monthly-review
```

### 8d. How scanning works after deployment
1. Flutter uploads the receipt image to `ocr-temp/<uid>/<uuid>.jpg`
2. `scan/ocr` downloads it, calls Vision API, deletes the temp file, returns text
3. `scan/extract` calls OpenAI → returns structured ReceiptDraft JSON
4. Flutter navigates to the review screen; user confirms and saves

---

## 9. Authentication providers (Google, Facebook, Phone, Email)

The app now has a proper sign-in screen. Anonymous sign-in still works via
"Continue as guest" — existing guests are unaffected.

### 8a. Enable providers in Supabase

Dashboard → **Authentication** → **Providers**. Enable what you want:

| Provider | Required credentials |
|----------|----------------------|
| **Anonymous** | Toggle ON (for guest mode) |
| **Email** | Toggle ON (auto-enabled) — optionally turn off email confirmation for dev |
| **Phone (SMS OTP)** | Toggle ON → choose SMS provider (Twilio recommended). Enter Account SID + Auth Token + Twilio phone number |
| **Google** | Toggle ON → get Client ID + Client Secret from [Google Cloud Console](https://console.cloud.google.com) → OAuth 2.0 credentials → Authorised redirect URI: your Supabase callback URL |
| **Facebook** | Toggle ON → get App ID + App Secret from [Meta Developer Portal](https://developers.facebook.com) → add Supabase callback URL to OAuth redirect URIs |

### 8b. Google OAuth setup (detailed)

You need **two** OAuth clients — one for Android, one for Supabase.

**Client 1 — Android (enables native Google sign-in on device)**
1. [Google Cloud Console](https://console.cloud.google.com) → select/create project → enable the **Google Sign-In API**.
2. **APIs & Services** → **Credentials** → **Create OAuth client ID** → **Android**.
3. Package name: `com.receiptiq`
4. SHA-1: get your debug fingerprint with:
   ```
   keytool -keystore ~/.android/debug.keystore -list -v -alias androiddebugkey -storepass android
   ```
5. Save. (No Client ID/Secret to copy — this client just needs to exist.)

**Client 2 — Web application (used by Supabase server)**
1. **Credentials** → **Create OAuth client ID** → **Web application**.
2. Authorised redirect URIs: `https://<your-project-ref>.supabase.co/auth/v1/callback`
3. Copy the **Client ID** and **Client Secret** → Supabase dashboard → **Authentication → Providers → Google**.

### 8c. Facebook OAuth setup (detailed)
1. [Meta for Developers](https://developers.facebook.com) → **My Apps** → **Create App**.
2. Add **Facebook Login** product. Set Valid OAuth Redirect URI to:
   `https://<project>.supabase.co/auth/v1/callback`
3. Copy **App ID** and **App Secret** into Supabase → Authentication → Facebook.

### 8d. Android deep-link (already configured in code)
The redirect scheme `com.receiptiq://login-callback/` is already set up in:
- `android/app/src/main/AndroidManifest.xml` (intent filter)
- `signInWithOAuth(redirectTo: 'com.receiptiq://login-callback/')`

In Supabase → Authentication → **URL Configuration** → **Redirect URLs**, add:
```
com.receiptiq://login-callback/
```

### 8e. Phone SMS provider (Twilio)
1. Create a free [Twilio](https://www.twilio.com) account.
2. Get a phone number and note: Account SID, Auth Token, phone number.
3. In Supabase → Authentication → Phone → enter those credentials.
4. Enable **SMS OTP** (not WhatsApp).

---

## 9. Monetisation / payments setup

### 9a. RevenueCat (Google Play in-app purchases)
1. Sign up at https://app.revenuecat.com — create a project, select **Google Play**.
2. Connect to Google Play Console and create two subscriptions:
   - Product ID: `receiptiq_starter_monthly` — price ~$1.99 / month
   - Product ID: `receiptiq_pro_monthly` — price ~$7.99 / month
3. In RevenueCat → **Entitlements**, create `starter` and `pro`.
   Attach the matching products to each entitlement.
4. Copy the **Android public API key** from RevenueCat → **API Keys**.
5. Add it to your `.env`:
   ```
   REVENUECAT_GOOGLE_KEY=appl_XXXXXXXXXXXXXXXXXXXX
   ```

### 9b. Supabase Edge Function secrets (never in .env or app binary)
Deploy the Edge Functions in `supabase/functions/payments/` and set these
secrets in the Supabase dashboard → **Edge Functions** → **Manage secrets**:

| Secret | Where to get it |
|--------|----------------|
| `DARAJA_CONSUMER_KEY` | Safaricom Developer Portal → app credentials |
| `DARAJA_CONSUMER_SECRET` | same |
| `DARAJA_SHORTCODE` | your M-Pesa PayBill / Till number |
| `DARAJA_PASSKEY` | Safaricom sandbox/production passkey |
| `DARAJA_CALLBACK_URL` | your Supabase function URL: `https://<project>.supabase.co/functions/v1/payments-mpesa-callback` |
| `PESAPAL_CONSUMER_KEY` | Pesapal merchant dashboard |
| `PESAPAL_CONSUMER_SECRET` | same |
| `PESAPAL_IPN_URL` | your Supabase function URL: `https://<project>.supabase.co/functions/v1/payments-pesapal-ipn` |
| | same redirect URL as above |

### 9c. Deploy Edge Functions
```bash
supabase functions deploy payments-initiate-stk payments-mpesa-callback payments-check-stk payments-mpesa-renew payments-initiate-pesapal payments-pesapal-ipn scan-ocr scan-extract scan-monthly-review --project-ref <project-ref> --use-api
```

### 9d. Set up the M-Pesa auto-renewal cron
In Supabase → **Database** → **Extensions**, enable **pg_cron**. Then run:
```sql
select cron.schedule(
  'mpesa-renew-daily',
  '0 7 * * *',  -- 7 AM UTC daily
  $$
    select net.http_post(
      url := 'https://<project>.supabase.co/functions/v1/payments-mpesa-renew',
      headers := '{"Authorization":"Bearer <SERVICE_ROLE_KEY>"}'::jsonb
    );
  $$
);
```

### 9e. Safaricom Daraja production approval
STK Push requires Safaricom to approve your production shortcode. This takes
**2–4 weeks**. Use sandbox (`api.safaricom.co.ke/sandbox`) during development.
Switch to production URLs (`api.safaricom.co.ke`) after approval.

> **Tip:** Flutterwave and Pesapal have instant sandbox access — you can test
> those payment flows immediately without waiting for Daraja approval.
