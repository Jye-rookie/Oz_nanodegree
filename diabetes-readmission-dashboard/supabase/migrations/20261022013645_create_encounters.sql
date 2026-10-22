-- UCI Diabetes 130-US Hospitals(1999-2008): 입원(encounter) 1건 = 1행.
-- 컬럼은 scripts/prep_data.py 의 코드 규칙과 같다(라벨은 화면에서 붙인다).
create table public.encounters (
  enc  bigint   primary key,   -- encounter_id
  pt   bigint   not null,      -- patient_nbr
  age  smallint not null,      -- 0~9 (10년 구간)
  sex  smallint not null,      -- 0 여, 1 남, 2 미상
  race smallint not null,      -- 0~4, 5 미상
  adm  smallint not null,      -- 입원 유형 0~3
  src  smallint not null,      -- 입원 경로 0~3
  dis  smallint not null,      -- 퇴원처 0~5 (4 = 사망·호스피스)
  los  smallint not null,      -- 입원일수
  labs smallint not null,
  proc smallint not null,
  meds smallint not null,
  nout smallint not null,      -- 직전 1년 외래
  nemr smallint not null,      -- 직전 1년 응급실
  ninp smallint not null,      -- 직전 1년 입원
  dg   smallint not null,      -- 주진단 질환군 0~8
  ndx  smallint not null,
  a1c  smallint not null,      -- 0 미검사, 1 정상, 2 >7, 3 >8
  ins  smallint not null,      -- 0 미사용, 1 유지, 2 감량, 3 증량
  chg  smallint not null,
  dmed smallint not null,
  rd   smallint not null,      -- 0 NO, 1 >30, 2 <30(30일 내 재입원)
  icd  text
);

create index encounters_pt_idx  on public.encounters (pt);
create index encounters_rd_idx  on public.encounters (rd);
create index encounters_age_idx on public.encounters (age);
create index encounters_dis_idx on public.encounters (dis);
create index encounters_dg_idx  on public.encounters (dg);

-- 읽기 전용 공개: 익명 사용자는 조회만 가능하고 쓰기 정책은 만들지 않는다.
alter table public.encounters enable row level security;
create policy "encounters are readable by everyone"
  on public.encounters for select
  to anon, authenticated
  using (true);
-- 쓰기 권한은 아예 회수하고 조회만 허용한다(RLS와 이중으로 막는다).
revoke all on public.encounters from anon, authenticated;
grant select on public.encounters to anon, authenticated;
