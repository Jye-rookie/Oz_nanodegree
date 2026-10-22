# 2026-10-22 작업 재현 프롬프트: 당뇨 재입원 케이스 탐색기 (제작, 스타일, GitHub Pages 배포, 결과 요약)

이 문서 하나로 같은 대시보드를 처음부터 만들고 GitHub Pages에 배포해 결과를 요약할 수 있습니다. 아래 "프롬프트" 블록을 Claude Code에 그대로 붙여넣으세요. 블록 앞뒤 글은 사람이 읽는 설명입니다.

## 이 작업이 만드는 것

| 항목 | 내용 |
|---|---|
| 산출물 | 데이터가 내장된 단일 `index.html`(약 6.8MB), 샘플 CSV, 데이터 변환 스크립트, README, 루트 이동 페이지 |
| 데이터 | UCI "Diabetes 130-US Hospitals for Years 1999–2008" (입원 101,766건, 환자 71,518명, 비식별 공개 데이터) |
| 독자 | 후향적 분석을 하는 임상연구자 |
| 핵심 질문 | 어떤 입원이 30일 안에 재입원으로 이어지는가 |
| 디자인 | MongoDB LeafyGreen 디자인 시스템(https://www.mongodb.design) 기준, 라이트·다크 모드 |
| 배포 | GitHub 저장소 main 브랜치 + GitHub Pages(Deploy from a branch, main, / root) |
| 동적 버전 | Supabase(Postgres) + 조회 함수(RPC). `dynamic/index.html`이 필터를 바꿀 때마다 DB에서 집계를 새로 조회 (아래 [L]) |

## 프롬프트

```text
당뇨 환자의 30일 내 재입원 위험요인을 임상연구자가 후향적으로 탐색하는 인터랙티브 대시보드를 단일 HTML 파일로 만들고, GitHub 저장소에 올려 GitHub Pages로 공개해줘. 모든 단계에서 아래 합의 사항을 따르고, 되돌리기 어려운 작업(다운로드, push, 저장소 설정 변경)은 실행 전에 나에게 확인받아줘.

[A. 진행 순서]
1. 데이터 내려받기와 확인  2. 인터뷰로 분석 기준 확정  3. 전처리  4. 대시보드 제작  5. 디자인 시스템 적용  6. 폴더 구조 제안 후 확인  7. 커밋과 push  8. Pages 활성화와 주소 확인  9. 루트 주소 이동 페이지 추가  10. 결과 요약  11. (이어서) Supabase 연동 동적 버전([L])

[B. 데이터]
- 출처: https://archive.ics.uci.edu/static/public/296/diabetes+130-us+hospitals+for+years+1999-2008.zip (zip 약 3.2MB, 풀면 diabetic_data.csv 약 19MB와 IDS_mapping.csv)
- 내려받기 전에 출처, 파일명, 크기를 알리고 확인받는다. 별도 빈 폴더에 풀고, 그 폴더에서 스크립트를 실행하지 않는다.
- 내용을 먼저 확인한다: 101,766행, 환자 71,518명, readmitted 분포(NO 54,864 / >30 35,545 / <30 11,357), 결측(weight 97%, payer_code 40%, medical_specialty 49%, A1Cresult의 None 83%, max_glu_serum의 None 95%).
- weight, payer_code, medical_specialty, max_glu_serum은 쓰지 않는다.

[C. 인터뷰로 정할 값 (이미 합의된 답)]
- 사용자: 임상연구자(후향적 분석)   - 핵심 질문: 재입원 위험요인
- 재입원 정의: readmitted == "<30" 만 재입원. ">30"은 "30일 초과"로 따로 표시
- 사망·호스피스 퇴원(discharge_disposition_id 11, 13, 14, 19, 20, 21, 2,423건): 기본은 포함. 화면에 안내하고 "사망·호스피스 퇴원 제외" 토글 제공
- 위험요인 묶음: 이전 이용 이력, 치료·검사 (인구통계는 필터와 케이스 정보에만 사용)
- 주진단: ICD-9를 질환군으로 묶어서 표시
- 환자 개별 탐색: 집계 + 환자 목록 탐색
- 단위: 입원(encounter). 환자 수는 patient_nbr 고유 개수. 같은 환자의 순서는 encounter_id 오름차순을 시간 순서로 간주(원본에 날짜 없음)하고 이 가정을 화면에 밝힌다.

[D. 전처리: 컬럼 배열 JSON으로 변환 (Python 표준 라이브러리만 사용)]
키: enc, pt, age, sex, race, adm, src, dis, los, labs, proc, meds, nout, nemr, ninp, dg, ndx, a1c, ins, chg, dmed, rd, icd
- enc=encounter_id, pt=patient_nbr, icd=diag_1 원문, los=time_in_hospital, labs=num_lab_procedures, proc=num_procedures, meds=num_medications, nout=number_outpatient, nemr=number_emergency, ninp=number_inpatient(직전 1년), ndx=number_diagnoses
- age: 구간 인덱스 0~9 ([0-10) ... [90-100))
- sex: Female 0, Male 1, 그 외 2
- race: Caucasian 0, AfricanAmerican 1, Hispanic 2, Asian 3, Other 4, "?" 5(미상)
- adm(admission_type_id): 1→0 응급, 2→1 긴급, 3→2 선택, 나머지→3 기타
- src(admission_source_id): 1·2·3→0 의뢰, 4·5·6→1 타시설 전원, 7→2 응급실, 나머지→3 기타
- dis(discharge_disposition_id): 1→0 자택 / 6·8→1 자택+방문서비스 / 3·4·22·23·24→2 요양·재활시설 / 2·5·9·10·12·15·16·17·27·28·29·30→3 타병원·기관 전원 / 11·13·14·19·20·21→4 사망·호스피스 / 그 외→5 기타
- a1c: None 0(미검사), Norm 1, ">7" 2, ">8" 3
- ins(insulin): No 0, Steady 1, Down 2, Up 3
- chg: change=="Ch" 이면 1. dmed: diabetesMed=="Yes" 이면 1
- rd(readmitted): NO 0, ">30" 1, "<30" 2
- dg(diag_1 → 질환군): V·E로 시작하거나 결측→8 기타 / 250.xx→4 당뇨병 / 정수부 390–459·785→0 순환기계 / 460–519·786→1 호흡기계 / 520–579·787→2 소화기계 / 800–999→3 손상·중독 / 710–739→5 근골격계 / 580–629·788→6 비뇨생식계 / 140–239→7 신생물 / 나머지→8 기타
- 변환 결과가 입원 101,766건, 환자 71,518명, rd==2 가 11,357건인지 출력해 확인한다.

[E. 대시보드 구성 (위에서 아래 순서, 한국어 UI)]
0) 제목 "당뇨 환자 30일 내 재입원 케이스 탐색기" + 한 줄 설명(미국 130개 병원, 1999–2008, UCI 공개 데이터, 비식별)
1) 필터 카드(칩 다중 선택, 선택 없음 = 전체): 연령대(10년 단위 "0–10세"…"90–100세"), 성별(여/남), 입원 유형(응급/긴급/선택/기타), 퇴원처(6개), 주진단 질환군(9개). 옵션 칸에 "사망·호스피스 퇴원 제외" 토글 칩과 "필터 초기화" 버튼. 필터를 바꾸면 선택된 케이스를 해제한다.
2) KPI 카드 5개: ① 30일 내 재입원률(큰 숫자 40px, 95% 신뢰구간과 전체 평균 병기) ② 입원 건수 ③ 재입원 건수 ④ 환자 수 ⑤ 평균 입원일수
3) 안내 박스: 선택 조건이 300건 미만이면 "표본이 적어 신뢰구간과 함께 해석" 문구. 아니면 제외 옵션이 꺼져 있을 때 "선택한 입원 중 사망·호스피스 퇴원 N건은 재입원이 불가능해 재입원률을 낮춘다"는 문구, 켜져 있으면 "사망·호스피스 퇴원을 제외한 입원만 분석" 문구.
4) 섹션 "이전 이용 이력": 최근 1년 입원 횟수(0/1/2/3회 이상), 응급실 방문(0/1/2회 이상), 외래 방문(0/1/2회 이상)
5) 섹션 "치료·검사": 입원일수(1–3/4–7/8일 이상), 투약 수(10종 이하/11–20/21종 이상), 검사 수(30건 미만/30–49/50건 이상), 시술 수(0/1/2건 이상), HbA1c(미검사/정상/>7/>8), 인슐린(미사용/유지/감량/증량), 약물 변경(변경 없음/변경함), 진단 수(5개 이하/6–8/9개 이상)
6) 섹션 "진단·퇴원 비교": 주진단 질환군(9개: 순환기계, 호흡기계, 소화기계, 손상·중독, 당뇨병, 근골격계, 비뇨생식계, 신생물, 기타), 퇴원처(자택, 자택+방문서비스, 요양·재활시설, 타병원·기관 전원, 사망·호스피스, 기타), 입원 경로(의뢰, 타시설 전원, 응급실, 기타)
   위 4~6의 각 항목은 카드 1개이며 가로 막대 행들로 구성한다. 행은 3열 격자(라벨 96px / 막대 가변 / 값 52px): 라벨 아래에 건수 작은 글씨, 막대(높이 12px, 둥근 모서리, 회색 트랙), 막대 위에 선택 조건 평균 위치를 나타내는 세로선(2px, 트랙보다 위아래 3px 길게), 오른쪽에 재입원률(Source Code Pro, 소수 1자리 %). 막대 폭 = 재입원률 / (해당 카드 최대값과 평균 중 큰 값 x 1.15).
   막대 색: 기본 파랑, 건수 100 미만이면 회색(흐림), "건수 100 이상이면서 재입원률이 선택 조건 평균의 1.2배 이상"이면 빨강.
   툴팁(마우스 올리면): 항목명, 재입원률, 95% 신뢰구간, 재입원 건수/전체 건수, 평균 대비 배수, 건수 100 미만이면 "건수가 적어 해석 주의".
7) 카드 "이전 입원 횟수 × 입원일수별 재입원률": 행 4(0/1/2/3회 이상) × 열 3(1–3/4–7/8일 이상) 표. 셀에 재입원률과 건수, 셀 배경은 파랑을 CSS color-mix로 surface에 섞어 농도(0~50%)로 표현(농도 = 재입원률 / 건수 30 이상 셀의 최대 재입원률 × 50). 건수 30 미만 셀은 회색 배경에 불투명도 0.55. 셀 툴팁에 재입원 N / 전체 N건.
8) 섹션 "환자 케이스 목록": 왼쪽 카드(정렬 선택 [이전 입원 횟수 | 입원일수 | 투약 수 | 응급실 방문, 모두 내림차순, 동률은 입원일수 내림차순], "30일 내 재입원 케이스만" 토글 칩, "N건 중 상위 40건" 표시, 표: 입원 ID/연령/성별/주진단/입원일/투약/이전 입원/결과 태그). 결과 태그는 "재입원 없음"(흐린 글씨), "30일 초과"(회색 칩), "30일 내 재입원"(빨강, 굵게). 행은 클릭 또는 Enter/Space로 선택하고 선택 행은 배경을 달리한다.
   오른쪽 카드 "케이스 상세": 입원 ID, 환자 ID·연령·성별·인종, 결과 태그, 주진단(질환군+ICD 코드), 입원 유형/경로, 퇴원처, 입원일수, 검사/시술, 투약 수, 진단 수, HbA1c, 인슐린, 약물 변경, 최근 1년 입원/응급/외래, 그리고 "이 환자의 기록 N건" 표(같은 patient_nbr의 입원을 encounter_id 순으로: ID, 입원일수, 질환군, 결과). 다른 입원이 없으면 그렇게 안내. 선택 전에는 "목록에서 행을 선택하세요".
9) 하단 주석: 재입원 정의, 사망·호스피스 처리, 결측 안내(HbA1c 83%·혈당 95%), "위험요인과의 연관성이지 인과가 아님", encounter_id 순서 가정.

[F. 계산 규칙]
- 재입원률 = (rd==2 건수) / 건수. 모든 집계는 현재 필터로 실시간 재계산.
- 95% 신뢰구간(Wilson): p=k/n, z=1.96, d=1+z²/n, c=p+z²/(2n), m=z·sqrt(p(1-p)/n+z²/(4n²)), 구간=[(c-m)/d, (c+m)/d]
- 평균 입원일수 = 입원일수 합 / 입원 건수. 환자 수 = pt 고유 개수.
- 데이터는 컬럼 배열 JSON을 HTML에 `const C={...}`로 내장한다(외부 요청 없음). 레이아웃 폭: 최대 1200px 가운데 정렬, 섹션 간격 16px.

[G. 디자인: MongoDB LeafyGreen 디자인 시스템 (https://www.mongodb.design, Foundations > Palette, Typography)]
CSS 변수(라이트 기본값, 다크는 prefers-color-scheme과 [data-theme] 두 곳에서 재정의, body 배경 명시):
- 라이트: --bg #ffffff, --surface #ffffff, --ink #001e2b, --ink2 #3d4f58, --ink3 #5c6c75, --line #e8edeb, --line2 #c1c7c6, --grid #e8edeb, --acc(데이터 파랑) #016bf8, --warn(위험 빨강) #db3030, --green #00684a, --link #016bf8, --chip #e8edeb, --chip-on #00684a, --chip-on-ink #ffffff, --mute #c1c7c6
- 다크: --bg #001e2b, --surface #112733, --ink #e8edeb, --ink2 #c1c7c6, --ink3 #889397, --line #3d4f58, --line2 #5c6c75, --grid #1c2d38, --acc #0498ec, --warn #ff6960, --green #00ed64, --link #0498ec, --chip #1c2d38, --chip-on #00ed64, --chip-on-ink #001e2b, --mute #3d4f58
- 사이트가 텍스트로 공개한 값은 다크 역할표(#001E2B, #112733, #E8EDEB, #C1C7C6, #889397, #3D4F58, #0498EC)와 링크 파랑(#016BF8)이다. 라이트의 회색·초록·빨강은 LeafyGreen 팔레트 기억 기준이라 공식 값과 다를 수 있다.
- 서체: 제목(h1 28px, 섹션 제목 20px, 굵기 400)은 font-family "MongoDB Value Serif", Georgia, "Times New Roman", "Noto Serif KR", "Apple SD Gothic Neo", serif. 본문(14px, 줄 높이 20px)은 "Euclid Circular A", "Helvetica Neue", Helvetica, Arial, "Apple SD Gothic Neo", "Noto Sans KR", "Malgun Gothic", sans-serif. 숫자와 작은 수치는 "Source Code Pro"(Google Fonts에서 400/500/600 로드) + tabular-nums. Value Serif와 Euclid는 웹폰트로 불러올 수 없으므로 대체 서체로 표시된다.
- 형태: 카드 모서리 12px, 안쪽 여백 16×20px, 1px --line 테두리. 칩은 알약형(모서리 16px, 13px 글씨, 선택 시 --chip-on 배경). 버튼 모서리 6px, 테두리 --line2. 선택 상자는 --surface 배경과 --line2 테두리. 첫 KPI 카드는 위쪽에 4px 초록 선. 안내 박스는 파랑 10% 배경과 파랑 40% 테두리. 툴팁은 #001e2b 배경, #e8edeb 글자, #3d4f58 테두리, 모서리 6px. 빨강 태그의 글자는 #001e2b.
- 접근성: 글자 대비 4.5:1 이상, 키보드 포커스에 2px --link 외곽선, 표 행은 tabindex로 키보드 선택 가능. 색만으로 의미를 전하지 않는다(경고 막대는 값과 툴팁 문구가 함께 있다).
- 반응형: 900px 이하에서 KPI는 2열, 첫 카드는 전체 폭, 목록/상세는 1열. 위험요인 카드 격자는 repeat(auto-fit, minmax(310px,1fr)). 좌우 여백은 max(16px, safe-area-inset). 가로 스크롤은 표 안에서만.

[H. 폴더 구조 (제안 후 확인받고 생성)]
Oz_nanodegree/ (저장소 루트)
├─ index.html   루트 이동 페이지
├─ README.md    프로젝트 소개, 데이터 출처, 실행·재현 방법, 해석 주의점
├─ .gitignore   .DS_Store, __pycache__/, build/, *.zip, diabetic_data.csv
└─ diabetes-readmission-dashboard/
   ├─ index.html           대시보드 본체(데이터 내장)
   ├─ PROMPT.md            재현 프롬프트
   ├─ data/sample_5rows.csv   원본에서 뽑은 5행 샘플(재입원 2건 + 그 외 3건, 인종 미상 제외, 대시보드가 쓴 22개 컬럼, 값은 원본 그대로)
   ├─ dynamic/index.html     Supabase 연동 동적 버전([L])
   ├─ supabase/              config.toml, migrations/*.sql ([L])
   └─ scripts/prep_data.py    UCI zip을 받아 build/cols.json을 만드는 스크립트(사용법을 파일 위에 주석으로 적고, 실행해 위 기준 건수가 나오는지 확인)
원본 diabetic_data.csv는 올리지 않는다.

[I. 배포 (각 단계 전에 확인)]
1. 저장소(https://github.com/Jye-rookie/Oz_nanodegree, 공개, 처음엔 비어 있음)용 새 폴더에서 git init -b main, 커밋(메시지 영어, 끝에 Co-Authored-By 줄), 원격 추가 후 main에 push. 개인 프로젝트 저장소에는 커밋하지 않는다.
2. push 후 GitHub API로 파일 6개가 올라갔는지 확인한다.
3. GitHub Pages: 저장소 Settings > Pages > Source "Deploy from a branch", Branch main, Folder "/ (root)"를 사용자가 직접 저장한다(에이전트의 브라우저는 GitHub에 로그인되어 있지 않다). 설정이 저장되면 Save 버튼은 회색으로 바뀌는 것이 정상이다.
4. 루트 주소로 바로 열기: 저장소 루트에 index.html을 추가한다. 내용은 meta refresh(0초)로 diabetes-readmission-dashboard/ 로 이동시키고, 이동하지 않을 때 누를 수 있는 링크와 라이트·다크 대응 최소 스타일을 둔다. 대시보드 파일은 복사하지 않는다(용량 중복 방지). 커밋하고 push한다. 이 push가 새 배포를 일으킨다.
5. 주소가 열릴 때까지 최대 약 2분 확인한다. 첫 배포는 몇 분 걸리며 그 전에는 404가 정상이다.
6. 확인할 주소: https://jye-rookie.github.io/Oz_nanodegree/ (HTTP 200, 대시보드로 이동), https://jye-rookie.github.io/Oz_nanodegree/diabetes-readmission-dashboard/ (HTTP 200, 응답 크기 6,798,215바이트).

[J. 검증]
- 스크립트 구문 오류가 없는지 확인한다.
- 전체 기준 수치(입원 101,766 / 환자 71,518 / 재입원 11,357 / 11.2%)가 KPI에 그대로 나오는지 확인한다.
- 필터를 바꾸면 KPI, 막대, 히트맵, 목록이 함께 바뀌고, 상세 패널에 같은 환자 기록이 나오는지 확인한다.
- 라이트·다크 모드에서 글자와 히트맵 셀 글자가 읽히는지 확인한다.
- 직접 확인하지 못한 항목은 확인하지 못했다고 보고한다.

[K. 결과 요약 (자유 형식, 독자·KPI·인사이트)]
독자는 임상연구자, KPI는 재입원률 11.2%를 중심으로 입원/재입원 건수·환자 수·평균 입원일수다. 인사이트는 아래 기준값 표의 수치로 쓴다. 5줄 요약도 요청받으면 줄여서 쓴다. 연관성이지 인과가 아니고, 1999–2008년 미국 병원 데이터이며, HbA1c는 83%가 미검사라 단정하지 않는다는 한계를 반드시 포함한다.

[L. Supabase 연동 동적 버전 (CLI 사용, 정적 버전은 그대로 유지)]
사전 준비(사용자가 직접): supabase.com에서 프로젝트 생성, DB 비밀번호는 비밀번호 관리자에 보관, 터미널에서 `npx supabase login`(브라우저 인증), 프로젝트 주소의 ref를 에이전트에 알려준다. secret/service_role 키와 DB 비밀번호는 에이전트에 붙여넣지 않고 저장소에도 올리지 않는다.
에이전트가 하는 일(되돌리기 어려운 단계는 실행 전에 확인받는다):
1. CLI는 `npx supabase`로 쓴다(설치 없이). `diabetes-readmission-dashboard/` 에서 `supabase init`.
2. `supabase migration new` 로 마이그레이션 2개를 만든다.
   (1) create_encounters: `public.encounters`(enc bigint PK, pt bigint, age/sex/race/adm/src/dis/los/labs/proc/meds/nout/nemr/ninp/dg/ndx/a1c/ins/chg/dmed/rd smallint not null, icd text; 컬럼 의미는 [D]와 같다). 인덱스 pt, rd, age, dis, dg. RLS 활성화, anon·authenticated 대상 `select` 정책 1개(using true). `revoke all on public.encounters from anon, authenticated` 후 `grant select` 만 부여(쓰기는 RLS와 권한 회수로 이중 차단).
   (2) dashboard_functions: 모두 `language sql stable`, `set search_path = public`, 호출자 권한(RLS 적용), anon·authenticated 에 execute 부여.
   - `enc_filtered(f jsonb)` returns setof encounters. 필터 jsonb 키: age, sex, adm, dis, dg (정수 배열, 빈 배열·없는 키 = 전체, 판정은 `f->'age' @> to_jsonb(e.age)`), exclude_dead(boolean, true 이면 dis<>4).
   - `dashboard_stats(f jsonb)` returns jsonb: `{kpi:{n,k,pts,los_sum}, factors:{<key>:[{b,n,k}...]}, heat:[{a,b,n,k}...], dead:<dis=4 건수>}`. n=건수, k=rd=2 건수, pts=고유 pt, los_sum=입원일수 합. factors 키와 구간 b: ninp=least(ninp,3), nemr=least(nemr,2), nout=least(nout,2), los(<=3:0, <=7:1, 그 외 2), meds(<=10:0, <=20:1, 그 외 2), labs(<30:0, <50:1, 그 외 2), proc=least(proc,2), a1c, ins, chg, ndx(<=5:0, <=8:1, 그 외 2), dg, dis, src. 한 쿼리에서 `cross join lateral (values ...)` 로 14개 요인을 한꺼번에 집계한다. heat 의 a=least(ninp,3), b=입원일수 구간.
   - `case_list(f, sort_key text default 'ninp', only_readmit boolean default false, lim integer default 40)` returns `{total, rows:[encounters 행...]}`. 정렬 키는 화이트리스트(los, meds, nemr, 그 외 ninp), 모두 내림차순 + 입원일수 내림차순 + enc. lim 은 1~200 으로 제한.
   - `patient_history(p bigint)` returns jsonb 배열(해당 환자의 입원, enc 오름차순).
3. 로컬 검증: Docker Desktop 실행 후 `supabase start`(필요한 서비스만), `supabase db reset` 으로 마이그레이션이 오류 없이 적용되는지 보고, `prep_data.py` 가 만든 `build/encounters.csv`(헤더 포함)를 로컬 DB에 `\copy` 로 넣은 뒤 기준값(아래 [M])과 같은지 확인한다. anon 역할로 delete·insert 가 permission denied 인지 확인한다. 끝나면 `supabase stop`.
4. `prep_data.py` 는 cols.json 외에 encounters.csv(컬럼 순서 = 테이블 컬럼 순서)도 쓴다. `build/` 는 .gitignore 대상이다.
5. 원격 반영(실행 전 확인): `supabase link --project-ref <ref>` -> `supabase db push --dry-run` -> 확인 후 `supabase db push`. `supabase migration list` 로 local/remote 가 같은지 본다.
6. 데이터 적재(비밀번호 불필요): 원격에는 `supabase db query --linked -f <파일>` 로 SQL 을 실행할 수 있다. encounters.csv 를 2,000행씩 `insert into public.encounters (...) values ... on conflict (enc) do nothing;` 파일 51개로 나눠 차례로 실행하고, 끝나면 건수(101,766 / 71,518 / 11,357)를 확인한다.
7. 키: `supabase projects api-keys --project-ref <ref> -o json` 에서 공개용 publishable 키(sb_publishable_...)만 화면 코드에 쓴다. 요청은 `POST {프로젝트 URL}/rest/v1/rpc/<함수>` 에 헤더 `apikey: <publishable 키>`, `Content-Type: application/json` 으로 보낸다. 원격에서도 anon 으로 insert/delete 가 401 이고 CORS preflight 가 200 인지 확인한다.
8. `dynamic/index.html` 은 정적 `index.html` 의 마크업·CSS 를 그대로 쓰고 내장 데이터(`const C=...`)와 브라우저 집계 코드를 제거한 뒤 아래로 바꾼다.
   - 필터를 jsonb 로 만들어 `dashboard_stats`, `case_list` 를 `Promise.all` 로 호출. 필터 변경 후 120ms 디바운스, 요청마다 일련번호를 두어 늦게 도착한 오래된 응답은 버린다.
   - 조회 중에는 KPI·막대·히트맵·목록을 불투명도 0.55 로 흐리게, 실패하면 안내 박스(role="alert")와 "다시 시도" 버튼. `[hidden]{display:none!important}` 리셋을 둔다.
   - 시작할 때 `dashboard_stats({})` 를 한 번 호출해 "전체" 재입원률을 KPI 안내에 쓴다. 케이스 상세는 선택할 때 `patient_history` 를 호출하고 불러오는 중 문구를 보인다. 목록의 icd 등 DB 문자열은 HTML 이스케이프한다.
   - 신뢰구간(Wilson), 막대 색 규칙, 히트맵 농도는 [F]와 같이 화면에서 계산하고, DB 에서는 건수와 합계만 받는다. 제목은 "당뇨 재입원 케이스 탐색기 (Supabase)", 설명에 Supabase 조회임을 밝힌다.
   - 단독 HTML 이므로 `<!doctype html>`, `<meta charset="utf-8">`, viewport 메타, `body{margin:0}` 를 넣는다(정적 `index.html` 에도 같은 헤더를 추가). 이를 빠뜨리면 글자가 깨지거나 여백이 어긋난다.
9. 로컬 서버(`python3 -m http.server`)로 열어 KPI 와 필터 결과가 기준값과 같은지, 케이스 선택 시 같은 환자 기록이 나오는지 확인한 뒤(이 페이지는 외부 요청이 필요하므로 Claude 아티팩트 미리보기에서는 동작하지 않는다), 비밀 값 검색(sb_secret, service_role, eyJ..., 비밀번호) 후 확인받고 commit·push 한다. Pages 주소: `https://<사용자>.github.io/<저장소>/diabetes-readmission-dashboard/dynamic/`.
10. README 에 동적 버전 절을 추가한다(구성 순서, 공개 키만 포함된다는 점, 무료 프로젝트는 오래 접속이 없으면 일시 중지되어 Supabase 대시보드에서 재개해야 한다는 점).

[M. 동적 버전 검증 기준값]
- 필터 없음: n 101,766 / k 11,357 / 환자 71,518 / 입원일수 합 447,362 / 사망·호스피스 2,423 (평균 입원일수 4.4일)
- 직전 1년 입원 구간(0/1/2/3회 이상): 건수 67,630 / 19,521 / 7,566 / 7,049, 재입원 5,706 / 2,523 / 1,319 / 1,809
- `exclude_dead=true`: n 99,343 / k 11,314 / 환자 69,990
- 연령 [6,7] + 질환군 [4]: n 2,739 / k 365 (13.3%) / 환자 2,420 / 사망·호스피스 41 (평균 입원일수 5.0일)
- 질환군 [4] 만: n 8,757 / k 1,137 / 환자 7,147
- `patient_history(8222157)`: enc 2278392 한 건
- 응답 시간: 집계 약 0.2~0.5초(첫 호출은 2~5초)
```

## 재현 시 확인할 기준값

재입원률은 `<30` 기준이며 전체는 11.2%입니다. 아래 표는 같은 기준으로 직접 집계한 값입니다.

| 구분 | 항목 | 건수 | 재입원률 |
|---|---|---|---|
| 전체 | 전체 | 101,766 | 11.2% (11,357건) |
| 최근 1년 입원 | 0회 / 1회 / 2회 / 3회 이상 | 67,630 / 19,521 / 7,566 / 7,049 | 8.4% / 12.9% / 17.4% / 25.7% |
| 최근 1년 응급실 | 0회 / 1회 / 2회 이상 | 90,383 / 7,677 / 3,706 | 10.5% / 14.4% / 21.3% |
| 입원일수 | 1–3 / 4–7 / 8일 이상 | 49,188 / 37,288 / 15,290 | 9.7% / 12.2% / 13.4% |
| 투약 수 | 10종 이하 / 11–20 / 21종 이상 | 25,861 / 52,025 / 23,880 | 9.1% / 11.5% / 12.8% |
| 진단 수 | 5개 이하 / 6–8 / 9개 이상 | 21,007 / 31,170 / 49,589 | 8.5% / 11.0% / 12.4% |
| 인슐린 | 미사용 / 유지 / 감량 / 증량 | 47,383 / 30,849 / 12,218 / 11,316 | 10.0% / 11.1% / 13.9% / 13.0% |
| 퇴원처 | 자택 / 자택+방문 / 시설 / 전원 / 사망·호스피스 / 기타 | 60,234 / 13,010 / 17,222 / 3,574 / 2,423 / 5,303 | 9.3% / 12.7% / 15.9% / 19.0% / 1.8% / 12.1% |
| 주진단 | 당뇨병 / 순환기계 / 호흡기계 / 근골격계 | 8,757 / 30,437 / 14,423 / 4,957 | 13.0% / 11.4% / 9.7% / 9.5% |
| 성별 | 여 / 남 | 54,708 / 47,055 | 11.2% / 11.1% |
| 조합 | 이전 입원 0회 + 입원일수 3일 이하 | 34,517 | 7.2% |
| 조합 | 이전 입원 3회 이상 + 입원일수 8일 이상 | 1,433 | 23.3% |

추가 확인값: 사망·호스피스 퇴원을 빼면 전체 재입원률 11.4%(99,343건 중 11,314건). 직전 1년에 입원이 있던 입원은 전체의 33.5%이고 재입원의 49.8%를 차지. 입원이 2건 이상인 환자는 16,773명.

## 알려진 한계

- 원본에 날짜가 없어 환자의 입원 순서는 `encounter_id` 순서로 대신했습니다.
- 1999–2008년 미국 병원 기록이라 현재 한국 진료 환경에 그대로 적용할 수 없습니다.
- 화면은 위험요인과 재입원의 연관성만 보여 주며 인과관계를 뜻하지 않습니다.
- 라이트 모드의 LeafyGreen 색 일부는 공식 값이 아니라 기억 기준입니다. 사이트 첫 화면에는 LeafyGreen이 유지보수 모드이고 새 제품은 Via를 쓰라는 안내가 있습니다.
- 이 프롬프트로 만든 결과물은 이 세션의 대시보드와 세부 디자인이 조금 다를 수 있습니다. 분석 기준과 위 기준값은 같아야 합니다.
- GitHub 저장소 이름과 사용자 이름(Jye-rookie)은 이 작업의 실제 값입니다. 다른 사람이 재현할 때는 자신의 저장소 주소로 바꿔야 합니다.
