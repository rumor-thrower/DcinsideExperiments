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

# ╔═╡ a1f3c2d0-0001-4000-8000-000000000001
begin
    import Pkg
    Pkg.activate(joinpath(@__DIR__, ".."))   # experiments/ 공유 환경

    # 로컬 패키지(Dcinside, DcinsideAnalysis)를 dev 모드로 설치 (최초 1회).
    let root = normpath(joinpath(@__DIR__, "..", "..")),
        have = keys(Pkg.project().dependencies),
        want = [("Dcinside", root),
                ("DcinsideAnalysis", normpath(joinpath(root, "..", "DcinsideAnalysis")))],
        miss = [Pkg.PackageSpec(path = p) for (n, p) in want if !(n in have)]
        isempty(miss) || Pkg.develop(miss)
    end
    Pkg.instantiate()
end

# ╔═╡ c03b12c8-ea24-4e68-a89a-a616db2b4798
begin
	using PlutoUI
	using DataFrames
	using Dcinside
	using DcinsideAnalysis   # Kiwi · Corpus · DcinsideDataFrames · Charts
end

# ╔═╡ aa000013-1301-4000-8000-000000000013
begin
	using HypertextLiteral

	const DISABILITY_KEYWORDS = ["장애", "불구", "실명", "자폐", "치료", "극복", "클리셰", "영구 장애"]

	const FRAME_VOCAB = Dict(
		:gaming    => ["디버프", "스탯", "패널티", "약점", "너프", "능력치", "상태이상",
		               "핸디캡", "제약", "쇠약", "디메리트", "마이너스"],
		:catharsis => ["성장", "회복", "완치", "기적", "노력", "이겨냈", "딛고",
		               "해냈", "역경", "강해", "각성", "시한부", "피폐"],
		:sympathy  => ["불쌍", "감동", "안타깝", "가엾", "측은", "눈물", "비련",
		               "가슴아프", "힘들", "애처롭", "불행", "고통"],
		:critical  => ["재현", "고정관념", "차별", "편견", "서사", "비판",
		               "문제적", "혐오", "장애인식", "의료화", "감동포르노"],
	)

	const KWIC_WINDOW = 40
	const OUTPUT_DIR  = let d = joinpath(@__DIR__, "output"); mkpath(d); d end
	md"상수 정의 완료 — 키워드 $(length(DISABILITY_KEYWORDS))개, 프레임 $(length(FRAME_VOCAB))종 | 출력: $(OUTPUT_DIR)"
end

# ╔═╡ d9be15e6-11d4-4e56-af91-99a60befe7ef
const api = Dcinside.API()

# ╔═╡ c708a4f0-2482-4d84-94f7-cc734cc1a5c0
const gallery_name = "genrenovel"

# ╔═╡ 448bc7e4-5fff-4f16-9c28-7070f51083df
@bind time Clock()

# ╔═╡ fa9b0c1e-3d72-4a85-b6e8-2f5c8d1e0a34
let time
	# 공통 중립 어휘 + 이 실험 전용 어휘를 순서대로 로드
	Kiwi.load_user_dict!(DcinsideAnalysis.base_dict_path())
	Kiwi.load_user_dict!(joinpath(@__DIR__, "vocab.dict"))
end

# ╔═╡ 9c9e951d-b26f-4469-a34e-befce57a9338
let ch = Dcinside.board(api, gallery_name; num=5)
	df = DcinsideDataFrames.to_dataframe(ch)
end

# ╔═╡ c1a2b3d4-e5f6-7890-abcd-ef1234567890
# title 열 → Kiwi 형태소 분석 (명사 추출) → id·title·morphemes 열만 출력
let time
	ch = Dcinside.board(api, gallery_name; num=10)
	df = DcinsideDataFrames.to_dataframe(ch)
	DcinsideDataFrames.parse_titles!(df, Kiwi.nouns)
	df[!, [:id, :title, :morphemes]]
end

# ╔═╡ aa000015-1501-4000-8000-000000000015
# 키워드 8개 × 20게시글 × (본문+댓글 포함) ≈ 요청 ~500회 × 1.5s ≈ 12~15분
corpus_df = let time
	@info "코퍼스 수집 시작..."
	df = Corpus.collect(api, gallery_name, DISABILITY_KEYWORDS; posts_per_keyword=20)
	@info "수집 완료" nrow=nrow(df)
	df
end

