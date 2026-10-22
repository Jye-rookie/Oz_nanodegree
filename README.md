# Oz_nanodegree

오즈 나노디그리 과제 모음입니다.

## diabetes-readmission-dashboard: 당뇨 환자 30일 내 재입원 케이스 탐색기

임상연구자가 후향적으로 재입원 위험요인을 살펴보는 인터랙티브 대시보드입니다. 필터로 환자군을 좁히고 위험요인별 재입원률, 이전 입원 횟수 x 입원일수 히트맵, 개별 입원 케이스까지 탐색할 수 있습니다.

- 데이터: [UCI Diabetes 130-US Hospitals for Years 1999–2008](https://archive.ics.uci.edu/dataset/296) (입원 101,766건, 환자 71,518명, 비식별 공개 데이터)
- 재입원 정의: 퇴원 후 30일 내 재입원(`readmitted = <30`), 전체 11,357건(약 11.2%)
- 디자인: MongoDB LeafyGreen 디자인 시스템 기준 (라이트·다크 모드)

### 폴더 구조

```
diabetes-readmission-dashboard/
├─ index.html          대시보드 본체 (데이터 내장, 브라우저에서 바로 열기)
├─ PROMPT.md           같은 결과를 다시 만드는 재현 프롬프트
├─ REPRO_PROMPT_20261022.md   제작·스타일·배포·결과 요약까지 담은 상세 재현 프롬프트(2026-10-22)
├─ data/sample_5rows.csv   대시보드에 쓴 원본 데이터 5행 샘플
├─ dynamic/index.html      Supabase(Postgres)에 연결된 동적 버전
├─ supabase/               DB 마이그레이션(테이블, 읽기 전용 정책, 조회 함수)
└─ scripts/prep_data.py    UCI 원본을 내려받아 대시보드용 컬럼 JSON으로 변환
```

### 실행

`diabetes-readmission-dashboard/index.html` 파일을 브라우저로 엽니다. 서버나 설치는 필요 없습니다. 글꼴 일부(Source Code Pro)는 인터넷 연결이 있을 때 불러옵니다.

### 동적 버전 (Supabase 연동)

`diabetes-readmission-dashboard/dynamic/index.html`은 같은 화면이지만 필터를 바꿀 때마다 Supabase에서 집계를 새로 조회합니다. 정적 버전(`index.html`)은 그대로 두었습니다.

- 데이터: `public.encounters` 테이블(입원 101,766건). 익명 사용자는 조회만 가능하고 쓰기 권한은 없습니다.
- 집계: DB 함수 `dashboard_stats`, `case_list`, `patient_history`를 REST(RPC)로 호출합니다.
- 화면 코드에는 공개용(publishable) 키만 들어 있습니다. `service_role`·`secret` 키와 DB 비밀번호는 저장소에 없습니다.
- 인터넷 연결이 필요합니다. 무료 프로젝트는 오래 사용하지 않으면 일시 중지될 수 있어, 그때는 Supabase 대시보드에서 프로젝트를 재개해야 합니다.

직접 구성하려면 Supabase 프로젝트를 만들고 아래 순서로 진행합니다.

```bash
cd diabetes-readmission-dashboard
npx supabase login
npx supabase link --project-ref <프로젝트 ref>
npx supabase db push                       # 스키마와 조회 함수 적용
python3 scripts/prep_data.py build         # build/encounters.csv 생성
# build/encounters.csv 를 Supabase 대시보드의 Table Editor에서 public.encounters 로 가져오기
```

가져온 뒤 입원 101,766건, 환자 71,518명, `rd = 2` 11,357건인지 확인합니다.

### 데이터 다시 만들기

```bash
python3 diabetes-readmission-dashboard/scripts/prep_data.py build
```

UCI에서 zip(약 3MB)을 내려받아 `build/cols.json`을 만들고 건수를 출력합니다. 정상이라면 입원 101,766건, 환자 71,518명, 30일 내 재입원 11,357건이 나옵니다.

### 해석할 때 주의할 점

- 위험요인과 재입원의 연관성만 보여 주며 인과관계를 뜻하지 않습니다.
- 사망·호스피스 퇴원(2,423건)은 재입원이 불가능해 재입원률을 낮춥니다. 화면의 옵션으로 제외할 수 있습니다.
- 원본에 날짜가 없어 같은 환자의 입원 순서는 `encounter_id` 순서로 간주했습니다.
- 1999–2008년 미국 병원 데이터라 현재 한국 진료 환경에 그대로 적용할 수 없습니다.
