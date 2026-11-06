# ~/.zsh/cloud.zsh — Google Cloud (gx*/g*) and Terraform (tf*). Guide: guides/gcloud-a-to-z.md

# === Google Cloud ===
# Names avoid oh-my-zsh git aliases (gcl, gcs, gst, gcp, gke are taken).
if (( $+commands[gcloud] )); then
  alias gx='gcloud'
  alias gcfg='gcloud config configurations list'
  alias gauth='gcloud auth login --update-adc'           # google login: regular + application (ADC), one browser trip
  alias gadc='gcloud auth application-default login'     # google login: application only (ADC: Terraform, SDKs)
  alias glogin='gcloud auth login'                       # google login: regular only (gcloud/kubectl CLI)
  alias gvms="gcloud compute instances list --format='table(name,zone.basename(),status,machineType.basename(),networkInterfaces[0].networkIP:label=INTERNAL_IP,scheduling.provisioningModel:label=MODEL)'"
  alias gkel="gcloud container clusters list --format='table(name,location,currentMasterVersion,currentNodeCount,status)'"
  alias garl="gcloud artifacts repositories list --format='table(name.basename(),format,name.segment(3):label=LOCATION,sizeBytes.size(units_out=G):label=GB)'"
  alias gsl='gcloud storage ls'
  alias gsm='gcloud secrets list'
  # stop impersonating, whether gimp (env) or `gcloud config set` started it
  gimpoff() { unset CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT; gcloud config unset auth/impersonate_service_account 2>/dev/null }

  # who am I, where am I: account, project, region, impersonation, kube context
  gwho() {
    gcloud config list --format='table[box](core.account,core.project,compute.region,auth.impersonate_service_account)' 2>/dev/null
    echo "kube: $(command kubectl config current-context 2>/dev/null || echo none)"
  }

  # switch project; no argument = fuzzy-pick from the projects you can see
  gpj() {
    local p=${1:-$(gcloud projects list --format='value(projectId)' | fzf --prompt='project> ')}
    [[ -n $p ]] && gcloud config set project "$p"
  }

  # switch named configuration (account + project + region bundle); no arg = pick
  gcon() {
    local c=${1:-$(gcloud config configurations list --format='value(name)' | fzf --prompt='config> ')}
    [[ -n $c ]] && gcloud config configurations activate "$c"
  }

  # --- cross-project inventory -------------------------------------------
  # VMs and clusters from every project you can see, cached for 12h in
  # ~/.cache/gx, so gssh/gkec/gtun/gvmon/gvmoff find a name whatever project is
  # active. A name that isn't cached triggers one refresh. gxr refreshes now.
  _GX_CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/gx

  _gx_projects() {
    local f=$_GX_CACHE/projects
    [[ -n $(find $f -mmin -720 2>/dev/null) ]] || { mkdir -p $_GX_CACHE; gcloud projects list --format='value(projectId)' >| $f }
    command cat $f
  }

  # _gx_inv vms|clusters [refresh]: "project<TAB>name<TAB>zone-or-location<TAB>status"
  _gx_inv() {
    local kind=$1 f=$_GX_CACHE/$1.tsv p tmp
    if [[ -n $2 || -z $(find $f -mmin -720 2>/dev/null) ]]; then
      mkdir -p $_GX_CACHE; tmp=$(mktemp -d)
      for p in $(_gx_projects); do
        if [[ $kind == vms ]]; then
          gcloud compute instances list --project $p --format="value[separator='	'](name,zone.basename(),status)" 2>/dev/null >| $tmp/$p &
        else
          gcloud container clusters list --project $p --format="value[separator='	'](name,location,status)" 2>/dev/null >| $tmp/$p &
        fi
      done
      wait
      for p in $tmp/*(N); do sed "s/^/${p:t}	/" $p; done >| $f
      rm -rf $tmp
    fi
    command cat $f
  }

  gxr() { rm -f $_GX_CACHE/*(N); _gx_inv vms >/dev/null; _gx_inv clusters >/dev/null; echo "cached: $(wc -l < $_GX_CACHE/vms.tsv) VMs, $(wc -l < $_GX_CACHE/clusters.tsv) clusters" }

  # _gx_pick vms|clusters [name] → "name zone project"; fzf when no name or ambiguous
  _gx_pick() {
    local kind=$1 name=$2 rows
    _gx_sel() {
      # GKE node VMs are reachable by exact name but kept out of the picker
      if [[ -n $name ]]; then _gx_inv $kind $1 | awk -F'\t' -v n="$name" '$2==n'
      else _gx_inv $kind $1 | awk -F'\t' '$2 !~ /^gke-/'; fi
    }
    rows=$(_gx_sel)
    [[ -z $rows && -n $name ]] && rows=$(_gx_sel refresh)
    [[ -z $rows ]] && { echo "no ${kind%s} named '$name' in any project (gxr to refresh)" >&2; return 1 }
    local -a lines=(${(f)rows})
    (( $#lines > 1 )) && rows=$(print -r -- $rows | column -t -s $'\t' | fzf --prompt="${kind%s}> " | awk '{print $1"\t"$2"\t"$3}')
    [[ -z $rows ]] && return 1
    print -r -- $rows | awk -F'\t' '{print $2, $3, $1}'
  }

  # ssh through IAP, any project: gssh [vm] [-- remote cmd]
  gssh() {
    local vm; vm=($(_gx_pick vms "$1")) || return; shift 2>/dev/null
    gcloud compute ssh "${vm[1]}" --zone "${vm[2]}" --project "${vm[3]}" --tunnel-through-iap "$@"
  }

  # copy through IAP: gscp ./file vm:/tmp/   (or vm:/path ./); VM looked up in any project
  gscp() {
    local a vmname vm
    for a in "$@"; do [[ $a == [^/.]*:* ]] && { vmname=${a%%:*}; break }; done
    if [[ -n $vmname ]] && vm=($(_gx_pick vms "$vmname")); then
      gcloud compute scp --tunnel-through-iap --recurse --zone "${vm[2]}" --project "${vm[3]}" "$@"
    else
      gcloud compute scp --tunnel-through-iap --recurse "$@"
    fi
  }

  # forward a VM port to localhost through IAP: gtun vm 8080 [local-port]
  gtun() {
    local vm; vm=($(_gx_pick vms "$1")) || return
    gcloud compute start-iap-tunnel "${vm[1]}" "$2" --zone "${vm[2]}" --project "${vm[3]}" --local-host-port="localhost:${3:-$2}"
  }

  gvmon()  { local vm; vm=($(_gx_pick vms "$1")) || return; gcloud compute instances start "${vm[1]}" --zone "${vm[2]}" --project "${vm[3]}" }
  gvmoff() { local vm; vm=($(_gx_pick vms "$1")) || return; gcloud compute instances stop  "${vm[1]}" --zone "${vm[2]}" --project "${vm[3]}" }

  # every VM / cluster you can see, across projects (cached; gxr refreshes)
  gvmsa() { _gx_inv vms      | column -t -s $'\t' -N PROJECT,NAME,ZONE,STATUS }
  gkela() { _gx_inv clusters | column -t -s $'\t' -N PROJECT,NAME,LOCATION,STATUS }

  # GKE credentials, any project; no arg = pick. Extra flags pass through (--dns-endpoint)
  gkec() {
    local c; c=($(_gx_pick clusters "$1")) || return
    gcloud container clusters get-credentials "${c[1]}" --location "${c[2]}" --project "${c[3]}" "${@:2}"
  }

  # kube contexts whose GKE cluster no longer exists; --delete removes them
  gkestale() {
    local live ctx p l n stale=()
    live=$(_gx_inv clusters refresh | awk -F'\t' '{print $1"_"$3"_"$2}')
    for ctx in $(command kubectl config get-contexts -o name); do
      [[ $ctx == (gke|connectgateway)_* ]] || continue
      [[ $ctx == connectgateway_* ]] && { stale+=($ctx); continue }   # fleet: checked below
      grep -qxF "${ctx#gke_}" <<<"$live" || stale+=($ctx)
    done
    for ctx in ${(M)stale:#connectgateway_*}; do
      p=${${ctx#connectgateway_}%%_*}; n=${ctx##*_}
      gcloud container fleet memberships list --project $p --format='value(name.basename())' 2>/dev/null | grep -qx $n && stale=(${stale:#$ctx})
    done
    (( ${#stale} )) || { echo "no stale contexts"; return }
    print -l -- $stale
    if [[ $1 == --delete ]]; then
      for ctx in $stale; do command kubectl config delete-context $ctx; done
    else
      echo "(${#stale} stale; run 'gkestale --delete' to remove them)"
    fi
  }

  # GKE operations still running (upgrades, resizes); cancel with gcloud container operations cancel ID
  gkeops() { gcloud container operations list --filter='status!=DONE' --format='table(name,operationType,targetLink.basename(),location,startTime.date())' "$@" }

  # run any command against another project, by unique prefix: gin my-proj gvms
  gin() {
    local p m; m=(${(M)${(f)"$(_gx_projects)"}:#$1*})
    case ${#m} in
      1) p=$m[1] ;;
      0) echo "no project matching '$1*'" >&2; return 1 ;;
      *) p=$(print -l $m | fzf --prompt='project> ') || return ;;
    esac
    shift
    # aliases (gvms, garl, gsm…) don't expand in argument position; expand by hand
    if (( $+aliases[$1] )); then
      ( export CLOUDSDK_CORE_PROJECT=$p; eval "${aliases[$1]} ${(q@)@[2,-1]}" )
    else
      CLOUDSDK_CORE_PROJECT=$p "$@"
    fi
  }

  # grant a role without the interactive condition prompt: gbind PROJECT MEMBER ROLE
  gbind() {
    [[ $# -eq 3 ]] || { echo "usage: gbind PROJECT user:you@example.com|group:…|serviceAccount:… roles/…" >&2; return 1 }
    gcloud projects add-iam-policy-binding "$1" --member="$2" --role="$3" --condition=None --format='value(etag)' >/dev/null && echo "granted $3 to $2 on $1"
  }

  # docker login for Artifact Registry in a region (default: your compute/region)
  garauth() { gcloud auth configure-docker "${1:-$(gcloud config get compute/region 2>/dev/null)}-docker.pkg.dev" }

  # images (with tags) in a repo: gart REGION-docker.pkg.dev/PROJECT/REPO
  gart() { gcloud artifacts docker images list "$1" --include-tags --format='table(package.basename(),tags,createTime.date())' "${@:2}" }

  # read a secret's latest version: gsmget NAME [version]
  gsmget() { gcloud secrets versions access "${2:-latest}" --secret "$1" }

  # readable logs: glogs 'resource.type="k8s_container" severity>=ERROR' [1h]
  glogs() {
    gcloud logging read "$1" --freshness="${2:-1h}" --order=desc --limit="${3:-50}" \
      --format='table(timestamp.date("%H:%M:%S"),severity,resource.labels.container_name,textPayload,jsonPayload.message)'
  }

  # my roles on the current project (or a given one): giam [project] [member]
  giam() {
    local p=${1:-$(gcloud config get project 2>/dev/null)} m=${2:-user:$(gcloud config get account 2>/dev/null)}
    gcloud projects get-iam-policy "$p" --flatten='bindings[].members' \
      --filter="bindings.members:$m" --format='value(bindings.role)'
  }

  # run gcloud as a service account for this shell only: gimp SA_EMAIL
  gimp() { export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT="$1"; echo "impersonating $1 (unset with: unset CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT)" }

fi

# === Terraform ===
if (( $+commands[terraform] )); then
  alias tf='terraform'
  alias tfi='terraform init'
  alias tfp='terraform plan'
  alias tfa='terraform apply'
  alias tfo='terraform output'
  alias tfv='terraform validate'
  alias tff='terraform fmt -recursive'
  alias tfs='terraform state list'
fi
