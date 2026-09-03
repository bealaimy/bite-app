export type Room = { id: string; code: string; area: string; radius_km: number; swipe_deadline: string }
export type Swipe = { place_id: string; vote: 'no' | 'yes' | 'super' }
export type Restaurant = { place_id: string; name: string; rating: number; vicinity: string; ratings: number }
// Legacy types retained while the original unused Family Ledger components remain in the workspace.
export type Role = 'admin' | 'member'
export type Category = { id: string; name: string; color: string; is_default: boolean }
export type Expense = { id: string; amount_cents: number; merchant: string; notes: string | null; spent_at: string; receipt_path: string | null; audio_path: string | null; category: { name: string; color: string } | null; profile: { display_name: string } | null }
