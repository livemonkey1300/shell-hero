# Guides

A personal DevOps learning library: cheatsheets and long-form manuals on the shell, Git and GitLab, Docker, Kubernetes, Helm, Tilt, CI, Linux security, Bazel and Google Cloud. Everything here is generic. Names such as `my-project`, `myapp`, `example.com` and `registry.example.com/team/app` are placeholders, so swap in your own.

Most topics come in two sizes:

- **A→Z**: one route through the topic, short enough to read in a sitting, then useful as a cheat sheet.
- **Field manual**: the long reference, with every recommendation, the traps, version notes and the reasons behind each default. Read it a chapter at a time, or search it when you need something.

Reading times assume about 200 words a minute. Technical text with commands to try takes longer.

## Index

| Guide | What it covers | Reading time | Size / pairing |
|---|---|---|---|
| [linux-command-helper.md](./linux-command-helper.md) | Shell aliases, finding files, processes, network and log investigation, git speed commands, Docker Compose debugging | ~10 min | Cheatsheet |
| [git-gitlab-a-to-z.md](./git-gitlab-a-to-z.md) | Git's object model, daily loop, rewriting history, recovery, glab and the GitLab API | ~45 min | A→Z, pairs with the field manual below |
| [git-gitlab-field-manual.md](./git-gitlab-field-manual.md) | The full Git and GitLab reference: config, history surgery, leaked secrets, tokens, MR and pipeline automation | ~3.5 h | Field manual |
| [docker-a-to-z.md](./docker-a-to-z.md) | Containers from first principles to hardened, scanned, signed stacks; Podman equivalents | ~45 min | A→Z, pairs with the field manual below |
| [docker-field-manual.md](./docker-field-manual.md) | BuildKit and bake, Compose, networking and SELinux on Fedora, hardening, supply chain, troubleshooting | ~4 h | Field manual |
| [kubernetes-cheatsheet.md](./kubernetes-cheatsheet.md) | Day-to-day `kubectl`: aliases, inspecting, logs, exec, port-forward, debugging | ~10 min | Cheatsheet |
| [kubernetes-field-manual.md](./kubernetes-field-manual.md) | Build, ship, debug, harden and air-gap: images, dev clusters, Helm, Kustomize, GitOps, security audit, day-2 ops | ~3 h | Field manual |
| [helm-cheatsheet.md](./helm-cheatsheet.md) | Helm commands for installing, upgrading, templating and debugging charts | ~5 min | Cheatsheet |
| [tilt-helm-kind.md](./tilt-helm-kind.md) | A fast local loop: Tilt building images into kind and deploying through your real Helm chart | ~5 min | Cheatsheet |
| [k8s-native-dev-and-debug.md](./k8s-native-dev-and-debug.md) | Inner-loop tools (Tilt, Skaffold, DevSpace, Telepresence), linting Kubernetes artefacts, attaching debuggers to pods | ~10 min | Cheatsheet |
| [lint-ci-a-to-z.md](./lint-ci-a-to-z.md) | Linters, formatters, pre-commit hooks, branch naming, GitLab CI pipelines and releases | ~45 min | A→Z, pairs with the field manual below |
| [lint-ci-branching-field-manual.md](./lint-ci-branching-field-manual.md) | Lint, format, hooks, branching strategies, merge policy, pipeline design and speed, deploys, CI debugging | ~4 h | Field manual |
| [linux-security-a-to-z.md](./linux-security-a-to-z.md) | Hardening a Linux host: accounts, SSH, firewall, SELinux, auditd, scanning, incident triage, Canadian compliance | ~1 h | A→Z, pairs with the field manual below |
| [linux-security-field-manual.md](./linux-security-field-manual.md) | The full reference, including ITSG-33 / ITSP.10.033, CPCSC, Protected B, container and Kubernetes audits, and evidence collection | ~6 h | Field manual |
| [bazel-field-manual.md](./bazel-field-manual.md) | Bazel 9: Bzlmod, BUILD files, language rules, remote cache and execution, GitLab CI, images, writing rules, adoption | ~4 h | Field manual (no A→Z) |
| [gcloud-a-to-z.md](./gcloud-a-to-z.md) | The `gcloud` CLI: auth and configurations, IAM, VMs over IAP, GKE, Artifact Registry, Secret Manager, logging, Terraform, cost | ~35 min | A→Z (no field manual) |

## Suggested learning order

For someone getting into DevOps. Start each step with the short guide; go to the field manual only when you need depth.

1. **Shell**: [linux-command-helper.md](./linux-command-helper.md). Everything else assumes you can find a file, a process and a port quickly.
2. **Git**: [git-gitlab-a-to-z.md](./git-gitlab-a-to-z.md), then dip into [the field manual](./git-gitlab-field-manual.md) for recovery and GitLab automation.
3. **Docker**: [docker-a-to-z.md](./docker-a-to-z.md). Images and containers are the unit that every later step ships.
4. **Kubernetes**: [kubernetes-cheatsheet.md](./kubernetes-cheatsheet.md) to get moving, then chapters 01–03 and 11 of [the field manual](./kubernetes-field-manual.md) (the model, daily `kubectl`, and when it breaks).
5. **Helm and Tilt**: [helm-cheatsheet.md](./helm-cheatsheet.md), [tilt-helm-kind.md](./tilt-helm-kind.md), then [k8s-native-dev-and-debug.md](./k8s-native-dev-and-debug.md) for a working local inner loop.
6. **CI**: [lint-ci-a-to-z.md](./lint-ci-a-to-z.md). Hooks, branching and pipelines tie the earlier steps together.
7. **Security**: [linux-security-a-to-z.md](./linux-security-a-to-z.md), then the container and Kubernetes chapters (15, 16) of [the field manual](./linux-security-field-manual.md).
8. **Optional**: [bazel-field-manual.md](./bazel-field-manual.md) if you work in a large polyglot monorepo, and [gcloud-a-to-z.md](./gcloud-a-to-z.md) if you run on Google Cloud.

## Notes

- The guides target Fedora first, with Debian and Ubuntu equivalents where tools differ. Versions are noted where they matter; check `--help` when a tool has moved on.
- The shell shortcuts in some guides (for example the `g*` Google Cloud helpers in the gcloud guide) are meant for your own `~/.zshrc`; the guide includes their source.
- The Canadian compliance material (ITSG-33, ITSP.10.033 and .171, CPCSC, Protected B, TBS timelines) summarizes public Government of Canada standards. Check the official sources before you rely on it.
