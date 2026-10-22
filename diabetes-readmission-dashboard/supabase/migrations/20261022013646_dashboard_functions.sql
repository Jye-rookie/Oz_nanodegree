-- 대시보드가 호출하는 조회 함수(RPC). 필터는 jsonb 하나로 받는다.
-- 필터 예: {"age":[6,7],"sex":[0],"adm":[],"dis":[],"dg":[4],"exclude_dead":true}
-- 빈 배열이나 없는 키는 "전체"를 뜻한다. 함수는 호출자 권한(security invoker)으로 실행되어 RLS가 적용된다.

create function public.enc_filtered(f jsonb default '{}'::jsonb)
returns setof public.encounters
language sql stable
set search_path = public
as $$
  select e.* from public.encounters e
  where (coalesce(jsonb_array_length(f->'age'),0) = 0 or f->'age' @> to_jsonb(e.age))
    and (coalesce(jsonb_array_length(f->'sex'),0) = 0 or f->'sex' @> to_jsonb(e.sex))
    and (coalesce(jsonb_array_length(f->'adm'),0) = 0 or f->'adm' @> to_jsonb(e.adm))
    and (coalesce(jsonb_array_length(f->'dis'),0) = 0 or f->'dis' @> to_jsonb(e.dis))
    and (coalesce(jsonb_array_length(f->'dg'),0)  = 0 or f->'dg'  @> to_jsonb(e.dg))
    and (coalesce((f->>'exclude_dead')::boolean, false) = false or e.dis <> 4)
$$;

-- KPI, 요인별 구간 집계(factors), 이전 입원 x 입원일수 히트맵(heat)을 한 번에 반환한다.
-- 구간 규칙은 화면(index.html)의 정적 버전과 같다.
create function public.dashboard_stats(f jsonb default '{}'::jsonb)
returns jsonb
language sql stable
set search_path = public
as $$
  with base as (select * from public.enc_filtered(f)),
  kpi as (
    select count(*)::int n,
           count(*) filter (where rd = 2)::int k,
           count(distinct pt)::int pts,
           coalesce(sum(los), 0)::int los_sum
    from base
  ),
  factors as (
    select v.factor, v.b, count(*)::int n, count(*) filter (where base.rd = 2)::int k
    from base
    cross join lateral (values
      ('ninp', least(base.ninp, 3)),
      ('nemr', least(base.nemr, 2)),
      ('nout', least(base.nout, 2)),
      ('los',  case when base.los <= 3 then 0 when base.los <= 7 then 1 else 2 end),
      ('meds', case when base.meds <= 10 then 0 when base.meds <= 20 then 1 else 2 end),
      ('labs', case when base.labs < 30 then 0 when base.labs < 50 then 1 else 2 end),
      ('proc', least(base.proc, 2)),
      ('a1c',  base.a1c::int),
      ('ins',  base.ins::int),
      ('chg',  base.chg::int),
      ('ndx',  case when base.ndx <= 5 then 0 when base.ndx <= 8 then 1 else 2 end),
      ('dg',   base.dg::int),
      ('dis',  base.dis::int),
      ('src',  base.src::int)
    ) as v(factor, b)
    group by v.factor, v.b
  ),
  heat as (
    select least(ninp, 3) a,
           case when los <= 3 then 0 when los <= 7 then 1 else 2 end b,
           count(*)::int n, count(*) filter (where rd = 2)::int k
    from base group by 1, 2
  )
  select jsonb_build_object(
    'kpi', (select to_jsonb(kpi) from kpi),
    'factors', coalesce((select jsonb_object_agg(factor, rows) from (
        select factor, jsonb_agg(jsonb_build_object('b', b, 'n', n, 'k', k) order by b) rows
        from factors group by factor) s), '{}'::jsonb),
    'heat', coalesce((select jsonb_agg(jsonb_build_object('a', a, 'b', b, 'n', n, 'k', k)) from heat), '[]'::jsonb),
    'dead', (select count(*)::int from base where dis = 4)
  )
$$;

-- 케이스 목록: 정렬 키는 화이트리스트만 허용한다.
create function public.case_list(
  f jsonb default '{}'::jsonb,
  sort_key text default 'ninp',
  only_readmit boolean default false,
  lim integer default 40)
returns jsonb
language sql stable
set search_path = public
as $$
  with base as (
    select * from public.enc_filtered(f) where (not only_readmit) or rd = 2
  ),
  top as (
    select * from base
    order by
      case sort_key when 'los' then los when 'meds' then meds when 'nemr' then nemr else ninp end desc,
      los desc, enc
    limit least(greatest(lim, 1), 200)
  )
  select jsonb_build_object(
    'total', (select count(*)::int from base),
    'rows', coalesce((select jsonb_agg(to_jsonb(top)) from top), '[]'::jsonb)
  )
$$;

-- 같은 환자의 입원 기록(encounter_id 순).
create function public.patient_history(p bigint)
returns jsonb
language sql stable
set search_path = public
as $$
  select coalesce(jsonb_agg(to_jsonb(e) order by e.enc), '[]'::jsonb)
  from public.encounters e where e.pt = p
$$;

grant execute on function public.enc_filtered(jsonb), public.dashboard_stats(jsonb),
  public.case_list(jsonb, text, boolean, integer), public.patient_history(bigint) to anon, authenticated;
