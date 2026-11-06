# ~/.zsh/k8s.zsh — kubectl, helm, flux shortcuts. Guide: guides/kubernetes-field-manual.md
(( $+commands[kubectl] )) || return 0

source <(command kubectl completion zsh)
# === Kubernetes ===
# kubectl colourized output via kubecolor, falls back to plain kubectl if missing
if command -v kubecolor >/dev/null 2>&1; then
  alias kubectl='kubecolor'
  compdef kubecolor=kubectl
fi
alias k='kubectl'
compdef k=kubectl
alias kgs='kubectl get svc'
alias kp='k get po,svc,endpoints,endpointslices.discovery.k8s.io -o wide -A'
alias kpn='k get po,svc,endpoints,endpointslices.discovery.k8s.io -o wide'
alias kev='k get events -A | grep Warning'
alias keva='k get events -A'
alias kevn='k get events | grep Warning'
alias kevan='k get events'

# Full-namespace overview: workloads + ingress + config + storage + autoscaling
alias ko='k get all,ingress,cm,secret,pvc,hpa -o wide'
alias koa='k get all,ingress,cm,secret,pvc,hpa -o wide -A'

# Pod watch (live, current namespace / all namespaces)
alias kpw='k get po -o wide -w'
alias kpwa='k get po -o wide -w -A'

# General-purpose shortcuts
alias kd='k describe'
alias kl='k logs -f'
alias klp='k logs -f -p'                    # previous container instance, useful after a crash/restart
alias kaf='k apply -f'
alias kdf='k delete -f'
alias kgn='k get nodes -o wide'
alias ktop='kubectl top pods --containers --sort-by=memory'
alias ktopn='k top nodes'
alias kgns='k config view --minify -o jsonpath="{..namespace}"; echo'   # show namespace set by kcontext

# CRD inspection — fast reads without leaving the terminal
alias kcrd='k get crd'
alias kcrdw='k get crd -o wide'
kcrdy() { k get crd "$1" -o yaml | less }    # full CRD definition
kexp() { k explain "$1" --recursive }        # fast schema read for any resource/CRD, e.g. `kexp pod.spec`

# Interactive resource creation — prompts for name/image/namespace/etc, then
# lets you run it, drop into an editor on the generated YAML first, or bail.
_kwizard_run() {
  local cmd="$1"
  echo "+ $cmd"
  read "choice?[r]un / [e]dit yaml first / [c]ancel? "
  case "$choice" in
    r|R)
      eval "$cmd" ;;
    e|E)
      local tmpfile
      tmpfile=$(mktemp /tmp/k-wizard-XXXX.yaml)
      eval "$cmd --dry-run=client -o yaml" > "$tmpfile"
      "${EDITOR:-vim}" "$tmpfile"
      k apply -f "$tmpfile"
      rm -f "$tmpfile" ;;
    *)
      echo "cancelled" ;;
  esac
}

# wizard: create a pod (prompts for name/image/ns/port; run, edit YAML, or cancel)
knewpod() {
  local name image ns port cmd
  read "name?Pod name: "
  read "image?Image (e.g. nginx:latest): "
  read "ns?Namespace (blank = current context): "
  read "port?Container port to expose (blank = skip): "
  cmd="k run $name --image=$image"
  [[ -n "$ns" ]] && cmd+=" -n $ns"
  [[ -n "$port" ]] && cmd+=" --port=$port"
  _kwizard_run "$cmd"
}

# wizard: create a deployment (prompts; run, edit YAML, or cancel)
knewdeploy() {
  local name image ns replicas port cmd
  read "name?Deployment name: "
  read "image?Image (e.g. nginx:latest): "
  read "ns?Namespace (blank = current context): "
  read "replicas?Replicas (blank = 1): "
  read "port?Container port to expose (blank = skip): "
  cmd="k create deployment $name --image=$image --replicas=${replicas:-1}"
  [[ -n "$ns" ]] && cmd+=" -n $ns"
  [[ -n "$port" ]] && cmd+=" --port=$port"
  _kwizard_run "$cmd"
}