# ╔═╡ aa000016-1601-4000-8000-000000000016
begin
	function classify_frame(text::AbstractString, vocab::Dict)::Symbol
		scores = Dict(f => sum(count(t, text) for t in v) for (f, v) in vocab)
		best   = maximum(values(scores))
		best |> iszero && return :none
		winners = [f for (f, s) in scores if s == best]
		length(winners) == 1 ? only(winners) : :ambiguous
	end

	# 동음이의 용례 제거: 각 (키워드, 패턴) 쌍에 대해 키워드 행 중 패턴 불일치 행을 제거
	filter_keyword_sense!(df, kw_patterns) =
		(foreach(((kw, pat),) -> filter!(r -> r.keyword != kw || occursin(pat, r.text), df), kw_patterns); df)

	corpus_nlp = let
		df = copy(corpus_df)
		# 플랫폼 공식 봇 계정 제거
		filter!(r -> r.author != "댓글돌이", df)
		filter_keyword_sense!(df, [
			("불구", r"불구(?!하)"),   # "불구하고/하여/하다"(역접) 제거 — 장애 의미만 유지
			("실명", r"실명(?!제)"),   # "실명제"(금융 실명제) 제거 — 失明(시력 상실)만 유지
			("자폐", r"(?<!활)자폐"), # "활자폐기물" 등 합성어 제거 — 自閉(자폐증)만 유지
		])
		transform!(df, :text => ByRow(t -> Kiwi.nouns(t))                      => :nouns)
		transform!(df, :text => ByRow(t -> classify_frame(t, FRAME_VOCAB))     => :frame)
		df
	end
end

# ╔═╡ aa000017-1701-4000-8000-000000000017
"""
    kwic(df, keyword; window, n) -> DataFrame

키워드 주변 문맥(KWIC) 추출.
반환 열: `left_context`, `keyword_hit`, `right_context`, `source_type`, `doc_id`, `search_kw`
"""
function kwic(df::DataFrame, keyword::AbstractString;
              window::Int=KWIC_WINDOW, n::Int=30)
	results  = NamedTuple[]
	seen_pos = Set{Tuple{String,Int}}()   # (source_id, byte_offset) — 중복 제거
	for row in eachrow(df)
		text   = row.text
		offset = firstindex(text)
		while true
			r = findnext(keyword, text, offset)
			r === nothing && break
			ks, ke = first(r), last(r)

			# 동일 문서·동일 위치(다른 keyword 행으로 중복 수집된 경우) 스킵
			pos_key = (row.source_id, ks)
			pos_key in seen_pos && (offset = nextind(text, ke); continue)
			push!(seen_pos, pos_key)

			# prevind/nextind으로 문자 경계를 정확히 계산 (멀티바이트 안전)
			# s[i:j] 는 i·j 모두 문자 시작 바이트여야 함
			ls = max(firstindex(text), prevind(text, ks, window))
			left = text[ls:prevind(text, ks)]

			right_start = nextind(text, ke)
			right = if right_start > ncodeunits(text)
				""
			else
				re_raw = nextind(text, ke, window)   # window번째 문자의 시작 바이트
				re     = re_raw <= ncodeunits(text) ? re_raw : lastindex(text)
				text[right_start:re]
			end

			push!(results, (
				left_context  = left,
				keyword_hit   = keyword,
				right_context = right,
				source_type   = row.source_type,
				doc_id        = row.doc_id,
				search_kw     = row.keyword,
			))
			length(results) >= n && @goto kwic_done
			offset = nextind(text, ke)
		end
	end
	@label kwic_done
	DataFrame(results)
end

# ╔═╡ aa000018-1801-4000-8000-000000000018
begin
	"""
	    cooccurrence_matrix(df, dis_kws, frame_vocab) -> DataFrame

	행: 장애 키워드, 열: 프레임명.
	값 = 해당 텍스트에서 장애 키워드와 프레임 어휘가 함께 등장한 행 수.
	"""
	function cooccurrence_matrix(df::DataFrame,
	                              dis_kws::Vector{String},
	                              frame_vocab::Dict)
		frames = sort(collect(keys(frame_vocab)))
		rows = map(dis_kws) do dkw
			sub = filter(r -> occursin(dkw, r.text), eachrow(df))
			counts = Dict(
				f => count(r -> any(occursin(t, r.text) for t in frame_vocab[f]), sub)
				for f in frames
			)
			merge((; keyword=dkw), NamedTuple(sort(collect(counts))))
		end
		DataFrame(rows)
	end

	cooc_df = cooccurrence_matrix(corpus_nlp, DISABILITY_KEYWORDS, FRAME_VOCAB)
end

