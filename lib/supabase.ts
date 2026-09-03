import 'react-native-url-polyfill/auto'
import 'react-native-get-random-values'
import * as SecureStore from 'expo-secure-store'
import { Platform } from 'react-native'
import { createClient } from '@supabase/supabase-js'

// Preview mode lets the interface run locally without credentials. Network actions
// will fail until real values are supplied in .env; no production data is exposed.
export const isSupabaseConfigured = Boolean(process.env.EXPO_PUBLIC_SUPABASE_URL && process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY)
const url = process.env.EXPO_PUBLIC_SUPABASE_URL || 'https://preview.supabase.co'
const key = process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY || 'preview-anon-key'

const nativeStorage = {
  getItem: (key: string) => SecureStore.getItemAsync(key),
  setItem: (key: string, value: string) => SecureStore.setItemAsync(key, value),
  removeItem: (key: string) => SecureStore.deleteItemAsync(key),
}

const webStorage = {
  getItem: async (key: string) => globalThis.localStorage?.getItem(key) ?? null,
  setItem: async (key: string, value: string) => { globalThis.localStorage?.setItem(key, value) },
  removeItem: async (key: string) => { globalThis.localStorage?.removeItem(key) },
}

export const supabase = createClient(url, key, {
  auth: { storage: Platform.OS === 'web' ? webStorage : nativeStorage, autoRefreshToken: true, persistSession: true, detectSessionInUrl: Platform.OS === 'web' },
})
