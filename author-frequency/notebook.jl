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
    using Dcinside
    using DcinsideAnalysis   # Kiwi · Corpus · DcinsideDataFrames · NameDict · Charts
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

`NameDict.parse(BASE_DICT)` 가 base.dict 의 `# ── 플랫폼·작품·인물 고유명사 ──` 섹션을
파싱해 `(form, canonical, entry_type)` DataFrame 을 반환한다.

- 독립 NNP → `canonical = form`
- alias (`원형/NNP`) → `canonical = 원형`
- `entry_type`: `:work` (약칭) / `:author` (작가) / `:other`

!!! note "TODO (media_type)"
    웹소설/인터넷소설/제외 구분은 base.dict 의 섹션 헤더를 세분한 뒤
    `section → media_type` 매핑으로 파생할 예정.
"""

# ╔═╡ b000000b-000b-4000-8000-00000000000b
name_df = NameDict.parse(BASE_DICT)

# ╔═╡ b000000c-000c-4000-8000-00000000000c
md"## 2. 코퍼스 수집"

# ╔═╡ b000000d-000d-4000-8000-00000000000d
# form 전체를 키워드로 수집 — posts_per_keyword × form 수 만큼 요청
corpus_df = let time
    forms = unique(name_df.form)
    @info "코퍼스 수집 시작..." n_forms=length(forms)
    df = Corpus.collect(api, gallery_name, forms; posts_per_keyword=20)
    @info "수집 완료" nrow=nrow(df)
    df
end

# ╔═╡ b000000e-000e-4000-8000-00000000000e
md"## 3. canonical 빈도 집계"

# ╔═╡ b000000f-000f-4000-8000-00000000000f
# keyword(=form) → canonical 매핑 후 집계
freq_df = let
    form2canonical = Dict(r.form => r.canonical for r in eachrow(name_df))
    form2type      = Dict(r.form => r.entry_type for r in eachrow(name_df))
    df = transform(corpus_df,
        :keyword => ByRow(k -> get(form2canonical, k, k))        => :canonical,
        :keyword => ByRow(k -> get(form2type,      k, :other))   => :entry_type,
    )
    sort(combine(groupby(df, [:canonical, :entry_type]), nrow => :n), :n; rev=true)
end

# ╔═╡ b0000010-0010-4000-8000-00000000000f
const OUTPUT_DIR = let d = joinpath(@__DIR__, "output"); mkpath(d); d end

# ╔═╡ b0000011-0011-4000-8000-000000000011
md"## 4. 시각화"

# ╔═╡ b0000012-0012-4000-8000-000000000012
# 상위 N 선택 슬라이더
@bind top_n Slider(5:5:50; default=20, show_value=true)

# ╔═╡ b0000013-0013-4000-8000-000000000013
# entry_type 필터
@bind filter_type Select(["all" => "전체", "work" => "작품", "author" => "작가", "other" => "기타"])

# ╔═╡ b0000014-0014-4000-8000-000000000014
# 상위 N 작품/작가 언급 빈도 막대 차트
let
    type_color = Dict("work" => "#4e79a7", "author" => "#f28e2b", "other" => "#bab0ac")
    sub = filter_type == "all" ? freq_df :
          filter(r -> string(r.entry_type) == filter_type, freq_df)
    top = first(sub, top_n)
    isempty(top) && return HTML("<p style='font-family:sans-serif'>데이터 없음</p>")

    bar_colors = [get(type_color, string(t), "#aaa") for t in top.entry_type]
    Charts.barchart(top.canonical, top.n;
        colors=bar_colors, bar_w=28, height=320, rotate_labels=true,
        legend=[("작품","#4e79a7"),("작가","#f28e2b"),("기타","#bab0ac")],
        title="언급 빈도 Top-$(nrow(top)) (필터: $(filter_type))",
        outfile=joinpath(OUTPUT_DIR, "01_author_freq_top$(top_n)_$(filter_type).svg"))
end

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
# ╠═b000000b-000b-4000-8000-00000000000b
# ╟─b000000c-000c-4000-8000-00000000000c
# ╟─b000000d-000d-4000-8000-00000000000d
# ╟─b000000e-000e-4000-8000-00000000000e
# ╟─b000000f-000f-4000-8000-00000000000f
# ╟─b0000010-0010-4000-8000-00000000000f
# ╟─b0000011-0011-4000-8000-000000000011
# ╠═b0000012-0012-4000-8000-000000000012
# ╠═b0000013-0013-4000-8000-000000000013
# ╟─b0000014-0014-4000-8000-000000000014