# ╔═╡ aa000019-1901-4000-8000-000000000019
# 키워드 빈도 막대 차트
let
	freq = sort(combine(groupby(corpus_nlp, :keyword), nrow => :n), :n; rev=true)
	Charts.barchart(freq.keyword, freq.n;
		width=620, height=280,
		title="키워드별 수집 행 수 (제목·본문·댓글 합산)",
		outfile=joinpath(OUTPUT_DIR, "01_keyword_freq.svg"))
end

# ╔═╡ aa000020-2001-4000-8000-000000000020
# 프레임 분포 막대 차트
let
	frame_order = [:gaming, :catharsis, :sympathy, :critical, :ambiguous, :none]
	frame_color = Dict(
		:gaming    => "#e15759",
		:catharsis => "#f28e2b",
		:sympathy  => "#59a14f",
		:critical  => "#4e79a7",
		:ambiguous => "#bab0ac",
		:none      => "#d3d3d3",
	)
	counts    = combine(groupby(corpus_nlp, :frame), nrow => :n)
	count_map = Dict(r.frame => r.n for r in eachrow(counts))
	present   = [(string(f), get(count_map, f, 0), frame_color[f])
	             for f in frame_order if get(count_map, f, 0) > 0]

	if isempty(present)
		HTML("<p style='font-family:sans-serif'>데이터 없음</p>")
	else
		Charts.barchart([x[1] for x in present], [x[2] for x in present];
			colors=[x[3] for x in present], width=560, height=280,
			title="프레임 분포",
			outfile=joinpath(OUTPUT_DIR, "02_frame_dist.svg"))
	end
end

# ╔═╡ aa000021-2101-4000-8000-000000000021
# 공기어 히트맵 — 값이 클수록 배경색 진하게
let
	frames  = [:gaming, :catharsis, :sympathy, :critical]
	max_val = max(maximum(maximum(cooc_df[!, f]) for f in frames), 1)

	cell_bg(v) = let
		i = round(Int, (1 - v/max_val) * 220)
		c = string(i, base=16, pad=2)
		"background:#$(c)$(c)ff;padding:6px 12px;text-align:center;font-size:13px"
	end

	header = join(["<th style='padding:6px 12px;background:#f0f0f0'>$f</th>" for f in frames])
	rows   = join(["<tr><td style='padding:6px 10px;font-weight:bold;background:#f8f8f8'>$(row.keyword)</td>" *
	               join(["<td style='$(cell_bg(row[f]))'>$(row[f])</td>" for f in frames]) *
	               "</tr>" for row in eachrow(cooc_df)])
	table  = """<table style="border-collapse:collapse;font-family:sans-serif">
	  <thead><tr><th style="padding:6px 10px;background:#f0f0f0">키워드</th>$header</tr></thead>
	  <tbody>$rows</tbody></table>"""

	write(joinpath(OUTPUT_DIR, "03_cooc_heatmap.html"), """<!DOCTYPE html>
	<html><head><meta charset="utf-8"></head><body>
	<h3 style="font-family:sans-serif">장애 키워드 × 프레임 공기어 히트맵</h3>
	<p style="font-size:12px;color:#666;font-family:sans-serif">진할수록 공기어 빈도 높음</p>
	$table</body></html>""")

	HTML("""<div>
		<h4 style="font-family:sans-serif;margin:8px 0">장애 키워드 × 프레임 공기어 히트맵</h4>
		<p style="font-size:12px;color:#666;font-family:sans-serif">진할수록 공기어 빈도 높음</p>
		$table
	</div>""")
end

# ╔═╡ aa000022-2201-4000-8000-000000000022
# 비판 프레임 부재 강조
let
	critical_n    = count(r -> r.frame == :critical, eachrow(corpus_nlp))
	noncritical_n = count(r -> r.frame in (:gaming, :catharsis, :sympathy), eachrow(corpus_nlp))
	Charts.barchart(["비판적 담론", "비비판적 담론 합계"], [critical_n, noncritical_n];
		colors=["#4e79a7", "#e15759"], width=360, height=260, bar_w=143, gap=10,
		bold_values=true, title="비판적 담론 부재 시각화",
		outfile=joinpath(OUTPUT_DIR, "04_critical_absence.svg"))
end

# ╔═╡ aa000023-2301-4000-8000-000000000023
@bind kwic_keyword Select(DISABILITY_KEYWORDS)

# ╔═╡ aa000024-2401-4000-8000-000000000024
# 키워드별 고빈도 공기 명사 Top-10
@bind topn_keyword Select(DISABILITY_KEYWORDS)

