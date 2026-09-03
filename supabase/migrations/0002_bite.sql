-- Bite: apply after 0001_family_ledger.sql. Google OAuth must be enabled in Supabase Auth.
create extension if not exists pgcrypto;

create table public.food_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9]{6}$'),
  host_id uuid not null references auth.users(id) on delete cascade,
  area text not null check (char_length(trim(area)) between 2 and 180),
  radius_km numeric(4,1) not null check (radius_km between 0.5 and 50),
  swipe_deadline timestamptz not null,
  status text not null default 'swiping' check (status in ('swiping','decided','visited','closed')),
  created_at timestamptz not null default now()
);
create table public.food_room_members (
  room_id uuid not null references public.food_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(), primary key(room_id,user_id)
);
create table public.room_swipes (
  room_id uuid not null references public.food_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  place_id text not null, place_name text not null check(char_length(place_name) <= 180),
  place_rating numeric(2,1) check(place_rating between 0 and 5),
  vote text not null check(vote in ('no','yes','super')),
  created_at timestamptz not null default now(), primary key(room_id,user_id,place_id)
);
create table public.room_visits (
  id uuid primary key default gen_random_uuid(), room_id uuid not null unique references public.food_rooms(id) on delete cascade,
  place_id text not null, place_name text not null, visited_at timestamptz not null default now()
);
create table public.place_reviews (
  id uuid primary key default gen_random_uuid(), visit_id uuid not null references public.room_visits(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  food smallint not null check(food between 1 and 5), vibe smallint not null check(vibe between 1 and 5),
  service smallint not null check(service between 1 and 5), value smallint not null check(value between 1 and 5),
  comment text check(char_length(comment) <= 1200), created_at timestamptz not null default now(), unique(visit_id,user_id)
);
create index room_swipes_room_place_idx on public.room_swipes(room_id,place_id);
create index room_visits_place_idx on public.room_visits(place_id,visited_at desc);

create or replace function public.create_food_room(p_area text,p_radius_km numeric,p_deadline timestamptz)
returns public.food_rooms language plpgsql security definer set search_path=public as $$
declare r public.food_rooms;
begin
 if auth.uid() is null then raise exception 'Not authenticated'; end if;
 if p_deadline <= now() or p_deadline > now() + interval '24 hours' then raise exception 'Deadline must be within the next 24 hours'; end if;
 insert into food_rooms(code,host_id,area,radius_km,swipe_deadline) values (upper(substr(encode(gen_random_bytes(6),'hex'),1,6)),auth.uid(),trim(p_area),p_radius_km,p_deadline) returning * into r;
 insert into food_room_members(room_id,user_id) values(r.id,auth.uid()); return r;
end $$;
create or replace function public.join_food_room(p_code text)
returns public.food_rooms language plpgsql security definer set search_path=public as $$
declare r public.food_rooms;
begin
 if auth.uid() is null then raise exception 'Not authenticated'; end if;
 select * into r from food_rooms where code=upper(trim(p_code));
 if r.id is null then raise exception 'Room not found'; end if;
 if r.status <> 'swiping' or r.swipe_deadline < now() then raise exception 'This room is no longer accepting swipes'; end if;
 insert into food_room_members(room_id,user_id) values(r.id,auth.uid()) on conflict do nothing; return r;
end $$;
create or replace function public.is_room_member(p_room uuid) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from food_room_members where room_id=p_room and user_id=auth.uid()) $$;

alter table public.food_rooms enable row level security; alter table public.food_room_members enable row level security;
alter table public.room_swipes enable row level security; alter table public.room_visits enable row level security; alter table public.place_reviews enable row level security;
create policy "members read rooms" on public.food_rooms for select to authenticated using(public.is_room_member(id));
create policy "members read membership" on public.food_room_members for select to authenticated using(public.is_room_member(room_id));
create policy "members read aggregate inputs" on public.room_swipes for select to authenticated using(public.is_room_member(room_id));
create policy "members write own current swipe" on public.room_swipes for insert to authenticated with check(user_id=auth.uid() and public.is_room_member(room_id) and exists(select 1 from food_rooms where id=room_id and status='swiping' and swipe_deadline>now()));
create policy "members update own current swipe" on public.room_swipes for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid() and public.is_room_member(room_id));
create policy "members read visits" on public.room_visits for select to authenticated using(public.is_room_member(room_id));
-- Reviews are community-visible, but only verified room participants can publish one.
create policy "community reads reviews" on public.place_reviews for select to authenticated using(true);
create policy "visitors publish one review" on public.place_reviews for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from room_visits v where v.id=visit_id and public.is_room_member(v.room_id)));
grant execute on function public.create_food_room(text,numeric,timestamptz), public.join_food_room(text), public.is_room_member(uuid) to authenticated;
