# ~/.zsh/bazel.zsh — Bazel shortcuts. Guide: guides/bazel-field-manual.md
(( $+commands[bazel] )) || return 0

# >>> bazel (see guides/bazel-field-manual.md) >>>
# binaries in ~/.local/bin: bazel (bazelisk), buildifier, buildozer, ibazel, target-determinator
# completion script: regenerate with `bazel help completion bash > ~/.zsh/completions/bazel-complete.bash`
alias b=bazel
alias bb='bazel build'
alias bt='bazel test'
alias br='bazel run'
alias bzq='bazel query'        # not bq: /usr/bin/bq already exists
alias bcq='bazel cquery'
alias baq='bazel aquery'
alias bi='bazel info'
alias bmod='bazel mod'
alias ib=ibazel

# which targets use this file directly: bwho //lib/auth:token.go
bwho(){ bazel query "rdeps(//..., $1, 1)" --output=label_kind; }
# why does A depend on B: bwhy //app:server @pypi//requests
bwhy(){ bazel query "somepath($1, $2)" --output=label; }
# where did the outputs land: bout //app:server
bout(){ bazel cquery "$1" --output=files 2>/dev/null; }
# open a test's log: btlog //lib/auth:auth_test
btlog(){ local p=${1#//}; p=${p/://}; ${PAGER:-less} "$(bazel info bazel-testlogs)/$p/test.log"; }
# tidy everything generated: BUILD files, use_repo lists, formatting
btidy(){ bazel run //:gazelle && bazel mod tidy && buildifier -r -lint=fix .; }
# every rule kind in the repo, counted
bkinds(){ bazel query 'kind(".*rule", //...)' --output=label_kind | cut -d' ' -f1 | sort | uniq -c | sort -rn; }

# bash completion through bashcompinit; must stay after the last compinit
[[ -r ~/.zsh/completions/bazel-complete.bash ]] || bazel help completion bash > ~/.zsh/completions/bazel-complete.bash 2>/dev/null
source ~/.zsh/completions/bazel-complete.bash 2>/dev/null
complete -o nospace -F _bazel__complete b 2>/dev/null
# <<< bazel <<<
