-- Base partagée de l'outil « Projets PolyFinances » (Supabase).
-- Une ligne par projet, et une ligne par personne dans chaque projet : deux personnes qui modifient
-- en même temps des choses différentes (même dans le même projet) ne s'écrasent pas.
-- Tout le monde qui a la page peut lire et modifier (pas de compte) : c'est voulu.

create table public.projets (
  id     text primary key check (char_length(id) <= 40),
  name   text not null check (char_length(name) <= 120),
  season text not null check (season in ('automne', 'hiver', 'annuel')),
  o      double precision not null default 0          -- ordre d'affichage
);

create table public.affectations (
  id       text primary key,                          -- '<projet>|<personne>'
  projet   text not null references public.projets(id) on delete cascade,
  personne text not null check (char_length(personne) <= 20),
  r        text not null check (r in ('chef', 'del', 'mem')),
  pole     text check (char_length(pole) <= 20),      -- pôle représenté, pour un délégué
  o        double precision not null default 0,       -- ordre d'arrivée dans le projet
  unique (projet, personne),
  check (id = projet || '|' || personne)
);
create index on public.affectations (projet);

-- Accès public (clé publishable) : lecture et écriture pour tous.
alter table public.projets enable row level security;
alter table public.affectations enable row level security;
create policy "lecture"     on public.projets for select to anon using (true);
create policy "ajout"       on public.projets for insert to anon with check (true);
create policy "modif"       on public.projets for update to anon using (true) with check (true);
create policy "suppression" on public.projets for delete to anon using (true);
create policy "lecture"     on public.affectations for select to anon using (true);
create policy "ajout"       on public.affectations for insert to anon with check (true);
create policy "modif"       on public.affectations for update to anon using (true) with check (true);
create policy "suppression" on public.affectations for delete to anon using (true);
grant select, insert, update, delete on public.projets, public.affectations to anon;

-- Modifs envoyées en direct à toutes les pages ouvertes.
alter publication supabase_realtime add table public.projets, public.affectations;

-- Journal de toutes les modifs (invisible pour la page) : permet de tout récupérer si quelqu'un efface tout.
create table public.journal (
  n     bigint generated always as identity primary key,
  at    timestamptz not null default now(),
  tbl   text not null,
  op    text not null,
  id    text not null,
  avant jsonb,
  apres jsonb
);
alter table public.journal enable row level security;   -- aucune politique : inaccessible avec la clé publique
revoke all on public.journal from anon, authenticated;

create function public.journaliser() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.journal (tbl, op, id, avant, apres)
  values (tg_table_name, tg_op,
          case when tg_op = 'DELETE' then old.id else new.id end,
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return null;
end $$;
create trigger journal after insert or update or delete on public.projets
  for each row execute function public.journaliser();
create trigger journal after insert or update or delete on public.affectations
  for each row execute function public.journaliser();
