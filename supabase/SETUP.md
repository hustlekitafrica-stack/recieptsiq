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

## Security note (for production later)
Calling Google Vision / OpenAI directly from the app exposes those keys in the
app binary. That's fine for a private dev build. Before public launch, move
those calls into a **Supabase Edge Function** so the keys live on the server.
