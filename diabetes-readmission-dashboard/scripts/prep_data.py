"""UCI Diabetes 130-US Hospitals 원본을 내려받아 대시보드용 컬럼 JSON(cols.json)으로 변환한다.

사용법: python3 prep_data.py [출력 폴더]
- 출처: https://archive.ics.uci.edu/dataset/296 (zip 약 3MB, 압축을 풀면 diabetic_data.csv 약 19MB)
- 결과 cols.json 은 index.html 안의 `const C={...}` 와 같은 구조다.
"""
import csv, io, json, sys, urllib.request, zipfile
from pathlib import Path

URL = "https://archive.ics.uci.edu/static/public/296/diabetes+130-us+hospitals+for+years+1999-2008.zip"
out = Path(sys.argv[1] if len(sys.argv) > 1 else "build")
out.mkdir(parents=True, exist_ok=True)

print("downloading", URL)
raw = urllib.request.urlopen(URL, timeout=120).read()
with zipfile.ZipFile(io.BytesIO(raw)) as z:
    text = z.read("diabetic_data.csv").decode("utf-8")

AG = ['[0-10)', '[10-20)', '[20-30)', '[30-40)', '[40-50)', '[50-60)', '[60-70)', '[70-80)', '[80-90)', '[90-100)']
RC = ['Caucasian', 'AfricanAmerican', 'Hispanic', 'Asian', 'Other']


def dg(c):  # diag_1(ICD-9) -> 질환군 인덱스
    if c in ('?', '') or c[0] in 'VE':
        return 8
    if c.startswith('250'):
        return 4
    try:
        i = int(float(c))
    except ValueError:
        return 8
    if 390 <= i <= 459 or i == 785: return 0   # 순환기계
    if 460 <= i <= 519 or i == 786: return 1   # 호흡기계
    if 520 <= i <= 579 or i == 787: return 2   # 소화기계
    if 800 <= i <= 999: return 3               # 손상·중독
    if 710 <= i <= 739: return 5               # 근골격계
    if 580 <= i <= 629 or i == 788: return 6   # 비뇨생식계
    if 140 <= i <= 239: return 7               # 신생물
    return 8                                   # 기타


names = 'enc pt age sex race adm src dis los labs proc meds nout nemr ninp dg ndx a1c ins chg dmed rd icd'.split()
cols = {k: [] for k in names}
for r in csv.DictReader(io.StringIO(text)):
    d = int(r['discharge_disposition_id']); a = int(r['admission_type_id']); s = int(r['admission_source_id'])
    dis = (0 if d == 1 else 1 if d in (6, 8) else 2 if d in (3, 4, 22, 23, 24)
           else 4 if d in (11, 13, 14, 19, 20, 21)
           else 3 if d in (2, 5, 9, 10, 12, 15, 16, 17, 27, 28, 29, 30) else 5)
    vals = [int(r['encounter_id']), int(r['patient_nbr']), AG.index(r['age']), {'Female': 0, 'Male': 1}.get(r['gender'], 2),
            RC.index(r['race']) if r['race'] in RC else 5, {1: 0, 2: 1, 3: 2}.get(a, 3),
            0 if s in (1, 2, 3) else 1 if s in (4, 5, 6) else 2 if s == 7 else 3, dis,
            int(r['time_in_hospital']), int(r['num_lab_procedures']), int(r['num_procedures']), int(r['num_medications']),
            int(r['number_outpatient']), int(r['number_emergency']), int(r['number_inpatient']), dg(r['diag_1']),
            int(r['number_diagnoses']), {'None': 0, 'Norm': 1, '>7': 2, '>8': 3}[r['A1Cresult']],
            {'No': 0, 'Steady': 1, 'Down': 2, 'Up': 3}[r['insulin']], 1 if r['change'] == 'Ch' else 0,
            1 if r['diabetesMed'] == 'Yes' else 0, {'NO': 0, '>30': 1, '<30': 2}[r['readmitted']], r['diag_1']]
    for k, v in zip(names, vals):
        cols[k].append(v)

(out / "cols.json").write_text(json.dumps(cols, separators=(',', ':')), encoding="utf-8")
n = len(cols['enc'])
print(f"입원 {n:,}건, 환자 {len(set(cols['pt'])):,}명, 30일 내 재입원 {cols['rd'].count(2):,}건 -> {out/'cols.json'}")
