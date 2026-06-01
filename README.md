# DcinsideExperiments

Pluto notebooks for text-analysis experiments on the DCinside genrenovel gallery,
built on [`Dcinside.jl`](https://github.com/rumor-thrower/Dcinside.jl) and
[`DcinsideAnalysis.jl`](https://github.com/rumor-thrower/DcinsideAnalysis.jl).

## Experiments

- `author-frequency/` — mention-frequency aggregation for works and webnovel authors
- `disability-discourse/` — frame analysis of disability discourse (KWIC, co-occurrence)

## Running

Each notebook activates the shared environment in this repo's root `Project.toml`,
which declares the two packages via `[sources]` Git URLs — `Pkg.instantiate()`
pulls them automatically. Requires Python with `kiwipiepy` available to PyCall.

```julia
using Pluto
Pluto.run(notebook = "author-frequency/notebook.jl")
```

## License

[MIT](LICENSE) — © 2026 rumor-thrower.
