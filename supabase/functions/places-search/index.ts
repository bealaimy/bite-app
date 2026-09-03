// Deploy with: supabase functions deploy places-search --no-verify-jwt
// Store Google API key as: supabase secrets set GOOGLE_MAPS_API_KEY=...
// The client never receives this key.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
const headers = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type', 'Content-Type':'application/json' }
Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok',{headers})
  const auth=req.headers.get('Authorization')||''; const sb=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:auth}}})
  const {data:{user}}=await sb.auth.getUser(); if(!user) return new Response(JSON.stringify({error:'Unauthorized'}),{status:401,headers})
  const {latitude,longitude,radiusMeters=3000}=await req.json(); if(!Number.isFinite(latitude)||!Number.isFinite(longitude)||radiusMeters>50000) return new Response(JSON.stringify({error:'Invalid location'}),{status:400,headers})
  const url='https://maps.googleapis.com/maps/api/place/nearbysearch/json?'+new URLSearchParams({location:`${latitude},${longitude}`,radius:String(radiusMeters),type:'restaurant',key:Deno.env.get('GOOGLE_MAPS_API_KEY')!})
  const result=await fetch(url); const body=await result.json();
  return new Response(JSON.stringify({results:(body.results||[]).map((p:any)=>({place_id:p.place_id,name:p.name,rating:p.rating,user_ratings_total:p.user_ratings_total,vicinity:p.vicinity,types:p.types}))}),{headers})
})