# ╔═╡ 2496d0f4-5b45-11f1-9781-0f03f23dfb35
let
	rows_df = kwic(corpus_nlp, kwic_keyword; n=30)
	nrow(rows_df) |> iszero && return md"검색 결과 없음"

	data_rows = [@htl("""<tr style="border-bottom:1px solid #eee">
		<td style="text-align:right;padding:4px 8px;color:#555;font-size:13px">$(r.left_context)</td>
		<td style="font-weight:bold;color:#c0392b;padding:4px 4px;white-space:nowrap;font-size:13px">$(r.keyword_hit)</td>
		<td style="padding:4px 8px;color:#555;font-size:13px">$(r.right_context)</td>
		<td style="padding:4px 8px;font-size:11px;color:#888">$(r.source_type)</td>
	</tr>""") for r in eachrow(rows_df)]

	@htl("""<div>
		<h4 style="font-family:sans-serif;margin:8px 0">KWIC — <span style="color:#c0392b">$(kwic_keyword)</span></h4>
		<table style="border-collapse:collapse;font-family:sans-serif;max-width:900px">
		  <thead><tr style="background:#f5f5f5">
		    <th style="padding:4px 8px;text-align:right;font-size:12px">좌측 문맥</th>
		    <th style="padding:4px 4px;font-size:12px">키워드</th>
		    <th style="padding:4px 8px;font-size:12px">우측 문맥</th>
		    <th style="padding:4px 8px;font-size:12px">유형</th>
		  </tr></thead>
		  <tbody>$(data_rows)</tbody>
		</table>
	</div>""")
end

# ╔═╡ 2496d5fe-5b45-11f1-8cad-db3dae0703dd
let
	sub    = filter(r -> occursin(topn_keyword, r.text), eachrow(corpus_nlp))
	all_n  = [n for r in sub for n in r.nouns]
	counts = sort(collect(Dict(n => count(==(n), all_n) for n in unique(all_n))),
	              by=x -> -x[2])
	top10  = first(counts, 10)
	isempty(top10) && return md"명사 없음"

	rows_html = [@htl("""<tr style="border-bottom:1px solid #eee">
		<td style="padding:4px 16px;font-size:14px">$i</td>
		<td style="padding:4px 16px;font-size:14px;font-weight:bold">$(p[1])</td>
		<td style="padding:4px 16px;font-size:14px">$(p[2])</td>
	</tr>""") for (i, p) in enumerate(top10)]

	@htl("""<div>
		<h4 style="font-family:sans-serif;margin:8px 0">
		  「$(topn_keyword)」 주변 고빈도 명사 Top-$(length(top10))
		</h4>
		<table style="border-collapse:collapse;font-family:sans-serif">
		  <thead><tr style="background:#f5f5f5">
		    <th style="padding:4px 16px;font-size:12px">순위</th>
		    <th style="padding:4px 16px;font-size:12px">명사</th>
		    <th style="padding:4px 16px;font-size:12px">빈도</th>
		  </tr></thead>
		  <tbody>$(rows_html)</tbody>
		</table>
	</div>""")
end

# ╔═╡ Cell order:
# ╟─a1f3c2d0-0001-4000-8000-000000000001
# ╠═c03b12c8-ea24-4e68-a89a-a616db2b4798
# ╟─d9be15e6-11d4-4e56-af91-99a60befe7ef
# ╟─c708a4f0-2482-4d84-94f7-cc734cc1a5c0
# ╟─448bc7e4-5fff-4f16-9c28-7070f51083df
# ╟─fa9b0c1e-3d72-4a85-b6e8-2f5c8d1e0a34
# ╟─9c9e951d-b26f-4469-a34e-befce57a9338
# ╟─c1a2b3d4-e5f6-7890-abcd-ef1234567890
# ╟─aa000013-1301-4000-8000-000000000013
# ╟─aa000015-1501-4000-8000-000000000015
# ╟─aa000016-1601-4000-8000-000000000016
# ╟─aa000017-1701-4000-8000-000000000017
# ╟─aa000018-1801-4000-8000-000000000018
# ╟─aa000019-1901-4000-8000-000000000019
# ╟─aa000020-2001-4000-8000-000000000020
# ╟─aa000021-2101-4000-8000-000000000021
# ╟─aa000022-2201-4000-8000-000000000022
# ╠═aa000023-2301-4000-8000-000000000023
# ╠═aa000024-2401-4000-8000-000000000024
# ╟─2496d0f4-5b45-11f1-9781-0f03f23dfb35
# ╟─2496d5fe-5b45-11f1-8cad-db3dae0703dd
