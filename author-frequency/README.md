# 작가/작품 언급 빈도 분석

genrenovel 갤러리에서 **작품 줄임말 및 웹소설 작가명** 단위로 언급 빈도를 집계하는 실험.

## 키워드 출처

검색 키워드는 [`analysis/dict/base.dict`](../../analysis/dict/base.dict) 의
`# ── 플랫폼·작품·인물 고유명사 ──` 섹션에서 파생한다.

- **작품 줄임말** — 주석에 `약칭` 이 포함된 NNP 항목
- **웹소설 작가명** — 주석에 `웹소설 작가` 가 포함된 NNP 항목
- **alias 행** (`줄임말\t원형/NNP`) — 검색어로 쓰되 빈도는 원형(canonical)에 합산

## 미디어 구분 (설계 예정)

base.dict 의 작품·작가 섹션을 다음으로 세분해 `media_type` 을 파생한다:

- 웹소설 작품 / 웹소설 작가  → `:web`
- 인터넷소설 작품 / 인터넷소설 작가 → `:internet`
- 제외 (애니·게임·만화) → 키워드에서 제외

노트북에서 `MultiSelect(["웹소설", "인터넷소설"])` 로 대상 미디어를 선택/세분한다.

## 파이프라인

1. `base.dict` 파싱 → `(form, canonical, media_type, entry_type)` 키워드 목록
2. `Corpus.collect(api, "genrenovel", forms; ...)` → 제목·본문·댓글 코퍼스
3. 각 행에 canonical 태깅 → `groupby(:canonical)` 빈도 집계
4. 상위 N개 작품/작가 언급 빈도 막대 차트 (media_type 별 색 구분)

## 실행

`notebook.jl` 을 Pluto 로 연다. 첫 셀이 공유 환경(`experiments/Project.toml`)을
활성화하고 로컬 패키지(`Dcinside`, `DcinsideAnalysis`)를 dev 설치한다.
