// Deploy: supabase functions deploy places-search
// Secret: supabase secrets set GOOGLE_MAPS_API_KEY=your-restricted-key
// Enable both Geocoding API and Places API in the Google Cloud project.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type', 'Content-Type':'application/json' }
Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok',{headers:cors})
  const auth = req.headers.get('Authorization') || ''
  const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global:{headers:{Authorization:auth}} })
  const { data:{user} } = await sb.auth.getUser(); if (!user) return json({error:'Unauthorized'},401)
  const { roomId } = await req.json(); if (typeof roomId !== 'string') return json({error:'Invalid room'},400)
  // RLS guarantees only a room member can spend this room's Places lookup.
  const { data:room, error } = await sb.from('food_rooms').select('area,radius_km').eq('id',roomId).single()
  if (error || !room) return json({error:'Room not found'},404)
  const key = Deno.env.get('GOOGLE_MAPS_API_KEY'); if (!key) return json({error:'Places search is not configured'},503)
  const geo = await fetch('https://maps.googleapis.com/maps/api/geocode/json?'+new URLSearchParams({address:room.area,key}))
  const geocoded = await geo.json(); const location = geocoded.results?.[0]?.geometry?.location
  if (!location) return json({error:'Area could not be located'},422)
  const radius = String(Math.min(Math.max(Number(room.radius_km) * 1000, 500), 50000))
  const nearby = await fetch('https://maps.googleapis.com/maps/api/place/nearbysearch/json?'+new URLSearchParams({location:`${location.lat},${location.lng}`,radius,type:'restaurant',key}))
  const body = await nearby.json(); if (body.status !== 'OK' && body.status !== 'ZERO_RESULTS') return json({error:'Google Places search failed'},502)
  return json({results:(body.results||[]).map((p:any)=>({place_id:p.place_id,name:p.name,rating:p.rating||0,user_ratings_total:p.user_ratings_total||0,vicinity:p.vicinity||room.area,types:p.types||[]}))})
})
function json(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:cors})}
