### A Pluto.jl notebook ###
# v0.20.21

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    return quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ b0000001-0001-4000-8000-000000000001
begin
    import Pkg
    Pkg.activate(joinpath(@__DIR__, ".."))   # experiments/ 공유 환경

    # 로컬 패키지(Dcinside, DcinsideAnalysis)를 dev 모드로 설치 (최초 1회).
    let root = normpath(joinpath(@__DIR__, "..", "..")),
        have = keys(Pkg.project().dependencies),
        want = [("Dcinside", root),
                ("DcinsideAnalysis", joinpath(root, "analysis"))],
        miss = [Pkg.PackageSpec(path = p) for (n, p) in want if !(n in have)]
        isempty(miss) || Pkg.develop(miss)
    end
    Pkg.instantiate()
end

# ╔═╡ b0000002-0002-4000-8000-000000000002
begin
    using PlutoUI
    using DataFrames
    using Unicode            # base.dict 는 NFD 한글 — 파싱 전 NFC 정규화에 사용
    using Dcinside
    using DcinsideAnalysis   # Kiwi · Corpus · DcinsideDataFrames
end

# ╔═╡ b0000003-0003-4000-8000-000000000003
md"""
# 작가/작품 언급 빈도 분석

genrenovel 갤러리에서 **작품 줄임말·웹소설 작가명** 단위로 언급 빈도를 집계한다.
키워드는 `analysis/dict/base.dict` 의 고유명사 섹션에서 파생한다 (README 참고).
"""

# ╔═╡ b0000004-0004-4000-8000-000000000004
const gallery_name = "genrenovel"

# ╔═╡ b0000005-0005-4000-8000-000000000005
const BASE_DICT = normpath(joinpath(@__DIR__, "..", "..", "analysis", "dict", "base.dict"))

# ╔═╡ b0000006-0006-4000-8000-000000000006
@bind time Clock()

# ╔═╡ b0000007-0007-4000-8000-000000000007
let time
    Kiwi.load_user_dict!(BASE_DICT)
    Kiwi.load_user_dict!(joinpath(@__DIR__, "vocab.dict"))
end

# ╔═╡ b0000008-0008-4000-8000-000000000008
const api = Dcinside.API()

# ╔═╡ b0000009-0009-4000-8000-000000000009
md"""
## 1. 사전 파싱 → 키워드 목록

base.dict 의 `# ── 플랫폼·작품·인물 고유명사 ──` 섹션에서
검색어(form)와 canonical(원형)을 추출한다.

- 독립 NNP 행 `form\tNNP\t점수\t# 주석` → `canonical = form`
- alias 행 `form\t원형/NNP\t점수` → `canonical = 원형`
- `entry_type`: 주석에 `작가` 포함 → `:author`, `약칭` 포함 → `:work`, 그 외 `:other`

!!! note "TODO (media_type)"
    웹소설/인터넷소설/제외 구분은 base.dict 의 섹션 헤더를 세분한 뒤
    `section → media_type` 매핑으로 파생할 예정. 현재는 `entry_type` 까지만.
"""

# ╔═╡ b000000a-000a-4000-8000-00000000000a
"""
    parse_name_dict(path) -> DataFrame

base.dict 의 고유명사 섹션을 파싱해 키워드 후보를 반환.
열: `form`, `canonical`, `entry_type` (:work/:author/:other)

!!! note "NFD 정규화"
    base.dict 는 NFD(조합형) 한글로 저장돼 있어, NFC 리터럴(`"작가"`/`"약칭"`)과
    바이트 단위 비교 시 매칭되지 않는다. 각 줄을 `:NFC` 로 정규화해 흡수한다.
"""
function parse_name_dict(path::AbstractString)
    rows = NamedTuple[]
    in_section = false
    for raw in eachline(path)
        line = Unicode.normalize(rstrip(raw), :NFC)
        if startswith(line, "#")
            # 섹션 경계: 고유명사 섹션 진입/이탈 판정
            if occursin("──", line)
                in_section = occursin("고유명사", line)
            end
            continue
        end
        (in_section && !isempty(line)) || continue

        # "form<TAB>pos[/...]<TAB>score  # comment"
        body, comment = let i = findfirst('#', line)
            i === nothing ? (line, "") : (line[1:prevind(line, i)], line[nextind(line, i):end])
        end
        fields = split(strip(body), '\t')
        length(fields) >= 2 || continue
        form = strip(fields[1])
        pos  = strip(fields[2])

        # alias 행이면 "원형/NNP" 에서 canonical 추출, 아니면 form 자신
        canonical = occursin('/', pos) ? String(split(pos, '/')[1]) : form
        # "약칭" 을 먼저 검사: 작품 제목 안의 "…작가…"(예: <백작가의 망나니>)가
        # author 로 오분류되는 것을 막는다. 작가 주석에는 "약칭" 이 없다.
        entry_type = occursin("약칭", comment) ? :work :
                     occursin("작가", comment) ? :author : :other
        push!(rows, (form = form, canonical = canonical, entry_type = entry_type))
    end
    DataFrame(rows)
end

# ╔═╡ b000000b-000b-4000-8000-00000000000b
name_df = parse_name_dict(BASE_DICT)

# ╔═╡ b000000c-000c-4000-8000-00000000000c
md"""
## 2. 코퍼스 수집 (TODO)

```julia
forms  = unique(name_df.form)
corpus = Corpus.collect(api, gallery_name, forms; posts_per_keyword=20)
```

## 3. canonical 빈도 집계 + 시각화 (TODO)

`corpus` 의 각 행 `keyword`(=form) → `name_df` 로 canonical 매핑 →
`groupby(:canonical)` 빈도 → 상위 N개 막대 차트.
"""

# ╔═╡ Cell order:
# ╟─b0000001-0001-4000-8000-000000000001
# ╠═b0000002-0002-4000-8000-000000000002
# ╟─b0000003-0003-4000-8000-000000000003
# ╠═b0000004-0004-4000-8000-000000000004
# ╠═b0000005-0005-4000-8000-000000000005
# ╟─b0000006-0006-4000-8000-000000000006
# ╟─b0000007-0007-4000-8000-000000000007
# ╠═b0000008-0008-4000-8000-000000000008
# ╟─b0000009-0009-4000-8000-000000000009
# ╠═b000000a-000a-4000-8000-00000000000a
# ╠═b000000b-000b-4000-8000-00000000000b
# ╟─b000000c-000c-4000-8000-00000000000c