# wizard: create a job (prompts; run, edit YAML, or cancel)
knewjob() {
  local name image ns cmd
  read "name?Job name: "
  read "image?Image (e.g. busybox): "
  read "ns?Namespace (blank = current context): "
  cmd="k create job $name --image=$image"
  [[ -n "$ns" ]] && cmd+=" -n $ns"
  _kwizard_run "$cmd"
}

# wizard: pick pod / deployment / job, then prompts for the rest
knew() {
  local kind
  read "kind?Create what? (pod/deployment/job): "
  case "$kind" in
    pod|p) knewpod ;;
    deploy*|d) knewdeploy ;;
    job|j) knewjob ;;
    *) echo "Unknown kind: '$kind' — expected pod, deployment, or job" ;;
  esac
}

command -v helm >/dev/null && source <(helm completion zsh)

# --- k8s core shortcuts (kd/kl/klp/ktop/kev already defined above) ---
alias kg='kubectl get'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgpw='kubectl get pods -o wide -w'
alias kgno='kubectl get nodes -o wide'
alias kx='kubectl exec -it'
alias ke='kubectl edit'
alias kevf='kubectl events --for'           # kev is taken (warnings, all ns); kevf pod/foo
alias ka='kubectl apply -f'
alias kk='kubectl apply -k'
alias kdiff='kubectl diff -f'
alias kdel='kubectl delete'
alias kdry='kubectl create --dry-run=client -o yaml'
alias kctx='kubectl ctx'                    # krew ctx/ns plugins, no kubectx binary installed
alias kns='kubectl ns'
alias h=helm
alias hls='helm list -A'
alias fx=flux
# h/fx completion lives at the bottom, after the final compinit (it resets compdefs)

# `command kubectl` below bypasses the kubecolor alias so piped output stays plain.

# shell into the first pod whose name matches; extra args pass through: kbash api -n my-ns
kbash() {
  local pod
  pod=$(command kubectl get pod -o name "${@:2}" | grep -m1 -- "$1") || { echo "no pod matching '$1'" >&2; return 1; }
  command kubectl exec -it "$pod" "${@:2}" -- sh -c 'command -v bash >/dev/null && exec bash || exec sh'
}

# fuzzy-pick a pod and tail it: klf [-n ns]
klf() {
  local pod
  pod=$(command kubectl get pods -o name "$@" | fzf) || return
  command kubectl logs -f --all-containers "$pod" "$@"
}

# decode every key of a secret: ksec my-secret [-n ns]
ksec() { command kubectl get secret "$@" -o go-template='{{range $k,$v := .data}}{{$k}}={{$v|base64decode}}{{"\n"}}{{end}}' }

# the real "get all": every namespaced kind, including custom resources: kgall [ns]
kgall() {
  command kubectl api-resources --verbs=list --namespaced -o name \
    | xargs -n1 kubectl get --show-kind --ignore-not-found ${1:+--namespace=$1}
}

# who owns this? ownership tree via krew tree plugin: kwho deploy web
kwho() { kubectl tree "$@" }

# port-forward in the background and print the URL: kpf svc/grafana 3000:80 [-n ns]
kpf() {
  local ports=${@[(r)[0-9]*]}
  command kubectl port-forward "$@" >/dev/null 2>&1 &!
  echo "http://localhost:${ports%%:*}"
}

# throwaway debug pod with network tools
knet() { command kubectl run -it --rm net-$RANDOM --image=nicolaka/netshoot --restart=Never -- bash }

kcontext() { k config set-context --current --namespace "$@" }   # set the default namespace: kcontext my-ns
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"                  # krew (kubectl plugin manager)
compdef h=helm 2>/dev/null
(( $+commands[flux] )) && source <(flux completion zsh) && compdef fx=flux
