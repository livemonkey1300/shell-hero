# ~/.zsh/docker.zsh — Docker and Compose shortcuts. Guide: guides/docker-a-to-z.md
(( $+commands[docker] )) || (( $+commands[podman] )) || return 0

# === Docker Compose ===
alias dc='docker compose'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias dcr='docker compose restart'
alias dcl='docker compose logs -f'
alias dcp='docker compose pull'
alias dcps='docker compose ps'
alias dcb='docker compose build'
alias dcex='docker compose exec'

# === Docker ===
alias dps='docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dpsa='docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dlogs='docker logs -f'
alias dstats='docker stats --no-stream'
alias dprune='docker system prune -f'
alias dinspect='docker inspect'
alias dexec='docker exec -it'
alias dimages='docker images'
alias d='docker'
alias di='docker images'
alias dex='docker exec -it'
alias dcud='docker compose up -d'
alias dnet='docker network ls'
alias dvol='docker volume ls'

# Docker cleanup — hung containers and stale networks
# List anything wedged: dead, mid-removal, or created-but-never-started
alias dhung='docker ps -a --filter status=dead --filter status=removing --filter status=created --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"'
# Force-remove those wedged containers (needs `drestart` if one is truly stuck in the daemon)
alias dhungrm='docker rm -f $(docker ps -aq --filter status=dead --filter status=removing --filter status=created) 2>/dev/null || echo "no hung containers"'
alias dstopall='docker stop -t 3 $(docker ps -q) 2>/dev/null || echo "nothing running"'
alias drmall='docker rm -f $(docker ps -aq) 2>/dev/null || echo "no containers"'
# Networks: prune unused, then the sledgehammer for "network has active endpoints"
alias dnetflush='docker network prune -f'
alias drestart='sudo systemctl restart docker.service'
# Everything at once: kill wedged containers, drop stale networks, prune the rest
alias dflush='docker rm -f $(docker ps -aq --filter status=dead --filter status=removing --filter status=created) 2>/dev/null; docker network prune -f; docker system prune -f'

# Force-flush a docker network that refuses to go away because endpoints are
# still attached. With no argument, does every user-defined network.
dnetforce() {
  local nets
  if [[ -n "$1" ]]; then
    nets=("$@")
  else
    nets=(${(f)"$(docker network ls --format '{{.Name}}' | grep -vxE 'bridge|host|none')"})
  fi
  local net ep
  for net in $nets; do
    for ep in ${(f)"$(docker network inspect "$net" --format '{{range $k, $v := .Containers}}{{$k}}
{{end}}' 2>/dev/null)"}; do
      [[ -n "$ep" ]] && docker network disconnect -f "$net" "$ep" 2>/dev/null
    done
    docker network rm "$net" 2>/dev/null && echo "removed network $net"
  done
  docker network prune -f
}
