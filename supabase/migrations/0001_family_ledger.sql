-- Family Ledger: run this entire file in Supabase SQL Editor before using the app.
-- All application tables and private media are protected by Row Level Security.

create extension if not exists pgcrypto;

create type public.family_role as enum ('admin', 'member');

create table public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 80),
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Family member' check (char_length(trim(display_name)) between 1 and 80),
  family_id uuid references public.families(id) on delete set null,
  role public.family_role not null default 'member',
  created_at timestamptz not null default now()
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 50),
  color text not null default '#176B5B' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  unique(family_id, name)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete restrict,
  category_id uuid not null references public.categories(id) on delete restrict,
  merchant text not null check (char_length(trim(merchant)) between 1 and 160),
  amount_cents integer not null check (amount_cents > 0 and amount_cents <= 100000000),
  notes text check (notes is null or char_length(notes) <= 2000),
  spent_at timestamptz not null default now(),
  receipt_path text unique,
  audio_path text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index expenses_family_spent_at_idx on public.expenses(family_id, spent_at desc);
create index expenses_user_spent_at_idx on public.expenses(user_id, spent_at desc);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, display_name)
  values (new.id, coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(new.email, '@', 1)));
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

-- First user in a workspace becomes its admin. This is the only route that assigns admin.
create or replace function public.create_family(family_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare new_family uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if exists (select 1 from public.profiles where id = auth.uid() and family_id is not null) then raise exception 'You already belong to a family workspace'; end if;
  insert into public.families(name) values (trim(family_name)) returning id into new_family;
  update public.profiles set family_id = new_family, role = 'admin' where id = auth.uid();
  insert into public.categories(family_id, name, color, is_default) values
    (new_family, 'Groceries', '#3D8B72', true), (new_family, 'Dining', '#E88542', true),
    (new_family, 'Transport', '#5379B8', true), (new_family, 'Bills', '#A66FC4', true),
    (new_family, 'Health', '#D85858', true), (new_family, 'Other', '#82938E', true);
  return new_family;
end;
$$;

create or replace function public.is_family_admin(target_family uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and family_id = target_family and role = 'admin');
$$;

-- Stops forged category IDs and attachment paths that do not match the expense owner.
create or replace function public.validate_expense()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.categories where id = new.category_id and family_id = new.family_id) then raise exception 'Category must belong to this family'; end if;
  if new.receipt_path is not null and new.receipt_path <> new.user_id::text || '/' || new.id::text || '/receipt.jpg' then raise exception 'Invalid receipt path'; end if;
  if new.audio_path is not null and new.audio_path <> new.user_id::text || '/' || new.id::text || '/voice-note.m4a' then raise exception 'Invalid audio path'; end if;
  new.updated_at = now(); return new;
end;
$$;
create trigger validate_expense_before_write before insert or update on public.expenses for each row execute procedure public.validate_expense();

alter table public.families enable row level security;
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.expenses enable row level security;

create policy "members view their family" on public.families for select to authenticated using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.family_id = families.id));
create policy "users view profile or admins view family profiles" on public.profiles for select to authenticated using (id = auth.uid() or public.is_family_admin(family_id));
create policy "users update only their display name" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid() and family_id = (select family_id from public.profiles where id = auth.uid()) and role = (select role from public.profiles where id = auth.uid()));

create policy "members read categories" on public.categories for select to authenticated using (exists (select 1 from public.profiles where id = auth.uid() and family_id = categories.family_id));
create policy "admins manage categories" on public.categories for all to authenticated using (public.is_family_admin(family_id)) with check (public.is_family_admin(family_id));

create policy "members read their own, admins read family expenses" on public.expenses for select to authenticated using (user_id = auth.uid() or public.is_family_admin(family_id));
create policy "members add only their own expense" on public.expenses for insert to authenticated with check (user_id = auth.uid() and exists (select 1 from public.profiles where id = auth.uid() and family_id = expenses.family_id));
create policy "owners update own; admins update family" on public.expenses for update to authenticated using (user_id = auth.uid() or public.is_family_admin(family_id)) with check ((user_id = auth.uid() and family_id = (select family_id from public.profiles where id = auth.uid())) or public.is_family_admin(family_id));
create policy "owners delete own; admins delete family" on public.expenses for delete to authenticated using (user_id = auth.uid() or public.is_family_admin(family_id));

-- Never create this bucket as public. Files are readable only by the owner or an admin of the expense's family.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('expense-media', 'expense-media', false, 10485760, array['image/jpeg', 'image/png', 'image/heic', 'audio/mp4', 'audio/m4a'])
on conflict (id) do update set public = false;

create policy "members upload only to their folder" on storage.objects for insert to authenticated with check (
  bucket_id = 'expense-media' and (storage.foldername(name))[1] = auth.uid()::text and exists (select 1 from public.profiles where id = auth.uid() and family_id is not null)
);
create policy "owner or relevant admin reads private media" on storage.objects for select to authenticated using (
  bucket_id = 'expense-media' and ((storage.foldername(name))[1] = auth.uid()::text or exists (select 1 from public.expenses e where (e.receipt_path = name or e.audio_path = name) and public.is_family_admin(e.family_id)))
);
create policy "owner removes their unneeded media; admin removes family media" on storage.objects for delete to authenticated using (
  bucket_id = 'expense-media' and ((storage.foldername(name))[1] = auth.uid()::text or exists (select 1 from public.expenses e where (e.receipt_path = name or e.audio_path = name) and public.is_family_admin(e.family_id)))
);

revoke all on function public.is_family_admin(uuid) from public;
grant execute on function public.create_family(text) to authenticated;
grant execute on function public.is_family_admin(uuid) to authenticated;
