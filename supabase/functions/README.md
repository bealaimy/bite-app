# Server-only features

Receipt OCR, audio transcription, email invitations, and any AI key must run in Supabase Edge Functions—not in the Expo client.

Use this execution flow:

1. The app creates an expense and uploads private media.
2. The app calls an authenticated Edge Function with the `expense_id`.
3. The function uses the caller JWT to confirm the caller owns the expense or is that family's admin.
4. The function fetches the private object using its server-only service role key, sends the bytes to the chosen OCR/transcription provider, validates its result, and updates only permitted draft fields.
5. The app shows the extracted merchant, amount, date, and category for confirmation before final save.

Never return permanent media URLs or put `SUPABASE_SERVICE_ROLE_KEY`, OCR keys, or AI keys in the app bundle.
