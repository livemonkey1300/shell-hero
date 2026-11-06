# Linux Security Field Manual

> harden · confine · audit · detect · respond · comply
> Generated 2026-09-23.

## Contents

- 00 · [Every recommendation, one page](#00-every-recommendation-one-page)
- 01 · [Threat model and layers](#01-threat-model-and-layers)
- 02 · [Accounts, sudo and PAM](#02-accounts-sudo-and-pam)
- 03 · [SSH hardening](#03-ssh-hardening)
- 04 · [Firewall and network exposure](#04-firewall-and-network-exposure)
- 05 · [SELinux in practice](#05-selinux-in-practice)
- 06 · [Kernel, boot and systemd](#06-kernel-boot-and-systemd)
- 07 · [Baseline audits: Lynis and OpenSCAP](#07-baseline-audits-lynis-and-openscap)
- 08 · [auditd and the journal](#08-auditd-and-the-journal)
- 09 · [File integrity and malware scanning](#09-file-integrity-and-malware-scanning)
- 10 · [Ban, block and detect at runtime](#10-ban-block-and-detect-at-runtime)
- 11 · [Exposure and vulnerability visibility](#11-exposure-and-vulnerability-visibility)
- 12 · [Incident response triage](#12-incident-response-triage)
- 13 · [Canadian requirements, mapped to settings](#13-canadian-requirements-mapped-to-settings)
- 14 · [Auditing permissions and privilege](#14-auditing-permissions-and-privilege)
- 15 · [Container hardening, from the inside](#15-container-hardening-from-the-inside)
- 16 · [Kubernetes security audit and hardening](#16-kubernetes-security-audit-and-hardening)
- 17 · [Running an audit end to end](#17-running-an-audit-end-to-end)

---


<a id="00-every-recommendation-one-page"></a>

## 00 · Every recommendation, one page

*Every default this manual picks, with the reason, in one place. Hardening is mostly a sequence problem: the order you apply controls decides whether you finish with a safer box or a locked-out one.*

### How to read this page

Every table row is a default: what to use when you have no specific reason to choose otherwise. Where a row says **close call**, the alternative is genuinely defensible and the tiebreaker is named. Where a row says **one-way door**, getting it wrong costs more than a revert.

The guide is Fedora/RHEL first. Debian/Ubuntu equivalents appear inline where the tool differs (AppArmor for SELinux, `ufw` or raw nftables for firewalld, `unattended-upgrades` for `dnf-automatic`). The mechanism underneath (nftables, auditd, PAM, systemd, OpenSSH) is the same on both families, which is why most of this page applies to either.

> **Note.** Chapters 00–06 cover the model and hardening. Chapters 07–12 cover audit (07 Lynis and OpenSCAP, 08 auditd, 09 file integrity), runtime prevention and detection (10), vulnerability and exposure visibility (11), and incident response (12). Chapters 13–17 turn all of it into compliance evidence: Canadian requirements mapped to settings (13), auditing permissions and privilege (14), container hardening from the inside (15), Kubernetes security audit and hardening (16), and running an audit end to end (17).

### The default tool per job

| Job | Pick | Why | Chapter |
|---|---|---|---|
| Hardening baseline | **scap-security-guide** CIS Level 1 Server profile, scanned with `oscap` | Machine-checkable, ships remediation (Bash and Ansible) per rule, maps to the compliance frameworks auditors ask for. Already packaged: `scap-security-guide` on Fedora/RHEL, `ssg-debian*`/`ssg-ubuntu*` content for Debian-family. Record it as the `CM-06` organization-defined values, with the version the profile implements | 07, 13 |
| Quick host audit | **Lynis** (`lynis audit system`) | Agentless, runs as a user for a partial view, no content files to keep current. Finds the obvious gaps in two minutes; it is a to-do list, not a compliance report | 07 |
| Firewall (single host) | **firewalld** (nftables backend) | Zones plus NetworkManager integration mean an interface moving networks changes policy without a script. Runtime/permanent split gives you a free undo. Raw **nftables** when the box is a router, a Kubernetes node, or needs sets and maps firewalld cannot express | 04 |
| Firewall (Debian/Ubuntu) | **raw nftables** with `/etc/nftables.conf` | `ufw` still drives iptables-nft through a translation layer and hides the ruleset you debug. One nft file under Git is readable and diffable | 04 |
| MAC | **SELinux, enforcing, targeted policy** | It already confines every network-facing daemon in the distro policy; turning it off removes the only control that stops a compromised daemon reading files its UID can read. AppArmor on Ubuntu, for the same reason | 05 |
| Privilege escalation | **sudo with per-role files in `/etc/sudoers.d/`**, `visudo -cf` in CI | Named commands, logged per invocation, reviewable in Git. `run0` (systemd 256+) is promising but has no rule language yet | 02 |
| Remote access | **OpenSSH, keys only, FIDO2 (`ed25519-sk`) for humans, SSH certificates past ~10 hosts** | Hardware-backed keys cannot be copied off a laptop. Certificates replace `authorized_keys` sprawl with one CA line and expiry | 03 |
| SSH brute force | **key-only auth + `PerSourcePenalties`** (OpenSSH 9.8+, on by default) | Password guessing against key-only auth is noise, not risk. fail2ban only for services that still accept passwords | 03, 10 |
| Audit logging | **auditd** with a lean starter ruleset (chapter 08), borrowing from the distro's `/usr/share/audit-rules/` | Kernel-level, tamper-evident with `-e 2`, understood by every SIEM. Start lean (`10-base-config`, `11-loginuid`, `43-module-load` plus the chapter 08 starter rules) and measure; the full `30-stig` set is heavy and floods build hosts | 08 |
| File integrity | **AIDE** | Packaged everywhere, database-and-compare model that is easy to reason about. The database must live off-host or be signed, or an attacker updates it | 09 |
| Intrusion prevention (network) | **fail2ban** on the firewalld backend, for password-auth services only | Parses logs and inserts firewall bans. Useless against a distributed attack and redundant for key-only SSH | 10 |
| Vulnerability scanning (host) | **`dnf updateinfo list --security`** plus OpenSCAP OVAL | The distro's own advisory data is authoritative for distro packages; third-party scanners guess from version strings and miss backports | 06, 07 |
| Vulnerability scanning (images), CI gate | **Trivy**, `--severity HIGH,CRITICAL --ignore-unfixed` | Images are where the unpatched userland actually lives on a container host. Same gate as the Kubernetes manual. On Fedora hosts themselves, OS package fixes come from `dnf advisory` (Trivy has no Fedora data, and Fedora advisories carry no CVE IDs). **The split is deliberate:** Trivy gates the pipeline and checks misconfiguration; Grype produces the audit record (image-evidence row below) because the Vulnerability Management Process already runs it | 11 |
| Secrets on a single host | **systemd credentials** (`LoadCredentialEncrypted=`, `systemd-creds encrypt`) | Encrypted at rest, bound to the TPM2 or host key, delivered to one unit in a private tmpfs, never in the environment or `ps` output | 06 |
| Secrets across a fleet | **OpenBao** (or Vault) with short-lived leases | Rotation without redeploy, per-host identity, audit trail. sops+age only for secrets that must live in Git | 06 |
| Disk encryption | **LUKS2**, TPM2 unlock via `systemd-cryptenroll` bound to PCR 7, plus a recovery key | Unattended boot without a key on disk; the recovery key is the plan for firmware updates that change PCRs | 06 |
| Service sandboxing | **systemd directives**, scored with `systemd-analyze security` | Free, already on the box, and each directive is one line that a reviewer can understand | 06 |
| Automatic updates | **dnf-automatic** (dnf5 plugin), apply on, reboot `when-needed` in a window. `upgrade_type = security` on RHEL-family; `default` on Fedora, where the packager picks each update's advisory type and a CVE fix filed as `bugfix` is skipped by `security` | An unpatched kernel is the most common real-world root. Debian/Ubuntu: `unattended-upgrades` | 06 |
| Fleet visibility | **journald + audit logs shipped off-host** (Grafana Alloy to Loki, or rsyslog to the SIEM) | Logs that stay on a compromised host are the attacker's logs. osquery on top only when you need to ask ad hoc questions across hosts | 08, 11 |
| Incident response | **Isolate at the network, snapshot, then investigate a copy** | Killing processes and rebooting destroys the memory and `/proc` state you needed | 12 |
| Compliance baseline | **ITSP.10.033-01 Medium, tailored**, as the named profile; CIS Level 1 Server as the host `CM-06` values; STIG only when a contract names it | Medium is the direct successor to PBMM, which Protected B candidate data implies. The profile leaves most values blank, so the benchmark supplies the numbers. CCCS names CIS first | 13 |
| Crypto (Protected B) | **`FIPS` crypto policy on RHEL**, FIPS mode decided at image build | The only shipped policy that restricts symmetric ciphers to AES (ITSP.40.111), and RHEL's OpenSSL module has a CMVP certificate. Fedora's modules are not validated, so a Fedora base cannot claim the CMVP requirement | 13 |
| Log retention | **Set at the log host**: 3 months online, 6 months stored, 2 years for incident records (TBS) | Local `auditd.conf` rotation on a busy host is days, not months. An assessor wants the log host's config and an old event pulled from it | 13, 08 |
| Permission audit | **The read-only `perm-audit.sh`**, run as root, quarterly, output copied off-host and diffed against an off-host baseline | Covers what a benchmark scores badly: new sudo rules, root timers running user-editable scripts, polkit grants, ACLs, keys. `AC-06(07)` needs a written review frequency; quarterly is the pick | 14 |
| Container runtime | **Podman rootless** for anything that does not need a shared root daemon | A user namespace is the single largest reduction in blast radius, and rootful Docker does not give one by default. Rootless Docker when tooling insists on the Docker API | 15 |
| Container audit | **The read-only `container-audit.sh`**, plus docker-bench with **CIS Docker 1.6.0** as the baseline of record | Reads the kernel's view (`/proc`, `ps -Z`) as well as inspect output. docker-bench and Trivy both implement 1.6.0; carry the 1.8.0 delta as manual checks until the tools catch up | 15 |
| Image evidence | **Syft CycloneDX SBOM + Grype**, `cosign verify`, all keyed by digest | Grype is a common choice for a vulnerability management process, so its reports carry the SLA history. The SBOM is itself the SR evidence and can be re-scanned without touching the registry. A report keyed by tag proves nothing | 15, 17 |
| Kubernetes baseline | **CIS Kubernetes 2.0.1, measured by kube-bench** (`--benchmark cis-2.0`); STIG V2R6 overlay only when a contract names DISA STIGs | kube-bench is the only scanner that matches the benchmark version. No STIG scanner exists for upstream Kubernetes, so a STIG is a manual checklist you pay for only when required. Kubescape stays for the NSA/CISA and RBAC view | 16 |
| Kubernetes policy engine | **PSA `restricted` as the cluster default**, plus **Kyverno** on `policies.kyverno.io/v1` (`ValidatingPolicy`, `ImageValidatingPolicy`), `Audit` first | PSA is built in with no webhook that can fail open; do not rebuild it in Kyverno. Kyverno covers what PSA cannot (registry, digest pinning, signatures) and its policy reports are continuous `CM-06` evidence | 16 |
| etcd encryption | **KMS v2** where a production plugin exists; **`aesgcm`** with scripted rotation in the air gap | `aescbc` is "weak" per the Kubernetes docs and `secretbox` is not AES. Close call for the appliance: `aesgcm` now, or wait for an OpenBao KMS v2 plugin; the tiebreaker is whether control-plane host compromise is in scope for `SC-28` | 16 |
| Evidence pipeline | **`collect-evidence.sh` on a monthly systemd timer, plus a scheduled GitLab pipeline** for images, SBOMs and cluster posture; bundles sealed with SHA-256 and shipped off-host, kept 13 months minimum | One run, one bundle, one date, read-only. TBS asks for configuration checking monthly; Level 2 assessors want months of history, not a snapshot | 17 |
| POA&M due dates | **Your vulnerability management process (VMP) SLAs, with a Protected B uplift**, capped by the TBS timelines for anything in a DND contract's scope | Internal hard deadlines often exceed TBS for Critical, Medium and Low. "Detected" is the first-seen date, never reset | 13, 17 |

### The positions worth arguing about

These are opinions with reasons, not consensus. Overrule them deliberately, not by default.

| Position | Reason |
|---|---|
| **Never `setenforce 0` to fix a problem. Use `semanage permissive -a DOMAIN_t` instead.** | Per-domain permissive keeps every other daemon confined while you collect denials for the one you are debugging. Global permissive turns off the whole policy and people forget to turn it back on |
| **`audit2allow -M` is the last resort, not the fix.** | Nine times in ten the real fix is a file context (`semanage fcontext` + `restorecon`), a port label or a boolean. A generated module encodes whatever the attacker or the bug did into policy |
| **Stop tuning `MaxAuthTries` and installing fail2ban for key-only SSH.** | The keyspace makes online guessing irrelevant. Spend the effort on FIDO2 keys and certificates, which fix the real risk: a stolen private key |
| **Egress filtering on servers is worth the pain.** | Almost every post-exploitation step (payload fetch, C2, exfiltration) is an outbound connection. Default-deny egress on a server with five known destinations is a short allow-list |
| **Put your sshd drop-in at `10-`, not `99-`.** | sshd uses the *first* value it reads for most keywords. Fedora ships `40-redhat-crypto-policies.conf` and `50-redhat.conf`; a `99-hardening.conf` loses to them silently |
| **Configure SSH algorithms through crypto-policies on Fedora/RHEL, not in sshd_config.** | `update-crypto-policies --set DEFAULT:NO-SHA1` changes OpenSSH, OpenSSL, GnuTLS and NSS together. Hand-picked cipher lists drift from the rest of the system and break at the next OpenSSH release |
| **Leave IPv6 on and firewall it.** | Disabling IPv6 by sysctl breaks things in confusing ways (localhost resolution, some daemons refuse to start) and is often re-enabled by an update. firewalld and `inet` nftables tables cover both families in one rule |
| **Docker on a hardened host is a firewall exception, whether you like it or not.** | Published container ports are wired in by the container engine's own rules, which bypass firewalld zone input rules. Bind published ports to `127.0.0.1` or put the engine's traffic behind a policy |
| **CIS Level 1, not Level 2, as the starting baseline.** | Level 2 breaks things (separate partitions, USB storage off, aggressive audit rules that fill disks). Level 1 plus the targeted items you actually need is a baseline you can keep |
| **The hardest control to skip is automatic security updates.** | Every other control in this manual raises the bar for an attacker. A known kernel or sudo CVE with public exploit code lowers it to the floor |
| **Password aging (`PASS_MAX_DAYS`) off; length and breach checks on.** | Forced rotation produces `Summer2026!` then `Autumn2026!`. NIST SP 800-63B dropped periodic rotation for this reason |
| **"We follow ITSG-33" is not a configuration.** | The Medium profile leaves most placeholder values empty. Until a named profile and a named, versioned benchmark supply the numbers, every scan failure is an opinion rather than a finding |
| **Quote the benchmark version the tool implements, not the current one.** | SSG 0.1.82's CIS RHEL 9 profile is v2.0.0 while CIS is at v3.0.0; docker-bench checks CIS Docker 1.6.0 while CIS is at 1.8.0. An assessor checking against the newer version finds rules you never scanned for |
| **Use a tiered Kubernetes audit policy, not STIG V-242403's literal `RequestResponse` rule.** | The literal rule writes Secret values and bearer tokens into the log store. Record the tiered policy as a documented deviation |
| **Collection is read-only; remediation goes through config management.** | An evidence run that changes the system proves nothing about the system. The next bundle proves the fix |
| **Evidence stored on the host it describes is not evidence.** | Whoever compromises the host can rewrite it. Ship bundles, baselines and their hashes off-host, and record the hash somewhere separate from the file |

### Canadian compliance in one table

The requirements an assessor will raise, what to do about each, and where the manual covers it. Control IDs use the zero-padded ITSP.10.033 form (`AC-06`, not `AC-6`) and ITSP.10.171 Rev. 3 IDs (`03.01.01`) for CPCSC. **There is no official CCCS mapping from controls to Linux settings**; the settings are this manual's reading of control intent.

| Requirement | What to do | Chapter |
|---|---|---|
| ITSP.10.033 profile (was ITSG-33; Medium replaces PBMM) | Name ITSP.10.033-01 Medium, tailored, in the SSP. Request the profile spreadsheet from CCCS and build the control matrix from it | 13 |
| Organization-defined values (`CM-06`) | Name a versioned benchmark per layer: CIS Level 1 Server for hosts, CIS Docker 1.6.0 for container hosts, CIS Kubernetes 2.0.1 for clusters. STIG only when a contract names it | 13, 15, 16 |
| CMVP-validated crypto (ITSP.10.033-01 §3.1) | RHEL with the `FIPS` policy and FIPS mode set at install. A Fedora base cannot meet it; upstream Kubernetes binaries are an open item | 13, 16 |
| Algorithms and protocols (ITSP.40.111, ITSP.40.062) | AES only, no SHA-1 in signatures, RSA ≥ 2048, TLS 1.3 (1.2 where required). `DEFAULT` crypto policy fails (ChaCha20, Camellia). Kubernetes: TLS 1.2 minimum with the four STIG ECDHE AES-GCM suites | 13, 16 |
| CPCSC Level 1 (13 controls, live now) | Re-key the mapping from CMMC Rev. 2 to ITSP.10.171 Rev. 3 IDs. Annual self-assessment; keep evidence for the attestation cycle or at least one year | 13, 17 |
| CPCSC Level 2 (98 controls, contracts from spring 2027) | Write the SSP and boundary statement now, and start the monthly evidence history so there is a year of it | 17 |
| TBS log retention (`AU-11`) | 3 months online, 6 months stored, incidents 2 years, set at the log host. Logs tamper-protected (`AU-09`) and forwarded | 13, 08 |
| TBS patch timelines (`SI-02`, `03.14.01`) | Critical 48 h, High 14 d, Medium 30 d, Low 90 d. Use the stricter of TBS and your internal VMP for anything in a DND contract's scope | 13, 17 |
| TBS scan frequency (`RA-05`, `CA-07`) | Internal scanning weekly or after significant change, external monthly, configuration checking monthly and after changes | 13, 17 |
| Privilege review (`AC-06(07)`, `03.01.01`) | Write down a frequency (quarterly), a privileged-role list and the permitted SUID set; the permission audit is the evidence | 14 |
| Segmentation (ITSP.80.023) | One data sensitivity per kernel: separate hosts, or tainted node pools, for Protected B workloads | 13, 15, 16 |
| Boundary protection (`SC-07`, `03.13.01`) | Host firewall default deny; no `--network host`; default-deny NetworkPolicy in every namespace, shipped in the namespace template | 04, 15, 16 |
| Data at rest (`SC-28`) | LUKS2 on hosts; etcd with KMS v2 or `aesgcm`, never `secretbox` | 06, 16 |
| Event logging (`AU-02`, `AU-12`) | auditd rules on hosts and container engines; Kubernetes `--audit-policy-file` with the tiered policy | 08, 15, 16 |
| Supply chain (`SI-07`, SR family) | Signed images and an SBOM per digest, verified at media load and at admission. Record the missing signing gate as a POA&M item until it exists | 15, 16 |
| Authority to process IT (PSPC Contract Security Program) | IT security checklist and a data flow diagram, which the boundary statement also needs | 13, 17 |

### One-way doors

Everything else in this manual can be reverted with an edit and a reload. These cannot, or cost a console trip, a restore or a rebuild.

| Door | What it costs | Mitigation |
|---|---|---|
| **Disabling SELinux** (`SELINUX=disabled` or `selinux=0`) | Files created while disabled carry no labels. Re-enabling needs a full relabel (`touch /.autorelabel`, reboot, minutes to hours), and anything that went wrong while unconfined stays unknown | Use permissive, per domain, never disabled |
| **Locking yourself out over SSH** | A console trip, a cloud serial console, or a rescue boot. On a remote bare-metal box with no out-of-band management, a datacentre visit | Keep a root session open, test in a second session, `sshd -t` before every reload, make firewall changes runtime-only behind a `systemd-run` timer that runs `firewall-cmd --reload` |
| **LUKS header loss or corruption** | The data is unrecoverable. No passphrase, recovery key or TPM helps: the header holds the wrapped volume key | `cryptsetup luksHeaderBackup` to off-host storage right after creation and after every keyslot change |
| **Wiping the last working LUKS keyslot** | Same as header loss, instantly | Enrol the new factor, test unlock, then wipe the old slot. Never the other order |
| **auditd immutable mode (`-e 2`)** | Rules cannot be changed until reboot. A bad rule that floods the log or fills `/var` stays until a reboot you may not be able to schedule | Stage the rule set with `-e 1` for a week, then flip to `-e 2` |
| **`kernel.modules_disabled=1`** | No module can load until reboot, including the one a USB NIC or a new filesystem needs | Only on appliances whose hardware never changes |
| **Enrolling your own Secure Boot keys / removing Microsoft's** | Option ROMs on GPUs and NICs signed by Microsoft stop loading; some boards will not POST to a display | Use shim and MOK (`mokutil`) rather than replacing platform keys |
| **Sealing LUKS to many PCRs (0, 2, 4)** | Every firmware or bootloader update breaks unattended unlock, and without a recovery key you are at the passphrase or nothing | PCR 7 only, plus a recovery key |
| **Setting the root password to locked with no sudo path** | Recovery needs a rescue boot and `rd.break` | Verify `sudo -l` works for at least two admin accounts before locking root |
| **faillock `deny` on root with `even_deny_root`** | Anyone can lock root out by guessing badly, including over the console | Leave `even_deny_root` off, or set `root_unlock_time` short |
| **Removing `sudo` group membership from yourself in the same session** | You have root now and never again | Change group membership from a second account, verify, then log out |
| **Naming the profile and baseline in a submitted SSP, IATO package or contract response** | The customer assesses you against it for the life of the authorization. Internally the choice is a document you can change; once submitted, it is not | Name the version as well ("CIS Kubernetes 2.0.1", "CIS RHEL 9 Level 1 Server v2.0.0 as implemented by SSG 0.1.82"), and decide before the document leaves |
| **Turning FIPS mode on after install** | Keys and certificates generated before the switch stay outside it; RHEL 10 has no `fips-mode-setup`, so it is install-time only. Changing a running fleet means reinstalling | Decide at image build, on for Protected B builds |
| **Shipping on a base image without CMVP-validated crypto** | No setting fixes it later. Rebasing the appliance changes every downstream image, package set and support path | Choose the base (RHEL or CentOS Stream bootc rather than Fedora) before the next customer delivery |
| **Upgrading Kyverno to 1.20 with `ClusterPolicy` still in use** | The migration guide says `ClusterPolicy` will be removed in 1.20, so policies still written that way do not carry across the upgrade | Migrate to `ValidatingPolicy` and `ImageValidatingPolicy` first, prove them in `Audit`, and treat 1.20 as an out-of-cycle review trigger |
| **Removing the old etcd encryption key before every Secret is rewritten** | Every Secret still written with it becomes unreadable. Recovery needs an etcd backup and the old key | Follow the four-step rotation; keep retired keys in offline escrow, never next to the etcd snapshots they unlock |
| **Deleting an evidence bundle** | Not recoverable. CPCSC wants evidence for the attestation cycle or at least one year; TBS keeps incident records two years | Retention at the store of 13 months minimum, 2 years for incidents; deletion is a named person's action, not a cron job |

### If you are hardening a box today, in order

The order matters. Earlier steps make later ones recoverable.

1. **Get a second way in.** Console, serial, cloud rescue, or a second admin account with a tested key. Everything after this can lock you out; this step is what makes that survivable.
2. **Patch and turn on automatic updates.** `dnf upgrade --refresh`, reboot, then `dnf5-automatic.timer` with `apply_updates = yes` and a reboot policy (chapter 06). The cheapest control with the largest effect.
3. **Check SELinux is enforcing.** `getenforce`. If it is not, set permissive first, relabel, fix denials, then enforce (chapter 05).
4. **Inventory what listens.** `ss -tulpn`. Stop and mask everything you cannot name a reason for (chapter 04).
5. **Default-deny inbound.** firewalld zone with only the services you kept; check the default zone is not `FedoraWorkstation`, which opens 1025–65535 (chapter 04).
6. **Harden SSH from a second session.** Drop-in at `10-hardening.conf`, `sshd -t`, reload, test a fresh login before closing the old one (chapter 03).
7. **Fix accounts and sudo.** Per-role sudoers files, faillock and pwquality through `authselect`, lock unused accounts, find SUID binaries you did not expect (chapter 02).
8. **Apply the sysctl hardening set** in one file under `/etc/sysctl.d/` (chapters 04 and 06).
9. **Sandbox your own services.** `systemd-analyze security` every unit you wrote and get it under 5.0 (chapter 06).
10. **Encrypt, and back up the header.** LUKS2 at install time is easy; in place later is not. Header backup off-host the same day (chapter 06).
11. **Turn on auditd with a real rule set and ship logs off-host** (chapter 08).
12. **Baseline file integrity** with AIDE *after* the box is in its hardened state, so the baseline records the hardened state, not the defaults (chapter 09).
13. **Scan against the baseline.** `oscap xccdf eval` with the CIS Level 1 profile, and fix or document every failure. A documented exception is a finished item (chapter 07).
14. **Write down what you did.** The next person, or you in six months, needs to know why `ptrace_scope` is 2 before they flip it back to debug something.
15. **Record it against the controls.** Name the profile and the versioned baseline, and write down the organization-defined values the profile leaves blank: review frequency, retention, patch timelines (chapter 13).
16. **Take the permission baseline.** Run `perm-audit.sh` as root on the hardened box and store the output off-host; every later run diffs against it (chapter 14).
17. **Audit the container engine.** `container-audit.sh` and docker-bench on any container host; check the process labels, because `getenforce` says nothing about whether containers are confined (chapter 15).
18. **Baseline the cluster**, if the box is a Kubernetes node: kube-bench against CIS 2.0.1, PSA `restricted` as the default, default-deny NetworkPolicy, an API audit policy (chapter 16).
19. **Turn it into the audit programme.** Install `collect-evidence.sh` on a monthly timer, ship sealed bundles off-host, keep an evidence index, and route every failure to a fix, a tailoring entry or a POA&M row with an owner and a date (chapter 17).

### Checklist

- [ ] A tested out-of-band path exists before any SSH or firewall change.
- [ ] `getenforce` prints `Enforcing` and nobody has a plan to change that.
- [ ] `ss -tulpn` shows nothing you cannot explain.
- [ ] The default firewalld zone is one you chose.
- [ ] `sshd -T` shows `permitrootlogin no`, `passwordauthentication no`, `kbdinteractiveauthentication no`.
- [ ] Security updates install automatically and reboots happen.
- [ ] The LUKS header backup exists somewhere other than the disk it describes.
- [ ] Logs leave the host.
- [ ] The SSP names the profile and a versioned baseline per layer.
- [ ] Permission and container audits have an off-host baseline and a written review frequency.
- [ ] Evidence bundles are collected monthly, sealed, stored off-host and kept at least 13 months.
- [ ] Every scan failure is fixed, tailored out or on the POA&M with an owner and a date.


---


<a id="01-threat-model-and-layers"></a>

## 01 · Threat model and layers

*Every Linux access decision is a stack of independent checks, and an attacker has to beat all of them. Hardening is making each layer say no on its own, so one mistake is not the whole story.*

### Start from the attacker

A threat model is three answers written down before you touch a config file: **what you are protecting, from whom, and what you will accept losing.** Without it, hardening becomes a checklist that grows until someone turns it off.

For a typical self-hosted host (a GitLab runner, a build box, a Kubernetes node, a bastion) the realistic attackers are, in order of likelihood:

| Attacker | How they arrive | What stops them |
|---|---|---|
| Internet scanner | Exposed service with a known CVE, or a weak password | Patching, default-deny inbound, key-only SSH |
| Supply chain | Malicious package, container image or CI dependency running as a service user | MAC confinement, service sandboxing, egress filtering |
| Compromised developer laptop | Stolen SSH key or token used from a trusted network | FIDO2 keys, short-lived certificates, least-privilege sudo |
| Malicious or careless insider | Legitimate access used beyond its purpose | sudo logging, auditd, off-host logs |
| Physical or cloud-console access | Stolen disk, snapshot, or a rescue boot | LUKS, Secure Boot, TPM-bound unlock |

**The first two rows cause most real incidents.** Nation-state kernel 0-days exist, but a box that is behind on `sudo` and `openssh` patches will be lost to something much cheaper first.

#### What "protect" means

Write down the assets explicitly. For a CI runner that might be:

- **Secrets it holds:** registry credentials, deploy keys, cloud tokens. Loss means lateral movement to everything they reach.
- **Integrity of what it builds:** a tampered runner signs and ships tampered artefacts. This is the asset people forget.
- **Availability:** matters less for a runner (rebuild it), more for a database.

The asset list decides the weight of each control. Integrity of build output argues for file integrity monitoring and immutable images; secrets argue for egress filtering and systemd credentials; availability argues against aggressive lockout policies that an attacker can trigger.

### The attack surface of a host

```text
                        +-------------------------------------------+
    network  ---------> | listening sockets (sshd, web, exporters)  |  04 network
                        +-------------------------------------------+
    users    ---------> | logins: SSH, console, su, sudo, polkit    |  02 accounts, 03 ssh
                        +-------------------------------------------+
    software ---------> | packages, images, CI jobs, scripts        |  06 updates, audit chapters
                        +-------------------------------------------+
    local    ---------> | SUID binaries, world-writable paths,      |  02 accounts
    privesc             | writable units/cron, exposed sockets      |
                        | (docker.sock, podman.sock)                |
                        +-------------------------------------------+
    kernel   ---------> | syscalls, modules, eBPF, io_uring,        |  06 kernel
                        | user namespaces, device drivers           |
                        +-------------------------------------------+
    boot     ---------> | firmware, bootloader, initramfs, kernel   |  06 boot
    & disk              | cmdline, unencrypted disk                 |
                        +-------------------------------------------+
```

Each band is a place an attacker enters or climbs. The job is to shrink each band (fewer sockets, fewer SUID binaries, fewer syscalls reachable) and to put a check between each band and the next.

#### The local privilege escalation shortlist

When someone has a shell as an unprivileged user, these are what they try first. Every one is covered later:

| Vector | Check | Chapter |
|---|---|---|
| Membership of `docker` group, or read-write on `docker.sock` | `getent group docker`; `ls -l /run/docker.sock` | 02 |
| Unexpected SUID/SGID binary | `find / -xdev -perm /6000 -type f` | 02 |
| sudo rule with a shell escape (`vim`, `less`, `find`, `tar`) | `sudo -l -U USER` | 02 |
| World-writable file executed by root (cron, unit, script) | `find / -xdev -type f -perm -0002` | 02 |
| Unpatched kernel or sudo | `dnf updateinfo list --security` | 06 |
| Readable secrets in env, history, or config | `grep -r` for tokens, `/proc/*/environ` | 06 |
| Writable `PATH` directory earlier than `/usr/bin` for root | `sudo sh -c 'echo $PATH'` vs `secure_path` | 02 |
| Capability-bearing binary | `getcap -r / 2>/dev/null` | 02 |

> **Gotcha.** Membership of the `docker` group is root. `docker run -v /:/host --privileged` gives a root shell on the host with no password prompt. Rootless Podman does not have this property because its "root" is your UID mapped into a user namespace.

### Defence in depth, concretely

Defence in depth is not "install lots of tools". It is arranging **independent** checks so that each one can fail without the attacker winning. Independent means different mechanisms, configured by different files, ideally failing for different reasons.

A worked example: an attacker gets remote code execution in `nginx` through a vulnerable module.

```text
  RCE in nginx worker (uid nginx)
        |
        v
  DAC: can read files owned by nginx or world-readable ...... /etc/shadow? no (0000)
        |                                                      app secrets 0640 root:app? no
        v
  SELinux: process is httpd_t, can only touch httpd_*_t ...... /home? no. outbound to DB port?
        |                                                      only if boolean httpd_can_network_connect_db
        v
  systemd sandbox: ProtectHome, ProtectSystem=strict,
                   NoNewPrivileges, empty capability set ...... SUID escalation? blocked by NoNewPrivileges
        |
        v
  seccomp: SystemCallFilter=@system-service ................. ptrace, kexec, module load? EPERM
        |
        v
  firewall egress: nginx may only talk to upstream app ...... fetch a payload from the internet? dropped
        |
        v
  auditd + off-host logs ..................................... the attempt is recorded where the
                                                               attacker cannot edit it
```

**No single layer here is sufficient and none is redundant.** DAC is bypassed by any bug that runs as the right user. SELinux is bypassed by a policy that is too broad. systemd sandboxing is bypassed by a unit someone forgot to harden. Stacked, the attacker needs a bug in each.

### Least privilege, three ways

Least privilege applies at three scales, and people usually only do the first:

1. **Users:** no shared accounts, no standing root, sudo rules that name commands (chapter 02).
2. **Services:** each daemon runs as its own user, with only the capabilities, files, syscalls and network destinations it needs (chapters 05 and 06).
3. **Credentials:** keys and tokens scoped to one purpose and short-lived (SSH certificates in chapter 03, systemd credentials in chapter 06).

The test for each: **if this identity is stolen right now, what is the blast radius?** If the answer for any service account is "the whole host", that is the next thing to fix.

### How the kernel checks stack

Every access a process makes (open a file, bind a port, send a signal, load a module) passes through a sequence of kernel checks. They are independent and **all must allow**. Knowing the order tells you which tool to reach for when something is denied.

```text
  syscall from process
        |
        v
  +-------------+   seccomp-bpf filter attached to the process.
  |  seccomp    |   Decides on syscall number and arguments only.
  +-------------+   Fails with EPERM/ENOSYS or kills the process.
        |
        v
  +-------------+   Which kernel objects this process can even see:
  | namespaces  |   mount, pid, net, user, ipc, uts, cgroup, time.
  +-------------+   Not a check; a view. You cannot open what is not in your view.
        |
        v
  +-------------+   Traditional UID/GID + mode bits + ACLs.
  |    DAC      |   The owner decides. root (uid 0) bypasses most of it ...
  +-------------+
        |
        v
  +-------------+   ... unless root has lost the capability that grants the bypass
  |capabilities |   (CAP_DAC_OVERRIDE, CAP_SYS_ADMIN, CAP_NET_BIND_SERVICE ...).
  +-------------+   Root is 41 capabilities, not one magic bit.
        |
        v
  +-------------+   LSM hooks: SELinux or AppArmor, plus Yama, Landlock,
  |  MAC / LSM  |   lockdown, BPF-LSM. Policy written by the admin, not the owner.
  +-------------+   Applies to root too. The last word.
        |
        v
     allowed
```

> **Note.** The exact ordering varies per hook in the kernel (some LSM checks run before capability checks for specific operations), but the model that matters holds: **each layer is independent, each can only deny, and none can override a denial from another.** SELinux cannot grant what DAC denied, and DAC cannot grant what SELinux denied.

#### DAC

Discretionary access control is the owner/group/other mode bits plus POSIX ACLs. "Discretionary" means the owner of a file decides who can read it, which is exactly the weakness: any process running as that owner can grant access to anyone.

```bash
ls -l /etc/shadow            # ----------. 1 root root  : nobody but CAP_DAC_OVERRIDE
getfacl /var/log/journal     # ACLs extend mode bits; check them when mode bits look right
stat -c '%a %U:%G %n' /etc/ssh/sshd_config
```

#### Capabilities

Root's powers are split into capabilities. A process can hold a subset, and systemd, containers and file capabilities are how you hand out only what is needed.

```bash
capsh --print                                # your current sets
grep Cap /proc/self/status                   # raw bitmasks
capsh --decode=000001ffffffffff              # decode one
getcap -r /usr/bin /usr/sbin 2>/dev/null     # binaries with file capabilities
systemd-analyze capability                   # the full list with numbers
```

The ones that matter most, because each is "root in disguise":

| Capability | Why it is effectively root |
|---|---|
| `CAP_SYS_ADMIN` | Mount, namespaces, BPF, dozens of ioctls. The "new root" |
| `CAP_SYS_MODULE` | Load kernel code |
| `CAP_SYS_PTRACE` | Read and write memory of any process, including root's |
| `CAP_DAC_OVERRIDE` / `CAP_DAC_READ_SEARCH` | Ignore file permissions / read any file |
| `CAP_SETUID` / `CAP_SETGID` | Become anyone |
| `CAP_SYS_RAWIO` | Raw device and I/O port access |
| `CAP_NET_ADMIN` | Rewrite firewall and routing; sniff with the right tricks |
| `CAP_BPF` + `CAP_PERFMON` | Load tracing programs that read kernel memory |

`CAP_NET_BIND_SERVICE` (bind below 1024) is the one you usually want to grant alone.

#### MAC

Mandatory access control is policy written by the administrator that applies to every process including root. On Fedora/RHEL that is SELinux type enforcement: every process has a domain (`httpd_t`), every file a type (`httpd_sys_content_t`), and the policy lists which domains may do what to which types. Chapter 05 is entirely about it.

```bash
getenforce
ps -eZ | grep -E 'sshd|nginx|chronyd'
ls -Z /var/www/html
```

#### Namespaces

Namespaces change what a process can see, not what it is allowed to do. They are the foundation of containers and of systemd's `PrivateTmp=`, `PrivateNetwork=` and `ProtectSystem=`.

```bash
lsns                              # namespaces visible to you
lsns -t user                      # user namespaces: where "root inside" lives
readlink /proc/$$/ns/*            # the namespaces of your shell
sysctl user.max_user_namespaces   # 0 disables unprivileged user namespaces
```

> **Gotcha.** Unprivileged user namespaces are both a hardening tool and an attack surface. Rootless Podman, Flatpak and browsers' sandboxes need them. Many kernel privilege escalations of the last five years were reachable only through them. Setting `user.max_user_namespaces=0` on a server with no rootless containers is reasonable; on a workstation it breaks Flatpak, Chrome's sandbox and rootless Podman.

#### seccomp

seccomp-bpf filters the syscalls a process may make. It is the narrowest layer: it knows nothing about files or users, only syscall numbers and argument values. It shines at removing whole kernel subsystems from reach (no `ptrace`, no `kexec_load`, no `init_module`, no `bpf`), which removes those subsystems' bugs from the attack surface.

```bash
grep Seccomp /proc/self/status        # 0 none, 1 strict, 2 filter
systemd-analyze syscall-filter @system-service | head -40
podman info --format '{{.Host.Security.SECCOMPEnabled}}'
```

#### The small LSMs

Alongside the major MAC, the kernel stacks small LSMs that each do one thing. Check which are active:

```bash
cat /sys/kernel/security/lsm
# lockdown,capability,yama,selinux,bpf,landlock,ipe,ima,evm
```

| LSM | Does | Control |
|---|---|---|
| Yama | Restricts `ptrace` to descendants, admin, or nobody | `kernel.yama.ptrace_scope` (chapter 06) |
| lockdown | Stops root from modifying the running kernel (`/dev/mem`, unsigned modules, kexec) | `lockdown=` kernel parameter, Secure Boot (chapter 06) |
| Landlock | Lets an unprivileged process sandbox itself | Used by applications; `RestrictFileSystems=` in systemd |
| BPF-LSM | Policy as eBPF programs | Used by tools like Tetragon and systemd's `RestrictFileSystems=` |
| IMA/EVM | Measure and appraise file integrity at open | Enterprise attestation; rarely hand-configured |

### Where each tool sits

```text
   +------------------------------------------------------------------+
   | PREVENT                                                          |
   |   network   firewalld / nftables, sysctl net.* ............ 04   |
   |   identity  sshd, sudo, PAM, faillock, polkit ........ 02, 03    |
   |   process   SELinux, systemd sandbox, seccomp ......... 05, 06   |
   |   kernel    sysctl kernel.*, lockdown, Yama ................ 06  |
   |   boot/disk Secure Boot, LUKS2, TPM2 ...................... 06   |
   |   software  dnf-automatic, Trivy, updateinfo ...... 06, audit    |
   +------------------------------------------------------------------+
   | VERIFY (does the config match intent?)                           |
   |   oscap + scap-security-guide, Lynis, sshd -T, ssh-audit,        |
   |   systemd-analyze security, ss -tulpn ........... 03-06, audit   |
   +------------------------------------------------------------------+
   | DETECT (did something happen?)                                   |
   |   auditd, AIDE, journald, fail2ban, off-host shipping ... detect |
   +------------------------------------------------------------------+
   | RESPOND (contain, preserve, recover)                             |
   |   isolation rules, snapshots, forensics, rebuild ....... response|
   +------------------------------------------------------------------+
```

The column people skip is **verify**. A hardening change that is never re-checked is a change that silently reverts at the next package update or the next colleague's quick fix. Every chapter here ends with the read-only command that proves its settings are live.

### What hardening will not fix

- **A vulnerable application with legitimate access.** If the app's user can read the database, SQL injection reads the database. MAC and sandboxing limit what happens next, not the first read.
- **Stolen credentials used as intended.** A valid FIDO2 touch from a compromised laptop still logs in. Short certificate lifetimes limit the window.
- **Kernel 0-days.** Reduced reachable surface (seccomp, no unprivileged BPF, no module load) shrinks the pool of usable bugs. It does not reach zero.
- **Misconfiguration you cannot see.** This is why chapters 07–12 exist: assume a layer will fail and make the failure visible.

### Checklist

- [ ] Assets, attackers and acceptable loss are written down for this host class.
- [ ] Nobody in the `docker` group who should not be root.
- [ ] You know which LSMs are active: `cat /sys/kernel/security/lsm`.
- [ ] Every service account's blast radius is smaller than "the whole host".
- [ ] Every prevent control has a matching verify command in a script or a scan.


---


<a id="02-accounts-sudo-and-pam"></a>

## 02 · Accounts, sudo and PAM

*Local privilege escalation almost never needs an exploit. It needs a sudo rule with a shell escape, a forgotten SUID binary or a group that is root by another name. Audit those before you tune password rules.*

### Inventory who can log in

Start with facts. Which accounts exist, which have a usable shell, which have a password, which are in a privileged group.

```bash
# Human-range accounts (UID >= 1000) with their shells
getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1, $3, $7}'

# Every account with a login shell, system or not
getent passwd | awk -F: '$7 !~ /(nologin|false|sync|shutdown|halt)$/ {print $1, $7}'

# Accounts with UID 0 (must be exactly one: root)
awk -F: '$3 == 0 {print $1}' /etc/passwd

# Password status for every account (needs root to read shadow)
sudo passwd -S -a 2>/dev/null | awk '{print $1, $2}'
# P = usable password, L = locked, NP = no password (fix those)

# Privileged groups
getent group wheel sudo adm docker libvirt systemd-journal
```

| Group | What it really grants |
|---|---|
| `wheel` (Fedora/RHEL), `sudo` (Debian/Ubuntu) | sudo to root per the default rule, plus polkit admin |
| `docker` | Root on the host via the Docker socket |
| `libvirt` | Define a VM that mounts the host disk; effectively root |
| `adm` | Read most logs under `/var/log`, including auth logs |
| `systemd-journal` | Read the whole journal, which may include secrets logged by mistake |
| `disk` | Raw read/write on block devices; root |
| `kvm`, `video`, `input` | Hardware access; `input` means keylogging |

> **Gotcha.** Treat `docker`, `libvirt` and `disk` as equivalent to `wheel` in every access review. People add users to `docker` "so they don't have to type sudo" and create a passwordless root path that no sudo log records.

#### Service accounts

Every daemon should run as its own system user with no shell and no password. Prefer `systemd-sysusers` for packaged users and `DynamicUser=yes` for your own services (chapter 06), so the account does not exist outside the service's lifetime.

```bash
# Create a static system user with no login
sudo useradd --system --no-create-home --shell /usr/sbin/nologin SVCNAME

# Declarative alternative: /etc/sysusers.d/SVCNAME.conf
#   u SVCNAME - "SVCNAME service" /var/lib/SVCNAME /usr/sbin/nologin
sudo systemd-sysusers
```

### Lock and expire accounts

Four different operations that people confuse:

| Goal | Command | Effect | Survives |
|---|---|---|---|
| Stop password login | `usermod -L USER` / `passwd -l USER` | Prefixes the shadow hash with `!` | **SSH keys still work** |
| Stop all login | `usermod -e 1 USER` | Account expired (day 1 = 1970-01-02) | Blocks keys too, via PAM `account` |
| Stop shell use | `usermod -s /usr/sbin/nologin USER` | No interactive shell | SFTP/port forwarding may still work |
| Delete | `userdel -r USER` | Removes account and home | Files elsewhere become orphans owned by a numeric UID |

**To fully disable a departing user, do both lock and expire**, and remove their `authorized_keys`:

```bash
sudo usermod -L -e 1 USER
sudo mv /home/USER/.ssh/authorized_keys /home/USER/.ssh/authorized_keys.disabled
sudo loginctl terminate-user USER       # kill live sessions
sudo pkill -KILL -u USER                # and anything left running
```

> **Gotcha.** `passwd -l` alone does not stop SSH key authentication. OpenSSH skips the password check entirely for pubkey auth; only the PAM `account` stack (which checks expiry) or `AllowGroups` in sshd stops it. This is the most common "we disabled that account" failure in incident reviews.

Find leftover files after a deletion:

```bash
sudo find / -xdev \( -nouser -o -nogroup \) -print 2>/dev/null
```

#### Password aging

Periodic forced rotation is counterproductive (NIST SP 800-63B). Set aging to off, enforce length and breach checks instead, and expire individual passwords when you have reason to believe one leaked.

```bash
chage -l USER                     # show aging
sudo chage -M -1 USER             # no maximum age
sudo passwd -e USER               # force change at next login (after a leak)
sudo chage -E 2026-12-31 USER     # contractor account that expires on a date
sudo chage -I 30 USER             # disable 30 days after password expiry
```

Defaults for new accounts live in `/etc/login.defs`:

```bash
grep -E '^(UMASK|HOME_MODE|PASS_MAX_DAYS|PASS_MIN_LEN|ENCRYPT_METHOD)' /etc/login.defs
# Fedora 43: UMASK 022, HOME_MODE 0700, ENCRYPT_METHOD YESCRYPT
```

yescrypt is the current default hash on Fedora and Debian 11+. If you see `$6$` (SHA-512) hashes in `/etc/shadow`, those users set passwords before the change; they will be rehashed on the next password change.

### sudo done properly

#### The shape

Never edit `/etc/sudoers`. Put one file per role in `/etc/sudoers.d/`, name it without dots or a trailing `~` (sudo skips files containing `.` or ending in `~`), and check it with `visudo` before it goes live.

```bash
sudo visudo -f /etc/sudoers.d/10-webops     # edits with a syntax check on save
sudo visudo -cf /etc/sudoers.d/10-webops    # check a file you wrote elsewhere
sudo visudo -c                               # check the whole tree
```

> **Gotcha.** A file named `10-webops.conf` is **silently ignored** because it contains a dot. The rule you thought was active is not, and nothing logs the fact. Name files `10-webops`, `20-ci-deploy`.

> **One-way door.** A syntax error in any included sudoers file breaks sudo for everybody. If root has no password and you have no other way in, you need a rescue boot. Always `visudo -cf` before copying a file into place, and keep a root shell open while you change sudo.

#### A least-privilege rule set

```ini
# /etc/sudoers.d/10-webops
# Role: web operators may manage the web tier and nothing else.

Cmnd_Alias WEB_SVC = /usr/bin/systemctl restart nginx.service, \
                     /usr/bin/systemctl reload nginx.service, \
                     /usr/bin/systemctl --no-pager status nginx.service
# Exact arguments, no wildcard, and never without --no-pager (see the gotcha below)
Cmnd_Alias WEB_LOG = /usr/bin/journalctl --no-pager -u nginx.service, \
                     /usr/bin/journalctl --no-pager -u nginx.service -n 500

%webops ALL=(root) WEB_SVC, WEB_LOG

# Deploy user runs one script, as the app user, not root, with no password.
# The script and its directory must be root-owned and not writable by deploy.
deploy  ALL=(app) NOPASSWD: /opt/app/bin/deploy.sh

Defaults:%webops  !requiretty
Defaults          use_pty
Defaults          logfile=/var/log/sudo.log
Defaults          log_input, log_output
Defaults          iolog_dir=/var/log/sudo-io/%{user}
Defaults          timestamp_timeout=5
Defaults          passwd_tries=3
```

> **Gotcha.** `systemctl status` and `journalctl` open a pager (`less`) when run on a terminal, and `!sh` inside `less` running as root is a root shell. Any sudo rule for them must pin `--no-pager` in the permitted arguments, as above, or be tagged `NOEXEC:`. The same applies to `systemctl edit`, `git log`, `man` and anything else that pages.

Rules for writing rules:

- **Absolute paths only.** A relative command name is resolved through the user's `PATH`.
- **Never allow an editor, pager, interpreter or archiver as root.** `vim`, `less`, `more`, `man`, `find`, `awk`, `tar`, `zip`, `git`, `python`, `perl`, `env`, `rsync` and `systemctl edit` all have documented shell escapes (GTFOBins). Use `sudoedit` for file editing: it copies the file, runs the user's editor as the user, and writes it back as root.
- **Wildcards in arguments match spaces.** `/usr/bin/cat /var/log/*` permits `cat /var/log/../../etc/shadow`. Avoid argument wildcards on anything that reads or writes files.
- **The script a NOPASSWD rule runs must not be writable by the user,** nor any directory on its path, nor anything it sources. Otherwise the user edits the script.
- **`NOEXEC:`** stops a permitted program from spawning children (via `LD_PRELOAD` of `sudo_noexec.so`). Useful for tools that should not shell out; not a guarantee for statically linked binaries.

```ini
# Let an operator edit one config file safely
%webops ALL=(root) sudoedit /etc/nginx/conf.d/app.conf
```

#### Reviewing what someone can do

```bash
sudo -l                        # what can I run?
sudo -l -U USER                # what can USER run? (needs root)
sudo -ll -U USER               # long format: shows options (NOPASSWD, runas) per rule
sudo -l -U USER /usr/bin/vim   # exit 0 if USER may run this exact command
```

Audit all rules at once:

```bash
sudo grep -rhv '^\s*#' /etc/sudoers /etc/sudoers.d/ | grep -v '^\s*$'
sudo grep -rn 'NOPASSWD' /etc/sudoers /etc/sudoers.d/
sudo grep -rnE 'ALL\s*=\s*\(ALL(:ALL)?\)\s*(NOPASSWD:\s*)?ALL' /etc/sudoers.d/
```

#### sudo logging

Every sudo invocation goes to the journal via syslog, whether or not you set `logfile`:

```bash
journalctl _COMM=sudo --since today
journalctl _COMM=sudo -g 'COMMAND=' -o short-iso | tail -20
```

With `log_input, log_output` above, full terminal sessions are recorded and replayable:

```bash
sudo sudoreplay -l                          # list recorded sessions
sudo sudoreplay -l user USER command bash   # filter
sudo sudoreplay TSID                        # replay one
```

> **Note.** I/O logs contain whatever was typed, including passwords typed into programs run under sudo. Protect `/var/log/sudo-io` (root-only, mode 0700) and ship it off-host if the host is a bastion. On busy CI hosts, `log_output` on a deploy script that prints megabytes will fill the disk; scope it with `Defaults:%humans`.

#### run0

systemd 256 and later ship `run0`, which asks the service manager to start the command via polkit instead of using a SUID binary. It has no rule language of its own (authorisation is a polkit rule), so it replaces `sudo -i` for admins, not fine-grained sudo rules. **Keep sudo for least-privilege rules; `run0` is reasonable for full-admin users.**

```bash
run0 systemctl restart nginx.service
```

### PAM basics

PAM is a stack of modules per service (`/etc/pam.d/sshd`, `/etc/pam.d/sudo`, `/etc/pam.d/login`) in four management groups:

| Group | Answers | Typical modules |
|---|---|---|
| `auth` | Is this really the user? | `pam_unix`, `pam_faillock`, `pam_u2f`, `pam_sss` |
| `account` | Is the account allowed in now? | `pam_unix` (expiry), `pam_access`, `pam_nologin` |
| `password` | Is the new password acceptable? | `pam_pwquality`, `pam_pwhistory`, `pam_unix` |
| `session` | Set up the session | `pam_limits`, `pam_systemd`, `pam_loginuid`, `pam_umask` |

Control flags decide how a module's result combines: `required` (fail, but keep going so the attacker cannot tell which module failed), `requisite` (fail immediately), `sufficient` (success ends the stack unless an earlier required failed), and the bracket syntax `[success=1 default=ignore]` for everything else.

#### Change PAM with authselect, not by hand

On Fedora and RHEL, `/etc/pam.d/system-auth` and `password-auth` are generated by `authselect`. Hand edits are overwritten on the next `authselect apply-changes` or package update.

```bash
authselect current                  # profile and enabled features
authselect list-features local      # what can be turned on (Fedora 43 profile: local)
sudo authselect enable-feature with-faillock
sudo authselect enable-feature with-pwhistory
sudo authselect apply-changes
authselect check                    # 0 if the generated files are untouched
```

Features worth knowing on the `local` profile (Fedora 40+ default; `sssd` for domain-joined hosts):

| Feature | Does |
|---|---|
| `with-faillock` | Lock accounts after repeated failures |
| `with-pwhistory` | Remember previous passwords |
| `with-pam-u2f` / `with-pam-u2f-2fa` | FIDO2 key as sole factor, or as second factor |
| `with-pamaccess` | Enable `/etc/security/access.conf` rules |
| `without-nullok` | Refuse empty passwords everywhere |
| `with-mkhomedir` | Create homes on first login (directory users) |

> **Version-sensitive.** The `local` profile arrived in authselect 1.5 (Fedora 40). Earlier Fedora and RHEL 8/9 use the `minimal` or `sssd` profile; the feature names are the same. Debian/Ubuntu use `pam-auth-update` and edit `/etc/pam.d/common-*`.

#### faillock

Configure in `/etc/security/faillock.conf`, not as module arguments:

```ini
# /etc/security/faillock.conf
deny = 5
fail_interval = 900
unlock_time = 600
audit
silent
# even_deny_root is deliberately NOT set
# root_unlock_time = 60
dir = /var/run/faillock
```

```bash
sudo faillock                       # all users with recorded failures
sudo faillock --user USER           # one user
sudo faillock --user USER --reset   # unlock
```

> **Gotcha.** faillock only counts failures that go through the PAM `auth` stack. SSH public key failures never touch PAM, so they are not counted; password and keyboard-interactive failures are. With key-only SSH, faillock mostly protects the console and `su`/`sudo`.

> **Gotcha.** `dir = /var/run/faillock` is a tmpfs: tallies reset at reboot. That is usually what you want. Setting `even_deny_root` lets anyone lock root out by failing on purpose; leave it off unless a compliance profile demands it, and then set `root_unlock_time` short.

#### pwquality

```ini
# /etc/security/pwquality.conf.d/50-local.conf
minlen = 14
minclass = 0
dictcheck = 1
usercheck = 1
maxrepeat = 3
enforce_for_root
retry = 3
```

Length is the control that matters. Character-class rules (`dcredit=-1`, `ucredit=-1`) push users toward `Password1!` and are gone from current NIST guidance. Use a drop-in in `pwquality.conf.d/` so package updates do not collide with your edits.

Test a candidate without changing anything:

```bash
echo 'correct horse battery staple' | pwscore
```

### SUID, SGID and world-writable files

#### Find them

```bash
# SUID or SGID regular files on the root filesystem
sudo find / -xdev -type f -perm /6000 -exec ls -l {} + 2>/dev/null

# World-writable files (excluding sticky /tmp-style dirs)
sudo find / -xdev -type f -perm -0002 -print 2>/dev/null

# World-writable directories WITHOUT the sticky bit (anyone can delete anyone's files)
sudo find / -xdev -type d -perm -0002 ! -perm -1000 -print 2>/dev/null

# Files with capabilities
sudo getcap -r / 2>/dev/null
```

Check each SUID binary belongs to a package and has not been modified:

```bash
for f in $(sudo find / -xdev -type f -perm /6000 2>/dev/null); do
  pkg=$(rpm -qf "$f" 2>/dev/null) || pkg="NOT OWNED BY ANY PACKAGE"
  echo "$f  $pkg"
done

rpm -Va --nomtime | grep -E '^..5|^.M'    # checksum or mode changed (Debian: dpkg --verify)
```

A file "not owned by any package" with the SUID bit is an incident until proven otherwise.

#### Reduce them

The expected Fedora set is small: `sudo`, `su`, `passwd`, `chage`, `gpasswd`, `newgrp`, `mount`, `umount`, `pkexec`, `unix_chkpwd`, `fusermount3`, `newuidmap`/`newgidmap` (via capabilities), plus a few desktop helpers. Remove what you do not use by removing the package, not by `chmod`, because the next update restores the bit.

```bash
rpm -qf /usr/bin/pkexec          # polkit
rpm -qf /usr/bin/at              # at (and it is often unneeded)
```

Mount options remove the attack class entirely for data paths:

```ini
# /etc/fstab: data volumes do not need SUID or device nodes
UUID=XXXX  /srv   xfs  defaults,nodev,nosuid         0 0
tmpfs      /tmp   tmpfs defaults,nodev,nosuid,size=4G 0 0
```

> **Note.** `noexec` on `/tmp` is less useful than it looks: `bash /tmp/script.sh` and `python /tmp/x.py` still run, and some installers break. `nosuid,nodev` are the valuable options.

### umask

The umask decides the permission of every file a process creates. `022` means new files are world-readable; `027` means group-readable, nothing for others; `077` means owner only.

```bash
umask                  # current, in octal
umask -S               # symbolic: u=rwx,g=rx,o=rx
```

Where it is set:

| Scope | Location |
|---|---|
| Login shells (all users) | `UMASK` in `/etc/login.defs`, applied by `pam_umask` |
| Interactive shells | `/etc/profile`, `/etc/bashrc`, or `~/.zshrc` |
| systemd services | `UMask=` in the unit (default `0022`) |
| sudo | `Defaults umask=0022` and `umask_override` |

**Set `027` for servers** in `/etc/login.defs` and `UMask=0027` on your own services. `077` breaks shared group directories and some package scriptlets that run under a user's session.

> **Gotcha.** A service that writes secrets or logs inherits `UMask=0022` from systemd, not the login umask. `systemd-analyze security UNIT` flags this line; set `UMask=0077` in every unit that writes anything sensitive.

### polkit

polkit authorises privileged actions requested over D-Bus: `systemctl` as a user, NetworkManager changes, `run0`, `pkexec`, libvirt, udisks. It is a second privilege system next to sudo, and it is often forgotten in reviews.

```bash
pkaction | wc -l                                         # every registered action
pkaction --verbose --action-id org.freedesktop.systemd1.manage-units
ls /usr/share/polkit-1/rules.d/ /etc/polkit-1/rules.d/   # vendor, then local rules
cat /usr/share/polkit-1/rules.d/50-default.rules         # admin = unix-group:wheel
```

Local rules are JavaScript in `/etc/polkit-1/rules.d/`, evaluated in lexical order across both directories. A rule granting one group the right to restart one unit, and nothing else:

```javascript
// /etc/polkit-1/rules.d/60-webops-nginx.rules
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        action.lookup("unit") == "nginx.service" &&
        (action.lookup("verb") == "restart" || action.lookup("verb") == "reload") &&
        subject.isInGroup("webops")) {
        return polkit.Result.YES;
    }
});
```

> **Note.** On headless servers, consider whether `pkexec` needs to exist at all. It was the vector for CVE-2021-4034 (PwnKit), exploitable by any local user for twelve years. `pkexec` is part of the `polkit` package on Fedora, so removal is not an option there; keep it patched and remove its SUID bit only if you accept that an update will restore it.

### Debian/Ubuntu differences

| Topic | Fedora/RHEL | Debian/Ubuntu |
|---|---|---|
| Admin group | `wheel` | `sudo` |
| PAM management | `authselect` | `pam-auth-update`, `/etc/pam.d/common-*` |
| Package verify | `rpm -Va` | `dpkg --verify` (or `debsums`) |
| Default umask in login.defs | `022` | `022` (and `USERGROUPS_ENAB yes` relaxes group bits) |
| faillock | on by feature | `pam_faillock` in `common-auth`, off by default |

### Traps

- `passwd -l` does not stop SSH key logins. Lock **and** expire.
- sudoers files containing a dot are silently ignored.
- A sudo rule for an editor, pager or interpreter is a root shell.
- `docker`, `libvirt`, `disk` groups are root.
- faillock does not count SSH key failures.
- Hand-edited `/etc/pam.d/system-auth` is overwritten by `authselect apply-changes`.
- `chmod u-s` on a packaged binary is undone by the next update; remove the package instead.
- Services inherit `UMask=0022` from systemd, not from `login.defs`.
- polkit is a second privilege path; review `/etc/polkit-1/rules.d/` alongside sudoers.

### Checklist

- [ ] Exactly one UID 0 account.
- [ ] No account with status `NP` (no password) and a login shell.
- [ ] Privileged group membership (`wheel`, `docker`, `libvirt`, `disk`, `adm`) reviewed.
- [ ] sudo rules name absolute commands; no editors, pagers or interpreters.
- [ ] `visudo -c` passes, and sudoers files are in Git with a CI check.
- [ ] `authselect check` passes; faillock and pwhistory enabled.
- [ ] Every SUID/SGID binary is owned by a package and passes `rpm -V`.
- [ ] No world-writable directories without the sticky bit.
- [ ] `UMASK 027` on servers; `UMask=0077` on units writing secrets.
- [ ] Local polkit rules reviewed.


---


<a id="03-ssh-hardening"></a>

## 03 · SSH hardening

*With keys only, brute force stops mattering and the real risk becomes a stolen private key. Hardware-backed keys and short-lived certificates fix that; everything else is tidying up. And sshd keeps the first value it reads, which decides where your drop-in goes.*

### What actually matters

In order of risk reduction:

1. **No passwords.** Keys only. This alone makes online guessing irrelevant.
2. **Keys that cannot be copied.** FIDO2 (`ed25519-sk`) keys live on a hardware token; malware on a laptop cannot exfiltrate them.
3. **Keys that expire.** SSH certificates signed by a CA, valid for hours, replace `authorized_keys` files that grow forever.
4. **Fewer people and paths in.** `AllowGroups`, no root login, no forwarding unless needed, a bastion in front.
5. **Modern algorithms.** On a current Fedora this is already handled by crypto-policies; verify rather than hand-tune.

Changing the port, tuning `MaxAuthTries`, and installing fail2ban for a key-only sshd are log-noise reduction, not security. Do them if the noise bothers you.

### How sshd reads its config

On Fedora 43 (OpenSSH 10.0) the main file starts with an `Include` of the drop-in directory, and the distro ships two drop-ins of its own:

```text
/etc/ssh/sshd_config
  Include /etc/ssh/sshd_config.d/*.conf      <- processed in lexical order, FIRST
    10-hardening.conf                         <- yours: wins for every keyword it sets
    40-redhat-crypto-policies.conf            <- Include of the crypto-policies back end
    50-redhat.conf                            <- distro defaults (X11Forwarding yes, UsePAM yes ...)
  ... rest of sshd_config (mostly comments)
```

**For most keywords, sshd uses the first value it obtains** (`man sshd_config`). So a drop-in named `99-hardening.conf` loses to `50-redhat.conf` for anything both set, and you get no warning. Name yours with a low number.

> **Gotcha.** The rule is first-wins, the opposite of systemd drop-ins and sysctl.d where the last file wins. A `99-` file "to make sure it overrides" is exactly backwards. Verify the effective value with `sshd -T`, never by reading files.

Debian/Ubuntu ship the same `Include` at the top of `sshd_config` and usually no distro drop-ins, but cloud images often add `50-cloud-init.conf` with `PasswordAuthentication yes`. The same first-wins rule applies.

### The hardened drop-in

Create the group first, add every account that should reach this host, and confirm membership from a fresh login (`id`) before you apply the drop-in.

```bash
sudo groupadd --system sshusers
sudo usermod -aG sshusers USER
```

```ini
# /etc/ssh/sshd_config.d/10-hardening.conf
# Loaded before 40-redhat-crypto-policies.conf and 50-redhat.conf; first value wins.

# --- who ---------------------------------------------------------------
PermitRootLogin no
AllowGroups sshusers

# --- how ---------------------------------------------------------------
PubkeyAuthentication yes
AuthenticationMethods publickey
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
HostbasedAuthentication no
GSSAPIAuthentication no
# Require touch on FIDO2 keys (default). Use verify-required to also demand the PIN.
PubkeyAuthOptions touch-required

# --- limits ------------------------------------------------------------
MaxAuthTries 3
LoginGraceTime 20s
MaxStartups 10:30:60
MaxSessions 4
ClientAliveInterval 300
ClientAliveCountMax 2

# --- what a session may do --------------------------------------------
DisableForwarding yes
PermitTunnel no
PermitUserEnvironment no
PermitUserRC no

# --- logging -----------------------------------------------------------
# VERBOSE logs the fingerprint of the key used for each login.
LogLevel VERBOSE

# --- host keys ---------------------------------------------------------
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_ecdsa_key

# --- exceptions: bastion users need forwarding for ProxyJump ------------
# Match blocks go LAST; everything after a Match line belongs to it, until the end
# of THIS file. sshd restores the pre-Include state after each included file, so
# the Match does not swallow 40-/50- drop-ins or the rest of sshd_config.
Match Group bastion-users
    DisableForwarding no
    AllowTcpForwarding yes
    X11Forwarding no
    AllowAgentForwarding no
    PermitTTY no
    ForceCommand /usr/sbin/nologin
```

What each block buys you:

| Setting | Why |
|---|---|
| `PermitRootLogin no` | Every admin action is attributable to a named user, then `sudo` |
| `AllowGroups sshusers` | An account created by a package or an attacker cannot log in over SSH even with a key |
| `AuthenticationMethods publickey` | One place that states the policy; add `publickey,keyboard-interactive` for key plus OTP |
| `KbdInteractiveAuthentication no` | Closes the PAM password path that `PasswordAuthentication no` alone leaves open on some setups |
| `GSSAPIAuthentication no` | Only for Kerberos-joined hosts; otherwise a slow, unused code path |
| `MaxAuthTries 3` | An agent offering many keys hits the limit: see the trap below |
| `LoginGraceTime 20s` | Unauthenticated connections hold a slot for less time |
| `MaxStartups 10:30:60` | Start dropping 30% of unauthenticated connections at 10, all at 60 |
| `DisableForwarding yes` | One switch for X11, agent, TCP and Unix socket forwarding |
| `PermitUserEnvironment no` | Stops `~/.ssh/environment` setting `LD_PRELOAD` for a forced command |
| `LogLevel VERBOSE` | Key fingerprints in the log are what let you tell which key was stolen |
| `HostKey` lines | Stop offering the RSA host key. Setting any `HostKey` disables the default list |

> **Gotcha.** `MaxAuthTries 3` counts each public key the client offers. A developer with six keys in their agent is rejected with "Too many authentication failures" before the right key is tried. Fix it on the client: `IdentitiesOnly yes` and an explicit `IdentityFile` per host in `~/.ssh/config`.

> **Gotcha.** `AllowGroups` is checked before authentication. If you apply it before adding yourself to the group, your key is never even considered. Check `id` from a **new** login; group changes do not reach sessions that were open when you ran `usermod`.

#### Timeouts on recent OpenSSH

```ini
# Close connections with no open channels (a forgotten ControlMaster, an idle -N)
UnusedConnectionTimeout 1h
# Close idle interactive sessions
ChannelTimeout session=30m
```

> **Version-sensitive.** `ChannelTimeout` and `UnusedConnectionTimeout` need OpenSSH 9.2+, `PerSourcePenalties` 9.8+, `RefuseConnection` 9.9+. RHEL 9 ships 8.7; check with `ssh -V` before copying these lines.

#### PerSourcePenalties instead of fail2ban

OpenSSH 9.8 added built-in penalties: sources that fail authentication, crash the pre-auth process, or hit `LoginGraceTime` are refused for a period, and repeat offenders accumulate time. It is on by default. For a key-only server this replaces fail2ban's SSH jail.

```ini
PerSourcePenalties authfail:30s noauth:10s grace-exceeded:30s max:10m
PerSourcePenaltyExemptList 10.0.0.0/8
PerSourceNetBlockSize 32:128
```

Put your monitoring and bastion networks in the exempt list, or a flapping health check will lock them out.

### Algorithms

#### On Fedora and RHEL: crypto-policies

sshd's algorithm lists come from `/etc/crypto-policies/back-ends/opensshserver.config`, pulled in by `40-redhat-crypto-policies.conf`. On Fedora 43 with the `DEFAULT` policy that is already modern: `mlkem768x25519-sha256` (post-quantum hybrid) first for key exchange, AEAD ciphers first, `RequiredRSASize 2048`.

```bash
update-crypto-policies --show
cat /etc/crypto-policies/back-ends/opensshserver.config
```

To tighten, change the policy, which moves OpenSSH, OpenSSL, GnuTLS and NSS together:

```bash
sudo update-crypto-policies --set DEFAULT:NO-SHA1
ls /usr/share/crypto-policies/policies/ /usr/share/crypto-policies/policies/modules/
```

**Prefer this to hand-written `Ciphers`/`MACs`/`KexAlgorithms` lines.** A pinned list in a `10-` drop-in overrides the policy silently and drifts when the next OpenSSH release adds or removes an algorithm. `FUTURE` is stricter still but refuses RSA keys under 3072 bits and SHA-1 signatures, which breaks old network gear and some Git hosts.

> **Gotcha.** `update-crypto-policies --set` affects every TLS client on the host too. `FUTURE` will break connections to servers presenting 2048-bit RSA certificates. Test a `curl` to your internal endpoints afterwards.

#### On Debian/Ubuntu, or when you must pin

```ini
# /etc/ssh/sshd_config.d/11-algorithms.conf  (Debian/Ubuntu, or pinned hosts)
KexAlgorithms mlkem768x25519-sha256,sntrup761x25519-sha512,curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
HostKeyAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,sk-ssh-ed25519@openssh.com,sk-ssh-ed25519-cert-v01@openssh.com,ecdsa-sha2-nistp256,rsa-sha2-512,rsa-sha2-256
PubkeyAcceptedAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,sk-ssh-ed25519@openssh.com,sk-ssh-ed25519-cert-v01@openssh.com,ecdsa-sha2-nistp256,rsa-sha2-512,rsa-sha2-256
```

> **Version-sensitive.** `mlkem768x25519-sha256` needs OpenSSH 9.9+; it became the default in 10.0. `sntrup761x25519-sha512@openssh.com` needs 8.5+ (default from 9.0); the name without the suffix arrived in 9.9, so on older servers use the `@openssh.com` form. An unknown algorithm name is a fatal config error, so check `ssh -Q kex` on the target before copying.

Check what the local binary supports:

```bash
ssh -Q kex
ssh -Q cipher
ssh -Q mac
ssh -Q key
```

### Verify with sshd -T

`sshd -T` prints the effective configuration after all includes, lowercase keys, one per line. It needs root because it loads host keys.

```bash
sudo sshd -t                     # syntax and key sanity only; silent on success
sudo sshd -T | sort              # full effective config
sudo sshd -T | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|authenticationmethods|allowgroups|maxauthtries|logingracetime|disableforwarding|x11forwarding|loglevel) '
```

Expected on the drop-in above:

```text
permitrootlogin no
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
authenticationmethods publickey
allowgroups sshusers
maxauthtries 3
logingracetime 20
disableforwarding yes
x11forwarding no
loglevel VERBOSE
```

`Match` blocks only apply when you describe a connection with `-C`:

```bash
sudo sshd -T -C user=USER,host=client.example.com,addr=10.0.0.5 | grep -E '^(disableforwarding|allowtcpforwarding|forcecommand) '
sudo sshd -T -C user=root,addr=203.0.113.9 | grep permitrootlogin
sudo sshd -T -C invalid-user,addr=203.0.113.9 | head    # what an unknown user sees
```

Then check the algorithms a client actually negotiates:

```bash
ssh -vv -o BatchMode=yes HOST exit 2>&1 | grep -E 'kex: algorithm|kex: host key|cipher:|MAC:'
```

### FIDO2 keys (ed25519-sk)

A FIDO2 SSH key has two halves: a private "key handle" file on disk and the secret on the token. **Without the token, the file is useless;** without the file, a non-resident key is useless. Stealing a laptop's `~/.ssh` gets an attacker nothing.

#### Generate

```bash
# Default: non-resident, touch required
ssh-keygen -t ed25519-sk -C "USER@LAPTOP-$(date +%Y%m)" -f ~/.ssh/id_ed25519_sk

# Also require the token PIN on each use (user verification)
ssh-keygen -t ed25519-sk -O verify-required -C "USER@LAPTOP" -f ~/.ssh/id_ed25519_sk_pin

# Resident (discoverable) key: stored on the token, recoverable on a new machine
ssh-keygen -t ed25519-sk -O resident -O verify-required -O application=ssh:work \
  -C "USER work" -f ~/.ssh/id_ed25519_sk_work

# Recover resident keys onto a new machine
ssh-keygen -K
```

| Option | Does | Pick when |
|---|---|---|
| (none) | Touch per use, handle file on disk | Default for a laptop you always carry |
| `-O verify-required` | PIN or biometric too | Admin keys, bastion access |
| `-O resident` | Key stored on token, `-K` recovers it | You move between machines; accept that anyone with the token and PIN gets the key |
| `-O application=ssh:NAME` | Separate slot per purpose | Several resident keys on one token |
| `-O no-touch-required` | No touch; must be allowed per key on the server | Unattended automation only, and then prefer a normal key or a certificate |

**Pick non-resident with `verify-required` for admin access**, and enrol **two tokens** (primary and a spare kept elsewhere) on every host or in the CA's principals. A single token is a single point of lockout.

> **Gotcha.** ed25519-sk needs a token with FIDO2 Ed25519 support (YubiKey firmware 5.2.3+, SoloKeys, Nitrokey 3). Older tokens support only `ecdsa-sk`. `ssh-keygen` fails with "Key enrollment failed: invalid format" or "unsupported algorithm"; fall back to `-t ecdsa-sk`.

> **Gotcha.** Agent forwarding a FIDO2 key through a chain of hosts works but every signature still needs a physical touch. That is the point; it also means automation cannot use your key, which is also the point.

#### Server side

The key goes in `authorized_keys` like any other. To demand the PIN server-side regardless of how the key was created:

```ini
# per key in authorized_keys
verify-required sk-ssh-ed25519@openssh.com AAAA... USER@LAPTOP

# or for all keys, in the drop-in
PubkeyAuthOptions verify-required
```

### SSH certificates and an SSH CA

`authorized_keys` does not scale: every host holds every key, nothing expires, and removing a leaver means editing every host. A **user CA** fixes it. Each host trusts one CA public key; users present short-lived certificates naming the principals (login names or roles) they may use.

```text
      CA private key (offline, or on a FIDO2 token, or in OpenBao)
             |
     signs   |  ssh-keygen -s CA -I id -n principals -V +8h user_key.pub
             v
      user_key-cert.pub  (identity, principals, validity, serial)
             |
     presents|  ssh HOST
             v
      sshd: TrustedUserCAKeys ca.pub      -> signature valid? not expired? not revoked?
            AuthorizedPrincipalsFile %u   -> is a principal in the cert allowed as this user?
```

#### Create the CAs

Keep user and host CAs separate so a compromise of one does not forge the other.

```bash
mkdir -p ~/ssh-ca && cd ~/ssh-ca
ssh-keygen -t ed25519 -f user_ca -C "user CA $(date +%Y)"
ssh-keygen -t ed25519 -f host_ca -C "host CA $(date +%Y)"
# A CA key can itself be a FIDO2 key: ssh-keygen -t ed25519-sk -O resident -f user_ca
```

> **One-way door.** Anyone with the user CA private key can log in as any principal on every host that trusts it, until you rotate the CA everywhere. Store it offline or on a hardware token, or let OpenBao's SSH secrets engine hold it and sign on request. Do not leave it on a build server.

#### Sign a user certificate

```bash
ssh-keygen -s ~/ssh-ca/user_ca \
  -I "USER@LAPTOP $(date -I)" \
  -n USER,deploy \
  -V +8h \
  -z SERIAL \
  ~/.ssh/id_ed25519_sk.pub
# writes ~/.ssh/id_ed25519_sk-cert.pub, which ssh picks up automatically

ssh-keygen -L -f ~/.ssh/id_ed25519_sk-cert.pub     # inspect: principals, validity, extensions
```

Restrict what the certificate allows with `-O`: `-O clear` removes all default permissions, then add back only what is needed (`-O permit-pty`), or pin it with `-O source-address=10.0.0.0/8` and `-O force-command=/usr/local/bin/backup`.

#### Trust the CA on servers

```bash
sudo install -m 0644 user_ca.pub /etc/ssh/user_ca.pub
sudo install -d -m 0755 /etc/ssh/auth_principals
echo 'USER' | sudo tee /etc/ssh/auth_principals/USER
printf 'deploy\nci\n' | sudo tee /etc/ssh/auth_principals/deploy
```

```ini
# add to /etc/ssh/sshd_config.d/10-hardening.conf (before any Match block)
TrustedUserCAKeys /etc/ssh/user_ca.pub
AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u
RevokedKeys /etc/ssh/revoked_keys
```

Without `AuthorizedPrincipalsFile`, the certificate's principals must match the login name exactly. With it, you map roles to accounts per host.

> **Gotcha.** If `RevokedKeys` names a file that does not exist or cannot be read, sshd refuses **all** public key authentication. Create an empty KRL before adding the line: `sudo ssh-keygen -k -f /etc/ssh/revoked_keys`.

#### Revoke

```bash
# Revoke by serial, by key, or by identity; -u updates an existing KRL
ssh-keygen -k -u -f revoked_keys -s user_ca.pub -z SERIAL
ssh-keygen -k -u -f revoked_keys stolen_key.pub
ssh-keygen -Q -f revoked_keys some_key.pub        # test: is this key revoked?
```

Distribute the KRL to every host with your config management. Short validity (`-V +8h`) means the KRL rarely matters; that is why short validity is the real revocation mechanism.

#### Host certificates

Host certificates end "trust on first use" prompts and the habit of typing `yes` to any fingerprint.

```bash
# On the CA machine, sign each host's public key
ssh-keygen -s ~/ssh-ca/host_ca -h \
  -I "HOST.example.com" \
  -n HOST.example.com,HOST,10.0.0.5 \
  -V +52w \
  ssh_host_ed25519_key.pub
```

```ini
# on the host
HostCertificate /etc/ssh/ssh_host_ed25519_key-cert.pub
```

```text
# on clients: ~/.ssh/known_hosts or /etc/ssh/ssh_known_hosts
@cert-authority *.example.com ssh-ed25519 AAAA...host-ca-public-key...
```

### Bastions with ProxyJump

A bastion is the only host reachable from outside; everything else accepts SSH only from the bastion's address. `ProxyJump` tunnels through it without putting keys on it.

```bash
ssh -J USER@BASTION USER@INTERNAL_HOST
ssh -J USER@BASTION1,USER@BASTION2 USER@INTERNAL_HOST
```

```ini
# ~/.ssh/config
Host bastion
    HostName bastion.example.com
    User USER
    IdentityFile ~/.ssh/id_ed25519_sk
    IdentitiesOnly yes

Host 10.20.*.* *.internal.example.com
    ProxyJump bastion
    User USER
    IdentityFile ~/.ssh/id_ed25519_sk
    IdentitiesOnly yes
```

**Use ProxyJump, never agent forwarding, to reach through a bastion.** With `-A`, root on the bastion can use your agent to authenticate as you anywhere while your session is open. With `-J`, the bastion only forwards an encrypted TCP stream; authentication to the inner host happens end to end from your laptop.

Bastion-side config: the `Match Group bastion-users` block in the drop-in above allows only TCP forwarding and no shell. Restrict where they may forward to:

```ini
Match Group bastion-users
    AllowTcpForwarding local
    PermitOpen 10.20.0.11:22 10.20.0.12:22 gitlab.internal.example.com:22
    PermitTTY no
    ForceCommand /usr/sbin/nologin
```

> **Note.** `PermitOpen` takes exact `host:port` pairs. `*` may stand for the whole host or the whole port, but there is no pattern matching and no CIDR: `*.internal.example.com:22` and `10.20.0.0/16:22` do not work. The names are compared literally with what the client requests, with no DNS lookup. For a range of addresses, use `PermitOpen *:22` and enforce the range at the bastion's firewall egress (chapter 04).

Inner hosts should accept SSH only from the bastion:

```bash
sudo firewall-cmd --permanent --zone=internal --add-source=BASTION_IP/32
sudo firewall-cmd --permanent --zone=internal --add-service=ssh
sudo firewall-cmd --permanent --zone=public --remove-service=ssh
sudo firewall-cmd --reload
```

### Audit with ssh-audit

`ssh-audit` connects as a client, records the banner, key exchange, host key and cipher offers, and flags weak or deprecated algorithms. It does not authenticate.

```bash
sudo dnf install ssh-audit            # Debian/Ubuntu: apt install ssh-audit
ssh-audit localhost
ssh-audit -p 2222 localhost
ssh-audit -l warn localhost           # only warnings and failures
ssh-audit -j localhost | jq .         # JSON for CI
ssh-audit -L                          # list built-in hardening policies
ssh-audit -P "POLICY NAME" localhost  # pass/fail against a policy; non-zero exit on fail
ssh-audit -M my_policy.txt localhost  # generate a policy from a host you trust
ssh-audit -c                          # listen on port 2222 and audit an SSH CLIENT that connects
```

**The useful CI shape** is `-M` against a golden host once, commit the policy file, then `-P my_policy.txt` against every host after each change. Drift fails the job.

> **Version-sensitive.** Fedora 43 packages ssh-audit 3.3.0; upstream is at 3.9.0 (July 2026). Every flag above appears in the upstream usage block ([github.com/jtesta/ssh-audit](https://github.com/jtesta/ssh-audit)); newer releases add options such as `--get-hardening-guide`, so check `ssh-audit -h` on your version. Only point it at hosts you own: a standard audit runs a connection-rate test (to judge DHEat exposure) unless you pass `--skip-rate-test`.

On a stock Fedora 43 host with crypto-policies `DEFAULT`, expect warnings about NIST ECDH curves and `hmac-sha1-etm` in the MAC list. `DEFAULT:NO-SHA1` removes the SHA-1 MACs.

### Do not lock yourself out

> **One-way door.** A broken sshd config or a firewall rule that drops port 22 on a host with no console access costs a datacentre visit or a rebuild. Existing sessions survive a reload, which is your safety net. Do not throw it away.

The procedure, every time:

1. **Keep an existing root session open** (`sudo -i` in one terminal). Do not close it until step 6 passes.
2. **Validate:** `sudo sshd -t`. Silent means valid. Any output means stop.
3. **Arm a dead-man switch** that reverts the change if you do not cancel it:

   ```bash
   sudo systemd-run --on-active=5min --unit=ssh-rollback \
     /bin/sh -c 'mv /etc/ssh/sshd_config.d/10-hardening.conf /root/10-hardening.conf.rolledback && systemctl reload sshd'
   ```

4. **Reload, do not restart:** `sudo systemctl reload sshd` (Debian/Ubuntu: `ssh`). Reload keeps existing sessions.
5. **Test in a new terminal with multiplexing off**, or you will reuse the old connection and prove nothing:

   ```bash
   ssh -o ControlMaster=no -o ControlPath=none -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519_sk USER@HOST 'id; sudo -n true && echo sudo-ok'
   ```

6. **Cancel the switch** once the new login works: `sudo systemctl stop ssh-rollback.timer`.

> **Gotcha.** If you have `ControlMaster auto` in `~/.ssh/config`, a "new" `ssh HOST` silently rides the existing authenticated connection and succeeds no matter what you broke. Always test with `-o ControlPath=none`.

Other ways people lock themselves out:

| Mistake | Prevention |
|---|---|
| `AllowGroups` before adding yourself | `id` from a fresh login shows the group |
| `PasswordAuthentication no` before a key works | Log in with the key once, with `-o PasswordAuthentication=no`, first |
| Changing `Port` without SELinux and firewall | `semanage port -a -t ssh_port_t -p tcp PORT` and `firewall-cmd --add-port=PORT/tcp` before the reload |
| `RevokedKeys` pointing at a missing file | Create an empty KRL first |
| Firewall change | Runtime-only change behind a `firewall-cmd --reload` rollback timer; see chapter 04 |
| Hardware token lost | Two tokens enrolled, or a certificate you can reissue |

### Client-side hardening

The client matters too: it decides which host keys you trust and what you forward.

```ini
# ~/.ssh/config  (top-level defaults go at the END; first match wins here too)
Host *
    IdentitiesOnly yes
    ForwardAgent no
    ForwardX11 no
    HashKnownHosts yes
    StrictHostKeyChecking ask
    UpdateHostKeys yes
    VerifyHostKeyDNS no
    ServerAliveInterval 60
    ControlMaster auto
    ControlPath ~/.ssh/cm-%C
    ControlPersist 10m
```

`ssh -G HOST` prints the effective client config for a host, the client twin of `sshd -T`.

### Traps

- sshd keeps the **first** value: name your drop-in `10-`, not `99-`.
- `passwd -l` does not stop key logins; `AllowGroups` or account expiry does.
- `MaxAuthTries` counts offered keys; set `IdentitiesOnly yes` on clients.
- A missing `RevokedKeys` file disables all public key authentication.
- Testing a new config over a multiplexed connection proves nothing.
- Agent forwarding through a bastion lends your identity to the bastion's root.
- Pinned algorithm lists fail hard on an older OpenSSH that does not know a name.
- `sshd -T` shows `Match` results only with `-C`.
- On Fedora, a non-standard port needs an SELinux port label as well as a firewall rule.

### Checklist

- [ ] Drop-in at `/etc/ssh/sshd_config.d/10-hardening.conf`; `sshd -t` silent.
- [ ] `sshd -T` shows root login, passwords and keyboard-interactive off.
- [ ] `AllowGroups` set, and every intended user is in it.
- [ ] Admins use FIDO2 keys, two tokens each.
- [ ] More than ~10 hosts: user CA with short validity, `AuthorizedPrincipalsFile`, empty KRL in place.
- [ ] Host certificates or pre-distributed `known_hosts`; nobody types `yes` to unknown fingerprints.
- [ ] Inner hosts accept SSH from the bastion only; nobody uses `-A`.
- [ ] `ssh-audit -P` policy check in CI.


---


<a id="04-firewall-and-network-exposure"></a>

## 04 · Firewall and network exposure

*A port that nothing listens on needs no firewall rule, so start with what listens, not with rules. Then default-deny both directions, remember that IPv6 is a second internet, and expect container engines to punch their own holes.*

### Start with what listens

The firewall is the second line. The first is not running the service. Before writing a single rule, inventory every listening socket and account for it.

```bash
sudo ss -tulpn                  # TCP+UDP, listening, with process, numeric
ss -tulpnH | awk '{print $1, $5}' | sort -u     # compact: proto and local address
sudo ss -tlpn 'sport = :22'     # who owns port 22
sudo ss -xlp | head             # Unix sockets: docker.sock, podman.sock, dbus
```

Read the local address column:

| Local address | Reachable from |
|---|---|
| `127.0.0.1:PORT`, `[::1]:PORT`, `127.0.0.53%lo` | This host only. Fine |
| `0.0.0.0:PORT` | Every IPv4 interface, including public ones |
| `[::]:PORT` or `*:PORT` | Every IPv6 interface, and usually IPv4 too (dual-stack socket) |
| `192.168.0.17:PORT` | That one interface |
| `172.17.0.1:PORT` | A container bridge; reachable by every container on it |

For every `0.0.0.0` or `[::]` line, answer: **what is it, who needs it, and from where?** If you cannot answer, stop it and see who complains.

```bash
# Map a PID to its unit, then to its package
systemctl status PID | head -3
rpm -qf "$(readlink -f /proc/PID/exe)"
```

> **Note.** Without `sudo`, `ss -p` shows process names only for your own processes. Run it as root for the real picture; a line with no `users:(...)` is owned by someone else, not by nobody.

A useful weekly check, run from a different host on the same network, shows what the network actually sees:

```bash
# Only against hosts you own
nmap -sS -sU --top-ports 200 -Pn HOST
nmap -6 -sS --top-ports 200 -Pn HOST_IPV6
```

### Disable what you do not need

```bash
systemctl list-unit-files --type=service --state=enabled
systemctl list-sockets                # socket-activated listeners, easy to miss
systemctl list-timers                 # scheduled jobs are surface too
```

Common candidates on a server:

| Unit | Does | Keep if |
|---|---|---|
| `avahi-daemon.service` / `.socket` | mDNS/DNS-SD on UDP 5353 | Desktop discovery only |
| `cups.service` / `.socket` | Printing on 631 | Never on a server |
| `wsdd.service` | Windows network discovery on 3702 | Desktop with SMB browsing |
| `rpcbind.service` / `.socket` | NFSv3 portmapper on 111 | You serve NFSv3 (NFSv4 does not need it) |
| `cockpit.socket` | Web console on 9090 | You use it, and only from an admin network |
| `sshd.service` | SSH | You manage the host over SSH |
| `bluetooth.service` | Bluetooth | Never on a server |
| `ModemManager.service` | Mobile broadband | Never on a server |

```bash
sudo systemctl disable --now avahi-daemon.socket avahi-daemon.service
sudo systemctl mask avahi-daemon.service avahi-daemon.socket     # stops dependency activation too
sudo dnf remove cups                                              # best: gone is gone
```

> **Gotcha.** Disabling a socket-activated service's `.service` unit is not enough. The `.socket` unit still listens and starts the service on the first connection. Disable and mask both.

`mask` links the unit to `/dev/null`, so nothing can start it, including another unit's `Wants=`. Use it for things that must never run; use `disable` for things you might turn back on.

### Pick the tool: firewalld or nftables

Both write nftables rules in the kernel. The question is who owns the ruleset.

| Situation | Pick | Why |
|---|---|---|
| Fedora/RHEL server or workstation | **firewalld** | Zones follow NetworkManager connections, runtime/permanent split gives a free rollback, libvirt/podman/fail2ban all integrate with it |
| Router, VPN gateway, NAT box | **nftables** | Sets, maps, verdict maps, flowtables and precise ordering that firewalld abstracts away |
| Kubernetes node | **neither by hand** | kube-proxy/CNI own the ruleset; add host policy through the CNI or a minimal nft table that does not touch theirs |
| Debian/Ubuntu server | **nftables** (`/etc/nftables.conf`) | `ufw` works but drives iptables-nft through a translation layer that hides the real ruleset |
| Immutable rules shipped as a file in Git | **nftables** | One file, `nft -c -f` in CI, atomic load |

**Never run both managing the same traffic.** firewalld flushes and owns its own `inet firewalld` table; a separate `nftables.service` loading `/etc/sysconfig/nftables.conf` at boot adds a second table that is evaluated independently. A packet must be accepted by **every** base chain on the hook, so a drop in either table wins, which makes debugging miserable.

```bash
systemctl is-enabled firewalld nftables
```

### firewalld

#### Zones in one picture

```text
  packet arrives on an interface or from a source address
        |
        v
  source match? --yes--> that source's zone        (--add-source=10.0.0.0/8)
        | no
        v
  interface's zone, else the default zone          (--change-interface, --set-default-zone)
        |
        v
  zone: services, ports, rich rules, icmp blocks
        |
        v
  zone target: default | ACCEPT | REJECT | DROP     (--set-target)
```

A zone is a trust level: the set of things allowed in from traffic classified into it. **Source-based zones beat interface zones**, which is how you give an admin network more access on the same NIC.

```bash
firewall-cmd --state
firewall-cmd --get-default-zone
firewall-cmd --get-active-zones
firewall-cmd --list-all                       # the default zone
firewall-cmd --list-all --zone=public
firewall-cmd --list-all-zones | less
firewall-cmd --info-service=ssh               # what a service definition opens
firewall-cmd --get-zone-of-interface=eth0
```

> **Gotcha.** The Fedora Workstation default zone `FedoraWorkstation` allows **TCP and UDP 1025–65535 inbound** by design, so desktop apps work without prompts. That makes every high port you start (a dev server on 8080, a debug port, a container published on 5432) reachable from the LAN. On any machine that leaves your desk, switch the default: `sudo firewall-cmd --set-default-zone=public`.

> **Note.** firewalld is installed but **inactive** on the reference workstation this guide was checked on. `firewall-cmd --state` is the first line of any audit; an installed firewall that is not running protects nothing.

#### Runtime vs permanent

Every change goes to one of two configurations:

| Flag | Changes | Survives reload/reboot | Use for |
|---|---|---|---|
| (none) | Runtime only | No | Trying a change safely |
| `--permanent` | On-disk config only | Yes, **but not active until reload** | Committing |
| `--timeout=300` | Runtime add, auto-removed after the time | No | Temporary openings (add operations only) |
| `--runtime-to-permanent` | Copies runtime to disk | Yes | After testing runtime |

**The safe workflow** for anything that could cut you off: make runtime-only changes, with a timer that runs `--reload` (which discards runtime changes and restores the permanent config) unless you cancel it.

```bash
# 1. arm the rollback: reload to permanent config in 5 minutes
sudo systemd-run --on-active=5min --unit=fw-rollback /usr/bin/firewall-cmd --reload

# 2. change runtime only (no --permanent)
sudo firewall-cmd --zone=public --add-rich-rule='rule family="ipv4" source address="ADMIN_CIDR" service name="ssh" accept'
sudo firewall-cmd --zone=public --remove-service=ssh

# 3. test from a NEW connection, then cancel the rollback and commit what is live
sudo systemctl stop fw-rollback.timer
sudo firewall-cmd --runtime-to-permanent
```

> **Gotcha.** `--timeout` applies only to *add* operations. Combining a timed allow with an untimed `--remove-service=ssh` is a trap: when the timer expires the allow disappears and the removal stays, which is exactly the lockout you were trying to avoid. Use `--timeout` for temporary openings, and the reload timer above for restrictive changes.

> **Gotcha.** `--permanent` changes are **not active** until `firewall-cmd --reload`. The classic confusion: you add a port with `--permanent`, test, it fails, you add it again without `--permanent`, it works, you forget the first one existed. Always `--list-all` and `--list-all --permanent` side by side.

```bash
diff <(firewall-cmd --list-all) <(firewall-cmd --list-all --permanent)
sudo firewall-cmd --check-config      # validate permanent config before reloading
sudo firewall-cmd --reload            # load permanent, keep connection state
```

`--complete-reload` also drops connection tracking state, which kills established sessions including yours. Avoid it over SSH.

#### Services and ports

```bash
sudo firewall-cmd --permanent --zone=public --add-service=https
sudo firewall-cmd --permanent --zone=public --remove-service=cockpit
sudo firewall-cmd --permanent --zone=public --remove-service=dhcpv6-client   # static v6 only
sudo firewall-cmd --permanent --zone=public --add-port=9100/tcp
sudo firewall-cmd --reload
```

Prefer named services over bare ports: they document intent and carry helpers. Define your own for an application:

```bash
sudo firewall-cmd --permanent --new-service=myapp
sudo firewall-cmd --permanent --service=myapp --set-description="MyApp API and metrics"
sudo firewall-cmd --permanent --service=myapp --add-port=8443/tcp
sudo firewall-cmd --permanent --service=myapp --add-port=9464/tcp
sudo firewall-cmd --permanent --zone=internal --add-service=myapp
sudo firewall-cmd --reload
```

#### Default-deny inbound

The `public` zone's `default` target rejects anything not explicitly allowed, while still permitting ICMP. For a stricter stance, drop silently:

```bash
sudo firewall-cmd --permanent --zone=public --set-target=DROP
sudo firewall-cmd --reload
```

**Close call: `REJECT` vs `DROP`.** `DROP` gives scanners nothing and makes them wait for timeouts; `REJECT` makes legitimate misconfigured clients fail fast instead of hanging. Tiebreaker: internet-facing interfaces `DROP`, internal networks `default` (reject), because your own colleagues debugging a hung connection is the larger cost internally.

> **Gotcha.** A zone target of `DROP` also drops ICMP that the zone does not explicitly allow. IPv6 needs ICMPv6 neighbour discovery and packet-too-big to function at all. firewalld accepts the essential ICMPv6 types before zone processing, but check `--list-icmp-blocks` after changing targets and test path MTU with a large transfer.

#### Admin networks with source zones

```bash
# SSH and the metrics port only from the admin network
sudo firewall-cmd --permanent --zone=internal --add-source=10.10.0.0/24
sudo firewall-cmd --permanent --zone=internal --add-service=ssh
sudo firewall-cmd --permanent --zone=internal --add-port=9100/tcp
sudo firewall-cmd --permanent --zone=public --remove-service=ssh
sudo firewall-cmd --reload
```

#### Rich rules

Rich rules add conditions (source, destination, rate, logging) a plain service cannot express.

```bash
# SSH from one address only, logged, rate-limited
sudo firewall-cmd --permanent --zone=public --add-rich-rule='
  rule family="ipv4" source address="203.0.113.10/32"
  service name="ssh" log prefix="ssh-allow " level="info" limit value="3/m" accept'

# Rate-limit new HTTPS connections
sudo firewall-cmd --permanent --zone=public --add-rich-rule='
  rule service name="https" accept limit value="50/s"'

# Block a hostile range with a logged drop
sudo firewall-cmd --permanent --zone=public --add-rich-rule='
  rule family="ipv4" source address="198.51.100.0/24" log prefix="blocked " level="warning" limit value="1/m" drop'

sudo firewall-cmd --permanent --zone=public --list-rich-rules
```

For large or changing blocklists, use an ipset, not hundreds of rich rules:

```bash
sudo firewall-cmd --permanent --new-ipset=blocklist --type=hash:net
sudo firewall-cmd --permanent --ipset=blocklist --add-entries-from-file=blocklist.txt
sudo firewall-cmd --permanent --zone=drop --add-source=ipset:blocklist
sudo firewall-cmd --reload
```

#### Logging denied packets

```bash
sudo firewall-cmd --set-log-denied=unicast     # all | unicast | broadcast | multicast | off
journalctl -k -g 'filter_IN_public_REJECT|_DROP' --since '10 min ago'
```

Leave it at `off` or `unicast` in steady state; `all` on a busy LAN floods the journal.

#### Egress filtering with policies

Zones filter traffic *into* the host. Policies (firewalld 0.9+) filter traffic *between* zones, including out of the host itself via the symbolic `HOST` zone. This is how you default-deny egress:

```bash
sudo firewall-cmd --permanent --new-policy=egress
sudo firewall-cmd --permanent --policy=egress --add-ingress-zone=HOST
sudo firewall-cmd --permanent --policy=egress --add-egress-zone=ANY
sudo firewall-cmd --permanent --policy=egress --set-target=REJECT

# Allow only what this host needs
sudo firewall-cmd --permanent --policy=egress --add-service=dns
sudo firewall-cmd --permanent --policy=egress --add-service=ntp
sudo firewall-cmd --permanent --policy=egress --add-service=https         # package mirrors, registries
sudo firewall-cmd --permanent --policy=egress --add-rich-rule='rule family="ipv4" destination address="10.20.0.5/32" port port="5432" protocol="tcp" accept'
sudo firewall-cmd --permanent --policy=egress --add-rich-rule='rule family="ipv4" destination address="10.30.0.10/32" service name="syslog-tls" accept'

sudo firewall-cmd --check-config && sudo firewall-cmd --reload
firewall-cmd --info-policy=egress
```

**Egress filtering is the control that breaks the most post-exploitation.** Payload download, reverse shells and exfiltration all need an outbound connection. A server that talks to a database, a log collector, DNS, NTP and a package mirror has a short allow-list.

> **Gotcha.** `--add-service=https` to `ANY` allows HTTPS to the whole internet, which is what an attacker's C2 uses too. Where you can, restrict by destination: point hosts at an internal mirror and proxy, and allow only those addresses. An allow-list by domain name needs a proxy; firewalls see IPs.

> **Gotcha.** Replies to inbound connections (your SSH session included) are accepted by connection tracking and are not affected by an egress policy. What breaks is anything the host *initiates* that you forgot: OCSP and CRL fetches, time sync, cloud metadata (169.254.169.254), container image pulls, and `dnf` to a mirror that changed address. Build the policy at runtime behind the reload rollback timer first, and watch the denied log.

#### Direct rules are deprecated

`firewall-cmd --direct` passed raw iptables syntax through. It is deprecated; use policies and rich rules. If you inherit direct rules, list them with `firewall-cmd --direct --get-all-rules` and migrate.

### Raw nftables

#### A complete host ruleset

```bash
#!/usr/sbin/nft -f
# /etc/nftables/host.nft
# Default-deny in and out, IPv4 and IPv6 in one table.

flush ruleset

table inet host {
    set admin_v4 {
        type ipv4_addr; flags interval
        elements = { 10.10.0.0/24 }
    }
    set admin_v6 {
        type ipv6_addr; flags interval
        elements = { fd00:10:10::/64 }
    }
    set egress_tcp_v4 {
        type ipv4_addr . inet_service; flags interval
        elements = { 10.20.0.5 . 5432, 10.30.0.10 . 6514, 10.40.0.2 . 443 }
    }

    chain input {
        type filter hook input priority filter; policy drop;

        ct state established,related accept
        ct state invalid drop
        iif "lo" accept

        # ICMP: v4 diagnostics, v6 cannot work without ND and PMTU
        ip protocol icmp icmp type { echo-request, destination-unreachable, time-exceeded } limit rate 10/second accept
        ip6 nexthdr icmpv6 icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-advert, packet-too-big, destination-unreachable, time-exceeded, parameter-problem } accept
        ip6 nexthdr icmpv6 icmpv6 type echo-request limit rate 10/second accept

        tcp dport 22 ip saddr @admin_v4 ct state new accept
        tcp dport 22 ip6 saddr @admin_v6 ct state new accept
        tcp dport { 80, 443 } ct state new accept

        limit rate 5/minute log prefix "nft-in-drop " level info
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
    }

    chain output {
        type filter hook output priority filter; policy drop;

        ct state established,related accept
        ct state invalid drop
        oif "lo" accept

        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        udp dport 53 accept
        tcp dport 53 accept
        udp dport 123 accept
        ip daddr . tcp dport @egress_tcp_v4 accept

        limit rate 5/minute log prefix "nft-out-drop " level info
        reject
    }
}
```

> **Gotcha.** `flush ruleset` removes **every** table, including those that Docker, Podman, libvirt, firewalld and Kubernetes created. On a container or virtualisation host, drop the `flush ruleset` line and use `destroy table inet host` then `table inet host { ... }` so you only replace your own table.

> **Version-sensitive.** `destroy table` (delete if it exists, no error if not) needs nftables 1.0.8 and kernel 6.3. On older systems use `table inet host; delete table inet host` as the idiom.

#### Load it safely

```bash
sudo nft -c -f /etc/nftables/host.nft          # check only, applies nothing
sudo nft list ruleset > /root/nft-before.nft   # snapshot for rollback

# Dead-man switch: restore the snapshot in 3 minutes unless cancelled
sudo systemd-run --on-active=3min --unit=nft-rollback \
  /usr/sbin/nft -f /root/nft-before.nft

sudo nft -f /etc/nftables/host.nft             # atomic: the whole file or nothing
# test from a new connection, then:
sudo systemctl stop nft-rollback.timer
```

Persist on Fedora/RHEL by including it from the service's config:

```bash
echo 'include "/etc/nftables/host.nft"' | sudo tee -a /etc/sysconfig/nftables.conf
sudo systemctl disable --now firewalld
sudo systemctl enable --now nftables
```

Debian/Ubuntu: put the ruleset in `/etc/nftables.conf` and `systemctl enable --now nftables`.

#### Inspecting

```bash
sudo nft list ruleset
sudo nft -a list chain inet host input          # with rule handles, for deletion
sudo nft delete rule inet host input handle 17
sudo nft add element inet host admin_v4 '{ 10.10.1.5 }'   # sets change without reloading rules
sudo nft list set inet host admin_v4
sudo nft monitor trace                          # after adding: meta nftrace set 1 to a rule
```

> **Gotcha.** Rules added with `nft add` at the command line are runtime only and vanish at reboot or at the next `nft -f`. The file is the truth; edit the file, check, load.

### Containers punch holes

Container engines insert their own NAT and filter rules for published ports. Those rules sit in chains that run before, or independently of, your zone input rules.

- **Docker:** `docker run -p 5432:5432` publishes on `0.0.0.0` via DNAT in its own chains; traffic is **forwarded** to the container, not delivered to the host's input chain, so firewalld zone rules for the host do not apply. With firewalld running, Docker puts its bridges in a `docker` zone.
- **Rootful Podman (netavark):** similar DNAT rules, in its own nftables or iptables table, with firewalld integration.
- **Rootless Podman:** ports are bound by a userspace process (`pasta` or `rootlessport`) in the host's network namespace, so they **do** go through the input chain and your firewall applies normally.

```bash
sudo nft list tables                 # see who owns what: firewalld, docker, netavark, ...
sudo ss -tlpn | grep -E 'docker-proxy|rootlessport|pasta|conmon'
```

**Default: bind published ports to loopback** (`-p 127.0.0.1:5432:5432`) or to a specific internal address, and front them with a reverse proxy that the firewall does see. To make it the default for every Docker container, set `"ip": "127.0.0.1"` in `/etc/docker/daemon.json`.

> **Version-sensitive.** Docker 29.0 added an **experimental** nftables firewall backend (`"firewall-backend": "nftables"` in `daemon.json`, or `--firewall-backend=nftables`); iptables is still the default (`docker info` shows `Firewall Backend: iptables` on Docker 29.8). With nftables, Docker creates `ip docker-bridges` and `ip6 docker-bridges` tables and there is **no `DOCKER-USER` chain**: put your filtering in your own table with base chains on the same hooks. It cannot be used in Swarm mode, and Docker will not enable IP forwarding itself ([docs.docker.com](https://docs.docker.com/engine/network/firewall-nftables/)).

### IPv6 is not optional

Every rule you write for IPv4 needs an IPv6 twin, or you need to be certain IPv6 is not routed to the host. Most hosts have a link-local address at minimum, and many cloud and ISP networks hand out global IPv6 by router advertisement without anyone asking.

```bash
ip -6 addr show scope global
ss -tlpn6                                     # IPv6 listeners
sysctl net.ipv6.bindv6only                    # 0: [::] sockets also accept IPv4
```

| Tool | IPv6 covered? |
|---|---|
| firewalld | Yes: zones apply to both families unless a rule names `family="ipv4"` |
| nftables `inet` table | Yes |
| nftables `ip` table | **No**, IPv4 only |
| legacy `iptables` | **No**: `ip6tables` is a separate ruleset |
| `ufw` | Yes if `IPV6=yes` in `/etc/default/ufw` (the default) |

> **Gotcha.** A rich rule with `family="ipv4" source address=...` allowing SSH from the admin network, plus `--remove-service=ssh`, leaves IPv6 SSH blocked, which is fine. The reverse mistake is common and dangerous: a hand-written iptables ruleset with `-P INPUT DROP` and no ip6tables equivalent leaves every service wide open over IPv6.

**Leave IPv6 enabled and firewall it.** Disabling it with `net.ipv6.conf.all.disable_ipv6=1` breaks software that binds `::1`, confuses NetworkManager, and is undone by the first interface created after the sysctl ran. If a host genuinely must not have routable IPv6, stop accepting router advertisements instead:

```ini
# /etc/sysctl.d/60-ipv6-no-ra.conf
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
```

### sysctl network hardening

Put these in one file, named after 50 so it overrides systemd's `50-default.conf` (for sysctl.d, **the last file wins**, unlike sshd).

```ini
# /etc/sysctl.d/60-net-hardening.conf

# Reverse path filtering: drop packets whose source would not route back via
# the arrival interface. 1 = strict, 2 = loose (systemd default).
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# SYN flood protection
net.ipv4.tcp_syncookies = 1

# Never accept ICMP redirects (route injection)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Never send redirects (we are not a router)
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# No source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Log packets with impossible source addresses
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore broadcast pings and bogus ICMP errors
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# TIME-WAIT assassination protection
net.ipv4.tcp_rfc1337 = 1
```

```bash
sudo sysctl --system                         # load all sysctl.d files in order
sysctl net.ipv4.conf.all.rp_filter net.ipv4.tcp_syncookies   # verify
systemd-analyze cat-config sysctl.d | grep -n rp_filter      # which file set it
```

| Key | Safe value | Breaks |
|---|---|---|
| `rp_filter = 1` | Single-homed hosts | Multi-homed hosts with asymmetric routing, some VPNs and policy routing. Use `2` there |
| `accept_redirects = 0` | Everywhere | Nothing on a correctly routed network |
| `send_redirects = 0` | Hosts that are not routers | A Linux router that relies on redirects (rare) |
| `log_martians = 1` | Most hosts | Floods the log on networks with broken routing; set 0 if so |
| `ip_forward = 0` | Plain servers | **Containers, Kubernetes, libvirt NAT, VPN servers**. Leave it 1 there |
| `accept_ra = 0` | Statically addressed servers | Hosts that get IPv6 by SLAAC |

> **Gotcha.** Setting `net.ipv4.ip_forward = 0` on a Docker, Podman (rootful), libvirt or Kubernetes host breaks container networking instantly. Those tools set it to 1 at start (except Docker's nftables backend, which refuses to start networks that need forwarding rather than enabling it). Leave forwarding alone on those hosts and filter the `forward` hook instead.

> **Note.** The `.all.` and `.default.` variants are different: `default` applies to interfaces created later, `all` is combined with the per-interface value (for `rp_filter` the kernel uses the maximum of `all` and the interface value). Set both, and check a real interface with `sysctl net.ipv4.conf.eth0.rp_filter`.

firewalld has its own reverse-path check for IPv6 (`IPv6_rpfilter=yes` in `/etc/firewalld/firewalld.conf`) because IPv6 has no `rp_filter` sysctl. Leave it on.

### Debian/Ubuntu equivalents

| Fedora/RHEL | Debian/Ubuntu |
|---|---|
| `firewall-cmd --permanent --add-service=https` | `nft` rule in `/etc/nftables.conf`, or `ufw allow https` |
| `firewall-cmd --list-all` | `nft list ruleset` / `ufw status verbose` |
| `systemd-run ... firewall-cmd --reload` rollback | `systemd-run` restoring a saved `nft` ruleset |
| `/etc/sysconfig/nftables.conf` | `/etc/nftables.conf` |
| firewalld policies for egress | `nft` output chain, or `ufw default deny outgoing` |

### Traps

- A socket-activated service keeps listening until its `.socket` unit is disabled.
- `FedoraWorkstation` zone opens 1025–65535 inbound.
- `--permanent` does nothing until `--reload`; runtime-only changes vanish on reload.
- `--complete-reload` kills established connections, including yours.
- `flush ruleset` deletes Docker's, libvirt's and firewalld's tables too.
- Docker-published ports bypass host input rules; bind to `127.0.0.1`.
- An `ip`-family nft table or a plain iptables ruleset leaves IPv6 open.
- `ip_forward = 0` breaks every container runtime.
- sysctl.d is last-file-wins; sshd_config.d is first-value-wins.

### Checklist

- [ ] `ss -tulpn` reviewed; every `0.0.0.0`/`[::]` listener has an owner and a reason.
- [ ] Unneeded services and their `.socket` units disabled and masked.
- [ ] `firewall-cmd --state` is `running` (or nftables is enabled and loaded).
- [ ] Default zone chosen deliberately, not `FedoraWorkstation` on a server.
- [ ] Runtime and permanent configs match.
- [ ] SSH and admin ports reachable only from admin sources.
- [ ] Egress default-deny on servers with a known destination list.
- [ ] IPv6 listeners and rules checked separately.
- [ ] Container ports bound to loopback unless there is a reason.
- [ ] Network sysctls in `/etc/sysctl.d/60-net-hardening.conf`, verified with `sysctl`.


---


<a id="05-selinux-in-practice"></a>

## 05 · SELinux in practice

*Almost every SELinux denial is a label that does not match where you put a file, a port you did not declare, or a boolean you did not flip. Read the denial, fix the label, and a custom policy module is almost never needed.*

### The model in five lines

- Every process has a **domain** (`httpd_t`, `sshd_t`, `container_t`) and every file, port and socket has a **type** (`httpd_sys_content_t`, `ssh_port_t`).
- The policy is a list of **allow rules**: domain X may perform permission P on objects of type Y. Anything not allowed is denied.
- Labels on files come from the **file context database**, a set of path regexes, applied at install time and by `restorecon`. They are stored in extended attributes on the file.
- **Booleans** are switches the policy authors built in for common variations (`httpd_can_network_connect`).
- The **targeted** policy (Fedora and RHEL default) confines network-facing and system daemons; interactive users run as `unconfined_t`, so SELinux rarely gets in the way of a shell.

**SELinux applies after DAC**, to root as well. A denial means DAC already said yes and the policy said no.

### Modes and state

```bash
getenforce                        # Enforcing | Permissive | Disabled
sestatus                          # mode, policy, config-file mode, MLS status
sestatus -b | head -30            # plus booleans
cat /etc/selinux/config           # SELINUX= and SELINUXTYPE= at boot
```

| Mode | Denials | Logged | Use |
|---|---|---|---|
| Enforcing | Blocked | Yes | Always, in production |
| Permissive | Allowed | Yes, once per access pattern | Collecting denials during a migration, briefly |
| Per-domain permissive | Allowed for one domain only | Yes | **Debugging one service while everything else stays enforced** |
| Disabled | No policy loaded | No | Never. See the one-way door below |

```bash
sudo setenforce 0                   # permissive until reboot (whole system)
sudo setenforce 1                   # back to enforcing
sudo semanage permissive -a httpd_t # make ONE domain permissive, persistently
sudo semanage permissive -l         # list permissive domains
sudo semanage permissive -d httpd_t # back to enforcing for that domain
```

**Use per-domain permissive, not `setenforce 0`.** It keeps every other daemon confined while you collect denials for the one you are fixing, and it shows up in `semanage permissive -l` so nobody forgets it.

> **One-way door.** `SELINUX=disabled` in `/etc/selinux/config` or `selinux=0` on the kernel command line means files created while disabled get **no labels at all**. Re-enabling needs a full relabel (`sudo touch /.autorelabel` and a reboot that can take a long time on large filesystems), and services fail in odd ways until it finishes. Anything that happened while the box was unconfined stays unknown. Permissive preserves labels; disabled does not.

> **Version-sensitive.** Kernels 6.4 and later removed runtime disabling (`SELINUX=disabled` used to unload SELinux early in boot). On current Fedora, `SELINUX=disabled` in the config only stops userspace loading a policy; `selinux=0` on the kernel command line is the real off switch. Neither is something you should need.

Boot into permissive once (for recovery) without editing any file: add `enforcing=0` to the kernel command line at the GRUB menu.

### Reading contexts

A context is `user:role:type:level`. For almost everything you do, **only the type matters**.

```bash
id -Z                                # your own context: unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023
ps -eZ | grep -E 'sshd|chronyd|nginx'
ps -eZ | grep container_t            # containers, each with unique MCS categories
ls -Z /var/www/html
ls -Zd ~/.ssh                        # ssh_home_t: sshd may read authorized_keys here
stat -c '%C %n' /etc/shadow
```

Expected vs actual label for any path:

```bash
matchpathcon /srv/www/index.html     # what the policy says it SHOULD be
ls -Z /srv/www/index.html            # what it IS
sudo restorecon -nv /srv/www/index.html   # -n: show what would change, change nothing
```

**`matchpathcon` vs `ls -Z` is the single most useful SELinux diagnostic.** When they differ, you have found the bug.

> **Gotcha.** `mv` keeps the source file's label; `cp` gives the new file the label of its destination directory. A config file written in your home directory and `mv`ed into `/etc/nginx/` arrives as `user_home_t`, and nginx cannot read it. `restorecon` fixes it; `cp` or `install` would have avoided it.

#### Ports have types too

```bash
sudo semanage port -l | grep -E '^(http_port_t|ssh_port_t|postgresql_port_t) '
sudo semanage port -l -C             # local customisations only
```

### Fixing denials: the decision tree

```text
  AVC denial in the audit log
         |
         v
  Is the file/dir label wrong for where it lives?   matchpathcon vs ls -Z
     yes -> restorecon (standard path) or semanage fcontext + restorecon (custom path)
         |
         no
         v
  Is it a network bind/connect to a non-standard port?
     yes -> semanage port -a -t TYPE_port_t -p tcp PORT
         |
         no
         v
  Does audit2why say a boolean would allow it?
     yes -> setsebool -P BOOLEAN on   (read what else it allows first)
         |
         no
         v
  Is the application doing something genuinely unusual that you intend?
     yes -> small local policy module (audit2allow), reviewed line by line
     no  -> you may have found an actual attack or a bug. Investigate.
```

Work down the tree in that order. Each step is broader than the one before.

### Reading AVC denials

Denials go to the audit log (`/var/log/audit/audit.log`) as `type=AVC`. Reading it needs root.

```bash
sudo ausearch -m AVC,USER_AVC -ts recent          # last 10 minutes
sudo ausearch -m AVC -ts today -c nginx           # by command name
sudo ausearch -m AVC -ts boot -i                  # -i: interpret numeric fields
sudo ausearch -m AVC -ts recent --raw | audit2why
```

A denial, annotated:

```text
type=AVC msg=audit(1758620000.123:4521): avc:  denied  { read } for  pid=2211
  comm="nginx" name="index.html" dev="dm-0" ino=123456
  scontext=system_u:system_r:httpd_t:s0              <- who: nginx in domain httpd_t
  tcontext=unconfined_u:object_r:user_home_t:s0      <- what: a file labelled user_home_t
  tclass=file permissive=0                           <- object class, and it was blocked
```

Read it as: **domain `httpd_t` was denied `read` on a `file` of type `user_home_t`.** The fix is almost certainly the file's label, not the policy.

#### audit2why

`audit2why` (an alias for `audit2allow -w`) explains each denial and says whether a boolean would allow it:

```bash
sudo ausearch -m AVC -ts recent --raw | audit2why
sudo audit2why -a                    # every denial in the log
```

Typical outputs and what they mean:

| audit2why says | Fix |
|---|---|
| "Missing type enforcement (TE) allow rule" | Probably a label; check `matchpathcon`. Module only if the label is right |
| "The boolean X was set incorrectly" | `setsebool -P X on`, after reading what else X permits |
| "Constraint violation" / MCS | Categories differ, often containers sharing files; see `:z`/`:Z` |
| "Policy is disabled" | You are debugging a box with SELinux off |

#### sealert

`setroubleshoot` turns denials into plain-language suggestions, including the exact `semanage` command. It is not installed by default on servers.

```bash
sudo dnf install setroubleshoot-server
sudo sealert -a /var/log/audit/audit.log | less
sudo sealert -l '*'                                  # all alerts it has recorded
journalctl -t setroubleshoot --since today
```

Its suggestions are ranked by confidence. Take the high-confidence label or boolean suggestion; be suspicious of the low-confidence "generate a local policy module" one at the end, which it always offers.

#### Denials you cannot see: dontaudit

The policy contains `dontaudit` rules that suppress expected, harmless denials. Occasionally one hides the denial you are chasing (the app fails, but nothing appears in the log).

```bash
sudo semodule -DB        # rebuild policy with dontaudit rules removed
# reproduce the failure, then read the log
sudo semodule -B         # rebuild with dontaudit rules back (do not forget)
```

### File contexts: semanage fcontext and restorecon

#### Standard paths

If a file is in a path the policy already knows (`/var/www`, `/etc/nginx`, `/var/lib/pgsql`), restore the default label:

```bash
sudo restorecon -Rv /var/www/html
sudo restorecon -Rnv /etc          # dry run over a tree: what is mislabelled?
```

#### Custom paths

When you put data somewhere non-standard, tell the policy what the path should be, then apply it. Two steps, always both:

```bash
# 1. add a rule to the file context database (persistent, survives relabel)
sudo semanage fcontext -a -t httpd_sys_content_t '/data/web(/.*)?'

# 2. apply it to the files that exist now
sudo restorecon -Rv /data/web
```

Or declare the custom path equivalent to a standard one, so it inherits every rule for that tree:

```bash
sudo semanage fcontext -a -e /var/www /data/web
sudo restorecon -Rv /data/web
```

Manage your customisations:

```bash
sudo semanage fcontext -l -C                     # local additions only
sudo semanage fcontext -d '/data/web(/.*)?'      # delete one
sudo semanage export > selinux-local.txt         # all local customisations, for Git
sudo semanage import < selinux-local.txt         # apply on another host
```

> **Gotcha.** `chcon -t httpd_sys_content_t FILE` changes the label immediately but not the database. The next `restorecon`, relabel or package update puts the old label back and the service breaks again weeks later. Use `chcon` only for a quick experiment; make it permanent with `semanage fcontext`.

> **Gotcha.** The path regex must match the whole path and is anchored. `'/data/web(/.*)?'` covers the directory and everything under it; `'/data/web/*'` is a regex (zero or more slashes), not a glob, and does not do what it looks like.

> **Note.** Some non-standard paths are already covered by broad default rules. On Fedora 43 `matchpathcon /srv/www/index.html` returns `httpd_sys_content_t` out of the box. Check with `matchpathcon` before adding a rule you may not need.

Common types to know:

| Type | For |
|---|---|
| `httpd_sys_content_t` | Read-only web content |
| `httpd_sys_rw_content_t` | Web content the server writes (uploads, caches) |
| `httpd_log_t` | Web server logs |
| `container_file_t` | Files containers may read and write |
| `public_content_t` | Shared read-only between FTP, HTTP, Samba |
| `ssh_home_t` | `~/.ssh` contents |
| `var_log_t` | Generic logs |
| `bin_t` | Executables run from custom paths (`/opt/app/bin`) |
| `etc_t` | Configuration |

### Ports

A daemon binding a non-standard port is denied `name_bind`. Label the port rather than changing the policy:

```bash
sudo semanage port -l | grep http_port_t
sudo semanage port -a -t http_port_t -p tcp 8443
sudo semanage port -m -t http_port_t -p tcp 9000     # -m: port already has another type
sudo semanage port -d -t http_port_t -p tcp 8443
```

For SSH on a non-standard port (chapter 03):

```bash
sudo semanage port -a -t ssh_port_t -p tcp 2222
```

Outbound connections are controlled too. `httpd_t` connecting to a database uses `name_connect` and is governed by booleans (`httpd_can_network_connect_db`) or port types.

### Booleans

```bash
getsebool -a | grep httpd                  # all httpd booleans and their state
sudo semanage boolean -l | grep httpd      # with descriptions
sudo semanage boolean -l -C                # booleans changed from default
sudo setsebool -P httpd_can_network_connect_db on   # -P: persistent
sudo setsebool httpd_can_network_connect on          # runtime only, lost at reboot
```

Booleans that come up constantly:

| Boolean | Allows |
|---|---|
| `httpd_can_network_connect` | Web server outbound to **any** port (reverse proxies). Broad |
| `httpd_can_network_connect_db` | Web server to database ports only. Prefer this |
| `httpd_can_network_relay` | Web server as a proxy to HTTP ports |
| `httpd_enable_homedirs` | Serve `~/public_html` |
| `container_manage_cgroup` | Containers running systemd inside |
| `container_use_devices` | Containers using host devices (GPUs) |
| `virt_use_nfs` / `virt_use_samba` | VMs on network storage |
| `domain_can_mmap_files` | Legacy; off on modern policy |

> **Gotcha.** A boolean is a policy branch the authors thought about, so it is safer than a custom module, but some are broad. `httpd_can_network_connect` lets a compromised web server connect anywhere, which is exactly the capability a reverse shell needs. Pick the narrowest boolean that works (`_db`, `_relay`), or label the specific port.

### Writing a local module (the last resort)

When the labels are right, no boolean fits, and the application genuinely needs an access the policy does not grant, generate a small module from the denials:

```bash
# 1. make just this domain permissive, reproduce the whole workflow so every denial is logged
sudo semanage permissive -a myapp_t

# 2. collect the denials since the last policy load
sudo ausearch -m AVC -ts recent --raw > avc.log

# 3. READ what would be allowed, before building anything
audit2allow -i avc.log

# 4. build a named module
audit2allow -i avc.log -M local_myapp
# writes local_myapp.te (source) and local_myapp.pp (compiled)

# 5. review the .te file line by line, then install
cat local_myapp.te
sudo semodule -i local_myapp.pp
sudo semanage permissive -d myapp_t

# manage
sudo semodule -l | grep local_
sudo semodule -r local_myapp
```

A reviewed `.te` looks like this, and should be about this short:

```text
module local_myapp 1.0;

require {
    type httpd_t;
    type myapp_cache_t;
    class file { read open getattr };
}

allow httpd_t myapp_cache_t:file { read open getattr };
```

**Why it is the last resort:** `audit2allow` turns whatever happened into policy. If the denial was caused by a mislabelled file, you have just granted a domain access to a generic type like `user_home_t` or `var_t`, which covers far more files than the one you meant. If the denial was an attacker probing, you have legalised the probe. Every line must be one you would defend.

Red flags in a generated `.te`:

| Line pattern | Why it is wrong |
|---|---|
| `allow X_t user_home_t:...`, `default_t`, `var_t`, `tmp_t`, `etc_t` write | Generic type: the real fix is a specific label on the specific path |
| `allow X_t self:capability { sys_admin dac_override ... }` | Granting root-like powers; find why the app thinks it needs them |
| `allow X_t shadow_t:file read` | Reading password hashes. Never |
| `allow X_t unreserved_port_t:tcp_socket name_bind` | Bind any high port; label the one port instead |
| `execmem`, `execstack`, `execmod` | Weakens memory protections; usually a JIT, sometimes an exploit |

Keep module sources (`.te`) in Git, not only the `.pp`, and version them (`module local_myapp 1.1;`).

### Containers: container_t and :Z

Podman and Docker (on Fedora with SELinux enabled) run containers as `container_t`, each with a unique pair of MCS categories (`s0:c123,c456`). Two containers cannot touch each other's files even though both are `container_t`, because their categories differ.

```bash
podman run --rm fedora:43 cat /proc/self/attr/current
# system_u:system_r:container_t:s0:c214,c753
ps -eZ | grep container_t
```

A bind mount of a host directory is denied by default because host files are not `container_file_t`:

```bash
podman run --rm -v ~/data:/data fedora:43 ls /data
# ls: cannot open directory '/data': Permission denied
```

| Suffix | Relabels host files to | Categories | Use |
|---|---|---|---|
| `:Z` | `container_file_t` | This container's own pair | One container owns the directory |
| `:z` | `container_file_t` | Shared (no categories) | Several containers share it |
| none | untouched | n/a | Named volumes, which podman labels itself |

```bash
podman run --rm -v ~/data:/data:Z fedora:43 ls /data
podman run --rm -v ~/shared:/shared:z fedora:43 ls /shared
```

> **One-way door.** `:Z` and `:z` **relabel the host files in place**. Never use them on `/`, `/home`, `/etc`, `/usr`, `/var` or a home directory: `-v /home/USER:/h:Z` relabels your whole home, sshd can no longer read `~/.ssh/authorized_keys` (it needs `ssh_home_t`), and your next SSH login fails. Recover with `restorecon -RF /home/USER` from a console. Use `:Z` only on directories that exist for the container.

> **Gotcha.** `:Z` on a directory another container already uses with `:Z` steals it: the categories change to the new container's pair and the first container loses access. Use `:z` for sharing, or a named volume.

For a container that genuinely needs broader access, prefer a targeted opt-out over disabling labelling:

```bash
podman run --security-opt label=type:container_runtime_t ...   # specific type
podman run --security-opt label=disable ...                     # no confinement: last resort
```

`udica` generates a per-container SELinux policy from a container's inspect output when `container_t` is too tight and `label=disable` too loose.

### AppArmor on Ubuntu

AppArmor is path-based MAC: profiles in `/etc/apparmor.d/` list which paths a program may read, write or execute, and which capabilities and network access it has. No labels on files, so no relabelling, but also no protection when a file is reachable by another path (hard links, bind mounts).

| Task | SELinux (Fedora/RHEL) | AppArmor (Ubuntu/Debian) |
|---|---|---|
| Status | `sestatus` | `sudo aa-status` |
| What confines a process | `ps -eZ` | `ps auxZ`, or `cat /proc/PID/attr/current` |
| Permissive for one service | `semanage permissive -a X_t` | `sudo aa-complain /etc/apparmor.d/usr.sbin.nginx` |
| Enforce | `semanage permissive -d X_t` | `sudo aa-enforce /etc/apparmor.d/usr.sbin.nginx` |
| Unconfine one profile | (no clean equivalent) | `sudo aa-disable PROFILE` |
| Read denials | `ausearch -m AVC` | `journalctl -k -g 'apparmor="DENIED"'` |
| Generate/extend policy | `audit2allow -M` | `sudo aa-logprof` (interactive, from logs), `aa-genprof` |
| Allow a custom path | `semanage fcontext` + `restorecon` | Edit `/etc/apparmor.d/local/PROFILE`, then `apparmor_parser -r` |
| Containers | `container_t` + `:Z` | `docker-default` profile; `--security-opt apparmor=PROFILE` |

```bash
sudo aa-status
sudo apparmor_parser -r /etc/apparmor.d/usr.sbin.nginx    # reload one profile after editing
journalctl -k -g 'apparmor="DENIED"' --since today
```

> **Note.** The `aa-*` tools come from `apparmor-utils` (`sudo apt install apparmor-utils`); the commands match the [Ubuntu Server AppArmor guide](https://ubuntu.com/server/docs/how-to/security/apparmor/). `aa-disable` does what the guide spells out by hand: a symlink in `/etc/apparmor.d/disable/` plus `apparmor_parser -R`. Ubuntu 24.04 and later also restrict unprivileged user namespaces through AppArmor (`kernel.apparmor_restrict_unprivileged_userns = 1`, off-by-default in 23.10); an application that needs them gets a profile, and the sysctl is the blunt global off switch.

### Traps

- `setenforce 0` "just to test" and never back; use `semanage permissive -a DOMAIN_t`.
- `SELINUX=disabled` costs a full relabel to undo.
- `mv` keeps the old label; `cp` and `install` take the destination's.
- `chcon` is undone by the next `restorecon`; use `semanage fcontext`.
- `semanage fcontext` without `restorecon` changes nothing on disk yet.
- `:Z` on a home directory breaks SSH logins.
- `audit2allow -M` on unreviewed denials grants generic types and root capabilities.
- A silent failure with no AVC may be a `dontaudit` rule: `semodule -DB`, then `-B`.
- `httpd_can_network_connect` is much broader than `httpd_can_network_connect_db`.

### Checklist

- [ ] `getenforce` is `Enforcing`; `/etc/selinux/config` says `enforcing`.
- [ ] `semanage permissive -l` is empty, or every entry has an owner and a date.
- [ ] `sudo ausearch -m AVC -ts today` reviewed; no unexplained denials.
- [ ] Custom paths use `semanage fcontext` rules, exported to Git with `semanage export`.
- [ ] Changed booleans (`semanage boolean -l -C`) are each justified.
- [ ] Local modules (`semodule -l | grep local_`) have reviewed `.te` sources in Git.
- [ ] No container runs with `label=disable` without a written reason.


---


<a id="06-kernel-boot-and-systemd"></a>

## 06 · Kernel, boot and systemd

*Most kernel exploits need a subsystem an ordinary server never uses: unprivileged BPF, ptrace of unrelated processes, module loading, user namespaces. Close those, make root unable to rewrite the running kernel, and sandbox every service so a daemon compromise stays a daemon compromise.*

### Kernel sysctl hardening

Every setting below removes attack surface that an ordinary server does not use. Put them in one file. sysctl.d files are applied in lexical order and **the last value wins**, so a `60-` name overrides systemd's `50-default.conf` and the distro's `10-` files.

```ini
# /etc/sysctl.d/60-kernel-hardening.conf

# Hide kernel pointers from everyone, including root (breaks KASLR info leaks)
kernel.kptr_restrict = 2

# dmesg only for CAP_SYSLOG (kernel log leaks addresses and hardware details)
kernel.dmesg_restrict = 1

# ptrace: 1 = only descendants, 2 = only CAP_SYS_PTRACE, 3 = nobody (until reboot)
kernel.yama.ptrace_scope = 2

# No BPF for unprivileged users. 1 = off until reboot, 2 = off but root may re-enable
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2

# Link and FIFO protections in world-writable sticky directories
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2

# No core dumps from SUID programs
fs.suid_dumpable = 0

# Full ASLR
kernel.randomize_va_space = 2

# Perf events for CAP_PERFMON only
kernel.perf_event_paranoid = 3

# SysRq: 0 off, 176 = sync + remount-ro + reboot (useful on a console-only box)
kernel.sysrq = 0

# Do not autoload obscure TTY line disciplines (historic exploit path)
dev.tty.ldisc_autoload = 0

# userfaultfd for privileged users only (widely used in kernel exploit races)
vm.unprivileged_userfaultfd = 0

# io_uring: 0 on, 1 only for the io_uring_group, 2 off for everyone
kernel.io_uring_disabled = 2

# Block kexec (replacing the running kernel) until reboot. One-way per boot.
kernel.kexec_load_disabled = 1
```

```bash
sudo sysctl --system                                   # apply every sysctl.d file in order
sudo sysctl -p /etc/sysctl.d/60-kernel-hardening.conf  # apply just this file
systemd-analyze cat-config sysctl.d | less             # every file, in the order applied
sysctl kernel.kptr_restrict kernel.yama.ptrace_scope   # verify the live value
```

#### What each one costs

| Key | Value | Breaks | Fedora 43 default |
|---|---|---|---|
| `kernel.kptr_restrict` | 2 | `perf` symbol resolution for non-root, some profilers | kernel default 0 |
| `kernel.dmesg_restrict` | 1 | `dmesg` as a user; use `sudo dmesg` or `journalctl -k` | kernel config dependent |
| `kernel.yama.ptrace_scope` | 1 dev, 2 server | 1: `gdb -p`/`strace -p` on non-children. 2: those tools without root. 3: all ptrace, **until reboot** | 0 (`10-default-yama-scope.conf`) |
| `kernel.unprivileged_bpf_disabled` | 1 | Unprivileged BPF tools; almost nothing in practice | 2 (kernel config) |
| `net.core.bpf_jit_harden` | 2 | Slight BPF JIT overhead | 0 |
| `fs.protected_fifos` / `_regular` | 2 | Rare scripts that write to other users' files in `/tmp` | 1 (systemd) |
| `fs.suid_dumpable` | 0 | Core dumps of SUID programs via systemd-coredump | 2 (systemd `50-coredump.conf`) |
| `kernel.perf_event_paranoid` | 3 | `perf` as non-root | 2 |
| `kernel.sysrq` | 0 | Magic SysRq on a hung console | 16 (sync only) |
| `dev.tty.ldisc_autoload` | 0 | Serial devices using unusual line disciplines (load the module explicitly) | 1 |
| `kernel.io_uring_disabled` | 2 | Software using io_uring: some databases, QEMU, newer runtimes fall back or fail | 0 |
| `kernel.kexec_load_disabled` | 1 | kdump crash kernels loaded after boot, kexec reboots | 0 |

> **Gotcha.** `kernel.yama.ptrace_scope = 3` and `kernel.kexec_load_disabled = 1` cannot be lowered without a reboot. Set 3 on a production box and the next time you need `strace -p` on a hung process, you cannot. Use 2 unless you have a specific reason.

> **Version-sensitive.** `perf_event_paranoid = 3` is honoured only by kernels carrying a distro patch (Debian, Ubuntu, Android); upstream kernels treat values above 2 as 2. `kernel.io_uring_disabled` needs kernel 6.6+. `fs.protected_fifos` and `fs.protected_regular` need 4.19+.

> **Gotcha.** Setting `fs.suid_dumpable = 0` overrides systemd's `50-coredump.conf`, which sets 2 so that SUID crashes still reach `systemd-coredump` (which stores them root-only). Either choice is defensible; 0 is simpler to reason about.

#### User namespaces

```bash
sysctl user.max_user_namespaces
```

Setting it to `0` removes unprivileged user namespaces, and with them a large class of kernel privilege escalations that are only reachable from inside one. It also breaks rootless Podman, Flatpak, Chromium and Firefox sandboxes, `bwrap`, and systemd's `PrivateUsers=` for non-root managers.

**Close call.** On a server that runs no rootless containers and no browsers, set `user.max_user_namespaces = 0`. On a workstation or a rootless-Podman CI runner, leave it and keep the kernel patched. The tiebreaker is whether anything on the box uses rootless containers; `lsns -t user` shows current users.

#### Modules

```bash
lsmod | wc -l
modinfo -F signer MODULE              # who signed it
cat /proc/sys/kernel/modules_disabled
```

Block modules you know you never want (obscure filesystems and network protocols with a history of bugs):

```ini
# /etc/modprobe.d/60-blacklist-rare.conf
install cramfs /bin/false
install freevxfs /bin/false
install hfs /bin/false
install hfsplus /bin/false
install jffs2 /bin/false
install udf /bin/false
install dccp /bin/false
install sctp /bin/false
install rds /bin/false
install tipc /bin/false
install firewire-core /bin/false
install usb-storage /bin/false
```

`install MODULE /bin/false` beats `blacklist MODULE`: `blacklist` only stops alias-based autoloading, while `install ... /bin/false` also stops explicit `modprobe` and dependency loading. Skip `usb-storage` on anything where someone might need a USB stick.

> **One-way door.** `kernel.modules_disabled = 1` stops **all** module loading until reboot: a new USB NIC, a filesystem you need to mount for recovery, a netfilter module a firewall rule needs. Only on appliances with fixed hardware, set as the last step of boot.

### Lockdown and Secure Boot

#### Kernel lockdown

Lockdown stops root from modifying the running kernel: no `/dev/mem`, no unsigned modules, no unsigned kexec, no hibernation to an unencrypted image, no raw MSR writes. It separates "root" from "kernel", which is the point of every other kernel control.

```bash
cat /sys/kernel/security/lockdown
# [none] integrity confidentiality     <- brackets mark the active mode
```

| Mode | Blocks |
|---|---|
| `none` | Nothing |
| `integrity` | Anything that would let root modify the running kernel |
| `confidentiality` | Also anything that would let root *read* kernel memory (kprobes-based tracing, some BPF, `/proc/kcore`) |

Fedora kernels enable `integrity` automatically when booted with Secure Boot on: they are built with `CONFIG_LOCK_DOWN_IN_EFI_SECURE_BOOT=y` (verified in `/boot/config-7.2.5-100.fc43.x86_64`), and otherwise default to `none` (`CONFIG_LOCK_DOWN_KERNEL_FORCE_NONE=y`). To force it without Secure Boot, or to raise it:

```bash
sudo grubby --update-kernel=ALL --args="lockdown=integrity"
sudo grubby --info=DEFAULT | grep args
```

Lockdown can be raised at runtime (`echo integrity > /sys/kernel/security/lockdown`) but never lowered without a reboot.

> **Gotcha.** Lockdown `integrity` refuses to load unsigned kernel modules. Out-of-tree modules built by DKMS or akmods (NVIDIA, VirtualBox, ZFS) stop loading until you sign them with a key enrolled in MOK. `confidentiality` also breaks many eBPF tracing tools (bpftrace, some Falco and Tetragon probes).

#### Secure Boot

Secure Boot makes firmware verify the bootloader, which verifies the kernel, which (with lockdown) verifies modules. Without it, anyone with physical or hypervisor console access can boot a modified kernel and read everything.

```bash
mokutil --sb-state                     # SecureBoot enabled | disabled
mokutil --list-enrolled | grep -E 'Subject:|Issuer:'
mokutil --list-new                     # keys queued for enrolment at next boot
bootctl status 2>/dev/null | head -20  # firmware, Secure Boot, boot loader details
```

Enrol your own key for locally built modules through shim's Machine Owner Key list rather than replacing the platform keys:

```bash
# Generate a signing key (akmods ships kmodgenca for this on Fedora; shown generically)
openssl req -new -x509 -newkey rsa:2048 -nodes -days 3650 \
  -subj "/CN=HOSTNAME module signing/" \
  -keyout /root/mok.key -outform DER -out /root/mok.der
sudo mokutil --import /root/mok.der     # asks for a one-time password
# reboot: the MokManager screen asks for that password to confirm
mokutil --test-key /root/mok.der
```

> **One-way door.** Replacing the firmware's platform key (PK) and KEK with your own, or removing Microsoft's UEFI CA from `db`, can stop GPU and NIC option ROMs from loading; some boards then show no display and cannot reach setup. Use shim and MOK, which layer on top of the existing chain.

> **Note.** The reference box reports `SecureBoot disabled` and lockdown `none`. That makes the TPM2 unlock below weaker (PCR 7 measures Secure Boot state, and "off" is a stable, forgeable state). Turning Secure Boot on is a firmware setting, reversible, and should come before TPM enrolment.

### Disk encryption with LUKS2

#### Check what you have

```bash
lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINTS
sudo cryptsetup status luks-UUID
sudo cryptsetup luksDump /dev/DEVICE | less
```

In the `luksDump` output, check:

| Field | Want | Why |
|---|---|---|
| `Version` | `2` | LUKS1 has no Argon2, no tokens, no TPM2 enrolment |
| Keyslot `PBKDF` | `argon2id` | Memory-hard; `pbkdf2` slots are far cheaper to brute-force on GPUs |
| `Cipher` | `aes-xts-plain64` | The default, hardware-accelerated |
| Keyslots | Every slot accounted for | An unknown slot is an unknown key that opens the disk |
| Tokens | `systemd-tpm2`, `systemd-recovery` as expected | Enrolled unlock methods |

Convert an old PBKDF2 keyslot to Argon2id in place (asks for that slot's passphrase):

```bash
sudo cryptsetup luksConvertKey --pbkdf argon2id /dev/DEVICE
```

#### Back up the header first

The LUKS header holds the volume key wrapped by each keyslot. If the header is damaged, **no passphrase, recovery key or TPM can open the disk**, because the thing they unwrap is gone.

```bash
sudo cryptsetup luksHeaderBackup /dev/DEVICE --header-backup-file /root/HOSTNAME-luks-header.img
sudo sha256sum /root/HOSTNAME-luks-header.img
# now move it OFF this disk: encrypted backup, password manager attachment, offline media
```

> **One-way door.** LUKS header loss or corruption makes the data unrecoverable. Take a header backup when the volume is created and again **after every keyslot change** (the backup contains the keyslots as they were). Store it off-host. It is not secret on its own (it still needs a passphrase) but anyone holding it plus an old passphrase you later removed can still open the disk, so protect it like a key.

Restore, if you ever need to:

```bash
sudo cryptsetup luksHeaderRestore /dev/DEVICE --header-backup-file HOSTNAME-luks-header.img
```

#### TPM2 unlock with systemd-cryptenroll

TPM2 unlock lets a server boot unattended while the disk stays useless if removed. The TPM releases the key only if the measured boot chain (the PCRs you bind to) matches what it was at enrolment.

```bash
systemd-analyze has-tpm2                              # "yes" plus the component list
systemd-cryptenroll --tpm2-device=list
sudo systemd-cryptenroll /dev/DEVICE                  # list current slots and token types
```

Enrol in this order: **recovery key first, then TPM2, test, then decide about the passphrase.**

```bash
# 1. A recovery key: high-entropy, printed once, store it in your password manager
sudo systemd-cryptenroll --recovery-key /dev/DEVICE

# 2. TPM2, bound to PCR 7 (Secure Boot state and certificates)
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/DEVICE

# optional: also require a PIN at boot (TPM + something you know)
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes /dev/DEVICE
```

Tell the initramfs to try the TPM:

```ini
# /etc/crypttab  (existing line, add tpm2-device=auto)
luks-UUID  UUID=DEVICE-UUID  none  discard,tpm2-device=auto
```

```bash
# Fedora: make sure the TPM stack is in the initramfs, then rebuild it
echo 'add_dracutmodules+=" tpm2-tss "' | sudo tee /etc/dracut.conf.d/60-tpm2.conf
sudo dracut -f
```

Reboot and confirm it unlocked without a prompt, then take a fresh header backup.

> **Gotcha.** If you omit `--tpm2-pcrs`, `systemd-cryptenroll` binds to **no PCRs at all** (the documented default on current systemd). The TPM then releases the key to any OS booted on that machine, including a live USB, which defeats the point. Always pass `--tpm2-pcrs=7` explicitly.

**Which PCRs:**

| PCR | Measures | Changes when |
|---|---|---|
| 0 | Firmware code | Firmware update |
| 2 | Option ROMs | New or updated PCIe card |
| 4 | Boot loader and kernel | **Every kernel update** |
| 7 | Secure Boot state and certificates | Secure Boot toggled, keys changed |
| 11 | Unified kernel image sections (with `systemd-pcrphase`) | UKI update; use a signed policy |

**Pick PCR 7 alone** on Fedora with shim and Secure Boot on: it survives kernel and firmware updates and still refuses a boot with Secure Boot off or a different signing chain. Binding to 0+2+4 is stronger on paper and breaks unattended boot after every update. Signed PCR policies (`--tpm2-public-key`, `--tpm2-pcrlock`) are the robust answer for PCR 4/11, and need UKIs; treat them as a project, not a flag.

> **One-way door.** Never wipe the last slot you know works. The order is always: enrol the new method, **reboot and test it**, then wipe the old one:
>
> `sudo systemd-cryptenroll --wipe-slot=password /dev/DEVICE`
>
> Wiping the passphrase before the TPM and recovery key are proven leaves you one firmware update away from an unopenable disk.

Re-enrol after a change that alters PCR 7 (Secure Boot toggled, dbx update that changes the measurement), unlocking with the recovery key:

```bash
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 /dev/DEVICE
```

### systemd service sandboxing

systemd can put every service in a sandbox built from the kernel primitives in chapter 01: namespaces, capability bounding, seccomp, cgroup IP filtering. Each directive is one line. None of it is on by default for units you write.

#### Score what you have

```bash
systemd-analyze security --no-pager | sort -k2 -n -r | head -20   # every service, worst first
systemd-analyze security sshd.service --no-pager                 # one unit, per-directive
systemd-analyze security --offline=yes ./myapp.service           # a unit FILE before installing it
systemd-analyze security --threshold=30 ./myapp.service           # non-zero exit if exposure > 3.0
```

The score is exposure from 0.0 (fully sandboxed) to 10.0 (none). **Aim under 5.0 for anything you wrote, under 2.0 for network-facing services.** Many distro units score 9.6 "UNSAFE" because they need broad access (`sshd`, `auditd`, container engines) or have simply never been hardened.

> **Note.** The score is a checklist, not a threat model. A 9.6 on `sshd.service` is expected: its job is to become any user. Focus on your own services and on third-party daemons that parse untrusted input (web servers, exporters, agents).

`--threshold` takes the exposure times ten (so 30 means 3.0), which makes it usable as a CI gate on unit files in a repository.

#### The directives that matter

| Directive | Does | Cost |
|---|---|---|
| `DynamicUser=yes` | Allocates a UID for the service's lifetime; implies several protections | Files must live in `StateDirectory=` etc. |
| `ProtectSystem=strict` | Whole filesystem read-only except `/dev`, `/proc`, `/sys` and the `*Directory=` paths | Paths the service writes must be declared |
| `ProtectHome=yes` | `/home`, `/root`, `/run/user` invisible | Services reading user files |
| `PrivateTmp=yes` | Private `/tmp` and `/var/tmp` | Services sharing files through `/tmp` |
| `PrivateDevices=yes` | Only pseudo-devices (`null`, `zero`, `random`) | Services that need hardware |
| `NoNewPrivileges=yes` | SUID binaries and file capabilities cannot raise privilege | Services that call `sudo` or `ping` (old setuid builds) |
| `CapabilityBoundingSet=` | Upper limit on capabilities, even as root | List what is needed; empty for most |
| `AmbientCapabilities=` | Grant a capability to a non-root service | Use for `CAP_NET_BIND_SERVICE` instead of running as root |
| `SystemCallFilter=@system-service` | seccomp allow-list of the syscalls normal services use | Rare syscalls; check the journal for `SECCOMP` |
| `SystemCallArchitectures=native` | Blocks 32-bit syscall ABI tricks | 32-bit binaries |
| `RestrictAddressFamilies=` | Which socket families (`AF_INET`, `AF_UNIX`, `AF_NETLINK`) | List what is used |
| `RestrictNamespaces=yes` | Cannot create namespaces | Services that run containers or sandboxes |
| `MemoryDenyWriteExecute=yes` | No writable-and-executable memory | **JITs**: Node.js, Java, .NET, LuaJIT, PCRE JIT |
| `ProtectKernelTunables/Modules/Logs=yes` | `/proc/sys`, module loading, kernel log off-limits | Almost none for normal services |
| `ProtectProc=invisible`, `ProcSubset=pid` | Other users' processes invisible in `/proc` | Monitoring agents |
| `IPAddressDeny=any` + `IPAddressAllow=` | Per-service IP firewall via cgroup BPF | List the peers |
| `SocketBindAllow=` / `SocketBindDeny=` | Which ports the service may bind | List the ports |
| `LoadCredentialEncrypted=` | Deliver a secret to the service decrypted, in a private tmpfs | Service reads a file instead of an env var |
| `UMask=0077` | New files private | Shared group files |

#### A hardened unit

This scores **1.3 OK** under `systemd-analyze security --offline=yes` on systemd 258 (verified on the reference box):

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=MyApp API
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/myapp --listen :443 --config ${CONFIGURATION_DIRECTORY}/myapp.toml
Restart=on-failure

# Identity: a throwaway UID, directories created and owned for it
DynamicUser=yes
StateDirectory=myapp
CacheDirectory=myapp
LogsDirectory=myapp
ConfigurationDirectory=myapp
UMask=0077

# Secrets: decrypted into $CREDENTIALS_DIRECTORY/db-password, visible to this unit only
LoadCredentialEncrypted=db-password

# Filesystem
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
DevicePolicy=closed
ProtectProc=invisible
ProcSubset=pid

# Privilege: bind 443 without root, and nothing else
NoNewPrivileges=yes
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
RestrictSUIDSGID=yes
RemoveIPC=yes

# Kernel
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
RestrictRealtime=yes
RestrictNamespaces=yes

# Syscalls
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
SystemCallErrorNumber=EPERM

# Network: only IPv4/IPv6/Unix sockets, only these peers, only port 443
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
IPAddressDeny=any
IPAddressAllow=localhost 10.20.0.0/16
SocketBindAllow=tcp:443
SocketBindDeny=any

[Install]
WantedBy=multi-user.target
```

```bash
systemd-analyze verify /etc/systemd/system/myapp.service
systemd-analyze security --offline=yes /etc/systemd/system/myapp.service
sudo systemctl daemon-reload && sudo systemctl enable --now myapp.service
journalctl -u myapp.service -b
```

> **Gotcha.** `PrivateUsers=yes` looks like a free point on the score, but it runs the service in a user namespace, where `CAP_NET_BIND_SERVICE` no longer applies to the host's network namespace. Binding port 443 then fails with `EACCES`. Either leave `PrivateUsers=` off for services that bind privileged ports, or bind a high port and let the firewall or a proxy forward 443.

> **Gotcha.** `MemoryDenyWriteExecute=yes` crashes JIT runtimes, sometimes only on the first code path that triggers JIT compilation, hours after start. Leave it off for Node.js, JVM, .NET and anything using PCRE2 JIT.

When the sandbox blocks something, the error is usually `EPERM` or `EROFS` in the service's own log, and seccomp kills appear in the audit log:

```bash
journalctl -u myapp.service -b | grep -iE 'permission denied|read-only file system|operation not permitted'
sudo ausearch -m SECCOMP -ts recent
systemd-analyze syscall-filter @system-service | grep -w SYSCALL_NAME
```

#### Hardening a unit you did not write

Never edit files under `/usr/lib/systemd/system/`; an update overwrites them. Add a drop-in:

```bash
sudo systemctl edit nginx.service
```

```ini
# /etc/systemd/system/nginx.service.d/override.conf
[Service]
ProtectSystem=strict
ReadWritePaths=/var/log/nginx /var/lib/nginx /run/nginx
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
NoNewPrivileges=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictNamespaces=yes
SystemCallArchitectures=native
SystemCallFilter=@system-service
```

```bash
systemctl cat nginx.service                # unit plus drop-ins, as systemd sees them
sudo systemctl restart nginx.service
systemd-analyze security nginx.service --no-pager | tail -1
```

Add directives one group at a time and restart between groups. When something breaks, the last group is the culprit.

#### Encrypted credentials

systemd credentials keep secrets out of unit files, environment variables (visible in `/proc/PID/environ` and `systemctl show`), and world-readable config.

```bash
systemd-analyze has-tpm2                 # 'yes' means credentials can be TPM-bound

# Encrypt from stdin; the name must match LoadCredentialEncrypted=
sudo mkdir -p /etc/credstore.encrypted
printf '%s' 'SECRET' | sudo systemd-creds encrypt --name=db-password - /etc/credstore.encrypted/db-password
# (read it from a file or a prompt rather than typing a real secret into shell history)

sudo systemd-creds decrypt /etc/credstore.encrypted/db-password -    # check
```

`LoadCredentialEncrypted=db-password` in the unit looks in `/etc/credstore.encrypted/` by default and exposes the plaintext at `$CREDENTIALS_DIRECTORY/db-password`, on a non-swappable private mount readable only by the service. The default key is `host+tpm2` when a TPM exists, so the file is useless if copied to another machine.

### Automatic security updates

Unpatched kernels, sudo, OpenSSH and glibc are how most Linux boxes are actually lost. Automating security updates is the single most effective control in this manual.

#### dnf-automatic (dnf5)

On Fedora 41+ `dnf-automatic` is a dnf5 plugin in the `dnf5-plugin-automatic` package.

```bash
sudo dnf install dnf5-plugin-automatic
```

```ini
# /etc/dnf/automatic.conf  (host overrides of /usr/share/dnf5/dnf5-plugins/automatic.conf)
[commands]
upgrade_type = default          # security on RHEL/Alma/Rocky; see below
download_updates = yes
apply_updates = yes
reboot = when-needed
reboot_command = shutdown -r +10 'Rebooting to apply security updates'
random_sleep = 900
network_online_timeout = 120

[emitters]
emit_via = motd,stdio
```

| Option | Values | Pick |
|---|---|---|
| `upgrade_type` | `default`, `security`, `distro-sync` | `default` on Fedora; `security` on RHEL-family servers |
| `apply_updates` | `yes`/`no` (default `no`) | `yes`; downloading without applying protects nothing |
| `reboot` | `never` (default), `when-changed`, `when-needed` | `when-needed`: reboots only for kernel, glibc, systemd and similar |
| `emit_via` | `stdio`, `motd`, `email`, `command`, `command_email` | `stdio` lands in the journal; add `email` if nobody reads journals |

Schedule it and control when it runs:

```bash
sudo systemctl enable --now dnf5-automatic.timer
systemctl list-timers dnf5-automatic.timer
sudo systemctl edit dnf5-automatic.timer
```

```ini
# /etc/systemd/system/dnf5-automatic.timer.d/override.conf
[Timer]
OnCalendar=
OnCalendar=Tue..Thu 03:00
RandomizedDelaySec=30m
```

The empty `OnCalendar=` clears the packaged schedule before setting yours; without it, both schedules apply.

```bash
journalctl -u dnf5-automatic.service --since '7 days ago'
dnf advisory list --security                    # what is still outstanding (updateinfo is an alias)
dnf needs-restarting; echo $?                   # dnf5: non-zero = reboot needed (-r is a no-op kept for dnf4 habits)
dnf needs-restarting -s                         # services started before their libraries were updated
```

> **Version-sensitive.** Fedora 41+ (dnf5) uses one `dnf5-automatic.timer` with the behaviour set in `[commands]`; dnf4's `dnf-automatic-notifyonly`, `-download` and `-install` timers are gone. RHEL 9 still uses dnf4's `dnf-automatic` with those timers and the same `/etc/dnf/automatic.conf` path. Option names match, except `upgrade_type = distro-sync`, which is dnf5-only. Keys and defaults checked against the [dnf5 automatic man page](https://dnf5.readthedocs.io/en/latest/dnf5_plugins/automatic.8.html) (dnf5 5.2) and the [dnf4 docs](https://dnf.readthedocs.io/en/latest/automatic.html).

> **Gotcha.** `upgrade_type = security` installs only packages named in a `security`-type advisory. On Fedora the advisory type is chosen per update by the packager in Bodhi, and **a CVE fix filed as `bugfix` or `enhancement` is skipped**. How often that happens could not be determined from Fedora's docs (Fedora Magazine itself suggests `dnf update --security`), but Fedora keeps no backport stream to fall back on, so on Fedora `upgrade_type = default` in a maintenance window is the safer choice. RHEL, AlmaLinux and Rocky classify errata centrally; `security` is fine there.

> **Gotcha.** Automatic updates without automatic reboots leave the old kernel and the old glibc in memory. `dnf needs-restarting` will say so, and nothing else will. Schedule the reboot, or accept you are patched on disk only.

#### Debian/Ubuntu

```bash
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
# /etc/apt/apt.conf.d/50unattended-upgrades:
#   Unattended-Upgrade::Automatic-Reboot "true";
#   Unattended-Upgrade::Automatic-Reboot-Time "03:00";
```

### Traps

- `ptrace_scope = 3`, `kexec_load_disabled = 1` and `modules_disabled = 1` hold until reboot.
- `io_uring_disabled = 2` and `MemoryDenyWriteExecute=yes` break some runtimes silently until a code path hits them.
- `user.max_user_namespaces = 0` breaks rootless Podman, Flatpak and browser sandboxes.
- Lockdown `integrity` stops unsigned DKMS/akmods modules loading.
- `systemd-cryptenroll --tpm2-device=auto` without `--tpm2-pcrs` binds to no PCRs.
- Never wipe the last working LUKS slot; header backup after every slot change.
- `PrivateUsers=yes` defeats `AmbientCapabilities=CAP_NET_BIND_SERVICE`.
- Editing units in `/usr/lib/systemd/system/` is overwritten on update; use `systemctl edit`.
- Updates without reboots leave the vulnerable kernel running.

### Checklist

- [ ] `/etc/sysctl.d/60-kernel-hardening.conf` present; live values match (`sysctl`).
- [ ] Rare filesystems and protocols blocked with `install ... /bin/false`.
- [ ] `mokutil --sb-state` says enabled; lockdown is `integrity` or higher.
- [ ] LUKS2 with Argon2id slots; every keyslot accounted for.
- [ ] Header backup off-host, taken after the last slot change.
- [ ] TPM2 enrolled with `--tpm2-pcrs=7`, recovery key stored, unattended boot tested.
- [ ] Every unit you wrote scores under 5.0; network-facing ones under 2.0.
- [ ] Secrets delivered with `LoadCredentialEncrypted=`, not `Environment=`.
- [ ] `dnf5-automatic.timer` enabled with `apply_updates = yes` and a reboot policy.


---


<a id="07-baseline-audits-lynis-and-openscap"></a>

## 07 · Baseline audits: Lynis and OpenSCAP

*A scanner gives you a list of things to decide about, not a set of instructions to carry out. Lynis tells you what looks weak on this host; OpenSCAP tells you where you stand against a named benchmark. Run both, apply neither blind.*

### Which tool, when

The two tools answer different questions, and they are easy to confuse because both print a score.

| Question | Tool | Why |
|---|---|---|
| "What's weak on this box?" | **Lynis** | Heuristics across ~250 tests, fast, no content to download, runs on anything with a shell |
| "Do we meet CIS Level 1 / STIG / PCI?" | **OpenSCAP** + `scap-security-guide` | Machine-checkable benchmark content, results in ARF that auditors accept, remediation generated per rule |
| "Did this host drift since last month?" | **OpenSCAP** (same profile, diff results) | Stable rule IDs, so run-over-run comparison means something |
| "Is my golden image OK?" in CI | **Lynis** for a smoke gate, **OpenSCAP** for the compliance record | Lynis has a clean exit-code gate; OpenSCAP has the evidence trail |

**Default pick: run Lynis first on every host, then OpenSCAP with one named profile on the hosts that have a compliance obligation.** Lynis is the cheaper one and its suggestions point at real problems; OpenSCAP is the only one whose output means anything to an auditor.

### Lynis

Lynis 3.1.7 is in Fedora (`dnf install lynis`) and Debian/Ubuntu (`apt install lynis`), though the distro packages lag upstream on Debian stable. It is a pile of POSIX shell: no agent, no daemon, nothing to leave behind.

#### Run an audit

```bash
# full audit, as root (the real one)
sudo lynis audit system

# CI / cron: no colours, no pauses, minimal chatter
sudo lynis audit system --cronjob

# quick mode: no "press ENTER" between sections
sudo lynis audit system --quick

# unprivileged: runs, but skips tests that need root
lynis audit system --quick --log-file ./lynis.log --report-file ./lynis-report.dat
```

As root, output goes to `/var/log/lynis.log` (every test and what it found, useful for "why did it say that") and `/var/log/lynis-report.dat` (machine-readable key/value). Unprivileged, point both at a writable path, as above.

Verified on this machine (Fedora 43, unprivileged, `--quick`): 251 tests performed, hardening index 75, and 17 tests listed under "Skipped tests due to non-privileged mode", including `AUTH-9229` (password hashing), `AUTH-9252` (sudoers permissions), `FIRE-4540` (empty nftables ruleset), `ACCT-9630` (auditd rules) and `CRYP-7930` (LUKS).

> **Gotcha.** The unprivileged hardening index is **not comparable** with the root one. The index is `points / total_points` over the tests that ran (`include/report:53`), so skipping 17 tests changes the denominator. Track the root number only.

#### Reading the output

The screen output ends with three blocks. Read them in this order:

1. **Warnings** (`!`): Lynis thinks something is actually wrong. On this machine: `FINT-4316` (no AIDE database) and `TOOL-5104` (fail2ban installed, all jails disabled). Both are real: a tool installed but not doing anything is worse than not installed, because it shows up as present in inventories.
2. **Suggestions** (`*`): hardening opportunities. 28 on this workstation. Many are context-dependent: `FILE-6310` (separate `/var` partition) is a one-way door on an installed host and not worth it on a laptop; `HTTP-6640` (Apache mod_evasive) is noise if Apache is only there as a dependency.
3. **Hardening index**: a single number from 0 to 100. Useful as a **trend on one host**, useless as a comparison between hosts with different roles.

Each finding carries a test ID. Look it up rather than guessing:

```bash
lynis show tests FINT-4316          # what the test checks, its category and group
lynis show details FINT-4316        # what it found last run (reads /var/log/lynis.log only)
grep FINT-4316 /var/log/lynis.log   # every line it logged, including what it looked at
lynis show settings --brief --nocolors   # effective settings after profiles are merged
lynis show tests skipped                 # what your profile skips
```

The report file is flat `key=value`, with `[]` marking multi-value keys and `|` separating fields:

```text
hardening_index=75
warning[]=FINT-4316|No AIDE database was found, needed for AIDE functionality|-|-|
warning[]=TOOL-5104|All jails in Fail2ban are disabled|/etc/fail2ban/jail.conf|-|
suggestion[]=AUTH-9230|Configure password hashing rounds in /etc/login.defs|-|-|
```

That makes it trivial to parse without Lynis Enterprise:

```bash
R=/var/log/lynis-report.dat
grep -E '^hardening_index=' "$R" | cut -d= -f2
grep -E '^warning\[\]=' "$R" | cut -d= -f2- | cut -d'|' -f1,2
grep -E '^suggestion\[\]=' "$R" | cut -d= -f2- | cut -d'|' -f1 | sort | uniq -c
```

#### Triage the suggestions

Don't work top-to-bottom. Sort them into three piles:

| Pile | Examples from a real Fedora run | Action |
|---|---|---|
| **Do it** | `BOOT-5264` harden systemd services, `KRNL-5820` disable core dumps, `AUTH-9230` hashing rounds, `USB-1000` disable usb-storage | Fix, via config management, not by hand |
| **Decide once, record it** | `AUTH-9286` password ageing (NIST 800-63B says don't force rotation), `FILE-6310` separate `/var` | Skip in a custom profile with a comment saying why |
| **Not applicable** | `HTTP-6640` mod_evasive on a host that doesn't serve HTTP | Skip in the profile |

The middle pile is where teams waste time: the same argument about password ageing every quarter. Write the decision into the profile once.

#### Custom profiles

Never edit `/etc/lynis/default.prf`; the file itself says so, and the package will overwrite it. Lynis looks for `default.prf` and then `custom.prf` in its profile directories (`include/functions:433`), so a `/etc/lynis/custom.prf` is picked up automatically.

```ini
# /etc/lynis/custom.prf — decisions, with reasons, so nobody relitigates them

# Workstations and servers score differently; set the role honestly
machine-role=server

# NIST SP 800-63B: no forced periodic rotation
skip-test=AUTH-9286

# /var on a separate partition: one-way door on installed hosts, handled in the image build
skip-test=FILE-6310

# No web server on this role
skip-test=HTTP-6640

# Skip one sub-check of a test rather than the whole test
skip-test=SSH-7408:port

# Make warnings fail the run (for CI gates)
error-on-warnings=yes
```

For a per-role profile kept in git, pass it explicitly: `lynis audit system --profile ./profiles/ci-runner.prf`. Settings are layered, so the file only needs the deltas.

Useful knobs from `default.prf` (verified in the 3.1.7 file):

| Setting | Does | When |
|---|---|---|
| `machine-role=server\|workstation\|personal` | Changes which suggestions are relevant | Always set it |
| `skip-test=ID` / `skip-test=ID:option` | Skips a test or one aspect of it | Recorded decisions |
| `error-on-warnings=yes` | Exit code **78** when any warning exists | CI gating |
| `quick=yes` | No pauses | Default already |
| `refresh-repositories=no` | Don't refresh package metadata during the vuln check | Air-gapped hosts |

#### Narrow the run

```bash
lynis show groups                              # accounting, authentication, ssh, kernel, ...
lynis audit system --tests-from-group ssh        # one group per run
lynis audit system --tests "SSH-7408 AUTH-9230"
lynis show categories                          # performance, privacy, security
```

Scoped runs are what you want in a pre-commit or a post-change check on one subsystem.

#### Lynis in CI

The use case: scan the image or VM you just built, fail the pipeline on warnings, keep the report as an artefact.

```yaml
# .gitlab-ci.yml — runs inside a freshly booted image build VM or container
lynis-audit:
  stage: verify
  image: registry.example.internal/base/fedora-hardened:43
  script:
    - dnf -y install lynis
    - cp ci/lynis/ci.prf /etc/lynis/custom.prf
    - lynis audit system --cronjob --report-file lynis-report.dat --log-file lynis.log
  after_script:
    - grep -E '^(hardening_index|warning\[\])' lynis-report.dat || true
  artifacts:
    when: always
    paths: [lynis-report.dat, lynis.log]
```

With `error-on-warnings=yes` in the profile, the job fails with exit 78 on any warning. Gate on **warnings**, not on the index: an index threshold invites people to fix cheap suggestions to get the number up while a warning sits there.

> **Gotcha.** Auditing inside a container audits the container's view: no kernel parameters that belong to it, no bootloader, no firewall, no systemd. Expect a lot of skipped and N/A tests. For an image you'll boot as a VM (bootc, cloud image), audit the booted VM, not the build container.

Lynis also has `lynis audit dockerfile Dockerfile`, which is a lint rather than an audit; `hadolint` is the better tool for that job.

### OpenSCAP

OpenSCAP is the scanner (`oscap`, package `openscap-scanner`); the **content** is a separate package, `scap-security-guide` (SSG), which ships SCAP data streams per distribution. On Fedora 43: `openscap-scanner-1.4.4`, `scap-security-guide-0.1.82`. On Debian/Ubuntu: `apt install openscap-scanner ssg-debian ssg-debderived`, though Ubuntu's supported path for CIS is the Ubuntu Security Guide (`usg`) on Ubuntu Pro.

```bash
sudo dnf install openscap-scanner scap-security-guide
ls /usr/share/xml/scap/ssg/content/
```

Verified: this box has data streams for `fedora`, `rhel8/9/10`, `cs9/cs10`, `almalinux9`, `debian11/12/13`, `ubuntu2204/2404/2604` and a handful of others. **Use the data stream that matches the host's OS**; the rules carry CPE applicability checks and a mismatched stream marks most of them `notapplicable`.

#### Pick a profile

```bash
oscap info --profiles /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
```

Profiles verified in `ssg-rhel9-ds.xml` (0.1.82):

| Profile ID suffix | What it is |
|---|---|
| `cis_server_l1` / `cis` | CIS RHEL 9, Level 1 / Level 2 Server |
| `cis_workstation_l1` / `cis_workstation_l2` | CIS workstation variants |
| `stig` / `stig_gui` | DISA STIG for RHEL 9 (without / with GUI) |
| `ospp` | Protection Profile for General Purpose OS (Common Criteria) |
| `pci-dss` | PCI-DSS v4.0.1 |
| `e8`, `ism_o` | ACSC Essential Eight, ISM Official |
| `anssi_bp28_*`, `bsi`, `ccn_*` | National baselines (FR, DE, ES) |

The Fedora stream (`ssg-fedora-ds.xml`) has `cis*` profiles labelled **DRAFT**, plus `ospp`, `pci-dss`, `standard` and `cusp_fedora`. Fedora is not a CIS-certified target; treat Fedora results as advisory and use the RHEL stream on RHEL.

**Default pick: `cis_server_l1` for servers, `stig` only when a contract names it.** Level 1 is designed to be applied without breaking a normal server; STIG and CIS Level 2 disable things (USB, some filesystems, `ptrace` for non-root) that will break developer workflows.

The full profile ID is `xccdf_org.ssgproject.content_profile_<suffix>`; `oscap` accepts the short suffix too.

#### Evaluate and produce the HTML report

```bash
DS=/usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
sudo oscap xccdf eval \
  --profile cis_server_l1 \
  --results-arf /var/tmp/oscap-arf.xml \
  --report /var/tmp/oscap-report.html \
  "$DS"
echo "exit: $?"
```

Exit codes: **0** every rule passed, **1** an error in evaluation, **2** at least one rule failed. Verified: an unprivileged `standard` profile run on this Fedora box exited 2.

The HTML report is self-contained (open it in a browser): a score, a pass/fail/error breakdown, and per-rule detail with rationale, the CCE and CIS/NIST references, and the remediation snippet in Bash and Ansible. It is what you hand to someone who asked "are we compliant?".

Useful eval flags (verified against `oscap xccdf eval --help`, 1.4.4):

| Flag | Does | When |
|---|---|---|
| `--profile ID` | Selects the benchmark profile | Always |
| `--results-arf FILE` | Full ARF result data stream | Evidence for auditors; input to `generate fix` |
| `--results FILE` | XCCDF results only, much smaller | When nobody wants the ARF |
| `--report FILE` | HTML report | Humans |
| `--thin-results` | Drops system characteristics from ARF/OVAL | Keeps results small; implies `--without-syschar` |
| `--rule ID` | Evaluate one rule | Checking a single fix |
| `--skip-rule ID` | Skip a rule | Quick exclusions (prefer tailoring for anything permanent) |
| `--tailoring-file FILE` | Apply a tailoring | Recorded exceptions |
| `--fetch-remote-resources` | Download remote OVAL (e.g. CVE feeds) | Connected hosts only |
| `--progress` | One line per rule, `rule:result` | Watching a long run |
| `--stig-viewer FILE` | Results in DISA STIG Viewer format | STIG shops |
| `--remediate` | **Apply fixes for every failing rule** | Never on a live host (see below) |

> **Gotcha.** A full ARF with system characteristics is big. Verified: the Fedora `standard` profile (75 rules) produced a 30 MB `--results-arf`. A CIS Level 2 run is several hundred rules. Use `--thin-results` for routine runs and keep the full ARF only for the audit record.

> **Gotcha.** Run it as root. Unprivileged, rules that need to read `/etc/shadow`, `/etc/audit`, sudoers or `rpm -V` results come back `fail` or `error`, not `notapplicable`. The unprivileged Fedora run above reported 51 fails out of 75, most of them from unreadable files. A non-root run is not a lighter scan; it is a wrong one.

#### Tailoring: recorded exceptions

The benchmark will contain rules you've decided not to meet. Record that in a **tailoring file**, not in someone's head and not with a string of `--skip-rule`.

The GUI tool (`scap-workbench`) writes tailoring files; the CLI path on 1.4 is `autotailor`, shipped with `openscap-utils`:

```bash
sudo dnf install openscap-utils
autotailor --help
autotailor \
  --unselect xccdf_org.ssgproject.content_rule_partition_for_var \
  --var-value xccdf_org.ssgproject.content_value_var_accounts_tmout=900 \
  --new-profile-id cis_l1_ours \
  --output tailoring.xml \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml cis_server_l1

sudo oscap xccdf eval --tailoring-file tailoring.xml --profile cis_l1_ours \
  --report report.html /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
```

> **Version-sensitive.** `autotailor` arrived in OpenSCAP 1.3.3; JSON tailoring import (`--json-tailoring`) and `--rule-role`/`--rule-severity` need 1.3.10+. Fedora 43 packages it in `openscap-utils` (1.4.4, the current upstream release). Flags above checked against the upstream [man page and source](https://github.com/OpenSCAP/openscap/blob/main/utils/autotailor.8); short IDs like `partition_for_var` also work, with the `xccdf_org.ssgproject.content_rule_` prefix added for you. Not installed on the reference box, so not run.

Commit `tailoring.xml` next to your config management code, one per role, with the reason for each unselected rule in the commit message.

#### Generate a remediation script, don't run one blind

`oscap` can turn a result into a remediation script for only the rules that failed. That is the right input to a change: a reviewed diff, not a live fix.

```bash
# the TestResult ID is in the ARF; grab it
RID=$(grep -o 'xccdf_org.open-scap_testresult_[A-Za-z0-9_.-]*' /var/tmp/oscap-arf.xml | head -1)

# Bash
oscap xccdf generate fix --fix-type bash    --result-id "$RID" \
  --output remediate.sh  /var/tmp/oscap-arf.xml

# Ansible (usually the better artefact to review and commit)
oscap xccdf generate fix --fix-type ansible --result-id "$RID" \
  --output remediate.yml /var/tmp/oscap-arf.xml

# Or: everything the profile would do, independent of any scan
oscap xccdf generate fix --fix-type ansible --profile cis_server_l1 \
  --output cis_l1_full.yml /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
```

Verified on this box: the fix script from the 51-failure Fedora run was **10,220 lines of Bash**, the Ansible version 11,157 lines. Other `--fix-type` values in 1.4.4: `puppet`, `anaconda`, `ignition`, `kubernetes`, `blueprint`, `kickstart`, `bootc`.

> **One-way door.** `oscap xccdf eval --remediate` and running a generated `remediate.sh` on a live host change hundreds of settings at once: SSH ciphers, PAM, sudo defaults, mount options, audit rules, kernel parameters. Some of those lock you out (a PAM `faillock` config plus a password typo on the only admin account; SSH `AllowGroups` that doesn't include you). The undo is a rebuild or a rescue boot. **Review the Ansible, apply it to a throwaway clone first, keep a console open, and land the result through your normal config management.**

The pattern that works:

1. Build a VM from your golden image.
2. Run the profile there, generate the Ansible playbook from the result.
3. Read the playbook; cut or tailor anything that breaks your workload.
4. Apply to the VM, reboot, re-scan, run your smoke tests.
5. Fold the surviving tasks into your image build (bootc Containerfile, kickstart, Ansible role).
6. Scan production **read-only** as the verification step.

Better still, bake the profile into the image at build time: the `kickstart`, `blueprint` (Image Builder) and `bootc` fix types exist for exactly this, so the host is compliant on first boot and scans only confirm it.

#### Rule-level lookups

```bash
# one rule, with rationale, against this host
sudo oscap xccdf eval --profile cis_server_l1 \
  --rule xccdf_org.ssgproject.content_rule_sshd_disable_root_login \
  --show-rule-details /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml

# a human-readable guide for the whole profile, no scan
oscap xccdf generate guide --profile cis_server_l1 \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml > cis-l1-guide.html
```

The guide is worth generating once and keeping: it is the full benchmark with rationale, readable without a CIS login.

#### Drift over time

Run the same profile on a schedule, keep the per-rule results, and diff the rule results rather than the score:

```bash
# monthly, from a systemd timer: one "rule:result" line per rule
sudo oscap xccdf eval --profile cis_server_l1 --progress \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml 2>/dev/null \
  | sort > "/var/lib/oscap/$(date +%Y-%m).txt"

diff /var/lib/oscap/2026-08.txt /var/lib/oscap/2026-09.txt
```

A rule that went from `pass` to `fail` between two runs is a change someone made; that is more useful than a score dropping by 0.4.

### Lynis vs OpenSCAP

| | Lynis 3.1.7 | OpenSCAP 1.4.4 + SSG 0.1.82 |
|---|---|---|
| Question it answers | "What's weak here?" | "Do we meet benchmark X?" |
| Content | Built-in shell tests | Versioned SCAP data streams per distro |
| Standards mapping | Loose (links to its own control pages) | Per rule: CIS, STIG, NIST 800-53, PCI, CCE |
| Runs unprivileged | Yes, with skipped tests listed | Technically, but results are wrong |
| Speed | ~1–2 minutes | Minutes; longer for STIG/CIS L2 |
| Output | Screen, log, `key=value` report | HTML report, XCCDF, ARF, STIG Viewer |
| Remediation | Suggestions with links | Generated Bash / Ansible / kickstart / bootc |
| Exceptions | `skip-test=` in a profile | XCCDF tailoring file |
| CI gate | `error-on-warnings=yes` → exit 78 | Exit 2 on any fail |
| Distro coverage | Any Unix with a shell | Only distros with SSG content |
| Auditor-grade evidence | No | Yes (ARF) |
| Remote scanning | `audit system remote` (copies itself over SSH) | `oscap-ssh user@host 22 xccdf eval ...` |

**Close call** only in one situation: a mixed fleet with distros SSG doesn't cover. There, Lynis everywhere is the tiebreaker, because a baseline on every host beats a benchmark on half of them.

### Where the rest of the guide picks up

Both tools will flag things covered in depth elsewhere. Don't fix them from the scanner's one-line suggestion:

| Finding area | Chapter |
|---|---|
| SSH config (`SSH-7408`, `sshd_*` rules) | 03 |
| Firewall (`FIRE-*`, `firewalld_*`) | 04 |
| SELinux (`MACF-*`, `selinux_*`) | 05 |
| sysctl, kernel modules, systemd hardening (`KRNL-*`, `BOOT-5264`) | 06 |
| auditd rules (`ACCT-9630`, `audit_rules_*`) | 08 |
| AIDE (`FINT-4316`, `aide_*`) | 09 |
| fail2ban (`TOOL-5104`) | 10 |

### Traps

- **Chasing the index.** A score is a trend line on one host. Gate on warnings (Lynis) or on specific failing rules (OpenSCAP), never on the number.
- **Running as a normal user and believing the result.** Lynis tells you what it skipped; OpenSCAP silently reports `fail`. Both need root for a real answer.
- **The wrong data stream.** `ssg-rhel9-ds.xml` on Fedora, or `ssg-fedora-ds.xml` on RHEL, gives you a result that looks plausible and isn't.
- **`--remediate` on production.** Hundreds of changes, some of which lock you out. Generate, review, test on a clone, then apply through config management.
- **Editing `default.prf`.** The next package update reverts it. Use `/etc/lynis/custom.prf` or a `--profile` file in git.
- **Exceptions in someone's memory.** Every skipped test or unselected rule belongs in a profile or tailoring file, in git, with a reason.
- **Auditing the build container instead of the booted host.** Container audits can't see the kernel, bootloader, firewall or systemd.
- **Installed but disabled.** Lynis's `TOOL-5104` (fail2ban with no jails) and `FINT-4316` (AIDE with no database) are the same failure: a control that appears in the inventory and does nothing. Finish the setup or remove the package.


---


<a id="08-auditd-and-the-journal"></a>

## 08 · auditd and the journal

*The kernel audit subsystem records what happened at the syscall boundary, attributed to the human who logged in, even after they sudo. That attribution is the whole value; a ruleset that doesn't serve it is just disk I/O.*

### How the pieces fit

```text
  process ──syscall──▶ kernel ──audit filter (your rules)──▶ kauditd
                                                               │ netlink
                                                               ▼
                                                            auditd ──▶ /var/log/audit/audit.log
                                                               │
                                                               └─▶ plugins (audisp): syslog, au-remote, af_unix
                                                                      │
                                                                      ▼
                                                           rsyslog / SIEM / remote auditd

  auditctl  ── loads/lists rules in the kernel (netlink)
  augenrules ─ concatenates /etc/audit/rules.d/*.rules ─▶ /etc/audit/audit.rules ─▶ auditctl -R
  ausearch / aureport ── read audit.log (and rotated logs), never the kernel
```

The facts that shape everything below:

- **Rules live in the kernel.** `auditd` only receives and writes events. Stop `auditd` and the kernel still evaluates rules; events go to the kernel ring buffer and `printk` instead.
- **Every event carries `auid`, the login UID.** It's set once at login by `pam_loginuid` and survives `sudo`, `su` and `setuid`. `uid=0 auid=1001` means "root, but it was alice". With `--loginuid-immutable` it cannot be changed after it's set.
- **Rules are evaluated on every syscall** by every process. Each extra syscall rule is a cost on the whole machine. Filesystem rules (`-F path=`/`-F dir=`) are cheaper, because they're only checked on filesystem-related syscalls.
- **One event is several records** sharing an `msg=audit(TIMESTAMP:SERIAL)`: `SYSCALL`, `EXECVE`, `CWD`, `PATH`, `PROCTITLE`. `ausearch` reassembles them; `grep` doesn't.

On Fedora 43 (audit 4.2.1) the tools are in `/usr/bin` and the rules are loaded by a **separate unit** (split out in [audit 4.0](https://github.com/linux-audit/audit-userspace/releases/tag/v4.0)), `audit-rules.service` (`ExecStart=/usr/bin/augenrules --load`), not by `auditd.service` itself. On Debian/Ubuntu, `apt install auditd audispd-plugins`; paths are the same.

### Inspect the current state

Everything here needs root.

```bash
sudo auditctl -s          # enabled, failure mode, backlog, lost count, pid of auditd
sudo auditctl -l          # rules currently loaded in the kernel
sudo augenrules --check   # do rules.d and audit.rules differ?
ls /etc/audit/rules.d/
systemctl status auditd audit-rules
```

Read `auditctl -s` for three fields:

| Field | Healthy | Meaning when it isn't |
|---|---|---|
| `enabled` | `1` (or `2` = immutable) | `0` means auditing is off |
| `lost` | `0`, or not climbing | Events dropped because the backlog overflowed. Climbing = your rules are too noisy or `-b` too small |
| `backlog` | Well under `backlog_limit` | Near the limit under load = you're about to lose events |

A stock Fedora install ships almost nothing active; `auditctl -l` typically returns `No rules` or a single rule. SELinux AVCs, logins and `sudo` still appear in `audit.log` because those are **user-space and kernel-generated events** that don't need rules (`USER_LOGIN`, `USER_CMD`, `AVC`).

### Writing rules

#### Where rules go

Put rule files in `/etc/audit/rules.d/`, named `NN-name.rules`. `augenrules` concatenates them in natural sort order into `/etc/audit/audit.rules` and loads that. Never edit `audit.rules` by hand; the next `augenrules` overwrites it.

`augenrules` also enforces order (from `man augenrules`): the last `-D` goes first, the last `-b` second, the last `-f` third, and the last `-e` last. So a finalize file with `-e 2` always ends up at the end regardless of name.

The audit package ships a library of rule fragments. On audit 4.x they're in **`/usr/share/audit-rules/`** (older releases: `/usr/share/audit/sample-rules/` or `/usr/share/doc/audit/rules/`). Numbering convention from its README:

| Prefix | Contents |
|---|---|
| `10` | Kernel and auditctl configuration (`-D`, `-b`, `-f`, `--loginuid-immutable`) |
| `20` | Exclusions that must match before the general rules |
| `30` | Main rules (`30-stig.rules`, `30-ospp-v42*.rules`, `30-pci-dss-v31.rules`) |
| `40` | Optional (`42-injection`, `43-module-load`, `44-installers`) |
| `50` | Server-specific |
| `70` | Local |
| `90`/`99` | Finalize (`-e 2`) |

For a STIG configuration the README says: copy `10-base-config`, `30-stig`, `31-privileged` and `99-finalize`. That's a heavy set. The starter set below is lighter and aimed at the questions you'll actually ask during an incident.

#### Rule anatomy

```text
-a always,exit -F arch=b64 -S execve -F auid>=1000 -F auid!=unset -F key=exec
 │   │     │     │           │          │                            │
 │   │     │     │           │          │                            └ tag, what you search on
 │   │     │     │           │          └ field filters (AND-ed)
 │   │     │     │           └ syscall(s), comma-separated
 │   │     │     └ ABI: rules are per-ABI; write b32 and b64 both
 │   │     └ list: exit (almost always), also user, exclude, filesystem
 │   └ action: always or never
 └ append (-A prepends)
```

Operators you'll use:

| Field | Example | Does |
|---|---|---|
| `arch` | `-F arch=b64` | Which syscall table. Omit it and syscall numbers are guessed, badly |
| `path` / `dir` | `-F path=/etc/shadow` | Filesystem rule for a file / a directory tree |
| `perm` | `-F perm=wa` | With path/dir: `r` read, `w` write, `x` execute, `a` attribute change |
| `auid` | `-F auid>=1000 -F auid!=unset` | Humans only (`unset` is `4294967295`, i.e. daemons that never logged in) |
| `uid` / `euid` | `-F euid=0` | Effective identity at the time |
| `success` / `exit` | `-F success=0`, `-F exit=-EACCES` | Failures only |
| `key` | `-F key=identity` | Tag. Up to 31 chars; several per rule allowed |
| `-C` | `-C auid!=obj_uid` | Compare two fields (e.g. acting on someone else's file) |

> **Gotcha.** `-w /etc/shadow -p wa -k identity` still works, but `man auditctl` on audit 4.x calls the `-w` form **deprecated due to poor system performance**. `-p` and `-k` on a watch are marked deprecated too. Audit 4.0 made watches hook fewer syscalls, which narrows the performance gap, but the syscall form is the one upstream tells you to write: `-a always,exit -F arch=b64 -F path=/etc/shadow -F perm=wa -F key=identity` (and the `b32` twin). Most blog-post rulesets still use `-w`.

> **Gotcha.** On x86_64, a 32-bit process makes syscalls through the b32 table. A ruleset with only `arch=b64` rules has a hole that any attacker who knows about audit will use. Either write both, or make 32-bit activity itself the alert: the shipped `21-no32bit.rules` is one rule, `-a always,exit -F arch=b32 -S all -F key=32bit-abi`, which records every 32-bit syscall (it logs, it doesn't block). On a host with no legitimate 32-bit software, any hit is worth a look. To remove the 32-bit ABI entirely, boot with `ia32_emulation=0` (kernel 6.7+).

#### A starter ruleset

This covers the list that matters in a real investigation: who changed identity files, sudoers, sshd config; who loaded a kernel module; who changed the clock; what humans executed. It deliberately avoids "all file deletes by anyone", which is where rulesets go to die.

```bash
# /etc/audit/rules.d/10-base.rules
## Remove any existing rules
-D
## Buffer: raise on busy hosts, watch 'lost' in auditctl -s
-b 8192
## How long the kernel waits when the backlog is full (the shipped 10-base-config value)
--backlog_wait_time 60000
## Failure mode: 1 = printk. 2 = panic (only if a lost event is worse than a dead host)
-f 1
## auid can't be changed after login
--loginuid-immutable
```

```bash
# /etc/audit/rules.d/30-identity.rules
## Accounts and groups
-a always,exit -F arch=b64 -F path=/etc/passwd  -F perm=wa -F key=identity
-a always,exit -F arch=b32 -F path=/etc/passwd  -F perm=wa -F key=identity
-a always,exit -F arch=b64 -F path=/etc/shadow  -F perm=wa -F key=identity
-a always,exit -F arch=b32 -F path=/etc/shadow  -F perm=wa -F key=identity
-a always,exit -F arch=b64 -F path=/etc/group   -F perm=wa -F key=identity
-a always,exit -F arch=b32 -F path=/etc/group   -F perm=wa -F key=identity
-a always,exit -F arch=b64 -F path=/etc/gshadow -F perm=wa -F key=identity
-a always,exit -F arch=b32 -F path=/etc/gshadow -F perm=wa -F key=identity
-a always,exit -F arch=b64 -F path=/etc/security/opasswd -F perm=wa -F key=identity
-a always,exit -F arch=b32 -F path=/etc/security/opasswd -F perm=wa -F key=identity

## Privilege: sudoers
-a always,exit -F arch=b64 -F path=/etc/sudoers   -F perm=wa -F key=sudoers
-a always,exit -F arch=b32 -F path=/etc/sudoers   -F perm=wa -F key=sudoers
-a always,exit -F arch=b64 -F dir=/etc/sudoers.d/ -F perm=wa -F key=sudoers
-a always,exit -F arch=b32 -F dir=/etc/sudoers.d/ -F perm=wa -F key=sudoers

## Remote access: sshd config (authorized_keys lives in home dirs; AIDE covers /root/.ssh, see chapter 09)
-a always,exit -F arch=b64 -F path=/etc/ssh/sshd_config   -F perm=wa -F key=sshd
-a always,exit -F arch=b32 -F path=/etc/ssh/sshd_config   -F perm=wa -F key=sshd
-a always,exit -F arch=b64 -F dir=/etc/ssh/sshd_config.d/ -F perm=wa -F key=sshd
-a always,exit -F arch=b32 -F dir=/etc/ssh/sshd_config.d/ -F perm=wa -F key=sshd

## Persistence: PAM, systemd units, cron
-a always,exit -F arch=b64 -F dir=/etc/pam.d/          -F perm=wa -F key=pam
-a always,exit -F arch=b32 -F dir=/etc/pam.d/          -F perm=wa -F key=pam
-a always,exit -F arch=b64 -F dir=/etc/systemd/system/ -F perm=wa -F key=systemd
-a always,exit -F arch=b32 -F dir=/etc/systemd/system/ -F perm=wa -F key=systemd
-a always,exit -F arch=b64 -F dir=/etc/cron.d/         -F perm=wa -F key=cron
-a always,exit -F arch=b32 -F dir=/etc/cron.d/         -F perm=wa -F key=cron
-a always,exit -F arch=b64 -F dir=/var/spool/cron/     -F perm=wa -F key=cron
-a always,exit -F arch=b32 -F dir=/var/spool/cron/     -F perm=wa -F key=cron

## Audit config itself
-a always,exit -F arch=b64 -F dir=/etc/audit/ -F perm=wa -F key=audit-config
-a always,exit -F arch=b32 -F dir=/etc/audit/ -F perm=wa -F key=audit-config
```

```bash
# /etc/audit/rules.d/40-kernel-time.rules
## Kernel modules: the syscall catches every loader, not just modprobe
-a always,exit -F arch=b64 -S init_module,finit_module -F key=module-load
-a always,exit -F arch=b32 -S init_module,finit_module -F key=module-load
-a always,exit -F arch=b64 -S delete_module -F key=module-unload
-a always,exit -F arch=b32 -S delete_module -F key=module-unload

## Time changes (chronyd excluded: it adjusts the clock all day)
-a never,exit -F arch=b64 -S adjtimex -F auid=unset -F uid=chrony -F subj_type=chronyd_t
-a never,exit -F arch=b32 -S adjtimex -F auid=unset -F uid=chrony -F subj_type=chronyd_t
-a always,exit -F arch=b64 -S adjtimex,settimeofday -F key=time-change
-a always,exit -F arch=b32 -S adjtimex,settimeofday,stime -F key=time-change
-a always,exit -F arch=b64 -S clock_settime -F a0=0x0 -F key=time-change
-a always,exit -F arch=b32 -S clock_settime -F a0=0x0 -F key=time-change
-a always,exit -F arch=b64 -F path=/etc/localtime -F perm=wa -F key=time-change
-a always,exit -F arch=b32 -F path=/etc/localtime -F perm=wa -F key=time-change
```

```bash
# /etc/audit/rules.d/50-exec.rules
## Every program a human runs (directly or via sudo), attributed by auid
-a always,exit -F arch=b64 -S execve,execveat -F auid>=1000 -F auid!=unset -F key=exec
-a always,exit -F arch=b32 -S execve,execveat -F auid>=1000 -F auid!=unset -F key=exec

## Privilege-escalation helpers worth their own key
-a always,exit -F arch=b64 -F path=/usr/bin/pkexec      -F perm=x -F key=priv-esc
-a always,exit -F arch=b64 -F path=/usr/bin/systemd-run -F perm=x -F auid!=unset -F key=priv-esc
```

```bash
# /etc/audit/rules.d/99-finalize.rules
## Uncomment only once the ruleset is stable: changes then need a reboot
#-e 2
```

The `chrony` exclusions are copied verbatim from `/usr/share/audit-rules/22-ignore-chrony.rules` (verified, audit 4.2.1); `subj_type` matches the SELinux domain, so they only work with SELinux enabled. They must sit above the `always` rules they exempt, which they do within this file. `a0=0x0` on `clock_settime` means `CLOCK_REALTIME` only; the monotonic clocks aren't interesting.

Load and confirm:

```bash
sudo augenrules --check
sudo augenrules --load
sudo auditctl -l | wc -l
sudo auditctl -s | grep -E 'enabled|lost|backlog'
```

> **Gotcha.** `systemctl restart auditd` is refused on Fedora/RHEL: the unit has `RefuseManualStop=yes` (verified in the Fedora 43 unit), so that auditd's own shutdown is attributable. Use `augenrules --load` to reload rules, `service auditd restart` (the legacy wrapper, which sends the right signal) to restart the daemon after changing `auditd.conf`, or `auditctl --signal reload`.

> **Note.** The `exec` rule is the expensive one: `execve` is frequent, and every hit writes `SYSCALL` + `EXECVE` + `PATH` + `CWD` + `PROCTITLE` records. On a CI runner or build host where humans (auid ≥ 1000) trigger thousands of compiler invocations, it can generate gigabytes a day. On those hosts, drop it to `-F euid=0` (only what humans run as root) or exclude the build user.

#### Excluding noise

`never` rules must come **before** the matching `always` rule, which is why exclusions go in `20-*.rules`. Common ones:

```bash
# /etc/audit/rules.d/20-exclude.rules
## Ignore a noisy service account's execs
-a never,exit -F arch=b64 -S execve,execveat -F auid=unset -F uid=gitlab-runner
## Drop whole record types you never read (exclude list, no arch/syscall)
-a always,exclude -F msgtype=CWD
```

Check what's actually noisy before excluding anything:

```bash
sudo aureport --key --summary          # events per key, busiest first
sudo aureport -x --summary             # events per executable
sudo aureport -s --summary             # events per syscall
```

### Searching: ausearch and aureport

`ausearch` reads the logs (including rotated ones), reassembles multi-record events and interprets numbers into names with `-i`. Always use it over `grep`.

#### ausearch by what you're asking

```bash
# a rule key, human-readable
sudo ausearch -k identity -i

# today, this boot, since a time
sudo ausearch -k sudoers -ts today -i
sudo ausearch -k exec -ts boot -i
sudo ausearch -k module-load -ts 09/22/2026 14:00:00 -te now -i

# everything a login session did, whatever uid it became
sudo ausearch -ul 1001 -ts today -i        # by auid (login uid)
sudo ausearch --session 42 -i              # by login session id

# one executable, one pid, one file
sudo ausearch -x /usr/bin/passwd -i
sudo ausearch -p 31337 -i
sudo ausearch -f /etc/shadow -i

# failures only
sudo ausearch -k identity --success no -i

# message types
sudo ausearch -m USER_LOGIN,USER_AUTH --success no -ts today -i   # failed logins
sudo ausearch -m AVC,USER_AVC -ts recent -i                     # SELinux denials, last 10 min
sudo ausearch -m USER_CMD -ts today -i                          # sudo commands
```

Time keywords (`man ausearch`): `now`, `recent` (10 minutes ago), `this-hour`, `boot`, `today`, `yesterday`, `this-week`, `week-ago`, `this-month`, `this-year`. Dates follow the locale's format (`date '+%x'` shows it).

Output formats, for piping into something else:

| Flag | Does | When |
|---|---|---|
| `-i` | Interpret uid/gid/syscall/arch to names | Humans, always |
| `--format text` | One English sentence per event | Timelines, tickets |
| `--format csv --extra-keys --extra-time` | CSV with key and broken-down time columns | Spreadsheets, pandas |
| `-r` / `--format raw` | Raw records | Feeding another `ausearch` or `aureport` |
| `--just-one` | First matching event only | Quick "did this ever happen" |
| `--checkpoint FILE` | Resume from the last event you processed | Cron jobs that alert on new events |

Chain searches with raw output:

```bash
# failed accesses to identity files, summarised by executable
sudo ausearch -k identity --success no --raw | aureport -x --summary -i

# what did auid 1001 run as root today
sudo ausearch -ul 1001 -k exec -ts today --raw | aureport -x --summary -i
```

#### Reading one event

```text
type=SYSCALL msg=audit(1790171016.967:4242): arch=x86_64 syscall=openat success=yes exit=3
  ppid=2201 pid=2250 auid=alice uid=root gid=root euid=root ... tty=pts1 ses=7
  comm="vim" exe="/usr/bin/vim" subj=unconfined_u:unconfined_r:unconfined_t:s0 key="sudoers"
type=CWD  msg=audit(1790171016.967:4242): cwd="/home/alice"
type=PATH msg=audit(1790171016.967:4242): item=0 name="/etc/sudoers.d/90-ops" nametype=CREATE ...
type=PROCTITLE msg=audit(1790171016.967:4242): proctitle="sudo vim /etc/sudoers.d/90-ops"
```

Read it as: **alice (auid), as root (uid), in login session 7 (ses), on pts1, used vim to create `/etc/sudoers.d/90-ops`**. `auid` plus `ses` is what makes the record useful; `uid=root` alone tells you nothing.

#### aureport for overviews

```bash
sudo aureport --summary              # totals for everything
sudo aureport -au --failed -i        # failed authentications
sudo aureport -l -i                  # logins
sudo aureport -m -i                  # account modifications (useradd, passwd, ...)
sudo aureport -k --summary           # hits per rule key
sudo aureport -n                     # anomalies (promiscuous mode, segfaults, ...)
sudo aureport --tty -ts today        # keystrokes, if pam_tty_audit is enabled
sudo aureport -t                     # time range covered by each log file
```

`aulast` and `aulastlog` rebuild `last`-style login history from the audit log. They're useful when `/var/log/wtmp` has been tampered with, since audit records are harder to edit convincingly (see chapter 12).

### Immutable mode

`-e 2` as the last rule locks the configuration: no rule can be added or removed, auditing can't be disabled, and `auditctl -e 0` fails until reboot. It's the defence against an attacker with root who wants to switch audit off before doing the interesting part.

```bash
sudo auditctl -s | grep enabled     # enabled 2 = immutable
```

> **One-way door.** Once `-e 2` is loaded, the only way to change rules is a reboot. That's the point, but it means a bad rule (one that floods the backlog, or a `-f 2` panic mode combined with a full disk) stays until the next reboot. Run the ruleset without `-e 2` for a week, watch `lost` in `auditctl -s` and log volume, then enable it.

An attacker with root can still stop `auditd` from writing (by killing it or filling the disk) and can reboot with different rules. Immutable mode buys you a **record of the attempt**, which is why remote forwarding matters.

### auditd.conf: disk and failure policy

`/etc/audit/auditd.conf` controls the daemon, not the rules. The settings that matter:

| Setting | Sensible value | Why |
|---|---|---|
| `log_format` | `ENRICHED` | Resolves uid/gid/syscall names at write time, so logs read correctly on another host |
| `max_log_file` | `50`–`100` (MB) | Per file |
| `num_logs` | `10`+ | Rotated files kept |
| `max_log_file_action` | `ROTATE` (or `KEEP_LOGS` with external archiving) | `KEEP_LOGS` never deletes; fills the disk if nothing ships them |
| `space_left` / `space_left_action` | `25%` / `SYSLOG` or `EMAIL` | First warning |
| `admin_space_left` / `admin_space_left_action` | `10%` / `SUSPEND` or `SINGLE` | Last warning. `SINGLE` drops to single-user; STIG wants it, laptops don't |
| `disk_full_action` | `SUSPEND` (or `HALT` for STIG) | What happens at 0 bytes |
| `flush` / `freq` | `INCREMENTAL_ASYNC` / `50` | Durability vs I/O |

Keep `/var/log/audit` on its own filesystem on servers where audit is a compliance control: a full `/var` then doesn't stop audit, and full audit doesn't stop `/var`.

### Forwarding logs off the host

A local audit log is evidence the attacker can delete. Ship it.

**Default pick: the `syslog` plugin into your existing rsyslog/journald pipeline**, then on to the SIEM. It's the path with the fewest moving parts. Use `au-remote` only when the receiver is another `auditd` (it speaks the native protocol with Kerberos option and queueing), or when a compliance profile demands it.

Both plugins are in the `audispd-plugins` package (verified via `dnf repoquery -l`): `/etc/audit/plugins.d/syslog.conf`, `au-remote.conf`, plus `af_unix`, `filter` and `statsd`.

```ini
# /etc/audit/plugins.d/syslog.conf
active = yes
direction = out
path = /usr/bin/audisp-syslog
type = always
args = LOG_INFO LOG_LOCAL6
format = string
```

```ini
# /etc/audit/plugins.d/au-remote.conf  → then set remote_server in /etc/audit/audisp-remote.conf
active = yes
direction = out
path = /usr/bin/audisp-remote
type = always
format = string
```

Restart with `sudo service auditd restart` after changing plugins.

> **Gotcha.** Sending audit to syslog with `LOG_INFO` puts it in the journal and `/var/log/messages` as well, doubling local volume and making `journalctl` noisy. Route `local6` to its own forwarding action in rsyslog and exclude it from the local files.

Agents (Wazuh, Elastic Agent's auditd integration, Splunk UF) can tail `audit.log` directly. Elastic's Auditbeat is an alternative that replaces `auditd` entirely by talking to the kernel over netlink itself. Don't run both: only one process can be the audit daemon.

### Performance cost

- **Filesystem rules are cheap.** `-F path=`/`-F dir=` with `perm` are checked only on filesystem syscalls touching those inodes. Dozens are fine.
- **Syscall rules on hot syscalls are not.** `execve` for all users, `openat` for anything, `connect`/`accept` for network auditing: each costs something on every call. Measure with a before/after `perf stat` or simply watch `auditctl -s` backlog and `aureport -t` volume.
- **Merge rules** with identical filters: `-S chmod,fchmod,fchmodat` in one rule, not three (`man auditctl`, PERFORMANCE TIPS).
- **Put `never` exclusions early** so noisy processes exit the rule list fast.
- **Log volume is the usual limit**, not CPU. A starter ruleset like the one above on a quiet server writes megabytes per day; add unfiltered `execve` on a build host and it's gigabytes.

### journalctl for security investigations

The journal holds what `auditd` doesn't: sshd's own messages, sudo, PAM, systemd starting and stopping things, kernel messages. On Fedora there's no `/var/log/secure` from rsyslog by default; the journal **is** the auth log.

#### sshd and logins

```bash
# the sshd unit: covers the listener and pre-auth connections
journalctl -u sshd.service --since "2 hours ago"

# failed attempts, with the source address
journalctl -u sshd.service --since today -g 'Failed|Invalid user'

# accepted logins
journalctl -u sshd.service --since "-7d" -g 'Accepted'
```

> **Version-sensitive.** From OpenSSH 9.8, per-connection work moved from `sshd` into a separate `sshd-session` binary (and `sshd-auth` in 10.x). Fedora 43 ships OpenSSH 10.0 with `/usr/libexec/openssh/sshd-session` and `sshd-auth` present (verified). Queries on **`_COMM=sshd`** then miss authentication messages; match **`_COMM=sshd-session`** as well, or use `-u sshd.service`. Fedora's fail2ban 1.1.0 `sshd` filter already reflects this (`_daemon = sshd(?:-session)?`, verified). On Debian 12 / Ubuntu 22.04 (OpenSSH 9.2/8.9), `_COMM=sshd` is still correct.

```bash
# field matches: several values of one field are OR-ed, different fields AND-ed
journalctl _COMM=sshd _COMM=sshd-session --since today

# one PID's whole story
journalctl _PID=31337

# on Debian/Ubuntu the unit is ssh.service, not sshd.service
journalctl -u ssh.service --since today
```

#### sudo, su, PAM, account changes

```bash
journalctl -t sudo --since today                      # every sudo, including refusals
journalctl -t sudo -g 'incorrect password|NOT in sudoers'
journalctl -t su --since today
journalctl _COMM=useradd _COMM=usermod _COMM=passwd _COMM=groupadd --since "-30d"
journalctl -g 'pam_unix\(.*:auth\): authentication failure' --since today
```

#### Time windows and boots

```bash
journalctl --since "2026-09-22 14:00" --until "2026-09-22 15:30"
journalctl --since "-45min"
journalctl --list-boots                 # when was it rebooted, and how often
journalctl -b -1 -p warning             # previous boot, warnings and worse
journalctl -k -b -g 'module|taint'      # kernel: module loads, tainting
journalctl -u 'session-*.scope' --since today   # interactive sessions starting/ending
```

An unexpected entry in `--list-boots` during an incident window is a finding in itself.

#### JSON output for tooling

```bash
# one JSON object per line
journalctl -u sshd.service --since today -o json

# only the fields you want
journalctl -t sudo --since today -o json --output-fields=MESSAGE,_UID,_PID,_HOSTNAME

# into jq: failed-password source IPs, counted
journalctl -u sshd.service --since today -o json \
  | jq -r 'select(.MESSAGE|test("Failed password")) | .MESSAGE' \
  | grep -oE 'from [0-9a-f.:]+' | sort | uniq -c | sort -rn | head
```

Verified here: `journalctl -t sudo -o json --output-fields=MESSAGE,_UID,_PID` returns one object per line and always includes the cursor and timestamp fields (`__REALTIME_TIMESTAMP` is microseconds since the epoch) as well as the ones you asked for. `-o json-pretty` for reading, `-o export` for `systemd-journal-remote`.

Trusted fields (prefixed `_`) are set by journald, not by the logging process, so a process can't forge `_UID`, `_PID`, `_COMM`, `_EXE` or `_SYSTEMD_UNIT`. It **can** put anything in `MESSAGE` and `SYSLOG_IDENTIFIER` (what `-t` matches). Pivot on underscore fields when the source matters.

#### Preserve before you rotate

```bash
# is the journal persistent? (volatile journals vanish at reboot)
ls -d /var/log/journal 2>/dev/null && echo persistent || echo volatile-only

# export a window for evidence, in a format journalctl can read back
sudo journalctl --since "2026-09-22 00:00" -o export > /var/tmp/journal-evidence.export
sudo journalctl --verify                 # corruption / FSS verification
```

`journalctl --file=` or `-D DIR` reads a copied journal on an analysis host. Forward Secure Sealing (`journalctl --setup-keys`) makes tampering detectable after the fact; chapter 12 covers evidence handling.

### Checklist

- `auditctl -s` shows `enabled 1` (or 2), `lost 0`, backlog well under the limit.
- Rules live in `/etc/audit/rules.d/`, versioned in config management, loaded with `augenrules --load`.
- Every syscall rule exists for both `b64` and `b32`, or 32-bit syscalls are blocked.
- Filesystem rules use `-F path=`/`-F dir=` with `perm`, not the deprecated `-w`.
- Every rule has a `key`, and you've run `ausearch -k KEY -i` against each one after a test change.
- The `execve` rule is scoped (humans, or root-only on build hosts).
- `auditd.conf` has a disk policy you chose on purpose, and `/var/log/audit` can't fill `/var` on servers.
- Audit events leave the host (syslog plugin or agent) and arrive somewhere you can query.
- `-e 2` is enabled only after a week of watching volume and `lost`.
- Journal is persistent (`/var/log/journal` exists), and your sshd queries match `sshd-session` on OpenSSH 9.8+.

### Traps

- **`grep audit.log`.** One event is several records; grep shows fragments without the `auid` or path that makes them mean anything. Use `ausearch -i`.
- **Trusting `uid`.** `uid=0` is every sudo. The human is `auid`.
- **b64-only rulesets.** A 32-bit binary walks straight past them.
- **Restarting with `systemctl`.** Refused by design on Fedora/RHEL. `augenrules --load` for rules, `service auditd restart` for the daemon.
- **Copying the full STIG set onto a build host.** Log volume and backlog losses follow. Start with the starter set and measure.
- **Immutable mode on day one.** A bad rule then needs a reboot to remove.
- **Local-only logs.** If the only copy is on the compromised host, it's the attacker's copy.
- **`_COMM=sshd` on new OpenSSH.** Misses every authentication message from `sshd-session`.


---


<a id="09-file-integrity-and-malware-scanning"></a>

## 09 · File integrity and malware scanning

*Integrity checking only works if the reference it compares against is out of the attacker's reach. A database, checksum list or signature set stored on the host it protects is evidence the attacker can rewrite. Most of this chapter is about where you keep the known-good copy.*

### What each tool catches

| Tool | Detects | Reference it trusts | Blind to |
|---|---|---|---|
| **`rpm -Va` / `debsums`** | Package-owned files that changed | The package database on the host | Files no package owns; a tampered rpmdb |
| **AIDE** | Any change to files you chose to cover | A database you built from a known-good state | Anything changed before you built it; anything outside its rules |
| **rkhunter / chkrootkit** | Known rootkit artefacts, suspicious config, hidden files | Built-in signatures and heuristics | Anything new; anything that hides from userspace (kernel rootkits) |
| **ClamAV** | Known malware by signature (mostly Windows, some Linux) | Signature database from `freshclam` | Custom or novel implants; cryptominers renamed and recompiled |
| **YARA** | Whatever your rules describe | Rules you (or a feed) wrote | Everything you didn't write a rule for |

**Default pick: `rpm -Va` for a quick "has anything shipped been touched", AIDE with an off-host database for real integrity monitoring, and YARA for hunting once you know what you're looking for.** rkhunter and ClamAV are worth running on specific hosts (mail and file servers for ClamAV; internet-facing hosts for rkhunter) but neither is a substitute for integrity monitoring.

> **Note.** All of these run in userspace on the host they're checking. A kernel-level rootkit can lie to every one of them. The only fully trustworthy check is from outside: boot rescue media, or mount the disk read-only on another machine, and run the check with a known-good binary and database. Chapter 12 covers when that's worth doing.

### Package verification

The package manager already knows what every shipped file should look like. Ask it.

#### rpm -Va on Fedora/RHEL

```bash
sudo rpm -Va                                  # every installed package; takes a few minutes
sudo rpm -Va --noconfig                       # skip %config files, which you're meant to edit
sudo rpm -Va --nomtime --nouser --nogroup     # just content and mode changes
sudo rpm -V openssh-server sudo shadow-utils  # specific packages
sudo rpm -Vf /usr/bin/ls                      # the package that owns this file
```

No output means clean. Each output line is a nine-character code, a type marker, and the path:

```text
S.5....T.  c /etc/ssh/sshd_config
..5....T.    /usr/bin/ps
missing      /usr/lib/systemd/system/foo.service
```

| Char | Meaning | Worry level |
|---|---|---|
| `S` | Size differs | With `5`, the content changed |
| `M` | Mode (permissions or file type) | High on binaries: a new setuid bit is a classic backdoor |
| `5` | Digest (content) differs | High on anything not marked `c` |
| `D` | Device major/minor | Rare |
| `L` | Symlink target | High for binaries and libraries |
| `U` / `G` | Owner / group | Medium |
| `T` | mtime | Low on its own |
| `P` | File capabilities | High: capabilities are quieter than setuid |
| `.` | Test passed | |
| `?` | Test couldn't run (usually: not readable) | You didn't run as root |

The type column: `c` config, `d` doc, `g` ghost, `l` licence, `r` readme. **A `5` on a `c` file is normal, you edited it. A `5` on a binary in `/usr/bin` or a library in `/usr/lib64` is the finding.**

> **Gotcha.** Unprivileged, `rpm -V` fills the output with `?` and `missing ... (Permission denied)`, and returns quietly for everything else. Verified here: an unprivileged `rpm -V openssh-server sudo` showed `..?......` for `/usr/bin/sudo` and `/etc/sudoers`. Run it as root, or the silence means nothing.

Filter the noise down to what matters:

```bash
# changed content or mode on non-config files in system paths
sudo rpm -Va --noconfig 2>/dev/null \
  | awk '$1 ~ /5|M|L|P/ && $NF ~ /^\/(usr|etc|boot)\//' \
  | grep -vE '\.pyc$|/usr/share/(doc|man|locale)/'
```

Then confirm the package itself is authentic and restore the file:

```bash
rpm -qf /usr/bin/ps                       # owning package
dnf download --destdir /var/tmp procps-ng
rpm -Kv /var/tmp/procps-ng-*.rpm          # signature and digest check against the imported keys
sudo dnf reinstall procps-ng              # put the shipped file back (after evidence is preserved)
```

> **Gotcha.** `rpm -Va` trusts the rpm database on the same disk. An attacker who can replace `/usr/bin/ps` can also rewrite the digests in `/var/lib/rpm`. It's a very good tripwire against careless attackers, admin mistakes and broken updates, and no protection against a careful one. For the careful one, verify from rescue media with `rpm --root=/mnt/sysimage -Va`, or compare with a separately stored AIDE database.

#### debsums and dpkg --verify on Debian/Ubuntu

```bash
sudo apt install debsums
sudo debsums -s              # silent: only report problems
sudo debsums -c              # list changed files only
sudo debsums -a -s           # include config files
sudo debsums -l              # packages that shipped without md5sums

# built into dpkg, no extra package; output uses rpm-style codes
sudo dpkg --verify
sudo dpkg --verify openssh-server
```

Two weaknesses to know: the reference is an **MD5** list in `/var/lib/dpkg/info/*.md5sums`, on the same disk, and some packages don't ship one at all (`debsums -l` lists them). To check against the archive instead of the local list, `debsums --generate=missing` or re-download with `apt-get download` and compare. **Default pick on Debian: `dpkg --verify`**, because it's always present; `debsums` when you want config files and the "no md5sums" report.

### AIDE

AIDE builds a database of file attributes (hashes, permissions, owner, inode, ACLs, SELinux context, xattrs) and later compares the live filesystem against it. It catches what package verification can't: changes to files no package owns (`/etc/sudoers.d/*`, `/root/.ssh/authorized_keys`, systemd drop-ins, your own scripts).

Installed here: AIDE 0.19.2 (`dnf install aide`, `apt install aide`); upstream's latest is 0.19.4 (August 2026, [github.com/aide/aide](https://github.com/aide/aide/releases)). Fedora paths: config `/etc/aide.conf`, database directory `/var/lib/aide`, logs `/var/log/aide`.

#### Initialise

```bash
sudo aide --config-check                              # parse the config, report errors
sudo aide --init                                      # builds /var/lib/aide/aide.db.new.gz
sudo mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
```

`--init` writes to `database_out` (`aide.db.new.gz`); `--check` reads `database_in` (`aide.db.gz`). The rename is deliberate: nothing becomes the reference until you promote it. This is the step Lynis's `FINT-4316` warning is about ("No AIDE database was found"): installed and never initialised.

On Debian, the wrapper does the same: `sudo aideinit` then `sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db`.

> **Gotcha.** Initialise **before** the host is exposed, from a known-good state: right after provisioning, or in the image build. A database built on a host that's already compromised faithfully records the compromise as "normal".

#### Check

```bash
sudo aide --check
echo "exit: $?"
sudo aide --check --limit '^/etc/(ssh|sudoers|pam\.d)'   # only paths matching a regex
sudo aide --check -W 4                                     # four hashing workers
```

The exit code is a bitmask (`man aide`, verified): **1** new files, **2** removed files, **4** changed files, added together. `0` is clean, `5` is "new and changed". Codes 14–17 are errors (write, argument, unimplemented, configuration). Script on the bits, not on "non-zero":

```bash
sudo aide --check > /var/log/aide/check-$(date +%F).log; rc=$?
(( rc >= 14 )) && echo "AIDE error $rc" && exit 1
(( rc & 4 ))   && echo "changed files"
(( rc & 2 ))   && echo "removed files"
(( rc & 1 ))   && echo "new files"
```

#### Update after a legitimate change

Every package update changes files. The workflow is: check, **read the report**, and only then accept the new state.

```bash
sudo dnf upgrade --refresh
sudo aide --update                     # check + write aide.db.new.gz with the current state
less /var/log/aide/aide.log            # or wherever report_url points
# every change explained by the update? then promote:
sudo mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
```

> **Gotcha.** `aide --update` followed by an automatic `mv` in the same cron job turns AIDE into a tool that approves every change, including the attacker's. The promotion step must be a human decision (or at least gated on "the only changes are in files owned by packages dnf just updated").

A way to gate it: take the list of changed paths from the report, map each to its owning package with `rpm -qf`, and compare against the packages in the last transaction (`dnf history info last`). Any changed path whose package wasn't in that transaction, or that no package owns, goes to a human. Everything else can be promoted by the script.

> **Version-sensitive.** The report line format (`f > ... : /path` style summary lines) changed between AIDE 0.16, 0.17 and 0.18. Check a real report from your version before parsing it, or set `report_format=json` (added in 0.18, per `man aide.conf`) and parse that instead. AIDE 0.19 also changed unrestricted `!regex` rules to recurse into matching directories; use the new `-regex` form to drop a whole subtree (NEWS for 0.19).

#### What to cover

The default `/etc/aide.conf` on Fedora is broad and noisy. Rules are `path GROUP` selections, `!path` exclusions and `=path` (this directory only, not recursive). A tighter set that still covers the persistence locations from chapter 12:

```ini
# /etc/aide.conf fragment — NORMAL and LOG are groups defined near the top of the
# stock Fedora 43 file (NORMAL = FIPSR+sha512; LOG = > for growing files). Debian
# names its groups differently; check yours (aide --config-check) before reuse
# Binaries and libraries: content, permissions, ownership, SELinux, xattrs
/usr/bin      NORMAL
/usr/sbin     NORMAL
/usr/lib64    NORMAL
/usr/libexec  NORMAL
/boot         NORMAL

# Configuration
/etc          NORMAL
!/etc/mtab$
!/etc/.*~$
!/etc/aide.conf$

# Persistence and access
/root/.ssh    NORMAL
/root/.bashrc NORMAL
/var/spool/cron NORMAL

# Logs: may only grow; a shrink or rewrite is a finding
/var/log      LOG
```

Check what a path would match before committing the config:

```bash
sudo aide --path-check=f:/etc/sudoers.d/90-ops
sudo aide --dry-init | head       # traverse and match, no database written
```

Home directories are usually excluded (they change constantly), which is why `/home/*/.ssh/authorized_keys` needs explicit lines or an osquery check (chapter 11).

#### Protect the database

The database, the config and the binary all live on the host. An attacker with root edits the file, runs `aide --update`, promotes it, and your next check is clean. Options, strongest first:

| Approach | Protects against | Cost |
|---|---|---|
| **Run the check from rescue media or another host** against the mounted disk | Everything, including kernel rootkits | Downtime or snapshot tooling |
| **Store the database off-host**, fetch it for each check, verify its hash | Database tampering | A small script and a place to keep it |
| **Sign the database** and keep the public key off-host | Undetected tampering | GPG in the loop |
| **Read-only media** (the README's original advice) | Tampering, until the attacker controls the mount | Impractical in the cloud |
| Same disk, `chattr +i` | Careless attackers only | Nothing, and roughly worth it |

A practical off-host pattern:

```bash
# after init/promotion: record the hash somewhere the host can't write
sha256sum /var/lib/aide/aide.db.gz /etc/aide.conf /usr/bin/aide \
  | ssh audit@vault.example.internal "cat > aide/$(hostname -s).sha256"

# before each check: verify from the trusted side
ssh audit@vault.example.internal "cat aide/$(hostname -s).sha256" | sha256sum -c -
```

Better still, pull the other way: a central host SSHes in with a forced-command key, copies the database out after init, and later pushes it back in (or runs `aide` against a snapshot). The monitored host then never holds the only trusted copy.

#### Schedule it

Fedora's `aide` package ships no timer (verified, `rpm -ql aide`), and the upstream README advises against unattended checks without verifying AIDE itself. If you schedule it, forward the result off the host:

```ini
# /etc/systemd/system/aide-check.service
[Unit]
Description=AIDE integrity check

[Service]
Type=oneshot
Nice=19
IOSchedulingClass=idle
ExecStart=/usr/bin/aide --check
# exit codes 1–7 are findings, not failures of the unit
SuccessExitStatus=1 2 3 4 5 6 7
```

```ini
# /etc/systemd/system/aide-check.timer
[Unit]
Description=Daily AIDE check

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
```

The output lands in the journal (`journalctl -u aide-check`), which your log shipping forwards. Alert on the unit's output containing "changed" or on a non-zero result, not on the unit failing.

### rkhunter and chkrootkit

Both look for known rootkit fingerprints: specific files, strings in binaries, hidden processes, promiscuous interfaces, suspicious startup entries. They're 2000s-era tools, still maintained lightly, and they mostly find old, known rootkits. Run them for the cheap signal; expect false positives and tune them out once.

**Default pick: rkhunter**, because it has a real config file for whitelisting, a file-properties database, and a cron job on Fedora. chkrootkit is a second opinion.

#### rkhunter

Installed here: rkhunter 1.4.6, with `/etc/cron.daily/rkhunter` and `/etc/sysconfig/rkhunter` (Fedora package).

```bash
sudo rkhunter --update                 # refresh its data files
sudo rkhunter --propupd                # baseline file properties (hashes of key binaries)
sudo rkhunter --check --sk --rwo       # check, skip keypresses, report warnings only
sudo rkhunter --list tests
sudo rkhunter --config-check
```

Log: `/var/log/rkhunter/rkhunter.log` on Fedora (`/var/log/rkhunter.log` on Debian). The log has the detail behind every one-line warning.

`--propupd` is rkhunter's own mini-AIDE for about 100 key binaries. Like AIDE, it must run from a known-good state and **again after every package update**, otherwise every update produces "file properties have changed" warnings. Tell it to use the package manager instead of its own hashes, and most of that noise goes away:

```ini
# /etc/rkhunter.conf.local  (survives package updates; rkhunter.conf does not)
PKGMGR=RPM                    # DPKG on Debian
ALLOW_SSH_ROOT_USER=no        # match your sshd config (chapter 03)
ALLOW_SSH_PROT_V1=0
SCRIPTWHITELIST=/usr/bin/egrep
SCRIPTWHITELIST=/usr/bin/fgrep
SCRIPTWHITELIST=/usr/bin/ldd
ALLOWHIDDENDIR=/etc/.java
ALLOWHIDDENFILE=/etc/.updated
ALLOWDEVFILE=/dev/shm/pulse-shm-*
```

Common false positives and what they mean:

| Warning | Usual cause | Fix |
|---|---|---|
| "The command '/usr/bin/egrep' has been replaced by a script" | Distros ship `egrep`/`fgrep`/`ldd` as scripts | `SCRIPTWHITELIST` |
| "File properties have changed" after updates | `--propupd` not rerun | `PKGMGR=RPM`, or `--propupd` after each update |
| "Hidden directory found: /etc/.java" | Java packaging | `ALLOWHIDDENDIR` |
| "Suspicious file types found in /dev" | PulseAudio/PipeWire shm, systemd | `ALLOWDEVFILE` |
| "Checking for listening processes... Warning" | A legitimate sniffer: `NetworkManager`, `dhclient`, `wireshark` | `ALLOWPROCLISTEN` |
| "SSH root access is allowed" | Your sshd config actually allows it | Fix sshd, don't whitelist |

Every whitelist entry is a place an attacker can hide. Whitelist the exact path, never a directory glob you don't control.

#### chkrootkit

Installed here: chkrootkit 0.58. On Fedora, `/usr/bin/chkrootkit` is a consolehelper wrapper and will prompt for the root password when run as a normal user; run it with `sudo`.

```bash
sudo chkrootkit            # all tests
sudo chkrootkit -q         # quiet: only things it considers infected/suspicious
sudo chkrootkit -x | less  # expert mode: dump the strings it inspected
sudo chkrootkit -r /mnt/sysimage   # check a mounted disk from rescue media
```

Typical false positives: `bindshell INFECTED (PORTS: 465)` when a mail server listens on 465; `PACKET SNIFFER` for `dhclient`/`NetworkManager`/`tcpdump` sockets; "suspicious files" under `/usr/lib/debug/.build-id` or `/usr/lib/python*/site-packages` (dot-files shipped by packages). Confirm each by checking which process owns the port or file (`ss -tlnp`, `rpm -qf`) rather than trusting the verdict.

> **Note.** `-r /mnt/sysimage` is the most valuable way to use chkrootkit: from a rescue boot, against the suspect disk, where a rootkit in the suspect kernel can't hide anything.

### ClamAV

ClamAV is signature-based antivirus. On Linux servers its real jobs are: scanning files **passing through** (uploads, mail attachments, shared drives) for Windows malware, and catching commodity Linux malware (known miners, Mirai-family bots, webshells). It won't find a targeted implant.

Installed here: ClamAV 1.4.6 (the 1.4 LTS line; upstream feature release is 1.5.4). Fedora packages: `clamav` (scanner, `clamscan`, `clamdscan`, `clamonacc`), `clamav-freshclam` (updater and its units), `clamd` (daemon, `clamd@.service`), with the daemon config at `/etc/clamd.d/scan.conf`. Debian: `clamav`, `clamav-freshclam`, `clamav-daemon`.

#### Signatures: freshclam

```bash
sudo systemctl enable --now clamav-freshclam.service    # daemon mode, checks several times a day
# or the timer-driven one-shot variant shipped in the same package
sudo systemctl enable --now clamav-freshclam-once.timer
sudo freshclam                                          # manual, verbose
sigtool --info /var/lib/clamav/daily.cvd                # version and build time of a db
```

**Pick one of the two units**, not both. Unit names verified from the Fedora 43 `clamav-freshclam` package.

> **Note.** Upstream's sample configs start with an `Example` line that stops freshclam and clamd from running. Fedora's `clamav.spec` comments it out in both `/etc/freshclam.conf` and `/etc/clamd.d/scan.conf` (since 2020, src.fedoraproject.org); a hand-built or upstream-tarball config still needs it removed. `/etc/freshclam.conf` is mode 600 on Fedora (it can hold a proxy password), so `sudo grep -n '^Example'` it.

> **Gotcha.** The ClamAV CDN rate-limits and blocks clients that update too often (more than once an hour) or from large NAT pools. For a fleet, run a **private mirror** (`cvdupdate`) and point `DatabaseMirror` at it. That's also the only way to feed air-gapped hosts.

#### On-demand scans: clamscan

`clamscan` loads the full signature database (about 1 GB of RAM, several seconds) every time it starts. Fine for an occasional scan, wrong for anything frequent.

```bash
# scan a tree, report only infected files, log it
sudo clamscan -r -i --log=/var/log/clamscan-$(date +%F).log /srv/uploads

# don't cross into other filesystems, skip pseudo-filesystems and big files
sudo clamscan -r -i --cross-fs=no \
  --exclude-dir='^/(proc|sys|dev|run)' \
  --max-filesize=100M --max-scansize=400M --alert-exceeds-max=yes /

# quarantine instead of printing
sudo clamscan -r -i --move=/var/quarantine /srv/uploads
```

Flags verified against `clamscan --help` (1.4.6):

| Flag | Does | When |
|---|---|---|
| `-r` | Recurse | Always for directories |
| `-i` | Print only infected files | Always, or the output is useless |
| `--log=FILE` | Write the report | Scheduled scans |
| `--cross-fs=no` | Stay on one filesystem | Scanning `/` |
| `--exclude-dir=REGEX` | Skip matching dirs | `/proc`, `/sys`, container storage |
| `--max-filesize` / `--max-scansize` | Skip large files / cap archive expansion | Performance; large files are **assumed clean** |
| `--alert-exceeds-max=yes` | Flag files that hit a limit | So "skipped" isn't silently "clean" |
| `--detect-pua=yes` | Potentially unwanted apps (hacking tools, adware) | Workstations; noisy on admin hosts |
| `--move=DIR` | Quarantine | Upload directories |
| `--remove` | Delete infected files | Almost never; see below |

> **One-way door.** `--remove` deletes the file, and with it the evidence and any chance to confirm a false positive. ClamAV false positives on legitimate binaries happen with every few signature releases. Use `--move` to a root-only quarantine directory instead.

#### The daemon: clamd and clamdscan

For anything frequent (mail filters, upload hooks, scheduled scans of large trees), run `clamd` once and send it work with `clamdscan`.

```ini
# /etc/clamd.d/scan.conf — the lines to uncomment/set on Fedora
LocalSocket /run/clamd.scan/clamd.sock
LocalSocketMode 660
LogSyslog yes
User clamscan
```

```bash
sudo systemctl enable --now clamd@scan
clamdscan --fdpass -i /srv/uploads/new-file.zip     # --fdpass: clamd reads via the caller's fd
clamdscan --multiscan --fdpass -i /srv/uploads       # parallel
clamdtop                                             # live view of the daemon
```

On SELinux hosts, clamd confined as `antivirus_t` can only read what policy allows. To scan the whole system: `sudo setsebool -P antivirus_can_scan_system 1` (chapter 05 covers booleans).

#### On-access scanning and its limits

`clamonacc` uses fanotify to scan files as they're opened, with optional blocking (`OnAccessPrevention yes`). It sounds like desktop antivirus. In practice:

- It watches only the paths you list (`OnAccessIncludePath`), and watching `/` is not supported: fanotify's permission events and the load make it impractical.
- It needs root, `clamd` running, and a kernel with fanotify permission events (`CONFIG_FANOTIFY_ACCESS_PERMISSIONS`; enabled in Fedora and RHEL kernels).
- With prevention on, every open on a watched path waits for a scan. A cold cache on a busy directory stalls applications; exclude `clamd`'s own user (`OnAccessExcludeUname clamscan`) or it deadlocks scanning itself.
- Container overlay filesystems and network filesystems behave inconsistently under fanotify.

**Default pick: no on-access scanning on servers.** Scan uploads explicitly at the point they arrive (a hook calling `clamdscan --fdpass`), and scan shares on a schedule. Use `clamonacc` only for a small, specific directory (an incoming SFTP drop) where blocking is actually wanted.

### YARA basics

YARA matches files (or process memory) against rules made of strings, byte patterns and conditions. It's the lingua franca for sharing detections: threat reports ship YARA rules, and you can write one in minutes for an indicator you found during an incident.

YARA 4.5.4 is packaged in Fedora 43 (`dnf install yara`) and Debian/Ubuntu; upstream is at 4.5.8. It wasn't installed on the machine this chapter was written on; the syntax below is from the upstream documentation.

> **Version-sensitive.** VirusTotal's Rust rewrite, **YARA-X** (command `yr`, 1.20 as of August 2026, not packaged in Fedora), is the successor; the original YARA's README says "This project is in maintenance mode" (github.com/VirusTotal/yara). Rule syntax is almost entirely compatible; the CLI differs: `yr scan --recursive --print-strings RULES PATH`, `yr compile -o rules.yarc RULES` then `yr scan -C rules.yarc PATH` ([virustotal.github.io/yara-x](https://virustotal.github.io/yara-x/docs/cli/commands/)). YARA-X's CLI has no process-memory scan, so keep `yara` for the PID trick below.

#### A rule

```text
rule xmrig_miner_config
{
    meta:
        description = "XMRig miner binary or config"
        author      = "ops"
        date        = "2026-09-23"

    strings:
        $a = "xmrig" nocase
        $b = "\"donate-level\"" ascii
        $c = "stratum+tcp://" ascii
        $d = { 78 6D 72 69 67 2F }          // "xmrig/" as hex

    condition:
        filesize < 20MB and 2 of them
}
```

Structure: `meta` is free-form documentation; `strings` are text (`ascii`, `wide`, `nocase`), hex with wildcards (`{ 4D 5A ?? ?? }`) or regex (`/pattern/`); `condition` is a boolean expression over them (`any of them`, `all of ($a*)`, `#a > 3`, `$a at 0`, `uint16(0) == 0x457f` for ELF).

#### Run it

```bash
yara -r rules.yar /tmp /var/tmp /dev/shm          # recurse, print matching rule and file
yara -r -s rules.yar /home                        # also print the matched strings and offsets
yara -r -p 4 -f rules.yar /srv                    # 4 threads, fast mode (first match per rule)
yara -r --timeout=30 rules.yar /                  # don't hang on huge files
sudo yara rules.yar 31337                         # scan a running process's memory by PID
yarac rules.yar rules.compiled && yara -C rules.compiled /tmp   # precompile a large set
```

Scanning a PID is the useful trick for fileless malware: an implant that deleted its binary after starting (see "deleted-but-open files" in chapter 12) is still in memory.

Where rules come from: your own incident notes first, then curated sets (Neo23x0 `signature-base`, Elastic's `protections-artifacts`, YARA-Forge bundles). Public rule sets are large and noisy; run them on a sample of known-clean hosts first and prune the rules that fire there.

### Checklist

- `sudo rpm -Va --noconfig` (or `dpkg --verify`) is clean, or every line is explained.
- AIDE is initialised from a known-good state, and the reference database's hash lives off the host.
- AIDE updates are promoted by a human, or gated on "only files from packages just updated".
- The AIDE config covers `/root/.ssh`, `/etc/sudoers.d`, systemd unit directories and cron spools.
- rkhunter uses `PKGMGR=RPM`/`DPKG`, overrides are in `rkhunter.conf.local`, and each whitelist entry is an exact path.
- `freshclam` runs from exactly one unit, against a private mirror if you have more than a handful of hosts.
- ClamAV uses `--move`, never `--remove`, and `--alert-exceeds-max=yes` so size limits don't hide files.
- You know how to boot rescue media and run `rpm --root`, `aide` and `chkrootkit -r` against the mounted disk.

### Traps

- **Initialising AIDE after the fact.** The database records whatever state the host is in, compromise included.
- **Auto-promoting AIDE updates.** Turns the integrity checker into an approval stamp.
- **Trusting `rpm -Va` against a careful attacker.** It compares against the rpmdb on the same disk.
- **Running verification unprivileged.** `rpm -V` and `aide` return partial results quietly.
- **Whitelisting directories in rkhunter.** Every glob is a hiding place.
- **Treating ClamAV as EDR.** It finds known samples, not intrusions.
- **`clamscan` in a tight loop.** It reloads a gigabyte of signatures each time; use `clamd`.
- **`--remove` on a false positive.** The file and the evidence are both gone.
- **Userspace checks against a kernel rootkit.** Only an out-of-band check (rescue media, mounted disk) is trustworthy.


---


<a id="10-ban-block-and-detect-at-runtime"></a>

## 10 · Ban, block and detect at runtime

*Log-driven banning, device allow-listing and syscall-level detection all do the same thing at different layers: they turn a known-bad pattern into an automatic response. Each one is only as good as the pattern it matches, so the work is in testing the match, not installing the tool.*

### What goes where

| Tool | Layer | Does | Pick it when |
|---|---|---|---|
| **fail2ban** | Logs → firewall | Bans source IPs after N failures | Services that still accept passwords (web logins, mail, FTP); on key-only SSH it's log hygiene |
| **CrowdSec** | Logs → local API → bouncers | Same, plus shared community blocklists and multi-host decisions | You run a fleet and want one decision to apply everywhere |
| **USBGuard** | Kernel USB authorisation | Allow-lists USB devices | Laptops, kiosks, servers in shared racks |
| **Falco** | Kernel syscalls (eBPF) | Alerts on suspicious runtime behaviour on hosts and in containers | Container hosts and Kubernetes nodes; anything where "what ran" matters |

**Default pick: fail2ban on single hosts, CrowdSec only if you'll actually use its shared decisions across a fleet.** Both do the same core job; fail2ban is already packaged and tuned for Fedora's journal and firewalld, CrowdSec is a bigger system with a bigger payoff when there's more than one host.

> **Note.** None of this replaces the basics from chapters 03 and 04. Key-only SSH and a closed firewall make brute-force attempts irrelevant, and OpenSSH 9.8+ throttles abusive sources itself with `PerSourcePenalties` (on by default); an `sshd` jail then just keeps the logs quiet. If fail2ban is the thing standing between the internet and a password-authenticated service, fix the service first.

### fail2ban

Installed here: fail2ban 1.1.0 (upstream is at 1.1.1; packages `fail2ban`, `fail2ban-server`, `fail2ban-firewalld`, `fail2ban-selinux`, `fail2ban-sendmail`). Debian/Ubuntu: `apt install fail2ban` (backend and banaction defaults differ; see below).

#### How it works

```text
journal / log file ──▶ filter (failregex) ──▶ jail counts hits per IP
                                                │  maxretry within findtime?
                                                ▼
                                             action (banaction) ──▶ firewalld / nftables
                                                │  after bantime
                                                ▼
                                             unban
```

A **jail** ties a **filter** (regexes in `filter.d/NAME.conf`) to a log source (**backend** and `logpath` or `journalmatch`) and an **action** (`action.d/NAME.conf`). Everything is ini files, layered: `.conf` files belong to the package, `.local` files and `jail.d/*.local` are yours.

#### What Fedora already configures

Verified on this machine:

- `/etc/fail2ban/jail.d/00-firewalld.conf` (from `fail2ban-firewalld`) sets `banaction = firewallcmd-rich-rules` and `banaction_allports = firewallcmd-rich-rules`.
- `/etc/fail2ban/paths-fedora.conf` sets `sshd_backend = systemd` (and the same for postfix, dovecot and others), so the `sshd` jail reads the journal, not `/var/log/secure`.
- The `sshd` filter's `journalmatch` is `_SYSTEMD_UNIT=sshd.service + _COMM=sshd + _COMM=sshd-session`, and its `_daemon` regex is `sshd(?:-session)?`. That already handles OpenSSH 9.8+'s `sshd-session` process (see chapter 08).
- **Every jail is disabled by default.** Lynis flags that as `TOOL-5104`: installed, running, and doing nothing.

On Debian/Ubuntu, `jail.d/defaults-debian.conf` enables `sshd` out of the box; since Debian 12 the default `backend` is `systemd` there too (no `/var/log/auth.log` without rsyslog), and the banaction defaults to `nftables` on recent releases.

#### Enable the sshd jail

```ini
# /etc/fail2ban/jail.local
[DEFAULT]
# never ban yourself: loopback, the management subnet, the bastion
ignoreip = 127.0.0.1/8 ::1 10.20.0.0/24 BASTION_IP

bantime  = 1h
findtime = 10m
maxretry = 5

# repeat offenders get longer bans: 1h, 2h, 4h ... capped at a week
bantime.increment = true
bantime.maxtime   = 1w
bantime.overalljails = true

[sshd]
enabled = true
mode    = aggressive      # normal | ddos | extra | aggressive (all of them)

[recidive]
enabled  = true           # bans IPs that keep getting banned, on all ports, for a week
```

```bash
sudo fail2ban-client -t                    # test the configuration
sudo systemctl enable --now fail2ban
sudo fail2ban-client status                # list active jails
sudo fail2ban-client status sshd           # failures, bans, currently banned IPs
```

Stock values in `jail.conf` (verified): `bantime = 10m`, `findtime = 10m`, `maxretry = 5`, `backend = auto`, `mode = normal`; `recidive` uses `bantime = 1w`, `findtime = 1d` and reads `/var/log/fail2ban.log`.

> **Gotcha.** `recidive` reads fail2ban's **own log file**. Fedora's stock `fail2ban.conf` has `logtarget = /var/log/fail2ban.log` (verified), so it works out of the box; but if you (or a hardening role) switch to `logtarget = SYSTEMD-JOURNAL` or `SYSLOG`, there's no `/var/log/fail2ban.log` and `recidive` never fires. Check `sudo fail2ban-client get logtarget`, and either set `logtarget = /var/log/fail2ban.log` in `fail2ban.local` or give `recidive` `backend = systemd` with `journalmatch = _SYSTEMD_UNIT=fail2ban.service`.

#### banaction with firewalld

Fedora's default, `firewallcmd-rich-rules`, adds one runtime firewalld rich rule per banned IP and port (`rule family='ipv4' source address='X' port port='22' protocol='tcp' reject`, verified in `action.d/firewallcmd-rich-rules.conf`). It's visible and easy to reason about:

```bash
sudo firewall-cmd --list-rich-rules
sudo fail2ban-client set sshd unbanip 203.0.113.9
sudo fail2ban-client unban --all
sudo fail2ban-client banned                 # all jails, all banned IPs (1.0+)
```

**Default pick: keep `firewallcmd-rich-rules`.** The alternatives on Fedora:

| banaction | Mechanism | Tiebreaker |
|---|---|---|
| `firewallcmd-rich-rules` | One rich rule per IP | Default. Fine into the low thousands of bans |
| `firewallcmd-ipset` | firewalld ipset + a **direct** rule | Scales to 65k entries, but uses firewalld's deprecated direct interface |
| `nftables-multiport` / `nftables-allports` | Its own nft table and set, bypassing firewalld | Hosts without firewalld (chapter 04's nft-only setups) |

> **Gotcha.** Mixing a firewalld host with the `nftables-*` actions works (they create a separate `inet f2b-table`), but `firewall-cmd --list-all` won't show the bans and a `firewall-cmd --reload` won't touch them. Someone debugging "why can't I connect" will look in the wrong place. Use the firewalld actions on firewalld hosts.

> **Gotcha.** `firewall-cmd --reload` drops runtime rich rules, including fail2ban's bans, and the `firewallcmd-rich-rules` action has an empty `actioncheck` (verified), so nothing notices. fail2ban still thinks the IPs are banned. If config management reloads firewalld, follow it with `fail2ban-client reload --restart --all`, which restarts the jails and re-applies bans from fail2ban's database.

#### Test a filter with fail2ban-regex

Never enable a custom filter without testing it against real log lines, both the lines that should match and the lines that shouldn't.

```bash
# one line against a stock filter (verified: 1 matched, 0 missed)
fail2ban-regex \
  'Sep 23 10:01:02 host sshd-session[1234]: Failed password for invalid user admin from 203.0.113.9 port 51022 ssh2' \
  sshd

# the live journal against the sshd filter, using its journalmatch
sudo fail2ban-regex systemd-journal sshd

# a filter mode, and print what matched / missed
sudo fail2ban-regex systemd-journal 'sshd[mode=aggressive]' --print-all-matched
sudo fail2ban-regex /var/log/nginx/access.log /etc/fail2ban/filter.d/nginx-limit-req.conf --print-all-missed
```

The summary to read is the last line, `Lines: N lines, I ignored, M matched, X missed`. A new filter with zero matches on a log that definitely contains failures is wrong; a filter that matches successful logins is dangerous.

#### A custom jail: GitLab sign-in failures

Self-hosted GitLab logs each failed web sign-in as `Failed Login: username=USER ip=IP` through its application logger (`log_failed_login` in `sessions_controller.rb`). That lands in `application_json.log`; the plain `application.log` that fail2ban's stock `gitlab` filter reads is deprecated since GitLab 15.10 ([docs.gitlab.com](https://docs.gitlab.com/administration/logs/)). Don't key on `production_json.log`: a failed sign-in there has no clean HTTP status to match on. A filter and jail for the JSON log:

```ini
# /etc/fail2ban/filter.d/gitlab-auth.local
[Definition]
failregex = "message":"Failed Login: username=\S* ip=<HOST>"
ignoreregex =
datepattern = "time":"%%Y-%%m-%%dT%%H:%%M:%%S
```

```ini
# /etc/fail2ban/jail.d/gitlab.local
[gitlab-auth]
enabled  = true
backend  = polling
logpath  = /var/log/gitlab/gitlab-rails/application_json.log
port     = http,https
maxretry = 10
findtime = 10m
bantime  = 1h
```

```bash
# verified with fail2ban-regex 1.1.0 against a sample Failed Login line: 1 matched
sudo fail2ban-regex /var/log/gitlab/gitlab-rails/application_json.log gitlab-auth --print-all-matched | head
```

> **Version-sensitive.** fail2ban merged a `logtype = json` mode for its stock `gitlab` filter in August 2026 (PR #4230), after 1.1.1; once your package has it, `filter = gitlab[logtype=json]` replaces the custom filter above. The `ip=` value is Rails' `request.remote_ip`: behind a reverse proxy it's the proxy unless GitLab's `trusted_proxies` is set, and banning the proxy bans everyone. GitLab also has its own rate limiting (Admin > Settings > Network) and Rack Attack; use those first for the web UI.

#### Traps specific to fail2ban

- **Banning through a proxy or NAT.** One corporate egress IP makes five mistyped passwords a company-wide outage. `ignoreip` the known NAT ranges.
- **IPv6.** Attackers rotate within a /64. fail2ban 1.x bans individual v6 addresses; `recidive` helps, and firewalld rich rules accept prefixes if you write your own action.
- **Log backend mismatch.** On Fedora there's no `/var/log/secure` by default; a jail with `backend = auto` and a `logpath` that doesn't exist fails quietly. `fail2ban-client status JAIL` shows `File list:` or `Journal matches:`; check it names something real.

### CrowdSec

CrowdSec splits fail2ban's job in two: the **security engine** parses logs and makes decisions (bans) into a local API; **bouncers** (remediation components) fetch decisions and enforce them in a firewall, nginx, Traefik or a WAF. Hosts can share one local API, and the engine can subscribe to a community blocklist built from other users' signals.

Not packaged in Fedora; the vendor repo is at packagecloud (`curl -s https://install.crowdsec.net | sudo sh` sets it up, or add the repo file by hand, which you should prefer on anything you care about). Not installed on the machine this chapter was written on; commands are from [docs.crowdsec.net](https://docs.crowdsec.net/) (engine 1.8.1, firewall bouncer 0.0.36 as of September 2026).

```bash
sudo dnf install crowdsec crowdsec-firewall-bouncer-nftables
sudo systemctl enable --now crowdsec crowdsec-firewall-bouncer

sudo cscli collections list                      # parsers + scenarios installed
sudo cscli collections install crowdsecurity/sshd crowdsecurity/linux
sudo cscli metrics                               # what's being parsed, what's matching
sudo cscli decisions list                        # current bans
sudo cscli decisions add --ip 203.0.113.9 --duration 4h --reason "manual"
sudo cscli decisions delete --ip 203.0.113.9
sudo cscli alerts list
sudo cscli bouncers list
```

Log sources are declared in `/etc/crowdsec/acquis.yaml` or files in `/etc/crowdsec/acquis.d/`; for the journal:

```yaml
# /etc/crowdsec/acquis.d/sshd.yaml
source: journalctl
journalctl_filter:
  - "_SYSTEMD_UNIT=sshd.service"
labels:
  type: syslog
```

Bouncer config: `/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml` (with `.local` overrides from bouncer v0.0.25). The engine alone blocks nothing; **no bouncer, no protection.**

**Tiebreaker vs fail2ban:** CrowdSec wins when you have several hosts and want a decision on one (or a community blocklist) applied on all of them, or when you want to block at nginx/Traefik rather than the firewall. For one host, fail2ban does the same job with less running and no external account.

> **Gotcha.** The nftables bouncer manages its own nft tables (`crowdsec` and `crowdsec6` by default), the same trade-off as fail2ban's `nftables-*` actions on a firewalld host: bans don't appear in `firewall-cmd` output. Document where the bans live.

> **Note.** The community blocklist sends CrowdSec signals (attacking IPs and scenario names) to the vendor's central API. It's opt-out: set `sharing: false` under `online_client` in `/etc/crowdsec/config.yaml` to stop sending signals, or comment out the whole `online_client` block to disable the central API entirely. Air-gapped or sensitive environments should do the latter and run the engine offline.

### USBGuard

USBGuard uses the kernel's USB authorisation interface to allow or block devices by attributes: vendor/product ID, serial, a hash of the descriptors, the interfaces the device exposes, the port it's plugged into. It defends against the rubber-ducky class of attack (a "keyboard" that types a payload) and against unapproved storage.

USBGuard 1.1.4 (the current upstream release) is packaged in Fedora (`dnf install usbguard`) and Debian/Ubuntu. Not installed here; commands and daemon settings checked against the upstream man pages (github.com/USBGuard/usbguard).

#### Deploy without locking yourself out

```bash
sudo dnf install usbguard
# 1. snapshot the devices connected right now as the allow-list
sudo sh -c 'usbguard generate-policy > /etc/usbguard/rules.conf'
sudo chmod 0600 /etc/usbguard/rules.conf
# 2. read it: every line is a device you're about to trust forever
sudo less /etc/usbguard/rules.conf
# 3. start it
sudo systemctl enable --now usbguard
```

> **One-way door.** Starting USBGuard with an empty or wrong policy blocks every USB device that isn't already authorised, including the USB keyboard you'd use to fix it on a desktop with no PS/2 port. Generate the policy with the keyboard plugged in, keep an SSH session open, and have a second way in before the first start. The undo on a remote box without SSH is a console or a rescue boot.

#### Day-to-day

```bash
sudo usbguard list-devices                  # every device, its rule id and state
sudo usbguard list-devices --blocked
sudo usbguard allow-device 12               # this time only
sudo usbguard allow-device -p 12            # and append a permanent rule
sudo usbguard block-device 12
sudo usbguard list-rules
sudo usbguard watch                         # live events
```

To let non-root users (desktop applet, `usbguard` CLI) manage devices, set `IPCAllowedGroups=wheel` in `/etc/usbguard/usbguard-daemon.conf`.

#### Rules worth writing

```text
# /etc/usbguard/rules.conf
# A specific YubiKey, by id and serial
allow id 1050:0407 serial "12345678" with-interface { 03:01:01 03:00:00 0b:00:00 }

# Any keyboard, but only on the internal port (hub 1, port 3)
allow with-interface equals { 03:01:01 } via-port "1-3"

# Reject anything that claims to be both storage and a keyboard: the classic BadUSB shape
reject with-interface all-of { 08:*:* 03:00:01 }

# Block (don't remove) mass storage everywhere else
block with-interface one-of { 08:*:* }
```

Interface classes you'll use: `03` HID (keyboards, mice, security keys), `08` mass storage, `09` hub, `0b` smart card, `e0` wireless. Rules are evaluated top to bottom; the first match wins.

Daemon settings (`usbguard-daemon.conf`) that decide how strict it is:

| Setting | Does | Sensible |
|---|---|---|
| `ImplicitPolicyTarget` | What happens when no rule matches | `block` |
| `PresentDevicePolicy` | Devices already connected when the daemon starts | `apply-policy` (or `keep` while rolling out) |
| `InsertedDevicePolicy` | Newly inserted devices | `apply-policy` |
| `IPCAllowedGroups` | Who may use the CLI/IPC | `wheel` |

On servers, `usb-storage` can simply be blacklisted as a kernel module (Lynis `USB-1000`, chapter 06). USBGuard is for when some USB devices must work and others mustn't.

### Falco

Falco watches syscalls through an eBPF probe (or a kernel module) and evaluates them against rules: "a shell was spawned in a container", "something wrote below `/etc`", "a process read `/etc/shadow` that isn't `sshd` or `login`", "outbound connection from a process that never makes one". It's detection, not prevention: it alerts, and something else acts.

It's a CNCF graduated project, not packaged by Fedora. Not installed on the machine this chapter was written on; details are from falco.org and the project CHANGELOG (latest release 0.45.0, 21 September 2026).

#### Install on a host

```bash
sudo rpm --import https://falco.org/repo/falcosecurity-packages.asc
sudo curl -o /etc/yum.repos.d/falcosecurity.repo https://falco.org/repo/falcosecurity-rpm.repo
sudo dnf install falco
```

The package installs several systemd units; enable exactly one driver:

| Unit | Driver | Pick |
|---|---|---|
| `falco-modern-bpf.service` | Modern eBPF (CO-RE, built into the binary) | **Default.** Needs kernel 5.8+ with BTF; Fedora and RHEL 9+ have both |
| `falco-kmod.service` | Kernel module | Old kernels without BTF (the legacy eBPF probe is gone since 0.44) |
| `falco-custom.service` | Your own config | Special cases |
| `falcoctl-artifact-follow.service` | Pulls rule updates | Optional; pin versions in production |

```bash
sudo systemctl enable --now falco-modern-bpf.service
journalctl -u falco-modern-bpf -f
```

On Kubernetes, the Helm chart (`falcosecurity/falco`) runs it as a DaemonSet with the same drivers; the Kubernetes Field Manual's chapter 10 covers cluster use. This chapter is about hosts.

> **Note.** The modern eBPF driver needs `CAP_BPF`, `CAP_PERFMON` and `CAP_SYS_RESOURCE` (or privileged mode in a container). That's a highly privileged component by design; it's the thing watching root. Pin its version and its rules like any other security-critical dependency.

#### Config and rules layout

| Path | Contents |
|---|---|
| `/etc/falco/falco.yaml` | Main config: driver, outputs, rules files to load |
| `/etc/falco/config.d/` | Config overrides that survive package upgrades (0.38+) |
| `/etc/falco/falco_rules.yaml` | Stock rules. **Don't edit**; upgrades replace it |
| `/etc/falco/falco_rules.local.yaml` | Your rules and overrides |
| `/etc/falco/rules.d/` | More of your rules, loaded in order |

#### A rule

```yaml
# /etc/falco/falco_rules.local.yaml
- list: ops_shell_binaries
  items: [bash, sh, zsh, dash]

- macro: in_ci_runner
  condition: container.image.repository startswith "registry.example.internal/ci/"

- rule: Shell in production container
  desc: An interactive shell started inside a container that isn't a CI job
  condition: >
    spawned_process and container
    and proc.name in (ops_shell_binaries)
    and proc.tty != 0
    and not in_ci_runner
  output: >
    Shell in container (user=%user.name container=%container.name
    image=%container.image.repository cmd=%proc.cmdline parent=%proc.pname)
  priority: WARNING
  tags: [container, shell, mitre_execution]

- rule: Write below etc outside package manager
  desc: Something other than dnf/rpm/systemd wrote a file under /etc
  condition: >
    open_write and fd.name startswith /etc/
    and not proc.name in (dnf, dnf5, rpm, systemd, systemd-tmpfiles, sssd)
  output: "Write below /etc (file=%fd.name proc=%proc.cmdline user=%user.name)"
  priority: ERROR
```

`spawned_process`, `open_write` and `container` are macros from the stock rules. To tune a stock rule without copying it, override pieces of it:

```yaml
- rule: Terminal shell in container
  condition: and not container.image.repository = "registry.example.internal/tools/debug"
  override:
    condition: append
```

Validate before reloading:

```bash
sudo falco --dry-run -r /etc/falco/falco_rules.yaml -r /etc/falco/falco_rules.local.yaml
sudo falco --list | head          # fields you can use in conditions
```

> **Version-sensitive.** From Falco 0.41, container metadata (`container.*` fields) comes from the **container plugin** rather than being built in. The package enables it with a drop-in, `/etc/falco/config.d/falco.container_plugin.yaml` (`load_plugins: [container]`); if you set `load_plugins` yourself, keep `container` in the list or every `container.*` field comes back empty. The `override` syntax above needs 0.37+ (selective overrides, CHANGELOG). 0.44 removed the legacy eBPF probe, gVisor support and gRPC output. Check `falco --version` and the release notes before copying rules between versions.

#### Outputs

Enabled per channel in `falco.yaml`:

```yaml
json_output: true
json_include_output_property: true

stdout_output:
  enabled: true           # → journal under systemd

file_output:
  enabled: true
  keep_alive: false
  filename: /var/log/falco/events.json

syslog_output:
  enabled: false

http_output:
  enabled: true
  url: https://falcosidekick.example.internal:2801/

program_output:
  enabled: false
  program: "jq -c '{rule, priority, output}' | logger -t falco"
```

Channels: `stdout_output`, `file_output`, `syslog_output`, `program_output`, `http_output` (gRPC output was removed in 0.44). **Default pick: `json_output: true` to stdout** (so the journal and your existing log shipping carry it) plus `http_output` to **Falcosidekick** if you need fan-out to Slack, Loki, Elasticsearch, a SIEM or a response function. Sidekick is a separate project that takes one HTTP stream and forwards it to many destinations.

#### Noise

Stock rules on a developer workstation or CI runner fire constantly: compilers write under `/etc` in containers, package managers spawn shells, Docker and Podman do things that look like escapes. Plan for a week of tuning per host role:

```bash
# which rules fire most (JSON output in the journal)
journalctl -u falco-modern-bpf --since "-24h" -o cat \
  | jq -r 'select(.rule) | .rule' | sort | uniq -c | sort -rn | head -20
```

Then add exceptions (`exceptions:` blocks, or `override` with `append`) per rule, narrowly: a specific image, a specific parent process. Disabling a whole rule because one tool trips it is how detection coverage erodes.

### Checklist

- fail2ban: `sshd` jail enabled, `ignoreip` covers your management networks, `fail2ban-client status sshd` shows a real journal match.
- Every custom filter has been run through `fail2ban-regex` against real lines, matched and missed both checked.
- `recidive` can actually read what fail2ban logs.
- Bans live where your team looks (firewalld on firewalld hosts).
- CrowdSec only with a bouncer installed, and the community signal sharing decided on purpose.
- USBGuard policy generated with your input devices attached, reviewed, and a second way in available before first start.
- Falco on container hosts with the modern eBPF driver, local rules in `falco_rules.local.yaml`, JSON output shipped off the host, and a tuning pass per host role.

### Traps

- **Installed, running, no jails.** Fedora's fail2ban ships with every jail disabled.
- **Banning the proxy.** A reverse proxy or corporate NAT without `ignoreip` or `trusted_proxies` turns one attacker into a full outage.
- **`firewall-cmd --reload` from config management.** Clears fail2ban's runtime bans until the next check.
- **Treating fail2ban as the defence.** It reduces noise; key-only SSH is the defence.
- **CrowdSec engine without a bouncer.** Decisions get made; nothing enforces them.
- **USBGuard with an empty policy.** Blocks the keyboard you'd use to fix it.
- **Editing `falco_rules.yaml`.** The next package upgrade reverts it; use the local file and overrides.
- **Muting a Falco rule instead of scoping an exception.** One noisy tool, one rule disabled, one class of attack invisible.


---


<a id="11-exposure-and-vulnerability-visibility"></a>

## 11 · Exposure and vulnerability visibility

*You can only defend what you can enumerate. What is listening, what is installed, what has a published fix you haven't applied, and what changed since yesterday: four inventories, each answered by a different tool, and each worth more on a whole fleet than on one host.*

### The four questions

| Question | Local, one host | Fleet |
|---|---|---|
| **What's reachable?** | `ss`, `lsof`, then `nmap` from outside the host | `nmap` sweeps of your own ranges; osquery `listening_ports` |
| **What's installed?** | `rpm -qa` / `dpkg -l`, Syft SBOM | osquery `rpm_packages`/`deb_packages`; SBOMs in a store |
| **What's vulnerable?** | `dnf updateinfo`, Trivy/Grype | Wazuh vulnerability detection; Grype over stored SBOMs |
| **What changed?** | AIDE (chapter 09), osquery diffs | osquery scheduled queries, Wazuh FIM/SCA |

> **Note.** Scope rule for this whole chapter: **scan only hosts and networks you own or are explicitly authorised to test.** Port scans and vulnerability scripts against someone else's address space are, at best, a terms-of-service violation and a call from your provider's abuse desk, and in many jurisdictions an offence. Your cloud provider's rules on scanning your own instances also apply. Everything below is written against `localhost` or `YOUR_SUBNET`.

### What's listening: ss and lsof

Start on the host. It's faster than a scan and it tells you **which process** owns each socket, which a scan never can.

```bash
# TCP and UDP listeners, numeric, with owning process (root to see other users' processes)
sudo ss -tulpn

# no header, TCP only, for scripts
sudo ss -Htlnp

# listening on anything other than loopback: the real exposure list
sudo ss -Htulpn | awk '$5 !~ /^(127\.|\[::1\]|::1)/'

# established connections, with process: who is talking out
sudo ss -tnp state established
```

Verified here, unprivileged: `ss -Htlnp` lists every listener but only shows `users:(("code",pid=...))` for processes owned by the calling user; system daemons (`systemd-resolved` on `127.0.0.53:53`, CUPS on `127.0.0.1:631`) appear without a process. **Run it as root for the exposure review.**

Read the local address column carefully:

| Local address | Reachable from |
|---|---|
| `127.0.0.1:PORT`, `[::1]:PORT`, `127.0.0.53%lo` | This host only |
| `0.0.0.0:PORT`, `*:PORT` | Every IPv4 interface |
| `[::]:PORT` | Every IPv6 interface, and **IPv4 too** unless `net.ipv6.bindv6only=1` or the app sets `IPV6_V6ONLY` |
| `10.1.2.3:PORT` | That interface only |

> **Gotcha.** A listener on `0.0.0.0` behind a firewall that drops the port is still one `firewall-cmd --add-service` away from exposed. The firewall is the second layer; binding to the right interface is the first. Also: container runtimes publish ports by writing their own nftables/iptables rules, which can bypass firewalld zones entirely (Docker's `-p 8080:80` binds `0.0.0.0` and inserts DNAT ahead of firewalld). Chapter 04 covers the fix; `ss` shows `docker-proxy` or `rootlessport` owning such ports.

`lsof` for the file-and-process side of the same question:

```bash
sudo lsof -nP -iTCP -sTCP:LISTEN          # listeners, no DNS or port-name lookups
sudo lsof -nP -i :5432                    # who owns port 5432
sudo lsof -nP -i @203.0.113.9             # every socket to/from an address
sudo lsof -nP -p 31337                    # everything one process has open
sudo lsof +L1                             # deleted-but-open files (chapter 12)
```

Then map each listener to a unit and a package, so you can decide whether it should exist:

```bash
PID=$(sudo ss -Htlnp 'sport = :631' | grep -oP 'pid=\K[0-9]+' | head -1)
systemctl status "$PID" | head -3        # which unit
rpm -qf "$(readlink -f /proc/$PID/exe)"  # which package
```

The review question for each line: **does this need to listen, on this interface, at all?** Every listener you remove is an entry that never appears in the rest of this chapter.

### Scanning your own hosts with nmap

`ss` tells you what the host thinks is listening. `nmap` from another machine tells you what's actually **reachable** through every firewall, NAT and cloud security group in between. You need both views, and they disagree more often than you'd expect.

Fedora 43 packages nmap 7.92 (`dnf install nmap`); upstream is at 7.991 (August 2026). Not installed on the machine this chapter was written on; flags below are from the nmap reference guide, stable across 7.x.

> **Version-sensitive.** Fedora is pinned to 7.92 by licence, and that won't change. Nmap moved to the Nmap Public Source License at 7.90; Fedora Legal classes every NPSL version (0.92 to 0.95) as not-allowed ([legal list, July 2024](https://lists.fedoraproject.org/archives/list/legal@lists.fedoraproject.org/)), and 7.90 to 7.92 are the only NPSL releases also usable under the old licence ([nmap.org/npsl](https://nmap.org/npsl/)), so Fedora downgraded to 7.92 (rhbz#2296006). Newer OS and service fingerprints and NSE scripts need upstream's x86_64 RPM from [nmap.org/download](https://nmap.org/download.html); there is no official container image. Fedora's package also lacks `ndiff` (verified, `dnf repoquery`); it ships in upstream's source tarball, Python 3 from 7.94.

#### Localhost first

```bash
# every TCP port on loopback, with service/version detection
nmap -sV -p- 127.0.0.1

# UDP needs root and is slow; top 100 ports is a sensible first pass
sudo nmap -sU --top-ports 100 127.0.0.1

# IPv6 loopback, which people forget
nmap -6 -sV -p- ::1
```

Scanning `127.0.0.1` from the host itself bypasses most firewall rules (loopback is usually accepted), so it confirms `ss` rather than testing the firewall. **The meaningful scan is from another host on the same network, and one from outside it.**

#### Your own subnet, from another host

```bash
# host discovery only: what's alive on the segment
sudo nmap -sn YOUR_SUBNET/24

# TCP SYN scan of all ports, service versions, OS guess, all output formats
sudo nmap -sS -sV -O -p- -T4 --reason -oA scan-$(date +%F) TARGET_HOST

# faster first pass across a subnet: top 1000 ports only
sudo nmap -sS -sV --top-ports 1000 -T4 -oA subnet-$(date +%F) YOUR_SUBNET/24
```

| Flag | Does | When |
|---|---|---|
| `-sn` | Ping/ARP discovery, no port scan | Inventory: what exists |
| `-sS` | SYN ("half-open") scan; root | Default for TCP as root |
| `-sT` | Full connect scan; no root needed | Unprivileged, or through some proxies |
| `-sU` | UDP | DNS, NTP, SNMP, WireGuard. Slow, needs root |
| `-sV` | Probe services for name and version | Always; the version is what vulnerability matching needs |
| `-O` | OS fingerprint | Inventory |
| `-p-` / `--top-ports N` | All 65535 ports / the N most common | Full audit / quick sweep |
| `-T4` | Faster timing | Your own LAN; `-T3` (default) across WANs |
| `--reason` | Why each port got its state | Debugging filtered vs closed |
| `-oA BASE` | Normal, grepable and XML output | Always keep XML: `ndiff` compares two runs |
| `-Pn` | Skip discovery, assume up | Hosts that drop ICMP |

Compare two runs to spot new exposure:

```bash
ndiff scan-2026-09-01.xml scan-2026-09-23.xml
```

A new open port between two scans is a change someone made. Chase it.

#### NSE and `--script vuln`

```bash
# the "default" script category: banners, TLS info, SSH host keys, HTTP titles
nmap -sV -sC TARGET_HOST

# specific, well-understood scripts
nmap -p 443 --script ssl-enum-ciphers,ssl-cert TARGET_HOST
nmap -p 22  --script ssh2-enum-algos,ssh-hostkey TARGET_HOST

# the "vuln" category — read the caution first
nmap -sV --script vuln TARGET_HOST
```

> **One-way door.** The `vuln` category includes scripts that send exploit-shaped traffic. Some are in the `intrusive` or `dos` categories as well: they can crash fragile services (old printers, embedded devices, some Java app servers), lock accounts by trying logins, or fill logs and trip your own IDS. A crashed production service or a locked service account doesn't undo itself. Run `--script vuln` only against hosts you own, in a window where a crash is acceptable, and prefer `--script "vuln and safe"` for routine use. List what a category contains first: `nmap --script-help vuln`.

`--script vuln` is a weak vulnerability scanner in any case: it has scripts for a few dozen famous CVEs, not a vulnerability database. For "what's unpatched", use the package-level tools below.

### What's unpatched: the package manager

The distribution already publishes which of your installed packages have security fixes available. That's the most accurate vulnerability data you'll get for OS packages, because it's matched against the exact builds the distro shipped, including backported fixes that a version-string scanner gets wrong.

#### Fedora and RHEL: dnf updateinfo

```bash
dnf updateinfo summary                                   # counts by type and severity
dnf updateinfo list --security                           # security advisories with pending updates
dnf updateinfo list --security --advisory-severities=critical,important
dnf updateinfo list --with-cve                           # advisories that reference CVEs (RHEL; empty on Fedora)
dnf updateinfo info FEDORA-2026-XXXXXXXXXX               # one advisory: CVEs, packages, description
dnf updateinfo list --security --json                    # for tooling
dnf updateinfo list --installed --security               # advisories already applied

# apply only security fixes, at the lowest version that fixes them
sudo dnf upgrade --security
sudo dnf upgrade --minimal --security --advisory-severities=critical,important
```

Verified here (dnf5): `dnf updateinfo summary` reported 1 critical security advisory pending, and `list --help` confirms `--security`, `--advisory-severities`, `--cves`, `--with-cve`, `--json`, `--installed`, `--updates`.

> **Version-sensitive.** Fedora 41+ uses dnf5, where the command is `dnf advisory` with `updateinfo` as an alias, and severity filtering is `--advisory-severities=`. On RHEL 8/9 (dnf4) it's `dnf updateinfo list --security --sec-severity=Critical`. Scripts that parse the text output break between the two; use `--json` on dnf5.

> **Gotcha.** Advisory data comes from repository metadata. A repo whose metadata doesn't load contributes nothing, silently. On this machine, three third-party repos (Kubernetes, HashiCorp, Docker CE) failed with `repomd.xml GPG signature verification error: Signing key not found`, which means `updateinfo` can't see advisories for anything installed from them. Third-party repos rarely publish updateinfo anyway, so packages from them need a different check (Trivy/Grype, or the vendor's feed).

To answer "are we fixed for this CVE?" on RHEL: `dnf updateinfo list --all --cve CVE-2026-12345` (`--cves=` on dnf5); Red Hat Insights (`insights-client`) adds fleet-level reporting.

> **Gotcha.** Fedora's advisory metadata carries **no CVE references**. Verified on Fedora 43: `dnf advisory list --all --with-cve` returns none of the 435 advisories in the repos, so `--cves=` silently matches nothing. Severity is populated (only 16 of 324 security advisory entries were `None`), but in Bodhi the packager picks each update's type, so a CVE fix filed as `bugfix` or `enhancement` never shows under `--security`. On Fedora, answer CVE questions from the Bodhi update page or the package changelog (`rpm -q --changelog PKG | grep CVE-`).

#### Debian and Ubuntu

```bash
sudo apt update
apt list --upgradable 2>/dev/null | grep -i security       # crude but works
sudo apt install debsecan && debsecan --suite trixie --only-fixed   # Debian: CVEs with fixes
pro security-status                                          # Ubuntu: packages by support status
sudo unattended-upgrade --dry-run -d                         # what the security auto-updater would do
```

**Default pick on both families: automatic updates** (`dnf-automatic` with `upgrade_type = security` on RHEL-family and `upgrade_type = default` on Fedora, because Fedora's packager-chosen update types let CVE fixes filed as bugfix or enhancement slip past a security-only filter; `unattended-upgrades` on Debian/Ubuntu), plus a scheduled `updateinfo`/`debsecan` report so you know what's pending when automation is paused.

### Trivy, Grype and Syft for hosts

Container scanners also scan hosts. Their real value on a host is **language packages the OS package manager doesn't know about**: the Python venv in `/opt/app`, a Go binary someone dropped in `/usr/local/bin`, the jar files in a Tomcat directory, `node_modules` in a deployed app.

> **Gotcha.** **Trivy** doesn't match **Fedora** OS packages: its [OS coverage table](https://trivy.dev/docs/latest/guide/coverage/os/) doesn't list Fedora at all (only Fedora CoreOS, SBOM-only), so on a Fedora host it inventories RPMs and reports nothing for them, which reads as "clean". **Grype** does, from 0.109 (February 2026), via a Vunnel provider built on Bodhi data; it inherits Bodhi's gaps, so treat `dnf updateinfo` as authoritative for the OS layer. RHEL 8/9, Alma, Rocky, Debian and Ubuntu are covered by both; Trivy lists RHEL 10 as SBOM-only.

Trivy 0.69.3 and Grype 0.117 are in the Fedora repos (`dnf install trivy grype`); upstream is at Trivy 0.74, Grype 0.119 and Syft 1.52 (September 2026). Syft isn't packaged (use the upstream release or container image). None was installed on the machine this chapter was written on; flags are from the official docs.

> **Gotcha.** Trivy's own supply chain was compromised in March 2026 ([CVE-2026-33634](https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23)): a malicious v0.69.4 release on GitHub, deb and RPM repos and images, malicious v0.69.5/v0.69.6 Docker Hub images, and hijacked `trivy-action`/`setup-trivy` tags. Pin scanners by version and digest, and if anything pulled `latest` in that window, rotate the secrets it could see.

#### Trivy: rootfs vs fs

| Command | Looks at | Use for |
|---|---|---|
| `trivy rootfs PATH` | **Installed** artefacts: OS package db, `site-packages`, jars, Go/Rust binaries, `node_modules` package.json | A host, a mounted disk, an unpacked image |
| `trivy fs PATH` | **Lock files** and manifests (`package-lock.json`, `poetry.lock`, `go.sum`) plus IaC | A source checkout in CI |

```bash
# the host's OS packages only (RHEL/Debian/Ubuntu hosts; not Fedora)
sudo trivy rootfs --pkg-types os --scanners vuln /

# everything installed, skipping pseudo-filesystems and container storage
sudo trivy rootfs --scanners vuln,secret \
  --skip-dirs /proc,/sys,/dev,/run,/var/lib/containers,/var/lib/docker,/home \
  --severity HIGH,CRITICAL --ignore-unfixed /

# an application directory on the host
sudo trivy rootfs --scanners vuln --severity HIGH,CRITICAL /opt/app

# a repo checkout: lock files
trivy fs --scanners vuln,misconfig --severity HIGH,CRITICAL .

# SBOM out, and scanning an SBOM later
sudo trivy rootfs --format cyclonedx --output host-sbom.cdx.json /
trivy sbom --severity HIGH,CRITICAL host-sbom.cdx.json
```

`--ignore-unfixed` is the same gate the Kubernetes Field Manual recommends for images: findings without a fix aren't actionable today, and a report of 400 of them gets ignored.

> **Gotcha.** `--scanners secret` over `/` will find things: private keys in `/etc/pki`, tokens in config files, test fixtures in `/usr/share`. Those are findings to triage, and the report itself now contains secrets. Write it somewhere root-only, and don't attach it to a ticket.

#### Syft and Grype: SBOM once, scan often

Syft builds the inventory; Grype matches an inventory against vulnerability data. Syft's directory-scan excludes must start with `./`, `*/` or `**/`, relative to the scan root; absolute paths like `/proc/**` are not accepted ([file selection docs](https://oss.anchore.com/docs/guides/sbom/file-selection/)). Splitting the two means you inventory each host once (expensive: a full filesystem walk) and re-scan the stored SBOM daily as new CVEs are published (cheap: no host access at all).

```bash
# inventory the host into a CycloneDX (or SPDX / Syft JSON) SBOM
sudo syft scan dir:/ \
  --exclude './proc/**' --exclude './sys/**' --exclude './var/lib/containers/**' \
  -o cyclonedx-json=/var/tmp/$(hostname -s)-sbom.cdx.json

# scan it, now or next week, on any machine
grype sbom:/var/tmp/HOST-sbom.cdx.json --only-fixed --fail-on high
grype db update && grype sbom:./HOST-sbom.cdx.json -o json > findings.json

# or scan a directory directly
sudo grype dir:/opt/app --only-fixed
```

**Close call: Trivy vs Syft+Grype.** Trivy is one binary that does inventory, vulnerabilities, secrets and misconfiguration, which is the right default for ad hoc host checks. Syft+Grype wins where you want an **SBOM store**: inventory the fleet weekly, rescan the stored SBOMs daily, answer "which hosts have `libfoo` 1.2.3?" without logging into any of them. Tiebreaker: whether you'll actually keep and query the SBOMs.

### osquery: the host as a database

osquery exposes the operating system as SQL tables: processes, sockets, users, packages, cron entries, kernel modules, SSH keys. The same query runs on every host, which is what makes it the backbone of fleet visibility.

Not in Fedora's repos; install from the osquery project's RPM/DEB repository (`pkg.osquery.io`); current release 5.23.1. Not installed on the machine this chapter was written on; table and column names below are from the osquery schema.

```bash
osqueryi                              # interactive shell, no daemon needed
osqueryi --json "SELECT ..."          # one-shot, JSON out
osqueryi ".tables"                    # list tables
osqueryi ".schema listening_ports"    # columns of one table
```

Run as root: most tables return partial results unprivileged, without saying so.

#### Queries worth keeping

Listening ports, with the process behind each:

```sql
SELECT DISTINCT p.name, p.path, lp.address, lp.port, lp.protocol, p.uid
FROM listening_ports lp
JOIN processes p USING (pid)
WHERE lp.address NOT IN ('127.0.0.1', '::1')
  AND lp.port != 0
ORDER BY lp.port;
```

Processes whose binary has been deleted from disk (a classic implant trick; chapter 12):

```sql
SELECT pid, name, path, cmdline, uid, parent
FROM processes
WHERE on_disk = 0;
```

SUID and SGID binaries, to diff against a known-good list:

```sql
SELECT path, username, groupname, permissions
FROM suid_bin
ORDER BY path;
```

Crontab entries, system and per-user:

```sql
SELECT event, minute, hour, day_of_month, month, day_of_week, command, path
FROM crontab;
```

`authorized_keys`, which needs a join to `users` to enumerate every account's file:

```sql
SELECT u.username, ak.key_file, ak.algorithm, ak.comment, ak.options
FROM users u
JOIN authorized_keys ak USING (uid);
```

Kernel modules currently loaded:

```sql
SELECT name, size, used_by, status
FROM kernel_modules
ORDER BY name;
```

Enabled systemd units whose unit file lives somewhere unusual (persistence):

```sql
SELECT id, active_state, fragment_path, user
FROM systemd_units
WHERE fragment_path NOT LIKE '/usr/lib/systemd/%'
  AND fragment_path != '';
```

Outbound connections from processes, excluding loopback:

```sql
SELECT p.name, p.path, pos.remote_address, pos.remote_port, pos.local_port
FROM process_open_sockets pos
JOIN processes p USING (pid)
WHERE pos.remote_address NOT IN ('', '0.0.0.0', '::', '127.0.0.1', '::1')
  AND pos.state = 'ESTABLISHED';
```

Installed packages, for a quick "which hosts have version X":

```sql
SELECT name, version, release FROM rpm_packages WHERE name = 'openssl-libs';
-- Debian/Ubuntu: SELECT name, version FROM deb_packages WHERE name LIKE 'libssl%';
```

#### Scheduled queries and differentials

`osqueryd` (the daemon) runs queries on a schedule and logs **differences** between runs: a new SUID binary, a new `authorized_keys` line, a new listener appears as an `added` row. That differential log, shipped to your SIEM, is a cheap change-detection system across the whole fleet.

```json
{
  "schedule": {
    "suid_bin": {
      "query": "SELECT path, username, permissions FROM suid_bin;",
      "interval": 3600
    },
    "authorized_keys": {
      "query": "SELECT u.username, ak.key_file, ak.key FROM users u JOIN authorized_keys ak USING (uid);",
      "interval": 3600
    },
    "listening_ports": {
      "query": "SELECT p.name, lp.address, lp.port, lp.protocol FROM listening_ports lp JOIN processes p USING (pid);",
      "interval": 600
    }
  }
}
```

That goes in `/etc/osquery/osquery.conf`. The osquery project ships query packs (`incident-response`, `it-compliance`, `ossec-rootkit`) as a starting point.

For more than a handful of hosts, a manager is the usual pattern: **Fleet** (fleetdm, open-core) is the common self-hosted choice for managing `osqueryd` configs, running live queries across hosts, and collecting results.

### Fleet-wide: Wazuh as SIEM and XDR

Everything above is per-host tooling. At some point you want one place where logs, integrity changes, configuration assessment and vulnerability matches from every host land, get correlated and alert. Wazuh is the widely used open-source option that covers most of this in one product. Not installed here; this is an overview from the official documentation.

Current stable at the time of writing is the 4.14.x line (4.14.7, 30 July 2026; 4.14.8 in release candidate); 5.0 is in beta (beta5, September 2026).

```text
  hosts: wazuh-agent ──(1514/tcp, encrypted)──▶ wazuh-manager ──▶ wazuh-indexer ──▶ wazuh-dashboard
          │ logs, FIM, SCA,                      │ decoders, rules,    (OpenSearch fork)   (OpenSearch
          │ inventory, rootcheck                 │ correlation,                             Dashboards fork)
          │                                      │ vuln detection
          └◀─────── active response ─────────────┘
```

| Capability | What it replaces or complements |
|---|---|
| Log collection and rules | Central view of the journal, `audit.log`, web and app logs (chapter 08) |
| File integrity monitoring (syscheck) | AIDE, centrally managed and alerting in real time (chapter 09) |
| Security configuration assessment (SCA) | CIS-style policy checks per host, similar in spirit to OpenSCAP (chapter 07) |
| Vulnerability detection | Matches agent package inventory against CVE feeds, fleet-wide |
| Rootcheck | rkhunter-style checks (chapter 09) |
| Active response | fail2ban-style automated blocking, triggered by any rule (chapter 10) |
| System inventory | osquery-style package, port and process inventory (and an osquery integration) |

**When it's worth it:** more than a few dozen hosts, or a compliance need for central log retention and alerting. Below that, the per-host tools in this guide plus log shipping to something you already run (Loki, Elasticsearch) cover the same ground with less to operate.

> **Gotcha.** Wazuh's indexer is an OpenSearch cluster with the usual appetite: plan for real memory and disk, retention policies from day one, and backups. The most common Wazuh failure is not detection quality; it's an indexer that filled its disk and stopped accepting events weeks ago.

> **Note.** The agent runs as root on every host and the manager can push active-response commands to them. Treat the manager as a tier-0 asset: it can run commands everywhere. Put it behind the same controls as your config management server.

### Checklist

- `sudo ss -tulpn` reviewed on every host role; every non-loopback listener has an owner and a reason.
- Container-published ports checked against the firewall (they may bypass it).
- An `nmap -sS -sV -p-` of each subnet from inside, and of public addresses from outside, with XML kept and `ndiff`-ed over time.
- `--script vuln` only against your own hosts, in a window where a crash is acceptable.
- `dnf updateinfo list --security` (or `debsecan`/`pro security-status`) scheduled and reported; security updates automated.
- Third-party repos load cleanly (signature errors mean no update data at all).
- Trivy or Syft+Grype over application directories and `/usr/local`, with `--ignore-unfixed` / `--only-fixed`; on Fedora, not relied on for OS packages (Trivy has no Fedora data; Grype's is Bodhi-derived).
- osquery queries for listeners, deleted binaries, SUID files, crontabs, `authorized_keys` and kernel modules, run on a schedule with differential logs shipped off the host.

### Traps

- **Scanning something you don't own.** Including "just checking" a neighbour's IP or a vendor's endpoint.
- **Trusting `ss` unprivileged.** It hides the process for other users' sockets.
- **`[::]` means IPv4 too**, on a default Linux sysctl.
- **Scanning localhost and calling it a firewall test.** Loopback bypasses most rules; scan from another host.
- **`--script vuln` as a vulnerability scanner.** It's a few dozen famous CVEs with crash risk, not a CVE database.
- **Trivy on Fedora reporting "0 OS vulnerabilities".** It has no Fedora data; use `dnf updateinfo` (Grype 0.109+ does match Fedora RPMs).
- **`--cves=` on Fedora.** Fedora advisories carry no CVE references, so it matches nothing.
- **Broken repo metadata.** A repo that fails to load publishes no advisories, and nothing warns you beyond the refresh line.
- **Secret-scanning `/` and attaching the report.** The report now contains the secrets.
- **A SIEM nobody sizes.** An indexer with a full disk is a SIEM that stopped weeks ago.


---


<a id="12-incident-response-triage"></a>

## 12 · Incident response triage

*Every command you run on a suspect host changes it, and the most valuable evidence is the most fragile. The first fifteen minutes are about capturing what disappears at power-off, in order, to somewhere the host can't reach, before you decide anything else.*

### The first fifteen minutes

Print this. The order matters more than the commands.

1. **Stop and write down the time (UTC) and what triggered this.** Alert text, who noticed, what they already did. Start a notes file off the host; every action from here gets a timestamp.
2. **Don't power off, don't reboot, don't "clean up".** Memory, network connections and running processes vanish at power-off, and they're usually where the answer is.
3. **Decide who's in charge and open a channel that isn't on the suspect infrastructure.** If the attacker has the mail server or the chat bot's token, they're reading your response.
4. **Get a snapshot if the platform offers one.** VM: memory plus disk snapshot. Cloud: disk snapshot of every volume. This is the cheapest evidence preservation there is, and it doesn't touch the guest.
5. **Capture volatile data, most volatile first** (next section), writing it **off the host**.
6. **Capture memory** if you can (AVML/LiME, or the hypervisor's dump).
7. **Only then contain.** Network isolation that keeps the host running beats killing processes.
8. **Rotate what the host could reach.** Keys, tokens and passwords that lived on or passed through it are compromised until proven otherwise.

> **One-way door.** Powering off, rebooting, reinstalling, or running a cleaner that deletes files destroys evidence that can't be recovered: process memory, network state, deleted-but-running binaries, the attacker's in-memory tooling. Once it's gone, "how did they get in" and "what did they take" may be unanswerable. Stabilise and capture first; the host has already been compromised for however long it was compromised, and another 15 minutes of network-isolated uptime rarely changes the outcome.

### Order of volatility

From RFC 3227, adapted to a Linux host. Collect top to bottom.

| Order | What | Lifetime | How |
|---|---|---|---|
| 1 | CPU state, kernel memory, process memory | Until the process exits or power-off | Memory capture (AVML, LiME, hypervisor dump) |
| 2 | Network connections, ARP/neighbour cache, routing | Seconds to minutes | `ss`, `ip neigh`, `ip route` |
| 3 | Running processes, open files, loaded modules | Until exit / reboot | `ps`, `/proc`, `lsof`, `lsmod` |
| 4 | Logged-in users, sessions | Until logout | `who`, `w`, `loginctl` |
| 5 | Temporary filesystems | Until reboot | `/tmp`, `/dev/shm`, `/run` (tmpfs) |
| 6 | Volatile journal | Until reboot, if the journal isn't persistent | `journalctl -o export` |
| 7 | Disk | Until overwritten | Snapshot or image |
| 8 | Remote logs | Retention period | Your SIEM, log server, cloud audit logs |

Items 5 and 6 get forgotten: on Fedora `/tmp` is tmpfs, and attackers love `/dev/shm`.

### Working on a suspect host

Rules for the whole collection phase:

- **Write output off the host.** Pipe over SSH to a collector, or to a USB device you mounted read-write for the purpose. Writing to the suspect disk overwrites unallocated space that might hold deleted evidence, and the attacker may be watching the directory.
- **Don't forward your agent.** `ssh -A` onto a compromised host hands the attacker (who has root there) your SSH agent for as long as you're connected. Connect with a dedicated incident key, `-o ForwardAgent=no`, and assume any password you type there is captured.
- **Distrust the host's binaries.** A rootkit replaces `ps`, `ss`, `ls`, `netstat`. Prefer reading `/proc` directly, or bring a statically linked toolkit (`busybox`, a known-good static build) on read-only media. Cross-check: if `ps` and `/proc` disagree, that's the finding.
- **Don't install anything with the package manager.** It writes to disk, updates the rpmdb and runs scriptlets. Bring tools with you.
- **Record hashes** of everything you collect, at collection time.

A pattern for shipping every command's output to a collector, with a header, without touching the suspect disk:

```bash
# on the suspect host, as root. COLLECTOR is a host you control; CASE is the case id.
CASE=IR-2026-0923
COLLECTOR=ir@collector.example.internal
run() {
  { printf '### %s\n### %s UTC\n' "$*" "$(date -u +%FT%TZ)"; "$@" 2>&1; } \
    | ssh -o ForwardAgent=no -i ~/.ssh/ir_ed25519 "$COLLECTOR" \
        "cat >> cases/$CASE/$(hostname -s).txt"
}
run date -u
run uptime
```

Single commands can be wrapped in `run`; pipelines and loops can't (they'd run locally before `run` sees them). For those, and for any big collection, put the commands in a script on read-only media and pipe its whole output through one `ssh` instead: `bash /mnt/ir/collect.sh 2>&1 | ssh -o ForwardAgent=no "$COLLECTOR" "cat > cases/$CASE/$(hostname -s).txt"`.

### Memory capture

Memory holds what the disk doesn't: decrypted payloads, injected code, command history not yet written, network keys, the attacker's tooling that never touched disk.

| Situation | Tool | Command |
|---|---|---|
| VM on libvirt/KVM | Hypervisor, no guest changes | `virsh dump --memory-only --format elf DOMAIN /evidence/DOMAIN.mem` |
| Cloud VM | Provider snapshot (disk); memory varies by provider | Snapshot every volume; check your provider's memory-capture option |
| Physical or no hypervisor access | **AVML** (static binary, no kernel module) | `sudo ./avml /mnt/usb/HOST.lime` |
| Old kernels, AVML fails | LiME (kernel module built for that exact kernel) | `sudo insmod lime.ko "path=/mnt/usb/HOST.lime format=lime"` |

Analysis happens elsewhere, with Volatility 3, which needs a symbol table (ISF) for the exact kernel build. Generate it from the kernel's debuginfo on an analysis box (`dwarf2json`), not on the suspect host.

> **Gotcha.** Memory capture writes a file the size of RAM. Write it to external media or a network share, never to the suspect root filesystem, and check there's room before you start. A 64 GB capture that fills the collector halfway through is a wasted 20 minutes.

### Collect the volatile evidence

#### System and time

```bash
date -u; date                            # UTC and local; note any skew vs your clock
uptime                                   # did it reboot recently?
hostnamectl
uname -a
cat /proc/sys/kernel/tainted             # non-zero: out-of-tree or unsigned modules, among others
timedatectl                              # NTP sync state; an attacker may have changed the clock
journalctl --list-boots | tail -5        # reboots in the incident window
```

#### Processes

```bash
# full tree, full command lines, start times
ps -eo pid,ppid,user,lstart,etime,stat,cmd --forest -ww

# the same from /proc, independent of ps (catches a trojaned ps)
for p in /proc/[0-9]*; do
  printf '%s\t%s\t%s\n' "${p#/proc/}" "$(readlink "$p/exe" 2>/dev/null)" \
    "$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)"
done

# compare counts: a gap means something is hidden from ps
ps -e --no-headers | wc -l; ls -d /proc/[0-9]* | wc -l

# for one suspicious PID: everything
PID=31337
ls -la /proc/$PID/                        # cwd, exe, root links
readlink /proc/$PID/exe /proc/$PID/cwd
tr '\0' '\n' < /proc/$PID/environ         # environment: LD_PRELOAD, proxies, odd PATHs
cat /proc/$PID/maps                       # loaded libraries, anonymous executable regions
ls -la /proc/$PID/fd/                     # open files and sockets
cat /proc/$PID/status | grep -E 'Name|PPid|Uid|Gid|Cap'
```

Things that should make you look twice: a process whose `exe` points to `/tmp`, `/dev/shm`, `/var/tmp` or a dot-directory; a process name in brackets (`[kworker/0:1]`) that has an `exe` link (real kernel threads don't); a binary marked `(deleted)`; `LD_PRELOAD` in the environment; a web server or database with a shell as a child.

```bash
# fake kernel threads: bracketed name but a real executable
for p in /proc/[0-9]*; do
  n=$(cat "$p/comm" 2>/dev/null); e=$(readlink "$p/exe" 2>/dev/null)
  [[ -n "$e" ]] && grep -q '^\[' "$p/cmdline" 2>/dev/null && echo "${p#/proc/} $n $e"
done

# children of web servers and databases
ps -eo pid,ppid,user,cmd --forest | grep -A3 -E 'nginx|httpd|php-fpm|java|postgres|mysqld' \
  | grep -E 'sh |bash|python|perl|curl|wget|nc '
```

#### Network

```bash
ss -tanp                                 # all TCP, with process
ss -uanp                                 # all UDP
ss -xp | head -50                        # unix sockets, with process
ss -tnp state established '( dport != :22 )'
ip -br addr; ip route; ip -6 route
ip neigh                                 # ARP/ND cache: what it talked to on the LAN
cat /etc/resolv.conf; resolvectl status 2>/dev/null | head -30
nft list ruleset                         # did the attacker add rules (or remove yours)?
cat /proc/net/tcp | wc -l                # compare with ss output counts
```

An established connection to an unfamiliar address from a process that shouldn't make outbound connections is the classic finding. Write down the remote address, port and PID before you contain anything; after isolation those connections are gone.

#### Users and logins

```bash
who -a                                   # current sessions, boot time, run level
w                                        # what each session is running
loginctl list-sessions
last -F -i -x | head -50                 # logins, reboots, shutdowns, full times, IPs
lastb -F -i | head -50                   # failed logins (needs root; /var/log/btmp)
lastlog2 -a                              # last login per account (Fedora 42+ replaces lastlog)
aulast -i 2>/dev/null | head -30         # the same from the audit log, harder to forge
journalctl -u sshd.service --since "-7d" -g 'Accepted|Failed|Invalid'
getent passwd | awk -F: '$3 == 0 || $3 >= 1000'   # uid 0 accounts and humans
awk -F: '$2 !~ /^[!*]/ {print $1}' /etc/shadow     # accounts that have a usable password hash
```

`last` reads `/var/log/wtmp`; `lastb` reads `/var/log/btmp`. Both are trivially editable by root, so an attacker who cleaned them leaves gaps. Cross-check with the journal and `aulast` (chapter 08): a login in the journal or audit log with no matching `wtmp` entry is evidence of tampering.

> **Version-sensitive.** Fedora 42+ removed `lastlog` in favour of `lastlog2` (verified present on Fedora 43, database `/var/lib/lastlog/lastlog2.db`). Debian 13 and Ubuntu 25.04+ are moving the same way, and toward `wtmpdb` for `last`. On older systems, `lastlog` reads `/var/log/lastlog`.

#### Kernel modules

```bash
lsmod
cat /proc/modules                        # compare with lsmod; a module hidden from one may show in the other
for m in $(lsmod | awk 'NR>1 {print $1}'); do
  modinfo -F filename "$m" 2>/dev/null
done | grep -vE '^/lib/modules/|^\(builtin\)$'    # modules not loaded from the standard tree
dmesg -T | grep -iE 'taint|module verification failed|loading out-of-tree'
```

A module that logged "module verification failed: signature and/or required key missing", or that has no file under `/lib/modules/$(uname -r)`, is worth serious attention.

### Scheduled jobs and persistence

Attackers want to survive a reboot. On Linux there are perhaps twenty common places to hide a restart hook; check all of them.

#### Cron, at and systemd timers

```bash
systemctl list-timers --all                         # system timers, next and last run
for u in $(loginctl list-users --no-legend | awk '{print $2}'); do
  echo "== $u"; systemctl --user -M "$u@" list-timers --all 2>/dev/null
done
ls -la /etc/cron.d/ /etc/cron.hourly/ /etc/cron.daily/ /etc/cron.weekly/ /etc/cron.monthly/
cat /etc/crontab
ls -la /var/spool/cron/ /var/spool/cron/crontabs/ 2>/dev/null     # Fedora / Debian user crontabs
for u in $(cut -d: -f1 /etc/passwd); do c=$(crontab -l -u "$u" 2>/dev/null) && echo "== $u" && echo "$c"; done
atq; ls -la /var/spool/at/ 2>/dev/null
```

#### Persistence locations to check

| Location | What hides there |
|---|---|
| `/etc/systemd/system/`, `/etc/systemd/system/*.wants/` | Units and enablement symlinks (compare with packaged units in `/usr/lib/systemd/system/`) |
| `~/.config/systemd/user/`, `/etc/systemd/user/` | User units, which run at login (and at boot with lingering: `ls /var/lib/systemd/linger/`) |
| `/etc/systemd/system/*.service.d/*.conf` | Drop-ins that add an `ExecStartPre=` to a legitimate service |
| `/etc/rc.d/rc.local`, `/etc/rc.local` | Legacy boot script (runs if executable) |
| `/etc/profile`, `/etc/profile.d/*.sh`, `/etc/bash.bashrc`, `/etc/bashrc` | Every login shell |
| `~/.bashrc`, `~/.bash_profile`, `~/.profile`, `~/.zshrc`, `~/.zprofile` | One user's shells |
| `~/.ssh/authorized_keys`, `/root/.ssh/authorized_keys` | Access, and `command=` options that run on login |
| `/etc/ssh/sshd_config.d/`, `AuthorizedKeysFile`, `AuthorizedKeysCommand` | Redirecting where keys are read from |
| `/etc/sudoers`, `/etc/sudoers.d/` | Privilege |
| `/etc/passwd`, `/etc/shadow`, `/etc/group` | Extra uid-0 accounts, added group memberships |
| `/etc/ld.so.preload`, `LD_PRELOAD` in `/etc/environment` | Userland rootkits (this file shouldn't exist on most hosts) |
| `/etc/pam.d/`, `/usr/lib64/security/` | Backdoored PAM modules that accept a magic password |
| `/etc/modules-load.d/`, `/etc/modprobe.d/` | Kernel modules loaded at boot, `install` hooks that run commands |
| `/etc/udev/rules.d/` | `RUN+=` commands on device events |
| `/etc/xdg/autostart/`, `~/.config/autostart/` | Desktop sessions |
| `/etc/update-motd.d/` (Debian/Ubuntu) | Runs as root at every SSH login |
| `/etc/NetworkManager/dispatcher.d/` | Runs on network changes |
| `/var/lib/containers/`, `~/.local/share/containers/`, `/var/lib/docker/` | A container with `--restart=always` or a Quadlet unit |
| Git hooks, CI runner config, `~/.gitconfig` `core.hooksPath` | Developer and runner hosts |

Quick checks for the highest-value entries:

```bash
cat /etc/ld.so.preload 2>/dev/null && echo "!! ld.so.preload exists"
awk -F: '$3 == 0 {print "uid0:", $1}' /etc/passwd
grep -rn 'command=' /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys 2>/dev/null
ls -la /var/lib/systemd/linger/ 2>/dev/null
systemctl list-unit-files --state=enabled --no-legend | awk '{print $1}' \
  | while read -r u; do p=$(systemctl show -P FragmentPath "$u"); \
      [[ "$p" == /etc/* ]] && echo "$u $p"; done       # enabled units defined in /etc, not packages
sudo rpm -Va --noconfig 2>/dev/null | grep -E '^..5|^.M' # changed shipped binaries (chapter 09)
podman ps -a; sudo podman ps -a; docker ps -a 2>/dev/null
```

### Files: recent, hidden and deleted

#### Recently modified

```bash
# regular files changed in the last 2 days on the root filesystem only
find / -xdev -type f -mtime -2 -printf '%TY-%Tm-%Td %TH:%TM %u %m %p\n' 2>/dev/null | sort

# changed after a specific time (the first alert, minus a margin)
find / -xdev -newermt '2026-09-22 13:00' ! -newermt '2026-09-22 16:00' -type f 2>/dev/null

# ctime: harder to fake than mtime (touch -d changes mtime, not ctime)
find /etc /usr /var/spool /root /home -xdev -cmin -1440 -type f 2>/dev/null

# executables in places executables shouldn't be
find /tmp /var/tmp /dev/shm /run -type f -perm -u+x 2>/dev/null -ls

# setuid/setgid, to diff against a known-good list (chapter 11's osquery query)
find / -xdev \( -perm -4000 -o -perm -2000 \) -type f -printf '%m %u %p\n' 2>/dev/null

# hidden directories in unusual places
find / -xdev -type d -name '.*' ! -path '/home/*' ! -path '/root/*' ! -path '/proc/*' 2>/dev/null
```

> **Gotcha.** `mtime` is set by `touch -d`, and attackers timestomp. `ctime` (inode change time) can't be set from userspace without changing the clock, so a binary with an old `mtime` and a recent `ctime` is a strong signal. `stat FILE` shows all three (plus birth time on ext4/XFS/Btrfs).

> **Note.** `find` itself updates access times on directories unless the filesystem is mounted `noatime`/`relatime` (Fedora's default is `relatime`). That's one reason the disk snapshot comes first.

#### Deleted but still open

An attacker's favourite trick: start the binary, delete it. It keeps running, the file vanishes from the directory tree, and a disk-only investigation never finds it. The kernel still holds the inode, and you can copy it back out.

```bash
lsof +L1                                          # open files with link count 0
ls -l /proc/[0-9]*/exe 2>/dev/null | grep '(deleted)'
ls -l /proc/[0-9]*/fd/ 2>/dev/null | grep '(deleted)'

# recover a deleted binary from a running process, to the collector
PID=31337
cat /proc/$PID/exe | ssh -o ForwardAgent=no "$COLLECTOR" "cat > cases/$CASE/pid$PID.exe"
sha256sum /proc/$PID/exe
```

Verified on this workstation: `ls -l /proc/*/exe | grep '(deleted)'` finds nothing, and an unprivileged `lsof +L1` lists a few legitimate entries (zsh prompt FIFOs under `/tmp` marked `(deleted)`). Deleted **FIFOs and temp files** from shells, browsers and databases are normal; a deleted **executable** backing a running process is not. Package upgrades also leave services running on deleted binaries until restart, so check `rpm -qf` on the original path and the upgrade time in `dnf history` before concluding.

#### Bash history and shell traces

```bash
ls -la /root/.bash_history /home/*/.bash_history /home/*/.zsh_history 2>/dev/null
# zero-length, symlinked to /dev/null, or recently truncated histories are findings
find / -xdev -name '.*history' -size 0 2>/dev/null
grep -h -E 'curl|wget|base64|chmod \+x|/dev/tcp|nc |python -c' /root/.bash_history /home/*/.bash_history 2>/dev/null
```

With `pam_tty_audit` enabled, keystrokes are in the audit log: `aureport --tty`.

### Logs and preservation

```bash
# the journal for the window, in a format journalctl can read back on the analysis host
journalctl --since '2026-09-22 00:00' --utc -o export | ssh "$COLLECTOR" "cat > cases/$CASE/journal.export"

# audit logs, raw
tar -C /var/log -cf - audit | ssh "$COLLECTOR" "cat > cases/$CASE/audit.tar"

# the rest of /var/log
tar -C /var/log --exclude=journal -cf - . | ssh "$COLLECTOR" "cat > cases/$CASE/varlog.tar"

# hashes of what you sent, recorded alongside
sha256sum /var/log/audit/* | ssh "$COLLECTOR" "cat > cases/$CASE/audit.sha256"
```

Then pull the off-host copies: your SIEM, the log server, cloud audit trails (CloudTrail, GCP Audit Logs), GitLab's audit events and `application_json.log` (failed logins), `auth_json.log` and `production_json.log` if the host touched GitLab, and firewall or load balancer logs for the host's addresses. **The off-host copy is the one the attacker couldn't edit.** Compare it with the local one; gaps in the local copy are evidence of tampering.

Disk: take a snapshot at the hypervisor or cloud layer, or image the disk from rescue media (`dd`/`dc3dd` to external storage, hash before and after). Analyse the image read-only on another machine (`mount -o ro,noexec,noload`), never the original.

### Containment

Choose based on what you need to learn and what's at risk. Default order, least destructive first:

| Option | Keeps | Loses | Use when |
|---|---|---|---|
| **Network isolate** (cloud security group / hypervisor / switch port / host firewall allowing only your IR IP) | Memory, processes, disk | Live C2 traffic observation | **Default.** Stops exfiltration and lateral movement, keeps evidence |
| **Pause the VM** (`virsh suspend`, cloud "stop" with memory preserved where offered) | Everything, frozen | Nothing, until resumed | You need time and the platform supports it |
| **Freeze a process** (`kill -STOP PID`) | Process memory, its sockets | The process's progress | One malicious process, the rest of the host is needed |
| **Kill processes / disable accounts** | Disk | Process memory, attacker's in-memory state | After memory capture |
| **Power off** | Disk | Everything volatile | Only if active destruction (ransomware encrypting) outweighs evidence |
| **Rebuild** | Nothing on that host | Everything | Recovery, after evidence is preserved |

A host-level isolation that leaves you connected:

```bash
# on the suspect host: drop everything except your IR workstation
IR_IP=10.20.0.15
nft add table inet ir
nft add chain inet ir in  '{ type filter hook input  priority -300 ; policy drop ; }'
nft add chain inet ir out '{ type filter hook output priority -300 ; policy drop ; }'
nft add rule inet ir in  iif lo accept
nft add rule inet ir out oif lo accept
nft add rule inet ir in  ip saddr $IR_IP tcp dport 22 ct state new,established accept
nft add rule inet ir out ip daddr $IR_IP ct state established accept
```

> **Gotcha.** Host-level isolation relies on the suspect kernel honouring it. An attacker with root can flush it (`nft flush ruleset`). Prefer isolation **outside** the host (security group, VLAN, hypervisor firewall, switch port) and use the host firewall only as an extra layer or when nothing else is available. Also: isolating a host tells an attacker who's watching that you've noticed. Decide whether that matters before you do it.

#### Credentials: assume they're gone

Rotate everything the host held or could reach, from a clean machine:

- SSH host keys (after the rebuild) and every user key whose private half was on the host; remove its public keys from `authorized_keys` everywhere.
- Tokens in environment files, CI runner registration tokens, GitLab personal/project/deploy tokens used there, container registry credentials (`~/.docker/config.json`, `${XDG_RUNTIME_DIR}/containers/auth.json`).
- Cloud credentials: instance roles (revoke active sessions), access keys in `~/.aws`, `~/.config/gcloud`.
- Kubeconfigs and service account tokens.
- Database and application secrets from config files or OpenBao/Vault leases issued to the host.
- Passwords typed on the host during the window, including yours during the response.

### What not to do

- **Don't reboot or power off** "to be safe". It destroys the most useful evidence.
- **Don't run a cleaner that deletes** (ClamAV `--remove`, rkhunter "fix" options). Quarantine or leave in place.
- **Don't install tools with `dnf`/`apt`** on the suspect host. Bring static binaries.
- **Don't write evidence to the suspect disk.**
- **Don't `ssh -A`** or use a privileged, reusable credential to log in.
- **Don't trust the host's `ps`, `ls`, `ss`.** Cross-check against `/proc` and off-host logs.
- **Don't kill processes before capturing them.** Their memory and open sockets go with them.
- **Don't tip off the attacker** from the suspect host (no emails from it, no chat messages from its bot tokens, no password changes typed on it).
- **Don't restore from backup onto the same host** before you know the entry point. You'll restore the vulnerability, and possibly the persistence.
- **Don't work alone and don't work from memory.** Timestamped notes, a second person, this checklist.

### Recovery, briefly

Rebuild, don't repair. A host an attacker had root on can't be proven clean by any tool in chapter 09. Rebuild from the image pipeline, restore data (not binaries or config) from a backup older than the first evidence of compromise, patch the entry point, rotate credentials, and watch the rebuilt host closely (chapter 08's audit rules, chapter 10's Falco) for the attacker's return. Then write the post-incident review while it's fresh.

### One-screen security command reference

| Task | Command | Chapter |
|---|---|---|
| Baseline audit | `sudo lynis audit system --quick` | 07 |
| Lynis test detail | `lynis show tests TEST-ID` | 07 |
| Benchmark scan + HTML report | `sudo oscap xccdf eval --profile cis_server_l1 --report r.html DS.xml` | 07 |
| Remediation for review | `oscap xccdf generate fix --fix-type ansible --result-id RID --output fix.yml arf.xml` | 07 |
| Audit status / rules | `sudo auditctl -s` / `sudo auditctl -l` | 08 |
| Reload audit rules | `sudo augenrules --load` | 08 |
| Search audit by key | `sudo ausearch -k KEY -ts today -i` | 08 |
| What a login did | `sudo ausearch -ul UID -ts today -i` | 08 |
| Audit summaries | `sudo aureport --summary`, `-au --failed`, `-k --summary` | 08 |
| SSH logins (OpenSSH 9.8+) | `journalctl -u sshd.service -g 'Accepted\|Failed' --since today` | 08 |
| sudo use | `journalctl -t sudo --since today` | 08 |
| Journal as JSON | `journalctl -u UNIT -o json --output-fields=MESSAGE,_PID,_UID` | 08 |
| Package file changes | `sudo rpm -Va --noconfig` / `sudo dpkg --verify` | 09 |
| Integrity check | `sudo aide --check` (exit bits: 1 new, 2 removed, 4 changed) | 09 |
| Rootkit check | `sudo rkhunter --check --sk --rwo` | 09 |
| Malware scan | `sudo clamscan -r -i --move=/var/quarantine PATH` | 09 |
| YARA hunt | `yara -r -s rules.yar PATH` / `yara rules.yar PID` | 09 |
| fail2ban status | `sudo fail2ban-client status sshd` | 10 |
| Test a filter | `fail2ban-regex systemd-journal sshd` | 10 |
| Unban | `sudo fail2ban-client set sshd unbanip IP` | 10 |
| USB devices | `sudo usbguard list-devices` | 10 |
| Validate Falco rules | `sudo falco --dry-run -r RULES.yaml` | 10 |
| Listeners with process | `sudo ss -tulpn` | 11 |
| Who owns a port | `sudo lsof -nP -i :PORT` | 11 |
| Scan own host | `nmap -sV -p- 127.0.0.1` | 11 |
| Diff two scans | `ndiff old.xml new.xml` (upstream nmap only; not in Fedora's package) | 11 |
| Pending security updates | `dnf advisory list --security` | 11 |
| Apply security updates | `sudo dnf upgrade --security` | 11 |
| Host vulns (non-Fedora OS, apps) | `sudo trivy rootfs --scanners vuln --ignore-unfixed /opt/app` | 11 |
| Host SBOM, scan later | `syft scan dir:/ -o cyclonedx-json=h.json` → `grype sbom:h.json` | 11 |
| Deleted-binary processes | `osqueryi "SELECT pid,name,path FROM processes WHERE on_disk=0"` | 11 |
| Process tree | `ps -eo pid,ppid,user,lstart,cmd --forest -ww` | 12 |
| Connections with process | `ss -tanp` | 12 |
| Login history | `last -F -i -x`, `lastb -F -i`, `lastlog2 -a`, `aulast` | 12 |
| Timers and cron | `systemctl list-timers --all`, `ls /etc/cron.d /var/spool/cron` | 12 |
| Recently changed files | `find / -xdev -type f -mtime -2` | 12 |
| Deleted but open | `lsof +L1`, `ls -l /proc/*/exe \| grep deleted` | 12 |
| Recover running binary | `cat /proc/PID/exe > /mnt/usb/pid.exe` | 12 |
| Export journal evidence | `journalctl --since DATE --utc -o export` | 12 |
| VM memory dump | `virsh dump --memory-only --format elf DOMAIN FILE` | 12 |

### Checklist

- The time, the trigger and every action are written down, in UTC, off the host.
- A VM or cloud snapshot exists before anyone runs anything on the guest.
- Volatile data was collected in order and written off the host, with hashes.
- Memory was captured, or there's a written reason why not.
- `ps` was cross-checked against `/proc`; deleted-but-running binaries were copied out.
- Persistence locations were checked, including user systemd units, lingering, `ld.so.preload`, PAM and containers.
- Local logs were compared against the off-host copies.
- Containment happened outside the host where possible.
- Every credential the host held or saw is on a rotation list, and the rotations were done from a clean machine.
- The host is rebuilt, not repaired.

### Traps

- **Rebooting first.** The fastest way to make an incident unexplainable.
- **Collecting to the suspect disk.** Overwrites deleted evidence and tells the attacker what you're doing.
- **`ssh -A` to the compromised host.** Lends the attacker your keys.
- **Trusting `ps` and `ls`.** Use `/proc` and a known-good toolkit.
- **Killing the process before capturing it.** The binary may exist only in memory.
- **Believing `wtmp`.** It's editable; the journal, audit log and off-host logs are the cross-check.
- **Host firewall as the only containment.** Root can flush it.
- **Forgetting user-level persistence.** User systemd units with lingering survive reboots without touching `/etc`.
- **Restoring from a backup taken after the compromise.** Restores the attacker too.


---


<a id="13-canadian-requirements-mapped-to-settings"></a>

## 13 · Canadian requirements, mapped to settings

*Canada publishes the controls and the profile, but not the numbers. ITSP.10.033 says "configure securely to organization-defined values"; the values come from TBS guidance, CCCS crypto publications and a CIS or STIG baseline you choose and write down. Everything technical in an audit hangs off that choice.*

### The stack in one picture

Every Canadian requirement you will be asked about sits at one of five levels. Auditors move between them freely; you need to know which level a question is really at before you answer it.

```text
  TBS policy            Directive on Security Management (App. B, App. J)
  "what must be true"   GC Event Logging Guidance, GC Guideline on Vuln Mgmt
        |
  Catalogue             ITSP.10.033  (was ITSG-33 Annex 3A)   20 families, AC-06 style IDs
  "the controls"        ITSP.10.171  (CPCSC, NIST 800-171 Rev. 3, 03.01.01 style IDs)
        |
  Profile               ITSP.10.033-01 Medium  (was Annex 4A Profile 1, PBMM)
  "which controls"      CPCSC Level 1 / 2 / 3  (13 / 98 / 200 controls)
        |
  Values                [Assignment: organization-defined ...]  <- mostly EMPTY in the profile
  "what number"         filled from: TBS timelines, ITSP.40.111/.062, CIS or DISA STIG
        |
  Settings + evidence   sshd_config, auditd.conf, crypto-policies, PSA labels ...
  "prove it"            OpenSCAP ARF, Lynis report, kube-bench JSON, aureport, SBOMs
```

The level people skip is **Values**. The Canadian profile deliberately leaves most placeholder parameters blank, so "we follow ITSG-33" is not a configuration. A CIS or STIG benchmark is what turns a control like `CM-06` into 400 checkable rules, and choosing one is a decision many organizations have not yet written down (see Decide these, at the end of this chapter).

### ITSG-33 to ITSP.10.033

ITSG-33 (*IT security risk management: A lifecycle approach*, annexes dated 1 November 2012) was partly superseded in 2026 by the series *Cyber security and privacy risk management: A lifecycle approach*.

| New publication | Effective | Replaces | What it is |
|---|---|---|---|
| **ITSP.10.033** | 31 March 2026 | ITSG-33 Annex 3A | The control catalogue, aligned with NIST SP 800-53 Rev. 5 and adapted for Canada |
| **ITSP.10.033-01** | 1 April 2026 (the web page says 2 April) | ITSG-33 Annex 4A Profile 1 (PBMM) | Suggested profile for **Medium** confidentiality, integrity and availability |
| ITSP.10.036 | referenced by ITSP.10.033 | probably Annex 1 (unconfirmed) | Organizational risk management activities |
| ITSP.10.037 | referenced by ITSP.10.033 | probably Annex 2 (unconfirmed) | System lifecycle activities; not yet listed on the series page |

What changes for an engineer:

- **Control IDs are zero-padded.** `AC-06`, `AU-02`, `IA-05(01)`, `SC-28(01)`, not NIST's `AC-6`. Canadian-specific additions are numbered from 400 (`SA-400`, `IA-04(400)`). Use the padded form in anything you hand a Canadian assessor; a spreadsheet keyed on `AC-6` will not join against theirs.
- **20 families.** AC, AT, AU, CA, CM, CP, IA, IR, MA, MP, PE, PL, PM, PS, PT, RA, SA, SC, SI, SR. **PM, PT and SR are new relative to ITSG-33.** SR (supply chain risk management) is the one that lands on engineering: signed artefacts, SBOMs, provenance.
- **The catalogue includes assurance activities**, not just controls. That is the hook an assessor uses to ask *how* you know a control works, which is what chapter 17, Running an audit end to end, produces.

> **Version-sensitive.** DND's DAOD 6003-series directives and the CCCS Cloud Security Assessment Program still reference ITSG-33 and its Annex 3 controls as of September 2026, and no transition has been announced for either. Expect documents that cite ITSG-33 and ITSP.10.033 side by side for a while. The families and control intent carry over; the numbering format and the Rev. 5 control set are what changed.

#### The Medium profile (the new PBMM)

ITSP.10.033-01 covers compromise that could cause a "medium level of injury to non-national interests". In practice that is the Protected B / Medium / Medium envelope that PBMM used to describe. Two facts matter operationally:

1. **The "Suggested placeholder values" column is usually empty** (ITSP.10.033-01 §3.2). The profile tells you *which* controls apply, not *what* the password length, lockout threshold or log retention is. You fill those in and record them as your organization-defined values.
2. **Crypto modules must be CMVP-validated** (§3.1). The Cryptographic Module Validation Program is joint between the Cyber Centre and NIST. That single sentence is why FIPS mode keeps coming up.

> **Note.** CCCS will email the profile as a spreadsheet on request (contact@cyber.gc.ca). Ask for it: it is the fastest way to build a control matrix, and it arrives keyed on the official IDs.

### CPCSC on ITSP.10.171

The Canadian Program for Cyber Security Certification (CPCSC) is run by PSPC and National Defence. Its standard is **ITSP.10.171**, *Protecting specified information in non-Government of Canada systems and organizations* (second release October 2025). It is NIST SP 800-171 **Rev. 3** with "no substantial technical changes"; "controlled unclassified information" becomes "specified information". Its assessment companion is ITSP.10.171-01.

#### Levels

| Level | Controls | Assessment | Who needs it |
|---|---|---|---|
| **1** | 13 | Annual self-assessment through the CCCS online tool; proof uploaded to your CanadaBuys profile | Select defence contracts from summer 2026 |
| **2** | 98 | External, by an SCC-accredited certification body, plus annual affirmation | Contracts handling controlled defence information |
| **3** | 200 | Assessed by National Defence / GC, plus annual affirmation | Highest-risk work: weapon systems, critical infrastructure, Five Eyes-shared information |

> **Version-sensitive.** The official page calls the Level 2 and 3 reassessment cycle "triannual". Literally that is three times a year; it is probably a typo for triennial (every three years). Unconfirmed. The split behind 98 and 200 (likely 800-171 Rev. 3, then plus 800-172 enhancements) is also not stated officially.

#### Rollout timeline

| When | What |
|---|---|
| March 2025 | First phase announced |
| April 2026 | Level 1 available (control list published 22 April 2026) |
| Summer 2026 | Level 1 required in select defence contracts, "only upon contract award" in the initial phase |
| April 2026 – March 2027 | Level 1 tools; DND contract cyber risk assessments; SCC starts accepting Level 2 certification-body applications |
| Spring 2027 | Level 2 begins appearing in select contracts |
| April 2027 – March 2028 | Level 2 and 3 added "gradually" to select contracts |

The practical reading: **Level 1 is live now. Level 2 is roughly six months out as a contract clause**, and 98 controls is not something you retrofit in a quarter. The evidence pipeline in chapter 17 is built so the same bundle serves both.

> **Gotcha.** CPCSC uses Rev. 3 numbering (`03.01.01`). The US CMMC Level 2 uses 800-171 **Rev. 2** (`3.1.1`, 110 requirements). Canada accepts a valid CMMC certification case by case after checking scope, but **a CMMC control mapping does not transfer one to one**: Rev. 3 merged, split and renumbered requirements. If your CPCSC Level 1 baseline was "mapped from CMMC 2.0 Level 1", re-key it against the ITSP.10.171 IDs below before an assessor does.

#### Level 1's 13 controls, technically

The official list, with what each means on systems you run. The ID and title are official; the technical reading is this manual's interpretation, not a CCCS mapping. Level 1 groups them into six cyber hygiene practices; the self-assessment asks for evidence kept "for the duration of your attestation cycle, or at least one year".

| ID | Title | On a host / in Docker / in Kubernetes | Evidence you keep |
|---|---|---|---|
| `03.01.01` | Account management | No shared or dormant local accounts; `docker` group membership controlled; RBAC subjects reviewed | `getent passwd` + `lastlog` export; `kubectl get clusterrolebindings -o wide`; dated review sign-off |
| `03.01.02` | Access enforcement | File modes, sudoers, SELinux enforcing; non-root containers; RBAC least privilege, PSA `restricted` | OpenSCAP ARF; `sudo -l -U USER`; `kubectl auth can-i --list --as=system:serviceaccount:NS:SA` |
| `03.01.20` | Use of external systems | Only approved registries and SaaS; air-gapped delivery pulls from the internal registry only | Registry allow-list; `policy.json`; Kyverno/admission policy on image source |
| `03.01.22` | Publicly accessible content | Nothing sensitive in public repos or public images | Repo visibility report; secret-detection results |
| `03.05.01` | User identification, authentication, re-authentication | Unique IDs; session timeouts (`ClientAliveInterval`, `TMOUT`); OIDC for cluster users | `sshd -T`; OpenSCAP rules for timeouts; API server OIDC flags |
| `03.05.02` | Device identification and authentication | SSH host keys or host certificates; mTLS between services; kubelet client certs | `ssh-keyscan` inventory; mTLS config; kube-bench node section |
| `03.05.03` | Multi-factor authentication | MFA on admin and remote access: FIDO2 SSH keys, MFA at the IdP for `kubectl` | `sshd -T \| grep -i pubkeyauthoptions`; IdP MFA policy export |
| `03.08.03` | Media sanitization | Disk wipe at decommission (`blkdiscard`, `nvme format`); PV reclaim and volume deletion | Sanitization records with serial numbers |
| `03.10.01` | Physical access authorizations | Not technical | Access lists |
| `03.10.07` | Physical access control | Not technical | Visitor logs, badge records |
| `03.13.01` | Boundary protection | Host firewall default deny; no `--network host`; NetworkPolicy default deny | `nft list ruleset`; `firewall-cmd --list-all-zones`; `kubectl get networkpolicy -A` |
| `03.14.01` | Flaw remediation | Patching to SLA; image rebuilds; CVE scanning | `dnf updateinfo list --security`; Trivy/Grype reports; POA&M |
| `03.14.02` | Malicious code protection | Anti-malware on hosts (SentinelOne on corporate endpoints); image scanning | EDR console export; ClamAV/scan logs; image scan reports |

Seven of the thirteen produce machine evidence. The rest are records. **An assessor for Level 1 mostly wants to see that the records exist and are dated**; see chapter 17 for what each level actually asks for.

### Protected B, technically

Protected B applies when unauthorized disclosure "could reasonably be expected to cause serious injury outside the national interest" (TBS *Standard on Security Categorization*, Appendix J of the Directive on Security Management). Appendix B of the same directive (which replaced MITS in 2019) requires unique identification and authentication of individuals and devices, need-to-know access for screened users, IT continuity and security in IT projects.

There is no single Canadian "Protected B hardening standard". The technical expectations are assembled from several publications:

| Area | Expectation | Basis |
|---|---|---|
| In transit | TLS 1.3 (1.2 where justified); mTLS between services | ITSP.40.062; ITSP.80.023 |
| At rest | AES in CMVP-validated modules: LUKS2 on hosts, etcd encryption and encrypted PVs in Kubernetes | ITSP.40.111; ITSP.10.033-01 §3.1 |
| Access | Unique IDs, MFA for privileged and remote access, least privilege | TBS DSM App. B; ITSP.10.033 AC/IA |
| Logging | Time-stamped, tamper-protected, forwarded centrally | TBS Event Logging Guidance; DAOD 6003-3 |
| Retention | ≥3 months online, ≥6 months stored; incidents ≥2 years | TBS Event Logging Guidance |
| Patching | Critical within 48 hours | TBS Guideline on Vulnerability Management |
| Segmentation | Default deny between security contexts; one kernel runs only containers of the same sensitivity | ITSP.80.023; ITSM.10.092 |

For contractors, processing protected information on your own IT needs an **Authority to process information technology** under the PSPC Contract Security Program. An IT security inspection happens after contract award and before any electronic processing: the Company Security Officer completes an IT security checklist and a data flow diagram. The detailed requirements are in Contract Security Manual Chapter 7 and RCMP GCPSG-015, which this manual has not reviewed.

> **Gotcha.** ITSP.80.023 says a kernel should only run containers "with the same data sensitivity and functionality". A shared Kubernetes node pool running a Protected B candidate workload next to an unclassified build job fails that on its face, whatever your NetworkPolicy says. Separate node pools with taints, or separate clusters. Chapter 16 covers the mechanics.

### Cryptography: ITSP.40.111 and 40.062

Two CCCS publications set the algorithm and protocol values that `SC-08`, `SC-12` and `SC-13` leave open.

| Topic | ITSP.40.111 (effective 29 May 2026) / ITSP.40.062 v3 (January 2025) |
|---|---|
| Symmetric | **AES only**, 128/192/256-bit keys; 3DES phased out by end of 2023 |
| Hash | SHA-2 and SHA-3; SHA-224 variants out by end of 2030; **no SHA-1 in signatures** |
| RSA / DH | ≥2048 bits now, ≥3072 by end of 2030 |
| ECC | P-256, P-384, P-521 (P-224 out by 2030); EdDSA recommended |
| Post-quantum | ML-KEM, ML-DSA, SLH-DSA approved; classical-only public-key schemes phased out by end of 2035 |
| TLS | 1.3 recommended; 1.2 acceptable where required; nothing older; check revocation (CRL/OCSP) |
| SSH | Protocol 2 only; host keys ECDSA, Ed25519 or Ed448 (RSA "sufficient"); AEAD ciphers preferred, CBC discouraged |
| IPsec | IKEv2 with signatures; no pre-shared keys |

On Fedora and RHEL, crypto is set system-wide by crypto-policies (chapter 03 covers the SSH side). What the shipped policies do against the list, verified on Fedora 43:

```bash
update-crypto-policies --show        # DEFAULT on this box
cat /proc/sys/crypto/fips_enabled    # 0 = not in FIPS mode
grep -E '^cipher' /usr/share/crypto-policies/policies/DEFAULT.pol
grep -E '^cipher' /usr/share/crypto-policies/policies/FIPS.pol
```

| Policy | TLS protocols | Symmetric ciphers | Fits ITSP.40.111? |
|---|---|---|---|
| `DEFAULT` | TLS 1.3, 1.2 | AES-GCM/CCM, **ChaCha20-Poly1305, Camellia**; 3DES still allowed for S/MIME | No: non-AES ciphers enabled |
| `FIPS` | TLS 1.3, 1.2 | AES only | Algorithms yes; CMVP validation depends on the OS vendor's modules |
| `FUTURE` | TLS 1.3, 1.2 | Stricter key sizes | Closer, not designed for the list |

**Default pick: `FIPS` policy on RHEL hosts that process Protected B candidate data**, because it is the only shipped policy that restricts symmetric ciphers to AES, and RHEL's OpenSSL module is the one with a CMVP certificate.

> **Gotcha.** `fips-mode-setup` is not present on Fedora 43 (verified: `command -v fips-mode-setup` finds nothing). FIPS mode there is the `fips=1` kernel argument plus the `FIPS` crypto policy, set at install or image build. More importantly, **Fedora's crypto modules are not CMVP-validated** (inferred from the validation list covering RHEL, not Fedora). A Fedora-based bootc appliance can run the `FIPS` *policy* but cannot claim the ITSP.10.033-01 CMVP requirement. That is a base-image decision, not a setting.

> **One-way door.** Switching FIPS mode on after install leaves keys and certificates generated before the switch outside it, and Red Hat recommends enabling FIPS at install time; RHEL 10 removed `fips-mode-setup`, so there it is install-time only. Decide at image build; changing it on a running fleet means reinstalling.

> **Version-sensitive.** The RHEL 9 vs RHEL 10 FIPS enablement details are from Red Hat documentation as recalled, not re-checked for this chapter. Confirm against the RHEL security hardening guide for your minor release.

Evidence commands for `SC-13`:

```bash
update-crypto-policies --show
cat /proc/sys/crypto/fips_enabled
sudo sshd -T | grep -E '^(ciphers|macs|kexalgorithms|hostkeyalgorithms)'
openssl s_client -connect HOST:443 -tls1_3 </dev/null 2>/dev/null | grep -E 'Protocol|Cipher'
openssl s_client -connect HOST:443 -tls1_1 </dev/null   # must fail
```

### TBS log retention and patch timelines

These are the numbers most often missing from a control matrix, and TBS publishes them.

#### Log retention

TBS *GC Event Logging Guidance* (modified 8 December 2025), PBMM values:

| Data | Minimum | What it means on a host |
|---|---|---|
| GC systems, online | 3 months | Searchable in the SIEM or on the log host, not just archived |
| GC systems, in storage | 6 months | Compressed archive, restorable |
| Security incident records | 2 years | Preserved evidence per chapter 12 |
| Cloud service providers | 90 days online | For hosted components |

It also requires that "logging facilities and log information must be protected against tampering and unauthorized access" (`AU-09`). Its OS event tables are Windows-only; for Linux, auditd rules from chapter 08 plus the STIG or CIS rule set fill the gap.

> **Gotcha.** Local `auditd.conf` rotation (`num_logs` × `max_log_file`) on a busy host is days, not months, and journald's defaults cap by size. **Retention is a property of the log host, not the source**: forward (chapter 08, *Forwarding logs off the host*) and set retention where the logs land. An assessor asking for `AU-11` evidence wants the log host's retention config and an old event pulled from it, not `auditd.conf`.

#### Patch timelines

Two public timelines apply, plus whatever your internal process sets, and they disagree. The last column is an example internal policy, for comparison:

| Severity | TBS Guideline on Vuln Mgmt (2026) | CCCS ITSM.10.096 (2022) | Example internal VMP (target / hard) |
|---|---|---|---|
| Critical | 48 hours | 48 hours ("extreme") | 24 h / 72 h |
| High | 14 days | 2 weeks | 7 days / 14 days |
| Medium | 30 days | next major update or 3 months | 30 days / 60 days |
| Low | 90 days | next major update or 1 year | 90 days / 180 days |

TBS also sets scan frequency: internal scanning at least weekly or after significant change, external monthly, configuration checking monthly and after configuration changes.

In this example the internal targets are inside the TBS numbers but the **hard deadlines are not** (Critical 72 h vs 48 h, Medium 60 d vs 30 d, Low 180 d vs 90 d). A Protected B uplift (one tier stricter for Protected B candidate data, DND/CAF-connected systems and auth or crypto components) closes most of that for the systems that matter, because a Medium on a Protected B system is then handled as High.

> **Gotcha.** If a DND contract flows TBS's guideline down, a Medium finding closed on day 45 can be inside an internal hard deadline and outside the contract. Use the stricter of the two for any system in a DND contract's scope, and say so in the POA&M.

### The baseline Canada does not publish

CCCS has no Linux, container or Kubernetes hardening benchmark of its own. ITSM.10.090 (*Harden operating systems and applications*, June 2024) tells you to keep a documented baseline configuration, never deploy defaults, disable non-essential services, use Secure Boot and TPM 2.0, and it **recommends CIS Benchmarks and discusses DISA STIGs**. No official Canadian text mandates either. In practice the benchmark is what you record as the organization-defined values for `CM-06`.

No Canadian profile exists in OpenSCAP either: a grep of the SSG 0.1.82 data streams for ITSG, ITSP.10 or cyber.gc.ca finds nothing. The nearest proxies are `cis`, `stig` and `cui` (800-171, marked DRAFT).

| Layer | Default baseline | Alternative and its tiebreaker |
|---|---|---|
| RHEL 9/10 hosts | **CIS Level 1 Server** (`cis_server_l1`) | DISA STIG when a contract names it: stricter, breaks more, and the only one US-origin assessors recognize without explanation |
| Fedora bootc appliance | CIS Fedora `cis_server_l1` (**DRAFT**, advisory only) | Rebase on a RHEL or CentOS Stream bootc image to get a supported CIS profile; see Decide these |
| Docker / Podman hosts | CIS Docker 1.8.0 | none worth it |
| Kubernetes | CIS Kubernetes 2.0.1 via kube-bench, NSA/CISA via Kubescape | DISA Kubernetes STIG V2R6 if STIG is the host baseline |

**Default pick: CIS Level 1 Server**, because it is designed to be applicable without breaking a normal server, it has a current OpenSCAP profile on RHEL 10, and CCCS names CIS first. Chapter 07 covers running and tailoring it.

#### The tool-lag problem

A scanner implements a benchmark version, and the benchmark moves faster than the scanner. What is current against what the tools check, September 2026:

| Benchmark | Current | Tool | Tool implements | Lag |
|---|---|---|---|---|
| CIS RHEL 9 | 3.0.0 | OpenSCAP SSG 0.1.82 `cis*` | **v2.0.0 (2024-06-20)** (verified in the profile description) | One major version |
| CIS RHEL 10 | 1.0.1 | SSG 0.1.82 `cis*` | v1.0.1 (verified) | None |
| DISA RHEL 9 STIG | V2R9 | SSG 0.1.82 `stig` | V2R9 (verified) | None |
| NIST 800-171 | Rev. 3 | SSG `cui` | DRAFT, Rev. 2-era text | Wrong revision for CPCSC |
| CIS Docker | 1.8.0 | docker-bench-security | **1.6.0** (per its README) | Two versions |
| CIS Docker | 1.8.0 | Trivy `docker-cis-1.6.0` | 1.6.0 | Two versions |
| CIS Kubernetes | 2.0.1 | kube-bench v0.16.0 `cis-2.0` | 2.0.x | None |
| CIS Kubernetes | 2.0.1 | Kubescape v4.0.14 | up to `cis-v1.12.0` | One major version |
| CIS Kubernetes | 2.0.1 | Trivy `k8s-cis-1.23` | 1.23 | Far behind |

Check the version a profile targets before you quote it:

```bash
oscap info --profile cis /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml | grep -A1 Description
oscap info --profile stig /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml | grep -A1 Description
```

How to handle it without pretending:

1. **Record the implemented version in the evidence**, not the current one: "CIS RHEL 9 Level 1 Server v2.0.0 as implemented by SSG 0.1.82". An assessor who sees "CIS RHEL 9" and checks against 3.0.0 will find rules you never scanned for.
2. **Diff the two benchmark versions once**, using the CIS change log, and list the new or changed recommendations as manual checks in the evidence index until the tool catches up.
3. **Use the scanner that matches** where one does: kube-bench for CIS Kubernetes, not Kubescape's or Trivy's CIS mode.
4. For CIS Docker 1.8.0, run docker-bench for the bulk and cover the delta by hand. If an internal container standard is still keyed on an old CIS Docker version (1.2 is common), re-key it to current section numbers when you touch it.

> **Gotcha.** The `cui` profile looks like the natural fit for CPCSC because it says "NIST 800-171". It is marked DRAFT and written against Rev. 2. Do not present a `cui` score as CPCSC evidence; use CIS or STIG results mapped to the ITSP.10.171 IDs in the table above.

### The mapping table

The core of this chapter. Families use ITSP.10.033 IDs; the ITSP.10.171 column uses the Rev. 3 family numbering (`03.01` = AC … `03.17` = SR), confirmed for the Level 1 families and inferred for the rest. The technical readings are this manual's, derived from control intent and CIS/STIG content: **there is no official CCCS mapping from controls to Linux settings.**

#### Technical families

| Family (key controls) | 171 | Linux host | Docker / Podman | Kubernetes | Evidence: tool and command | Chapter |
|---|---|---|---|---|---|---|
| **AC** Access control (`AC-02`, `AC-03`, `AC-06`, `AC-07`, `AC-17`) | 03.01 | No shared accounts; sudo scoped and logged; `faillock`; `PermitRootLogin no`; SELinux enforcing | Rootless or userns-remap; `USER` non-root; `--cap-drop ALL`; no `--privileged`; `docker` group = root | RBAC least privilege; no workload `cluster-admin`; PSA `restricted`; `automountServiceAccountToken: false` | `oscap xccdf eval --profile cis_server_l1`; `lynis audit system`; docker-bench §2, §5; `kube-bench run --targets policies`; `kubescape scan framework nsa` | 02, 03, 05, 14, 15, 16 |
| **AU** Audit (`AU-02`, `AU-03`, `AU-08`, `AU-09`, `AU-11`, `AU-12`) | 03.03 | auditd rules; chrony; forwarding; log file modes; retention 3 + 6 months at the log host | auditd watches on `dockerd`, `/var/lib/docker`, `/etc/docker`; logging driver to central store | API server `--audit-policy-file`, `--audit-log-maxage`; node logs shipped | `auditctl -s`; `auditctl -l`; `aureport --summary`; docker-bench §1; kube-bench §1.2, §3.2; `chronyc tracking` | 08, 15, 16 |
| **CA** Assessment and monitoring (`CA-07`) | 03.12 | Scheduled scans; POA&M | Image scans in CI | Scheduled posture scans | OpenSCAP ARF over time; scheduled pipeline artefacts | 07, 17 |
| **CM** Configuration management (`CM-02`, `CM-06`, `CM-07`, `CM-08`, `CM-11`) | 03.04 | Named baseline (CIS/STIG) as `CM-06` values; unneeded packages and services removed; `fapolicyd` allow-listing | Minimal images pinned by digest; read-only rootfs; no sshd in images | Pinned images; admission control; GitOps as the baseline | `oscap` + tailoring file; `systemctl list-unit-files --state=enabled`; docker-bench §4; `trivy config`; Kyverno policy reports | 06, 07, 15, 16 |
| **IA** Identification and authentication (`IA-02`, `IA-05`, `IA-05(01)`) | 03.05 | pwquality; MFA for admin and SSH; key-only SSH with ITSP.40.062 algorithms | Registry authentication; no secrets in images or build args | OIDC with MFA; short-lived SA tokens; no static tokens | `sshd -T`; `authselect current`; `trivy image --scanners secret`; kube-bench §1.2 | 02, 03, 15, 16 |
| **MP** Media protection (`MP-06`) | 03.08 | LUKS2; `blkdiscard` / `nvme format` at decommission | Volume deletion | PV reclaim policy; encrypted storage classes | `lsblk -f`; `cryptsetup luksDump`; sanitization records | 06 |
| **RA** Risk assessment (`RA-05`, `RA-05(01)`, `RA-05(05)`) | 03.11 | Weekly authenticated scanning; patch to SLA | CVE scan of every image | Scan running workloads and nodes | `dnf updateinfo list --security`; `grype sbom:FILE`; `trivy image`; `trivy k8s --report summary` | 11, 17 |
| **SC** System and communications (`SC-07`, `SC-08`, `SC-12`, `SC-13`, `SC-28`) | 03.13 | nftables/firewalld default deny; crypto-policy `FIPS`; TLS 1.3; LUKS2 at rest | Networks per security context; no `--network host`; TLS on any exposed daemon socket | NetworkPolicy default deny; mTLS; etcd encryption via KMS; TLS on kubelet and API | `nft list ruleset`; `update-crypto-policies --show`; docker-bench §2, §5; kube-bench §1.2, §4; `openssl s_client` | 03, 04, 06, 15, 16 |
| **SI** System integrity (`SI-02`, `SI-03`, `SI-04`, `SI-07`) | 03.14 | Patching; anti-malware; AIDE; runtime detection | Rebuild cadence; immutable containers | Node patching; Falco-type detection; admission rejects vulnerable images | `aide --check`; `rpm -Va`; Trivy/Grype; Falco alerts | 09, 10, 11 |
| **SR** Supply chain | 03.17 | `gpgcheck=1` on every repo | Signed images; CycloneDX/SPDX SBOM per the 2026 Minimum Elements | Admission-time signature verification; SBOM attestation | `dnf repolist -v`; `syft`/`trivy --format cyclonedx`; `cosign verify`; Kyverno `verifyImages` | 11, 15, 16 |

#### Process families

These produce records, not scan output. They still end up in the evidence bundle.

| Family | 171 | Technical footprint | Evidence |
|---|---|---|---|
| **AT** Awareness and training | 03.02 | none | Training records |
| **CP** Contingency planning | none in Rev. 3 | Backups; etcd snapshots; tested restores | Restore test logs with dates |
| **IR** Incident response | 03.06 | Log forwarding to a SOC; volatile capture tooling | IR plan; exercise records (chapter 12) |
| **MA** Maintenance | 03.07 | Controlled remote maintenance sessions | Session logs; bastion records (chapter 03) |
| **PE** Physical | 03.10 | none | Visitor and badge logs |
| **PL / PM / PS** | 03.15 / none / 03.09 | none | Plans, screening records |
| **PT** Personal information | none | Data minimization in logs | PIA |
| **SA** Acquisition | 03.16 | Vendor SSDLC and base image provenance | SBOM review; SSDLC evidence |

### Decide these

One recommendation each, for a team starting without a written baseline. Most are reversible and should be made quickly; two are not.

1. **Name the profile: ITSP.10.033-01 Medium, tailored.** Reason: it is the direct successor to PBMM, which is what Protected B candidate data implies, and DND documents referring to ITSG-33 PBMM map onto it. Reversible (it is a document), but everything downstream keys on it. Request the CCCS spreadsheet and build the control matrix from it.
2. **Adopt CIS Level 1 Server as the host baseline, recorded as the `CM-06` values.** Reason: CCCS names CIS first, Level 1 does not break normal servers, and the RHEL 10 profile is current. STIG only for contracts that name it. Reversible.
3. **Base any appliance on an image with CMVP-validated crypto.** Reason: ITSP.10.033-01 requires CMVP validation and Fedora's modules are not validated, so no setting on a Fedora bootc base can meet it. **One-way door**: rebasing changes every downstream image, package set and support path; decide before the next customer delivery, not after.
4. **Decide FIPS mode at image build, on for Protected B builds.** Reason: turning it on later means reinstalling. **One-way door** per fleet.
5. **Adopt the stricter of TBS and your internal VMP for anything in a DND contract's scope.** Reason: internal hard deadlines often exceed TBS for Critical, Medium and Low. Reversible; a paragraph in the VMP.
6. **Set log retention at the log host: 3 months online, 6 months archived, 2 years for incidents.** Reason: TBS numbers, and the only place retention can actually hold. Reversible.
7. **Re-key any CPCSC Level 1 mapping to ITSP.10.171 Rev. 3 IDs.** Reason: one derived from CMMC Rev. 2 will not match the self-assessment tool. Reversible, an afternoon.
8. **Re-key container standards to current CIS Docker and retire public-registry allowances.** Reason: old CIS numbering no longer matches tool output, and public registries conflict with air-gap policy. Reversible.
9. **Pick a Kubernetes baseline: CIS Kubernetes 2.0.1 via kube-bench, plus PSA `restricted` by default.** Reason: kube-bench is the only scanner current with the benchmark. Reversible.

### Traps

- **Quoting "CIS RHEL 9" without the version.** The OpenSCAP profile is v2.0.0; the benchmark is v3.0.0. Put the implemented version in every report.
- **Using unpadded IDs.** `AC-6` in your matrix, `AC-06` in theirs: nothing joins. ITSP.10.033 pads.
- **Treating the `cui` profile as CPCSC.** DRAFT, Rev. 2. Not evidence.
- **Reusing a CMMC mapping for CPCSC.** Different revision, different numbering.
- **Retention in `auditd.conf`.** It is set where logs land, not where they start.
- **`DEFAULT` crypto policy on Protected B systems.** It enables ChaCha20 and Camellia; ITSP.40.111 is AES only.
- **FIPS policy on a non-validated OS.** The algorithms comply; the CMVP requirement does not.
- **Assuming the Medium profile gives you numbers.** Its placeholder values column is usually empty. The numbers are yours to choose and record.
- **Shared node pools across sensitivity levels.** ITSP.80.023 wants one sensitivity per kernel.
- **"We align to ITSG-33" with no profile named.** It is unassessable; the first question from any assessor is "which profile, tailored how?".
- **Waiting for Level 2 to appear in a contract.** Spring 2027 is one planning cycle away, and 98 controls need a year of evidence history to look credible.


---


<a id="14-auditing-permissions-and-privilege"></a>

## 14 · Auditing permissions and privilege

*A permission audit answers three questions: who can become root, who can change what root runs, and who can read what they should not. Every finding in this chapter is one of those three, and each has a command whose output an assessor can keep.*

### What this audit proves

Chapter 02 is how to set accounts, sudo and PAM up properly. This chapter is how to **prove**, on a schedule, that they still are, and to hand that proof to someone who was not in the room. The difference matters. A fix is done once. An audit runs every quarter, produces the same files each time, and gets compared with the last run.

Every check below answers one of three questions:

```text
  1. Who can become root?           sudo, polkit, SUID/SGID, file caps, root-equivalent groups,
                                    authorized_keys on root
  2. Who can change what root runs? writable paths under root cron/timers/units, sudo NOPASSWD
                                    scripts, dotfiles of admins, world-writable dirs, ACLs on /etc
  3. Who can read what they should not? home and credential-file modes, adm/systemd-journal,
                                    ACLs, unowned files a new UID inherits
```

Default tool: **the read-only script at the end of this chapter, run as root, output copied off the host.** It collects inventories, flags the known-bad patterns and diffs against a baseline. OpenSCAP (chapter 07) still does the benchmark-by-rule scoring; this script covers the things a benchmark scores badly, such as "which sudo rule is new since last quarter" and "which root timer runs a script a user can edit".

> **Note.** Chapter 13 explains why the numbers come from you. ITSP.10.033 controls carry placeholders ("[Assignment: organization-defined frequency]"), and the Medium profile, ITSP.10.033-01, leaves them mostly blank. For this chapter that means **you choose the review frequency, the list of privileged roles and the permitted SUID set, and you write them down.** The audit then checks the host against what you wrote.

### The controls in scope

IDs are ITSP.10.033 (zero-padded). "Medium" is whether ITSP.10.033-01 selects the control, read from the profile PDF.

| Control | Plain meaning | Medium | Sections below |
|---|---|---|---|
| `AC-02` | Accounts exist on purpose, are reviewed, and are removed when not needed | Selected | Accounts, SSH keys |
| `AC-02(07)` | Privileged accounts are managed as a role and monitored | Selected | Root-equivalent groups, sudo |
| `AC-03` | The system enforces the access decisions you approved | Selected | DAC, ACLs, polkit |
| `AC-03(04)` | Discretionary access control is governed by policy | Selected | Modes, ACLs |
| `AC-06` | Least privilege for users and for processes | Selected | Everything |
| `AC-06(01)` | Access to security functions is authorized to named roles | Selected | sudo, polkit |
| `AC-06(02)` | Admins use non-privileged accounts for non-security work | Selected | sudo, SELinux users |
| `AC-06(05)` | Privileged accounts are restricted to named personnel | Selected | Groups, sudo |
| `AC-06(07)` | Privileges are reviewed at a defined frequency | Selected | The whole audit cycle |
| `AC-06(09)` | Use of privileged functions is logged | Selected | sudo logging (chapter 08) |
| `AC-06(10)` | Non-privileged users cannot run privileged functions | Selected | SUID, caps, writable paths |
| `CM-05` | Only authorized people can change the system | Selected | Cron/timer ownership, writable chains |
| `CM-06` | Configuration settings match a documented baseline | Selected | Critical file modes, baseline diff |
| `CM-07(01)` | Functions and services are periodically reviewed | Selected | SUID and root-service inventory |
| `IA-05(02)` | Public key authenticators are managed | Selected | authorized_keys inventory |
| `SC-39` | Each process runs in its own execution domain | Selected | systemd sandboxing |

On the CPCSC side, Level 1 includes `03.01.01` (account management) and `03.01.02` (access enforcement), and asks you to keep "account lists, device inventories, access reviews" for at least a year. Every file the script writes is one of those.

> **Gotcha.** Committing to ITSG-33, NIST SP 800-53 and CPCSC Level 1 is not enough if nothing names a Linux host baseline, a privileged-role list or an access-review frequency. **`AC-06(07)` cannot pass without a written frequency**, whatever the hosts look like. Pick quarterly for servers and appliance images, write it into the system security plan, and make this audit the evidence.

### DAC: modes, umask and special bits

#### What the bits mean to an auditor

| Bit | On a file | On a directory | Audit concern |
|---|---|---|---|
| setuid (`4000`) | Runs as the file's owner | Ignored on Linux | Every root-owned one is a privilege boundary |
| setgid (`2000`) | Runs as the file's group | New files inherit the directory's group | Files: inventory. Dirs: normal for shared project dirs |
| sticky (`1000`) | Ignored | Only the owner can delete or rename entries | A world-writable dir **without** it lets anyone delete anyone's files |
| `o+w` (`0002`) | Anyone can modify | Anyone can create and delete entries | Almost always a finding outside `/tmp`, `/var/tmp`, `/dev/shm` |

`find -perm` has two forms and the difference decides what you get:

```bash
find / -xdev -type f -perm -4000     # ALL listed bits set: setuid files
find / -xdev -type f -perm /6000     # ANY listed bit set: setuid OR setgid
find / -xdev -type d -perm -0002 ! -perm -1000   # world-writable dirs missing the sticky bit
```

> **Gotcha.** Fedora puts `/` and `/home` on separate btrfs subvolumes, and each subvolume has its own device number. `find / -xdev` **stops at `/home`** and silently skips every home directory. Walk each local mount instead: `findmnt -rn -o TARGET -t ext4,xfs,btrfs` gives the list (verified on Fedora 43, where it returns `/`, `/home` and `/boot`).

#### umask evidence

The login umask (`UMASK` in `/etc/login.defs`, applied by `pam_umask`) and the service umask (`UMask=` per unit, default `0022`) are separate settings, and chapter 02 covers where each one comes from. The audit records both:

```bash
awk '/^(UMASK|HOME_MODE)/' /etc/login.defs          # Fedora 43 default: UMASK 022, HOME_MODE 0700
systemctl show -p UMask --value sshd.service         # 0022 unless the unit sets it
```

#### Evidence

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `AC-03(04)` | Shadow and sudoers modes | `stat -c '%a %U:%G %n' /etc/shadow /etc/gshadow /etc/sudoers /etc/sudoers.d` | `0 root:root` for shadow files, `440`/`750 root:root` for sudoers (Fedora 43 defaults) |
| `CM-06` | Login umask | `grep ^UMASK /etc/login.defs` | The value your baseline names (`027` recommended in chapter 02) |
| `AC-03` | Temp dirs are sticky | `stat -c '%a %n' /tmp /var/tmp /dev/shm` | `1777` on all three |
| `AC-03` | No world-writable dir without sticky | the `find` above | Empty output |

### SUID and SGID inventory

The expected SUID set on a Fedora server is small (chapter 02 lists it and explains how to reduce it). The audit questions are different: **is every one owned by a package, is every one unmodified, and is the list the same as last time?**

```bash
# Inventory across every local mount, sorted so it diffs cleanly
for m in $(findmnt -rn -o TARGET -t ext4,xfs,btrfs); do
  sudo find "$m" -xdev -type f -perm /6000 2>/dev/null
done | sort -u > suid-sgid.txt

# Package ownership: anything unowned is an incident until explained
while read -r f; do rpm -qf "$f" >/dev/null 2>&1 || echo "UNOWNED $f"; done < suid-sgid.txt

# Integrity: mode (M) or digest (5) changed on a packaged file
rpm -Vf $(cat suid-sgid.txt) 2>/dev/null | grep -E '^..5|^.M'
```

#### Baseline and diff

A baseline is the inventory from a host in a known-good state, stored where the host cannot rewrite it (the same rule as the AIDE database in chapter 09). The next run diffs against it:

```bash
diff -u BASELINE/suid-sgid.txt suid-sgid.txt
comm -13 BASELINE/suid-sgid.txt suid-sgid.txt    # only new entries
comm -23 BASELINE/suid-sgid.txt suid-sgid.txt    # only removed entries
```

A new entry has three legitimate explanations, and the audit record should name which one applies:

1. A package was installed. Check `dnf history list` for a transaction between the two runs, and `rpm -qf FILE` to match it.
2. A package was updated and gained a helper. Same check.
3. A human did it. Nothing else explains it, and it goes to incident handling (chapter 12).

> **Note.** Do not accept a new SUID binary into the baseline just because a package owns it. `pkexec` is package-owned and was a local root exploit for twelve years (CVE-2021-4034). The baseline is the list of SUID binaries **you decided to keep**, so a package that adds one needs the same review as any other privilege change (`CM-07(01)`).

#### Evidence

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `AC-06(10)` | SUID/SGID set matches the approved list | `diff -u BASELINE/suid.txt suid.txt` | No diff, or each line explained by a `dnf history` transaction |
| `CM-07(01)` | Every SUID file is package-owned | `rpm -qf` loop above | No `UNOWNED` lines |
| `CM-06` | No packaged SUID file altered | `rpm -Vf ...` | No `5` or `M` flags |

### File capabilities

File capabilities are SUID split into pieces: a binary gets one power (`cap_net_raw`) instead of all of root. They do not show up in `ls -l` and are missed by audits that only check SUID.

```bash
sudo getcap -r / 2>/dev/null
```

The Fedora 43 workstation set, verified with `getcap -r /usr`:

```text
/usr/bin/arping cap_net_raw=p
/usr/bin/clockdiff cap_net_raw=p
/usr/bin/newgidmap cap_setgid=ep
/usr/bin/newuidmap cap_setuid=ep
/usr/bin/suexec cap_setgid,cap_setuid=ep
/usr/bin/mtr-packet cap_net_raw=ep
/usr/libexec/sssd/krb5_child cap_dac_read_search,cap_setgid,cap_setuid=p
```

| Capability | Equivalent to | Verdict |
|---|---|---|
| `cap_net_raw`, `cap_net_bind_service` | Raw sockets, low ports | Low; expected on network tools |
| `cap_setuid`, `cap_setgid` | Becoming any user | Root-equivalent. Expected only on `newuidmap`/`newgidmap` (rootless containers) and known helpers |
| `cap_dac_override`, `cap_dac_read_search` | Ignoring file permissions (write, or read) | Root-equivalent for reading; `dac_read_search` reads `/etc/shadow` |
| `cap_sys_admin`, `cap_sys_module`, `cap_sys_ptrace` | Root | Never on a file outside a vendor-justified exception |

`suexec` is Apache's helper (`httpd` package). On a host that does not serve CGI, its presence is a `CM-07` finding in itself: remove the package rather than the capability, because the next update puts the capability back.

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `AC-06` | Capability set matches baseline | `getcap -r / \| sort \| diff -u BASELINE/filecaps.txt -` | No diff |
| `AC-06(10)` | No root-equivalent caps on unexpected files | `getcap -r / \| grep -E 'cap_(sys_admin\|sys_module\|sys_ptrace\|dac_override\|setuid)'` | Only the approved helpers |

### World-writable and unowned files

```bash
# World-writable regular files: each needs a reason
sudo find / -xdev -type f -perm -0002 2>/dev/null
# Files whose UID or GID maps to no account
sudo find / -xdev \( -nouser -o -nogroup \) 2>/dev/null
```

**Unowned files are an access-control problem, not tidiness.** When the account that owned them is deleted, the numeric UID stays on the files. The next account created with that UID owns them outright, including anything in a shared directory. That is why `AC-02` account removal needs a sweep for orphaned files (chapter 02 shows the `userdel` side).

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `AC-03` | No world-writable files outside temp dirs | `find / -xdev -type f -perm -0002` | Empty, or each path in an exceptions list |
| `AC-02` | No orphaned files | `find / -xdev \( -nouser -o -nogroup \)` | Empty |

### POSIX ACLs

An ACL grants access that the mode bits do not show. `ls -l` marks it with a trailing `+` and nothing more, so a mode-only audit calls `/etc/app/secret.conf` "0640 root:root, fine" while a named user has write access.

```bash
# Every path with entries beyond owner/group/other, absolute names, one filesystem
sudo getfacl -R -s -p --one-file-system /etc /srv /opt /var/lib /home 2>/dev/null > acls.txt

# Named entries that grant write, per file
awk '/^# file:/{f=substr($0,9)} /^(user|group):[^:]+:.w/{print f}' acls.txt | sort -u

# Default ACLs: inherited by every new file created below
awk '/^# file:/{f=substr($0,9)} /^default:/{print f}' acls.txt | sort -u
```

`-s` (`--skip-base`) is the flag that makes this usable: it prints only files that have extended entries. `-p` keeps the leading `/` so the output diffs against a baseline taken from another directory.

Three behaviours change the verdict:

- **The mask caps every named entry.** `user:deploy:rw-` with `mask::r--` is effectively read-only; `getfacl` prints `#effective:r--` next to it. Read the effective column, not the entry.
- **`chmod g=...` on a file with an ACL changes the mask, not the owning group's bits.** A well-meaning `chmod 640` can widen or narrow every named entry at once.
- **Default ACLs propagate.** A `default:group:devs:rwx` on `/srv/app` gives `devs` write access to every file created there from now on, including files root creates later.

> **Gotcha.** `cp` and `tar` drop ACLs unless told otherwise (`cp -a`, `tar --acls`), and so do many backup tools. A restored host can pass an ACL audit because the ACLs that the application needed are gone. The baseline diff catches that as "removed", which is why the diff shows both directions.

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `AC-03(04)` | Named write entries only where approved | the `awk` write filter above | Only paths in the ACL register |
| `AC-03(04)` | Default ACLs known | the `default:` filter above | Only approved shared dirs |
| `CM-06` | ACL set unchanged | `diff -u BASELINE/acls.txt acls.txt` | No diff |

### Homes and dotfiles

**A writable dotfile is code execution as that user**, and an admin's dotfile is code execution as root at their next `sudo`. Someone who can append to `~admin/.bashrc` can add an alias for `sudo` or a `PATH` entry, and wait.

```bash
# Home directory modes and owners for human accounts and root
getent passwd | awk -F: '($3>=1000 && $3<65534) || $1=="root" {print $6}' \
  | xargs -r sudo stat -c '%a %U %n'

# Startup files and credential files that others can write or read
for h in /root /home/*; do
  for f in .bashrc .bash_profile .profile .zshrc .zprofile .ssh .ssh/authorized_keys \
           .netrc .pgpass .docker/config.json .kube/config; do
    [ -e "$h/$f" ] && sudo stat -c '%a %U %n' "$h/$f"
  done
done
```

What passes:

| Path | Maximum mode | Why |
|---|---|---|
| Home directory | `700` (Fedora `HOME_MODE 0700`) | `711` lets others traverse to any file they can guess the name of |
| Shell startup files | `644`, owned by the user | Never group- or other-writable |
| `~/.ssh` | `700` | sshd's `StrictModes` refuses keys otherwise, which fails closed |
| `authorized_keys` | `600` | Same |
| `.netrc`, `.pgpass`, `.docker/config.json`, `.kube/config` | `600` | They hold passwords or tokens in plain text; `.docker/config.json` may hold registry credentials |

> **Gotcha.** `HOME_MODE` in `login.defs` applies only to homes `useradd` creates. Homes created by an installer, a configuration tool or an older release keep whatever mode they got. A Fedora 43 workstation checked for this chapter had `HOME_MODE 0700` and a home directory at `711`. Audit the actual mode, not the default.

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `AC-03` | Homes are private | `stat -c '%a' /home/*` | `700` |
| `AC-06(10)` | Admin startup files not writable by others | the loop above | No group or other write bit |
| `IA-05` | Credential files private | the loop above | `600` |

### SSH key inventory

`authorized_keys` is an account's second password list, and it **survives `passwd -l`** (chapter 02). The audit is a list of every key that can log in, with its fingerprint, reconciled against a register of who holds which key.

```bash
# Where sshd actually looks (needs root; upstream default: .ssh/authorized_keys .ssh/authorized_keys2)
sudo sshd -T | grep -iE '^(authorizedkeysfile|authorizedkeyscommand|trustedusercakeys|authorizedprincipalsfile)'

# Fingerprint every key, per user, one line each
for h in /root /home/*; do
  u=$(stat -c %U "$h")
  for k in "$h/.ssh/authorized_keys" "$h/.ssh/authorized_keys2"; do
    [ -r "$k" ] || continue
    grep -vE '^\s*(#|$)' "$k" | while read -r line; do
      printf '%s %s ' "$u" "$k"; ssh-keygen -lf /dev/stdin <<<"$line"
    done
  done
done
```

What to flag:

- **Any key on `root`.** With `PermitRootLogin no` (chapter 03) it is dead weight; without it, it is an unattributed root login that `auid` cannot trace to a person.
- **Keys with no matching register entry**, and keys belonging to people who have left. The register is the `AC-02` evidence; the fingerprint list proves it matches reality.
- **`authorized_keys2`.** OpenSSH's built-in default for `AuthorizedKeysFile` still lists it (`man sshd_config`); distro configs often override that, so trust `sshd -T`, not memory. Rarely reviewed either way.
- **`AuthorizedKeysCommand` set.** Keys then come from a program, not the file. Audit the program and its data source instead.
- **Keys without `from=` or `restrict` on service accounts.** A deploy key usable from anywhere is a wider grant than the deploy needs.

**Default: move humans to SSH certificates** (chapter 03). A certificate has an expiry and a key ID that appears in the auth log, which turns this inventory from "every key file on every host" into "the CA's signing log".

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `IA-05(02)` | Every key is registered | fingerprint loop, compared with the register | Every fingerprint maps to a current person or service |
| `AC-02` | No keys for departed users | same | None |
| `AC-06(05)` | No direct root keys | `sudo cat /root/.ssh/authorized_keys` | File absent or empty |

### Accounts and login shells

Chapter 02 has the inventory commands. The audit adds two things: a dated copy, and a diff.

```bash
getent passwd | awk -F: '{print $1":"$3":"$7":"$6}' | sort > accounts.txt
diff -u BASELINE/accounts.txt accounts.txt
awk -F: '$3==0 {print $1}' /etc/passwd                   # exactly: root
getent passwd | awk -F: '$3<1000 && $1!="root" && $7 !~ /(nologin|false|sync|shutdown|halt)$/'
sudo awk -F: '$2=="" {print $1}' /etc/shadow             # empty password field
lastlog2                                                 # last login per account (Fedora 43)
```

A system account with a real shell is a finding unless documented. Dormant human accounts (`lastlog2`) are the `AC-02` item assessors ask about first.

> **Version-sensitive.** Fedora 43 ships `lastlog2` (a SQLite-backed replacement that avoids the Y2038 limit of `/var/log/lastlog`). Older releases and RHEL 9 use `lastlog`. Both answer the same question.

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `AC-02` | Account list matches the approved list | `diff -u BASELINE/accounts.txt accounts.txt` | Every change has a ticket |
| `IA-04` | One UID 0 | `awk -F: '$3==0' /etc/passwd` | `root` only |
| `AC-02` | No dormant human accounts | `lastlog2` | No account unused past your defined period |

### Groups that equal root

The table of what each group grants is in chapter 02. For the audit, two things are easy to get wrong.

**Primary group membership is invisible in `getent group`.** A user whose primary GID is `docker` does not appear in the member list of `docker:x:967:`. Check both:

```bash
for g in wheel docker libvirt disk adm systemd-journal kvm; do
  line=$(getent group "$g") || continue
  gid=$(cut -d: -f3 <<<"$line")
  printf '%-16s members=%s primary=%s\n' "$g" "${line##*:}" \
    "$(getent passwd | awk -F: -v g="$gid" '$4==g{printf "%s ", $1}')"
done
```

**polkit can make a group root with no sudo rule at all.** Fedora's libvirt package ships `/usr/share/polkit-1/rules.d/50-libvirt.rules`, which returns `polkit.Result.YES` for `org.libvirt.unix.manage` to any member of `libvirt`, with no password (read on Fedora 43). `libvirt` membership is therefore passwordless root through a VM that mounts the host disk, and it leaves no sudo log.

`adm` and `systemd-journal` are not root, but they read the logs that are your `AU` evidence. Membership in them is an `AU-09`-shaped question (who can read audit information), so list it in the same review.

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `AC-06(05)` | Root-equivalent groups hold only named admins | the loop above | `docker`, `libvirt`, `disk` empty or matching the privileged-role list |
| `AC-02(07)` | Privileged membership reviewed | dated copy of the loop output, signed off | A review record each cycle |

### sudoers review

Chapter 02 covers writing rules. The audit reads what exists and asks four questions: does it parse, what does each user actually get, which rules need no password, and which rules are broader than they look.

```bash
sudo visudo -c                 # parse every file; non-zero exit on any error
sudo visudo -cs                # strict: an alias referenced but never defined is an error
sudo grep -rvhE '^\s*(#|$)' /etc/sudoers /etc/sudoers.d/     # effective lines
sudo find /etc/sudoers.d -type f \( -name '*.*' -o -name '*~' \)   # silently ignored files
for u in $(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1}'); do
  echo "### $u"; sudo -ll -U "$u"
done > sudo-l.txt
sudo sha256sum /etc/sudoers /etc/sudoers.d/* > sudoers.sha256
```

`sudo -ll -U USER` is the evidence that matters. It shows the result of every file, alias and group rule as it applies to that user, with `NOPASSWD` and the run-as user per rule. An assessor reads that, not the rule files.

#### The matching rules that make a rule broader

All of these are from `man sudoers` for sudo 1.9.17 (the Fedora 43 package):

| Rule as written | What it actually allows |
|---|---|
| `/usr/bin/systemctl` (no arguments) | **Any arguments.** A command with no arguments listed may be run with any |
| `/usr/bin/systemctl ""` | Only with no arguments at all |
| `/usr/bin/cat /var/log/*` | `*` matches across spaces and `/`, so `cat /var/log/../../etc/shadow` matches |
| `/opt/tools/` (trailing slash) | Any file in that directory, now or later |
| `^/usr/bin/systemctl restart [a-z]+\.service$` | A regular expression: args starting `^` and ending `$` are regex, which gives exact matching |
| `ALL` in the command position | Everything, including a shell |

**Default: rewrite wildcard argument rules as regex rules or `sudoedit`.** A regex anchored at both ends closes the `*` traversal hole; `sudoedit` removes the editor shell escape entirely.

#### NOPASSWD

`NOPASSWD` is not wrong in itself: a CI deploy user cannot type a password. It is wrong when the command it permits is broader than the job, or when the script it runs is writable by the user it is granted to. The audit for each `NOPASSWD` line:

1. Is the command exact (full path, fixed or regex-anchored arguments)?
2. Is the target, every directory above it and everything it sources owned by root and not group- or other-writable? The writable-chain check in the script does this.
3. Is the run-as user narrower than root (`(app)` rather than `(root)` or `(ALL)`)?

> **Gotcha.** A sudo rule that a human was "only going to use for a week" stays until someone removes it. Put `sudoers.d` in Git with a CI check (`visudo -cf FILE` on every file), and the diff between the repository and `sudoers.sha256` becomes `CM-05` evidence that nobody changed privileges outside review.

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `CM-06` | sudoers parses | `visudo -c` | `parsed OK` for every file, exit 0 |
| `AC-06(01)` | Each user's effective rights match their role | `sudo -ll -U USER` per user | Matches the role definition |
| `AC-06` | No shell-escape binaries, no unanchored wildcards | `grep` of effective lines | No editors, pagers, interpreters or `*` in arguments |
| `CM-05` | sudoers unchanged outside change control | `diff` of `sudoers.sha256` with the repository | Hashes match the reviewed commit |
| `AC-06(09)` | Privileged use logged | `journalctl _COMM=sudo --since -7d` (chapter 08) | Entries present and shipped off-host |

### polkit rules

polkit is the second privilege system, and it has two layers that disagree in an audit:

- `.policy` files (`/usr/share/polkit-1/actions/`) set each action's **implicit** authorization: `yes`, `auth_self`, `auth_admin`, `auth_admin_keep`, `no`.
- `.rules` files (`/etc/polkit-1/rules.d/`, `/usr/share/polkit-1/rules.d/`) are JavaScript that runs first and can return `YES` for anyone who matches.

```bash
# Actions any active local session can use with no authentication at all
pkaction --verbose | awk '/^[a-z].*:$/{a=$1} /implicit active: +yes/{print a}'

# Rules that can grant with no prompt; read each subject test
sudo grep -l 'Result.YES' /etc/polkit-1/rules.d/*.rules /usr/share/polkit-1/rules.d/*.rules

# Local (admin-written) rules: every one needs an owner and a reason
sudo ls -l /etc/polkit-1/rules.d/
cat /usr/share/polkit-1/rules.d/50-default.rules     # who counts as admin: unix-group:wheel
```

> **Gotcha.** `pkaction` shows only the `.policy` defaults. For `org.libvirt.unix.manage` it prints `implicit active: auth_admin_keep`, which reads as "needs an admin password", while `50-libvirt.rules` hands it to the whole `libvirt` group with no prompt (both read on Fedora 43). **Audit the rules directory, not just `pkaction`.** `/etc/polkit-1/rules.d/` is `root:polkitd 0750` on Fedora, so a non-root audit cannot see it and silently reports nothing.

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `AC-06(01)` | Local polkit rules are approved | `ls -l /etc/polkit-1/rules.d/` | Each file in the change record |
| `AC-03` | Passwordless grants known | `grep -l Result.YES` over both dirs | Every hit reviewed; group conditions match the privileged-role list |

### systemd units running as root

A root daemon with no sandbox is a root shell waiting for its first parsing bug. Chapter 06 shows how to sandbox a unit; the audit lists which running services are root and unsandboxed, worst first.

```bash
# Exposure score per unit as JSON (0.0 fully sandboxed, 10.0 none)
systemd-analyze security --no-pager --json=short > systemd-security.json

# Running services whose User= is empty or root and which do not use DynamicUser=
for u in $(systemctl list-units --type=service --state=running --no-legend --plain | awk '{print $1}'); do
  usr=$(systemctl show -p User --value "$u"); dyn=$(systemctl show -p DynamicUser --value "$u")
  if [ -z "$usr" -o "$usr" = root ] && [ "$dyn" != yes ]; then
    printf '%s %s\n' "$(jq -r --arg u "$u" '.[]|select(.unit==$u)|.exposure' systemd-security.json)" "$u"
  fi
done | sort -rn | head -20
```

Verified on systemd 258 (Fedora 43), where a workstation had 36 root services, the worst at 9.8. Normal for a desktop, which is why the verdict is per unit:

| Unit type | Expected | Action |
|---|---|---|
| Your own services | Under 5.0, under 2.0 if network-facing (chapter 06's targets) | Findings if over |
| Distro daemons whose job is privilege (`sshd`, `auditd`, `systemd-logind`) | High scores, accepted | Record the acceptance once, with reason |
| Third-party agents parsing untrusted input (EDR, exporters, backup agents) | Often 9.x | Drop-in with the sandbox directives that do not break it, or a documented vendor exception |
| Container engines (`docker.service`) | 9.x, and root by design | Chapter 15 |

`--threshold=N` (exposure times ten) makes `systemd-analyze security --offline=yes FILE` a CI gate on unit files before they ship, which is better `SC-39` evidence than any audit of a running host.

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `SC-39` | Own services sandboxed | `systemd-analyze security UNIT` | Exposure at or under your threshold |
| `AC-06` | Root services justified | the loop above | Each root unit in the accepted list |
| `CM-06` | Units gated before release | `systemd-analyze security --offline=yes --threshold=50 FILE` in CI | Pipeline passes |

### SELinux user mapping

Chapter 05 covers SELinux for services. For people, SELinux maps each Linux login to an SELinux user, and on a default Fedora or RHEL install every login maps to `unconfined_u`: **SELinux does not restrict humans at all.**

```bash
sudo semanage login -l        # Linux login -> SELinux user (needs root)
sudo semanage user -l         # SELinux users -> allowed roles and MLS range
id -Z                         # your current context
```

The confined users worth knowing:

| SELinux user | Can | Use for |
|---|---|---|
| `unconfined_u` | Everything DAC allows | The default; not least privilege |
| `staff_u` | Log in, use `sudo` into `sysadm_r` when a sudo rule says so | Admins: `AC-06(02)` separation between daily work and admin work |
| `user_u` | Log in; no `sudo`, no `su`, no SUID transitions to root | Non-admin humans on servers |
| `guest_u`, `xguest_u` | Terminal or browser only | Kiosks |

With `staff_u`, a sudo rule can pin the role and type (`%admins ALL=(ALL) TYPE=sysadm_t ROLE=sysadm_r ALL`), so even root from sudo runs in a domain the policy constrains.

> **Version-sensitive.** Confining admins with `staff_u` works on current Fedora and RHEL 9, but some tools (for example rootless Podman, and anything that expects `unconfined_t`) behave differently under confined users. Pilot on one admin account first. The audit finding is not "everyone must be confined"; it is "the mapping is a decision on record".

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `AC-06(02)` | Admin logins mapped as decided | `semanage login -l` | Matches the documented mapping |
| `AC-03` | SELinux enforcing | `getenforce` | `Enforcing` |

### cron and timer ownership

**Anything root runs on a schedule is only as protected as the least-protected path in its chain.** If root's cron runs `/opt/app/bin/cleanup.sh` and `/opt/app/bin` is owned by the app user, the app user is root by Tuesday. This is a `CM-05` question: who can change what root executes?

```bash
# Where scheduled root work lives
sudo ls -l /etc/crontab /etc/cron.d /etc/cron.{hourly,daily,weekly,monthly} /var/spool/cron
sudo cat /etc/cron.allow /etc/cron.deny 2>/dev/null
for u in $(getent passwd | cut -d: -f1); do sudo crontab -l -u "$u" 2>/dev/null | sed "s/^/$u: /"; done
systemctl list-timers --all --no-pager
systemctl show -p User,ExecStart SERVICE     # for each timer's service

# The writable-chain check: the file and every parent must be root-owned
# and not other-writable (group-writable only if the group is root)
p=/opt/app/bin/cleanup.sh
while [ "$p" != / ]; do stat -L -c '%a %U:%G %n' "$p"; p=$(dirname "$p"); done
```

Fedora 43 ships `/etc/crontab` as `600`, `/etc/cron.d` and `/var/spool/cron` as `700`, all `root:root` (verified). A wider mode on any of them lets users read root's schedule, which is reconnaissance for exactly this attack.

`systemctl show -p ExecStart` prints `path=` per command. Some units give a bare name (`systemd-tmpfiles-clean.service` shows `path=systemd-tmpfiles`), so resolve it with `command -v` before walking the chain; the script does.

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `CM-05` | Root cron and timer targets not writable by others | writable-chain check per target | Every link `root`-owned, no other-write |
| `AC-03` | Cron spool and config private | `stat` on the paths above | Fedora defaults or tighter |
| `AC-06` | Only approved users may use cron | `cron.allow` exists and lists them | Present and minimal |

### The audit script

Read-only: it runs `find`, `stat`, `getfacl`, `getcap`, `rpm -qf`, `visudo -c`, `sudo -l -U`, `systemd-analyze security`, `semanage login -l` and friends, and writes only into its output directory. Run it as root; as a normal user it still runs and marks what it could not see. Checked with `shellcheck` and run on Fedora 43 (non-root, `SCAN_ROOTS=/etc`, and with `-b` against that run).

```bash
sudo ./perm-audit.sh -o /var/tmp/perm-audit-$(date +%F)          # first run: this is the baseline
sudo ./perm-audit.sh -o /var/tmp/perm-audit-$(date +%F) -b BASELINE_DIR   # later runs
```

```bash
#!/usr/bin/env bash
# perm-audit.sh: read-only permission and privilege audit for one Linux host.
# Writes inventories plus REPORT.txt to an output directory. Changes nothing else.
#
#   sudo ./perm-audit.sh                          # audit, report in ./perm-audit-HOST-DATE
#   sudo ./perm-audit.sh -o /srv/evidence/run1    # choose the output directory
#   sudo ./perm-audit.sh -b /srv/evidence/base    # audit, then diff against a baseline run
#   SCAN_ROOTS="/etc /usr" ./perm-audit.sh        # limit the filesystem walk (testing)
#
# Run as root for a complete result; as a normal user it still runs and marks gaps.
set -uo pipefail
export LC_ALL=C

OUT="./perm-audit-$(hostname -s)-$(date +%Y%m%d-%H%M%S)"
BASE=""
while getopts "o:b:h" opt; do
  case "$opt" in
    o) OUT=$OPTARG ;;
    b) BASE=$OPTARG ;;
    *) sed -n '2,12p' "$0"; exit 0 ;;
  esac
done

umask 077
mkdir -p "$OUT" || exit 1
R="$OUT/REPORT.txt"
: >"$R"

say()  { printf '%s\n' "$*" >>"$R"; }
flag() { printf 'FLAG  %s\n' "$*" >>"$R"; }
sect() { printf '\n== %s\n' "$*" >>"$R"; }
count() { if [[ -s $1 ]]; then wc -l <"$1"; else echo 0; fi; }

[[ $EUID -eq 0 ]] || say "WARNING: not root; shadow, sudoers, other users' homes and cron spools are incomplete."
say "host=$(hostname -f 2>/dev/null || hostname) kernel=$(uname -r) date=$(date -Is) uid=$EUID"

# Local, real filesystems only. Each btrfs subvolume is its own mount, so walk every one.
if [[ -n ${SCAN_ROOTS:-} ]]; then
  read -r -a ROOTS <<<"$SCAN_ROOTS"
else
  mapfile -t ROOTS < <(findmnt -rn -o TARGET -t ext4,xfs,btrfs | sort -u)
fi
say "scan roots: ${ROOTS[*]}"
walk() { local r; for r in "${ROOTS[@]}"; do find "$r" -xdev "$@" 2>/dev/null; done | sort -u; }

# ---------- DAC: SUID/SGID, capabilities, world-writable, unowned ----------
sect "SUID/SGID binaries (AC-06, CM-07)"
walk -type f -perm -4000 >"$OUT/suid.txt"
walk -type f -perm -2000 >"$OUT/sgid.txt"
say "suid=$(count "$OUT/suid.txt") sgid=$(count "$OUT/sgid.txt")"
while read -r f; do
  if ! rpm -qf "$f" >/dev/null 2>&1; then flag "SUID/SGID not owned by any package: $f"; fi
done < <(cat "$OUT/suid.txt" "$OUT/sgid.txt" | sort -u)

sect "File capabilities (AC-06)"
for r in "${ROOTS[@]}"; do getcap -r "$r" 2>/dev/null; done | sort -u >"$OUT/filecaps.txt"
say "files with capabilities=$(count "$OUT/filecaps.txt")"
grep -E 'cap_(sys_admin|sys_module|sys_ptrace|dac_override|setuid|setgid)' "$OUT/filecaps.txt" \
  | while read -r l; do flag "powerful file capability: $l"; done

sect "World-writable (AC-03, CM-06)"
walk -type f -perm -0002 ! -path '/proc/*' ! -path '/sys/*' >"$OUT/ww-files.txt"
walk -type d -perm -0002 ! -perm -1000 >"$OUT/ww-dirs-nosticky.txt"
walk -type d -perm -2000 >"$OUT/setgid-dirs.txt"
say "world-writable files=$(count "$OUT/ww-files.txt") world-writable dirs without sticky=$(count "$OUT/ww-dirs-nosticky.txt") setgid dirs=$(count "$OUT/setgid-dirs.txt")"
head -20 "$OUT/ww-dirs-nosticky.txt" | while read -r d; do flag "world-writable dir without sticky bit: $d"; done
for d in /tmp /var/tmp /dev/shm; do
  [[ -d $d ]] && [[ $(stat -c %a "$d") != 1777 ]] && flag "$d mode is $(stat -c %a "$d"), expected 1777"
done

sect "Unowned files (AC-02, CM-08)"
walk \( -nouser -o -nogroup \) >"$OUT/unowned.txt"
say "unowned files=$(count "$OUT/unowned.txt")"

sect "POSIX ACLs (AC-03(04))"
for d in /etc /srv /opt /var/lib /home; do
  [[ -d $d ]] && getfacl -R -s -p --one-file-system "$d" 2>/dev/null
done >"$OUT/acls.txt"
grep -c '^# file:' "$OUT/acls.txt" | sed 's/^/paths with extended ACLs=/' >>"$R"
awk '/^# file:/{f=substr($0,9)} /^default:/{print "default ACL on: " f}' "$OUT/acls.txt" | sort -u >>"$R"
awk '/^# file:/{f=substr($0,9)} /^(user|group):[^:]+:.w/{print f}' "$OUT/acls.txt" | grep '^/etc' | sort -u \
  | while read -r l; do flag "named ACL entry grants write under /etc: $l"; done

# ---------- Critical file modes ----------
sect "Critical file modes (AC-03, CM-06)"
check_mode() { # path max_octal owner
  local p=$1 max=$2 own=$3 m o
  [[ -e $p ]] || return 0
  m=$(stat -c %a "$p"); o=$(stat -c %U:%G "$p")
  echo "$m $o $p" >>"$OUT/critical-modes.txt"
  (( 8#$m & ~8#$max )) && flag "$p mode $m exceeds $max"
  [[ $o == "$own" ]] || flag "$p owned by $o, expected $own"
}
: >"$OUT/critical-modes.txt"
check_mode /etc/passwd 644 root:root
check_mode /etc/group 644 root:root
check_mode /etc/shadow 0 root:root
check_mode /etc/gshadow 0 root:root
check_mode /etc/sudoers 440 root:root
check_mode /etc/sudoers.d 750 root:root
check_mode /etc/ssh/sshd_config 600 root:root
check_mode /etc/crontab 600 root:root
check_mode /etc/cron.d 700 root:root
check_mode /var/spool/cron 700 root:root
say "umask (login.defs): $(awk '/^UMASK/{print $2}' /etc/login.defs)  HOME_MODE: $(awk '/^HOME_MODE/{print $2}' /etc/login.defs)"

# ---------- Accounts, groups that equal root ----------
sect "Accounts (AC-02, IA-02, IA-04)"
getent passwd | awk -F: '{print $1":"$3":"$7":"$6}' | sort >"$OUT/accounts.txt"
awk -F: '$3==0 && $1!="root"{print "FLAG  UID 0 account: "$1}' /etc/passwd >>"$R"
getent passwd | awk -F: '$3<1000 && $1!="root" && $7 !~ /(nologin|false|sync|shutdown|halt)$/ {print "FLAG  system account with a login shell: "$1" "$7}' >>"$R"
if [[ -r /etc/shadow ]]; then
  awk -F: '$2=="" {print "FLAG  empty password field: "$1}' /etc/shadow >>"$R"
fi

sect "Groups that equal root (AC-06(05), AC-02(07))"
: >"$OUT/priv-groups.txt"
for g in wheel sudo docker libvirt disk adm systemd-journal kvm lxd; do
  line=$(getent group "$g") || continue
  echo "$line" >>"$OUT/priv-groups.txt"
  members=${line##*:}
  primaries=$(getent passwd | awk -F: -v gid="$(cut -d: -f3 <<<"$line")" '$4==gid{printf "%s,", $1}')
  say "$g: ${members:-<none>} ${primaries:+(primary: ${primaries%,})}"
  case $g in docker|libvirt|disk|lxd) [[ -n $members$primaries ]] && flag "root-equivalent group $g has members: $members$primaries" ;; esac
done

# ---------- sudo and polkit ----------
sect "sudoers (AC-06, AC-06(09), CM-05)"
if [[ -r /etc/sudoers ]]; then
  if visudo -c >"$OUT/visudo.txt" 2>&1; then say "visudo -c: OK"; else flag "visudo -c failed (see visudo.txt)"; fi
  cat /etc/sudoers /etc/sudoers.d/* 2>/dev/null | grep -vE '^\s*(#|$)' >"$OUT/sudoers-effective.txt"
  sha256sum /etc/sudoers /etc/sudoers.d/* 2>/dev/null >"$OUT/sudoers.sha256"
  find /etc/sudoers.d -maxdepth 1 -type f \( -name '*.*' -o -name '*~' \) 2>/dev/null \
    | while read -r f; do flag "sudoers.d file is silently ignored (dot or ~ in name): $f"; done
  grep -nE 'NOPASSWD' "$OUT/sudoers-effective.txt" | while read -r l; do flag "NOPASSWD: $l"; done
  grep -nE '\(ALL(:ALL)?\)\s*(NOPASSWD:\s*)?ALL\s*$' "$OUT/sudoers-effective.txt" | while read -r l; do say "full root rule: $l"; done
  grep -nE '/(vi|vim|nano|less|more|man|find|awk|tar|zip|git|python[0-9.]*|perl|env|rsync|bash|sh|su)\b' "$OUT/sudoers-effective.txt" \
    | while read -r l; do flag "sudo rule names a shell-escape binary: $l"; done
  grep -nE '/[^ ,]*\*' "$OUT/sudoers-effective.txt" | while read -r l; do flag "wildcard in a sudo command: $l"; done
  getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1}' | while read -r u; do
    printf '### %s\n' "$u"; sudo -l -U "$u" 2>&1
  done >"$OUT/sudo-l.txt"
else
  say "sudoers not readable: run as root"
fi

sect "polkit (AC-06, AC-03)"
ls -l /etc/polkit-1/rules.d/ /usr/share/polkit-1/rules.d/ >"$OUT/polkit-rules.txt" 2>&1
grep -l 'Result.YES' /etc/polkit-1/rules.d/*.rules /usr/share/polkit-1/rules.d/*.rules 2>/dev/null \
  | while read -r f; do say "rule can return YES with no prompt (read its subject test): $f"; done
find /etc/polkit-1/rules.d -type f 2>/dev/null | while read -r f; do say "local polkit rule: $f"; done

# ---------- Homes, dotfiles, SSH keys ----------
sect "Home directories and dotfiles (AC-03, IA-05)"
: >"$OUT/homes.txt"; : >"$OUT/authorized_keys.txt"
getent passwd | awk -F: '$3>=1000 && $3<65534 || $1=="root" {print $1":"$6}' | while IFS=: read -r u h; do
  [[ -d $h ]] || continue
  m=$(stat -c %a "$h"); o=$(stat -c %U "$h")
  echo "$m $o $h" >>"$OUT/homes.txt"
  (( 8#$m & 8#027 )) && flag "home $h is mode $m (group or other bits set)"
  [[ $o == "$u" ]] || flag "home $h owned by $o, not $u"
  for f in .bashrc .bash_profile .profile .zshrc .zprofile .ssh .ssh/authorized_keys .ssh/config .netrc .pgpass .docker/config.json .kube/config; do
    p="$h/$f"; [[ -e $p ]] || continue
    pm=$(stat -c %a "$p"); po=$(stat -c %U "$p")
    (( 8#$pm & 8#022 )) && flag "$p is group/other-writable ($pm)"
    case $f in .netrc|.pgpass|.docker/config.json|.kube/config|.ssh/authorized_keys)
      (( 8#$pm & 8#077 )) && flag "$p readable by others ($pm)" ;; esac
    [[ $po == "$u" || $po == root ]] || flag "$p owned by $po, not $u"
  done
  for k in "$h/.ssh/authorized_keys" "$h/.ssh/authorized_keys2"; do
    [[ -r $k ]] || continue
    while read -r line; do
      [[ -z $line || $line == \#* ]] && continue
      fp=$(ssh-keygen -lf /dev/stdin <<<"$line" 2>/dev/null | awk '{print $1" "$2" "$4}')
      opts=$(grep -oE '^(command|from|restrict|no-[a-z-]+|permitopen|expiry-time)[^ ]*' <<<"$line")
      echo "$u $k ${fp:-UNPARSEABLE} ${opts:+opts=$opts}" >>"$OUT/authorized_keys.txt"
    done <"$k"
  done
done
say "authorized keys found=$(count "$OUT/authorized_keys.txt")"
grep -E '^root ' "$OUT/authorized_keys.txt" | while read -r l; do flag "root has an authorized key: $l"; done

# ---------- systemd units running as root, unsandboxed ----------
sect "systemd services as root (AC-06, SC-39, CM-07)"
: >"$OUT/root-services.txt"
systemd-analyze security --no-pager --json=short 2>/dev/null >"$OUT/systemd-security.json"
systemctl list-units --type=service --state=running --no-legend --plain | awk '{print $1}' | while read -r u; do
  usr=$(systemctl show -p User --value "$u"); dyn=$(systemctl show -p DynamicUser --value "$u")
  [[ -z $usr || $usr == root ]] && [[ $dyn != yes ]] || continue
  exp=$(jq -r --arg u "$u" '.[] | select(.unit==$u) | .exposure' "$OUT/systemd-security.json" 2>/dev/null)
  echo "${exp:-?} $u" >>"$OUT/root-services.txt"
done
sort -rn -o "$OUT/root-services.txt" "$OUT/root-services.txt"
say "running services as root=$(count "$OUT/root-services.txt"); worst five:"
head -5 "$OUT/root-services.txt" >>"$R"

# ---------- cron and timers: ownership and writable paths ----------
sect "cron and timers (CM-05, AC-06)"
writable_chain() { # flag if the file or any parent dir is writable by non-root
  local p=$1
  while [[ -n $p && $p != / ]]; do
    if [[ -e $p ]]; then
      local m o g; m=$(stat -L -c %a "$p"); o=$(stat -L -c %U "$p"); g=$(stat -L -c %G "$p")
      if [[ $o != root ]] || (( 8#$m & 8#002 )) || { [[ $g != root ]] && (( 8#$m & 8#020 )); }; then
        echo "$p ($o:$g $m)"; return 0
      fi
    fi
    p=$(dirname "$p")
  done
  return 1
}
{
  ls -l /etc/crontab /etc/cron.d /etc/cron.{hourly,daily,weekly,monthly} /var/spool/cron /var/spool/at 2>/dev/null
} >"$OUT/cron-files.txt"
grep -hvE '^\s*(#|$|[A-Z_]+=)' /etc/crontab /etc/cron.d/* 2>/dev/null \
  | awk '$6=="root"{for(i=7;i<=NF;i++) if($i ~ /^\//){print $i; break}}' \
  | sort -u | while read -r cmd; do
      w=$(writable_chain "$cmd") && flag "root cron runs $cmd but $w is writable by non-root"
    done
for f in /etc/cron.{hourly,daily,weekly,monthly}/*; do
  [[ -f $f ]] || continue
  w=$(writable_chain "$f") && flag "cron script $f: $w writable by non-root"
done
systemctl list-timers --all --no-legend --plain 2>/dev/null >"$OUT/timers.txt"
systemctl list-timers --all --output=json 2>/dev/null | jq -r '.[].activates' 2>/dev/null | while read -r svc; do
  usr=$(systemctl show -p User --value "$svc"); [[ -z $usr || $usr == root ]] || continue
  for exe in $(systemctl show -p ExecStart --value "$svc" | grep -oE 'path=[^ ;]+' | cut -d= -f2); do
    [[ $exe == /* ]] || exe=$(command -v "$exe") || continue
    w=$(writable_chain "$exe") && flag "timer $svc runs $exe as root; $w writable by non-root"
  done
done

# ---------- SELinux user mapping ----------
sect "SELinux login mapping (AC-03(04), AC-06)"
say "mode: $(getenforce 2>/dev/null || echo unknown)"
if semanage login -l >"$OUT/semanage-login.txt" 2>&1; then
  awk 'NR>2 && $2=="unconfined_u"{print "unconfined login: "$1}' "$OUT/semanage-login.txt" >>"$R"
else
  say "semanage login -l needs root"
fi

# ---------- Baseline diff ----------
if [[ -n $BASE ]]; then
  sect "Diff against baseline $BASE (CM-02, CM-06(03)-style drift)"
  for f in suid.txt sgid.txt filecaps.txt ww-files.txt ww-dirs-nosticky.txt unowned.txt priv-groups.txt \
           accounts.txt sudoers.sha256 authorized_keys.txt root-services.txt critical-modes.txt; do
    [[ -f $BASE/$f ]] || { say "$f: not in baseline"; continue; }
    if ! diff -u "$BASE/$f" "$OUT/$f" >"$OUT/diff-$f" 2>/dev/null; then
      add=$(grep -c '^+[^+]' "$OUT/diff-$f"); del=$(grep -c '^-[^-]' "$OUT/diff-$f")
      flag "$f changed: +$add -$del (see diff-$f)"
    else
      rm -f "$OUT/diff-$f"; say "$f: unchanged"
    fi
  done
fi

sect "Summary"
say "flags=$(grep -c '^FLAG' "$R")"
( cd "$OUT" && sha256sum -- *.txt *.json 2>/dev/null >SHA256SUMS )
echo "report: $R  ($(grep -c '^FLAG' "$R") flags)"
```

What it produces:

| File | Contents | Control evidence |
|---|---|---|
| `REPORT.txt` | Counts per section and every `FLAG` line | Summary for the review record |
| `suid.txt`, `sgid.txt`, `filecaps.txt` | Sorted inventories | `AC-06(10)`, `CM-07(01)` |
| `ww-files.txt`, `ww-dirs-nosticky.txt`, `unowned.txt` | Sorted inventories | `AC-03`, `AC-02` |
| `acls.txt` | Every extended ACL | `AC-03(04)` |
| `accounts.txt`, `priv-groups.txt`, `authorized_keys.txt` | Account, group and key inventories | `AC-02`, `AC-06(05)`, `IA-05(02)` |
| `sudoers-effective.txt`, `sudo-l.txt`, `sudoers.sha256` | Effective rules and per-user rights | `AC-06(01)`, `CM-05` |
| `systemd-security.json`, `root-services.txt` | Exposure per unit, root services | `SC-39`, `AC-06` |
| `diff-*.txt` | Changes since the baseline (with `-b`) | `CM-06`, `AC-06(07)` |
| `SHA256SUMS` | Hash of every output file | Integrity of the evidence itself |

#### Handling the output

Copy the directory off the host the same day, to the evidence store chapter 17 builds; a report left on the audited host can be edited by whoever it is about. It lists accounts, keys and weak spots, so handle it at the system's classification (chapter 17). Keep the baseline off-host too and pass it back read-only with `-b`. Keep every run for at least a year (the CPCSC Level 1 minimum for account lists and access reviews). **Record a verdict for every `FLAG`**: fixed, accepted with reason and expiry, or false positive. An unexplained flag in last quarter's report is the first thing an assessor asks about.

### Traps

- `find / -xdev` on Fedora skips `/home` (separate btrfs subvolume). Walk every mount.
- `getent group` omits users whose **primary** group is the privileged one.
- `pkaction` shows `.policy` defaults; a `.rules` file can grant the same action to a whole group with no prompt.
- A non-root audit sees no `/etc/polkit-1/rules.d`, no sudoers, no shadow and no other homes, and reports "nothing found".
- ACL entries are capped by the mask; read `#effective`, not the entry.
- Backups and `cp` without `-a` strip ACLs, so a restored host can "pass".
- `HOME_MODE` applies only to new homes; audit the real mode.
- A sudo command with no arguments listed permits **any** arguments; `""` means none.
- `authorized_keys` survives `passwd -l`; `authorized_keys2` is often forgotten.
- A root cron job is as safe as the least-protected directory above its script.
- A baseline stored on the audited host proves nothing.



---


<a id="15-container-hardening-from-the-inside"></a>

## 15 · Container hardening, from the inside

*A container gets exactly the isolation its runtime configured and nothing more. Namespaces decide what it can see, capabilities and seccomp what it can do, SELinux what it can touch, cgroups how much it can use, and the kernel underneath is shared. An audit reads each of those back from the host, because the defaults leave several of them open.*

### Scope

This chapter covers the security internals and the audit angle: what each isolation layer actually does, which control it satisfies, and the command that proves it. **How to write a hardened `docker run`, a hardened `daemon.json` or a signing pipeline is in the Docker Field Manual**, and this chapter links there instead of repeating it:

| You want to | Go to |
|---|---|
| Harden one container: caps, seccomp, read-only rootfs, limits, rootless | Docker Field Manual, chapter 07 (Runtime security: least privilege) |
| Harden `dockerd`: `daemon.json`, socket, TLS, auditd rule file, docker-bench flags | Docker Field Manual, chapter 08 (Host and daemon hardening) |
| Scan, SBOM, sign, verify | Docker Field Manual, chapter 09 (Image supply chain) |
| SELinux labels, `:z`/`:Z`, `udica` | Chapter 05, SELinux in practice |
| The controls and profiles themselves | Chapter 13, Canadian requirements |
| Pods, PSA, RBAC, kube-bench | Chapter 16, Kubernetes security audit and hardening |

### The isolation stack

```text
   container process (PID 1 inside, e.g. PID 4048079 on the host)
   │
   ├─ user namespace ........ is container UID 0 host UID 0?   rootful Docker: yes
   ├─ pid/mnt/net/ipc/uts/cgroup namespaces ... what it can SEE
   ├─ capability bounding set  ................ which root powers survive
   ├─ no_new_privs  .......................... can setuid/file caps raise it again?
   ├─ seccomp filter  ........................ which syscalls reach the kernel
   ├─ SELinux: container_t:s0:cX,cY  ......... which files/ports/processes it may touch
   ├─ cgroup v2 (memory.max, pids.max, cpu.max) how much it may consume
   ▼
   ONE SHARED KERNEL  ◀── every container on the host, and the host itself
```

**The last line is the point.** Every layer above is a kernel feature filtering one process, and a kernel bug bypasses all of them at once. That is why ITSP.80.023 says containers "should be segmented based on their relative security context to ensure that a given system kernel only runs containers with the same data sensitivity and functionality." No amount of hardening makes a container host safe for mixing Protected B workloads with an internet-facing scraper. That segmentation decision comes first; everything below is about making each container as small a target as possible.

#### What you get by default

Defaults on this Fedora 43 host, docker-ce 29.8.1 with no `daemon.json` and Podman 5.8.4 rootless, all verified:

| Layer | Docker (rootful, defaults) | Podman (rootless, Fedora defaults) | Read it back |
|---|---|---|---|
| User namespace | **Off**: container root is host root (`/proc/PID/uid_map` is `0 0 4294967295`) | On: container UID 0 is your UID, 1–65536 map to your `/etc/subuid` range | `cat /proc/PID/uid_map` |
| Namespaces | pid, mnt, net, ipc, uts, cgroup private | Same | `sudo lsns -p PID` |
| Capabilities | **14** (`CapEff 00000000a80425fb`) | **11** (`00000000800405fb`) | `grep Cap /proc/PID/status` |
| The three Docker adds | `NET_RAW`, `MKNOD`, `AUDIT_WRITE` | Absent | `capsh --decode=MASK` |
| seccomp | Builtin profile (`name=seccomp,profile=builtin`) | `/usr/share/containers/seccomp.json`, `defaultAction SCMP_ACT_ERRNO` | `grep Seccomp: /proc/PID/status` (2 = filter) |
| no-new-privileges | Off | Off, and no `containers.conf` key to turn it on | `grep NoNewPrivs /proc/PID/status` |
| SELinux | **`spc_t`** (unconfined) unless `"selinux-enabled": true` | `container_t` with an MCS pair (`label = true` default) | `ps -o label= -p PID` |
| cgroup limits | None: `memory.max` and `pids.max` unlimited, `PidsLimit null` | `pids_limit = 2048`, no memory or CPU cap | `/sys/fs/cgroup/.../memory.max` |

> **Gotcha.** Docker's own defaults on Fedora give you **no SELinux confinement**. On a stock docker-ce install with no `daemon.json`, `selinux-enabled` is off and running containers typically carry the process label `spc_t` (unconfined), with a few as `container_runtime_t`; containers started with `--security-opt seccomp=unconfined` show `Seccomp: 0`, meaning no filter at all. Podman on the same host confines by default. **`getenforce` saying `Enforcing` tells you nothing about whether your containers are confined.** Read the process labels.

### Each layer, and how to read it back

Every check here reads the kernel's view of the process, not the engine's view of its config. **Inspect output shows what was requested; `/proc` shows what the kernel did.** An audit wants both, and a mismatch between them is itself a finding.

```bash
PID=$(docker inspect -f '{{.State.Pid}}' CONTAINER)    # podman inspect -f '{{.State.Pid}}' works too
```

#### Namespaces

A namespace gives the process its own copy of one kernel resource. A container shares a namespace with the host when its ID matches PID 1's:

```bash
sudo readlink /proc/1/ns/{pid,net,ipc,uts,mnt,cgroup,user}
sudo readlink /proc/$PID/ns/{pid,net,ipc,uts,mnt,cgroup,user}
sudo lsns -p $PID          # the same, tabulated
```

| Shared namespace | What the container gains | Flag that does it |
|---|---|---|
| net | Every host interface and listening socket, including `127.0.0.1` services | `--network host` |
| pid | Sees and can signal every host process; with `SYS_PTRACE`, reads their memory | `--pid host` |
| ipc | Host shared memory segments | `--ipc host` |
| uts | Can change the host's hostname (with `SYS_ADMIN`) | `--uts host` |
| user | Container root is host root | Rootful Docker default, `--userns host` |

#### cgroups v2

cgroups are the resource budget. This host runs cgroup v2 with the systemd driver; each Docker container is a scope under `system.slice`:

```bash
cat /sys/fs/cgroup/cgroup.controllers
# cpuset cpu io memory hugetlb pids rdma misc dmem
CID=$(docker inspect -f '{{.Id}}' CONTAINER)
cat /sys/fs/cgroup/system.slice/docker-$CID.scope/{memory.max,pids.max,cpu.max}
# max / 66931 / max 100000   <- no memory cap, pid cap is the host's, no CPU quota
```

`max` means unlimited. **An unlimited container can take the host down with a fork bomb or a leak**, which is an availability control (`SC-06`, resource availability; not selected in the Medium profile, but the CIS checks 5.11, 5.12 and 5.29 expect limits).

#### Capabilities

Root's powers split into about 40 capabilities. The bounding set is the ceiling; nothing inside the container can gain a capability outside it.

```bash
sudo grep -E '^Cap(Eff|Bnd)' /proc/$PID/status
capsh --decode=00000000a80425fb     # Docker's default 14
capsh --decode=00000000800405fb     # Podman's default 11
```

The Docker-only three are the interesting ones for an audit. `NET_RAW` allows ARP and ICMP spoofing against neighbours on the same bridge; `MKNOD` creates device nodes; `AUDIT_WRITE` writes into the host audit log. **Podman's set is the better starting point; neither is least privilege.** The least-privilege position is `--cap-drop ALL` and add back the one that fails (Docker Field Manual, chapter 07).

#### seccomp

seccomp is a syscall filter attached to the process. Docker's builtin profile and Podman's `seccomp.json` both deny by default (`SCMP_ACT_ERRNO`) and allow a list; the blocked set includes `kexec_load`, `init_module`, `mount`, `bpf` for unprivileged callers and namespace-creating `unshare`.

```bash
sudo grep -E '^Seccomp(_filters)?:' /proc/$PID/status
# Seccomp: 2   (filter active)     Seccomp: 0   (none: unconfined or --privileged)
```

`seccomp=unconfined` removes the filter, and `--privileged` removes it silently: a privileged container shows `Seccomp: 0` without anyone having asked for it.

#### SELinux: container_t and MCS

Chapter 05 explains `container_t`, the MCS category pair (`s0:c214,c753`) that keeps two containers apart, and `:z`/`:Z`. For the audit, three labels matter:

| Label on the container process | Meaning |
|---|---|
| `container_t:s0:cX,cY` | Confined, separated from other containers by categories |
| `spc_t` | "Super privileged container": **unconfined**. What `--privileged`, `label=disable` and docker-ce without `selinux-enabled` give you |
| `container_runtime_t` | The engine's own domain; a workload process should not have it |

```bash
ps -eo pid,label,comm | grep -E 'container_t|spc_t|container_runtime_t'
docker inspect -f '{{.Name}} {{.ProcessLabel}}' $(docker ps -q)   # empty ProcessLabel = no label applied
```

#### no-new-privileges

`PR_SET_NO_NEW_PRIVS` stops setuid binaries and file capabilities from raising privilege after exec. It closes the "drop a setuid shell into `/tmp`" route and costs almost nothing.

```bash
sudo grep NoNewPrivs /proc/$PID/status     # 1 = set
```

#### User namespaces and rootless

With a user namespace, container UID 0 maps to an unprivileged host UID, so an escape lands as nobody in particular. **This is the single largest reduction in blast radius available, and rootful Docker does not do it by default.**

```bash
sudo cat /proc/$PID/uid_map
#          0          0 4294967295     <- no user namespace: container root is host root
#          0       1001          1     <- rootless Podman: container root is UID 1001
#          1     589824      65536        and the rest map into /etc/subuid
podman info --format '{{.Host.Security.Rootless}}'           # true
docker info --format '{{.SecurityOptions}}'                  # contains name=rootless or name=userns if on
```

**Default pick: Podman rootless** for anything that does not need a shared root daemon, which on a Fedora host is most things. Rootless Docker is the alternative when tooling insists on the Docker API; `userns-remap` is the least attractive option on Docker 29 (it loses the containerd image store; Docker Field Manual, chapter 08, explains why).

### Controls, mapped to layers

IDs from ITSP.10.033; "Medium" is selection in ITSP.10.033-01, read from the profile PDF. The container meaning is this manual's reading, not an official mapping (none exists; chapter 13).

| Control | Medium | Container meaning | Setting | Evidence |
|---|---|---|---|---|
| `AC-06` Least privilege | Selected | No privileged containers, caps dropped, non-root user, no socket mounts | `--cap-drop ALL`, `--user`, no `--privileged` | Audit script findings; docker-bench 5.4, 5.5, 5.32 |
| `AC-06(05)` Privileged accounts | Selected | `docker` group is root; its members are privileged accounts | Group kept to named admins, or rootless | `getent group docker` (chapter 14) |
| `CM-07` Least functionality | Selected | Minimal images, no sshd, only needed ports, no host namespaces | Distroless or minimal base; `127.0.0.1:` publishes | Image SBOM package count; docker-bench 5.7, 5.9, 5.10 |
| `CM-02` / `CM-06` Baseline and settings | Selected | `daemon.json` and `containers.conf` are the documented baseline | Docker Field Manual chapter 08 file | `docker info` fields; docker-bench section 2 |
| `CM-08` Component inventory | Selected | Every image's contents are known | SBOM per digest | Syft SBOM file per release |
| `SC-39` Process isolation | Selected | Namespaces, seccomp, SELinux MCS: separate execution domains | Private namespaces, seccomp on, `container_t` | `/proc/PID/status`, `ps -Z`, `lsns` |
| `SC-07` Boundary protection | Selected | Published ports and host networking | No `--network host`, loopback publishes | Inspect `PortBindings`; `ss -tlnp` |
| `SI-07` Integrity | Selected | Image is exactly what was scanned and signed; container cannot modify itself | Digest pinning, `--read-only`, signature verification | `cosign verify` output; `ReadonlyRootfs` |
| `SI-07(01)` Integrity checks | Selected | Verification actually runs, at pull or admission | `policy.json` signature requirement | Verification log per deploy |
| `SR-11` Component authenticity | Selected | Only authentic images run | cosign or `policy.json` | `cosign verify` |
| `SR-04` Provenance | Not selected | Where the image came from, who built it | SLSA provenance attestation | `cosign verify-attestation --type slsaprovenance` |
| `RA-05` Vulnerability scanning | Selected | Every image scanned, on a schedule | Grype/Trivy in CI and nightly | Scan reports per digest, dated |
| `AU-02`, `AU-12` Event logging | Selected | Engine binaries, config and socket audited | auditd watches | `auditctl -l`; `ausearch -k docker` |

CPCSC Level 1 touches the same ground through `03.01.02` (access enforcement: non-root, least privilege), `03.13.01` (boundary protection: no host networking), `03.14.01` (flaw remediation: rebuild and scan) and `03.14.02` (malicious code protection: image scanning).

> **Note.** `SR-04` is not selected in the Medium profile, but many secure-SDLC standards make signature verification and an SBOM part of the pre-release gate. **An organization can select more than the profile**; when it has written the requirement down, the assessor holds it to its own text.

### Audit a running host

#### inspect queries

Each of these is a single read-only query over every container, running or stopped. All verified on Docker 29.8.

```bash
docker ps -aq | xargs docker inspect > inspect.json     # snapshot once, query many times

# Privileged
jq -r '.[] | select(.HostConfig.Privileged) | .Name' inspect.json

# Engine socket mounted (root on the host from inside the container)
jq -r '.[] | select(any(.Mounts[]?; .Source | test("(docker|podman|containerd)\\.sock$"))) | .Name' inspect.json

# Sensitive host paths bind-mounted, with RW/RO
jq -r '.[] | .Name as $n | .Mounts[]? | select(.Type=="bind" and (.Source |
  test("^/$|^/(etc|root|boot|dev|proc|sys|usr|var/lib/docker)(/|$)"))) |
  "\($n) \(.Source) -> \(.Destination) rw=\(.RW)"' inspect.json

# Added capabilities, and containers that did not drop ALL
jq -r '.[] | select((.HostConfig.CapAdd // []) | length > 0) | "\(.Name) \(.HostConfig.CapAdd)"' inspect.json
jq -r '.[] | select(((.HostConfig.CapDrop // []) | index("ALL")) == null) | .Name' inspect.json

# Host network, PID, IPC namespaces
jq -r '.[] | .HostConfig as $h | select($h.NetworkMode=="host" or $h.PidMode=="host" or $h.IpcMode=="host")
  | "\(.Name) net=\($h.NetworkMode) pid=\($h.PidMode) ipc=\($h.IpcMode)"' inspect.json

# Missing limits (0 or null means unlimited)
jq -r '.[] | .HostConfig as $h | select(($h.Memory // 0)==0 or ($h.PidsLimit // 0)<=0)
  | "\(.Name) mem=\($h.Memory) pids=\($h.PidsLimit)"' inspect.json

# Root user (empty User means the image default, usually root)
jq -r '.[] | select((.Config.User // "") | test("^(|root|0)(:.*)?$")) | .Name' inspect.json

# Weakened security options
jq -r '.[] | select((.HostConfig.SecurityOpt // []) | any(test("unconfined|label[=:]disable")))
  | "\(.Name) \(.HostConfig.SecurityOpt)"' inspect.json
```

The Go-template form works without `jq`, one field at a time:

```bash
docker inspect --format '{{.Name}} priv={{.HostConfig.Privileged}} net={{.HostConfig.NetworkMode}} pid={{.HostConfig.PidMode}} user={{.Config.User}} ro={{.HostConfig.ReadonlyRootfs}} caps+={{.HostConfig.CapAdd}} sec={{.HostConfig.SecurityOpt}}' $(docker ps -aq)
```

Run over a typical developer workstation, the script at the end of this chapter finds privileged containers, Docker-socket mounts, containers running as root, images not pinned by digest and, on stock docker-ce, every container unconfined by SELinux. **That is what local development defaults look like**, and it is fine on a laptop that holds no customer data. It is a finding the moment a development Compose file becomes the shipped configuration, which is why the audit runs on the release artefact, not only on hosts.

#### Podman

Podman's inspect uses the same `HostConfig` field names, plus `.EffectiveCaps` and `.BoundingCaps` as decoded lists, so the same `jq` works. The difference is where containers live:

```bash
podman ps -a                          # this user's rootless containers only
sudo podman ps -a                     # rootful containers only
podman inspect CONTAINER --format '{{.EffectiveCaps}} {{.ProcessLabel}}'
```

> **Gotcha.** **Root cannot see rootless containers.** Each user has their own store under `~/.local/share/containers`, and `sudo podman ps -a` lists none of them. A complete Podman audit runs once as root and once as each user with containers (`loginctl list-users`, then as that user). Quadlet units in `~/.config/containers/systemd/` are the quickest way to find which users run containers at all.

#### From the process table

The engine API can be lied to or be unreachable. The kernel's view cannot. This cross-check needs no Docker access at all:

```bash
ps -eo pid,user,label,comm | awk '$3 ~ /spc_t|container_t/'
for p in $(pgrep -f containerd-shim); do sudo ps --ppid "$p" -o pid=,label=,comm=; done
```

A process with `spc_t` that no inspect output explains is worth a look (chapter 12).

### docker-bench and the CIS lag

#### Three versions of one benchmark

| Source | CIS Docker version | Status |
|---|---|---|
| CIS (cisecurity.org) | **1.8.0** | Current |
| docker-bench-security | **1.6.0** (per its README; no tagged releases, last commit 4 June 2026) | Two versions behind |
| Trivy compliance spec `docker-cis-1.6.0` | 1.6.0 | Same lag |
| A typical older internal container standard | **1.2** | Six versions behind |

**Default: declare CIS Docker 1.6.0 as the organization-defined `CM-06` baseline today**, because both docker-bench and Trivy produce evidence against it automatically. Read the 1.8.0 PDF once, list the checks that were added or changed, and carry them as manual checks with an owner until the tools catch up. Declaring 1.8.0 while your only tool checks 1.6.0 produces a baseline no report can demonstrate.

> **Version-sensitive.** The 1.7 and 1.8 deltas were not checked for this chapter: the benchmark PDFs are behind a CIS registration, and neither tool implements them. Check-by-check differences are **couldn't determine**.

#### The numbering shifted

Section 5 renumbered between 1.2 and 1.6: 1.6 opens with a new 5.1 (swarm mode), and the container-runtime checks move down one. Mapping 1.2 citations (as an older internal standard would quote them) to what docker-bench prints (1.6 IDs read from docker-bench's `tests/5_container_runtime.sh`):

| Requirement | CIS 1.2 ID (as cited) | CIS 1.6 ID (docker-bench) |
|---|---|---|
| No sensitive host mounts | 5.5 | 5.6 |
| No sshd in containers | 5.6 | 5.7 |
| Only needed ports | 5.8 | 5.9 |
| No host network namespace | 5.9 | 5.10 |
| Read-only root filesystem | 5.12 | 5.13 |
| Non-root user, trusted base, minimal packages, rebuilt, no secrets, verified packages | 4.1, 4.2, 4.3, 4.4, 4.10, 4.11 | Unchanged |

1.6 also has checks that 1.2-era standards never mention: 5.26 (no-new-privileges), 5.29 (PIDs limit), 5.31 (host user namespace not shared) and **5.32 (Docker socket not mounted)**.

> **Gotcha.** An internal container standard written against CIS 1.2 tends to be out of date in four ways: it cites numbering that no current tool prints, it often approves public registries such as Docker Hub and Quay (which conflicts with air-gapped delivery from an internal registry pinned by digest), it predates rootless Podman and bootc, and it says nothing about signing. **An assessor comparing it with a docker-bench report will find the IDs do not line up.** Update it to cite 1.6.0 as the baseline of record, with the renumbering table above.

#### Run it for evidence

Flags and output markers are in the Docker Field Manual, chapter 08. For evidence, keep the log and its JSON, and a before/after pair:

```bash
sudo sh docker-bench-security.sh -l /var/tmp/docker-bench-$(date +%F).log   # also writes .json
grep -c '\[WARN\]' /var/tmp/docker-bench-*.log
trivy image --compliance docker-cis-1.6.0 --report summary REGISTRY/APP@sha256:DIGEST
```

The Trivy spec runs against an image, so it can only evidence the image-level checks; daemon and host sections need docker-bench on the host (inferred from the scan target, not tested).

### Scans, SBOMs and signatures as evidence

The commands are in the Docker Field Manual, chapter 09. What matters here is what you keep, and which control it answers.

| Artefact | Tool (default) | Control | Keep |
|---|---|---|---|
| CVE report per digest | **Grype** (run per MR and nightly under your vulnerability management process) | `RA-05`, `03.14.01` | JSON report, date, digest, and the SLA verdict per finding |
| CIS image compliance | Trivy `--compliance docker-cis-1.6.0` | `CM-06` | Summary report per release |
| SBOM | **Syft**, CycloneDX JSON | `CM-08`, `SR-04` | One SBOM per released digest, attached as an attestation |
| Signature verification | **cosign** | `SI-07`, `SI-07(01)`, `SR-11` | `cosign verify` output at release and at media load |

Why Grype as the CVE default: run per MR and nightly, and fed into Renovate and your ticket tracker, its reports carry the SLA history. Trivy earns its place for the compliance spec and misconfiguration scanning, not as a second CVE opinion.

```bash
D=REGISTRY/APP@sha256:DIGEST
syft "$D" -o cyclonedx-json=sbom.cdx.json
grype sbom:./sbom.cdx.json -o json > grype.json
cosign verify --key cosign.pub "$D" > cosign-verify.json
cosign verify-attestation --key cosign.pub --type cyclonedx "$D" > sbom-attestation.json
sha256sum sbom.cdx.json grype.json cosign-verify.json sbom-attestation.json > SHA256SUMS
```

**Everything is keyed by digest, never by tag.** A report for `app:1.4` proves nothing about what ran if the tag moved. Your VMP SLAs (for example, Critical 24 hours with a 72-hour hard deadline, raised one tier for Protected B candidate data) run from the scan date on that digest.

> **Gotcha.** It is common for a standard to put SBOM generation and signature verification in the pre-release gate while the as-built CI has **no image signing and no SBOM**. Until that closes, **there is no `SI-07` or `SR-11` evidence for container images**, only registry access control and pipeline attestations. Record it as a POA&M item with a date rather than letting an assessor discover it.

For air-gapped delivery the verification point that matters is media load, not pull: a CAPEC-style threat model typically rates the offline media handoff as the dominant supply-chain risk. `cosign verify --key ... --insecure-ignore-tlog=true` works offline (Docker Field Manual, chapter 09); on the bootc appliance, the `policy.json` signature requirement does the same job at stage time.

### daemon.json as evidence

The hardened file and the reasoning for each key are in the Docker Field Manual, chapter 08. For an audit, each key needs a way to prove it is in force, which `docker info` provides without reading the file:

| Key | Control | Evidence command | Pass looks like |
|---|---|---|---|
| `selinux-enabled` | `SC-39` | `docker info --format '{{.SecurityOptions}}'` | Contains `name=selinux` |
| `no-new-privileges` | `AC-06` | same | Contains `name=no-new-privileges` |
| `userns-remap` or rootless | `AC-06`, `SC-39` | same | Contains `name=userns` or `name=rootless` |
| `live-restore` | availability | `docker info --format '{{.LiveRestoreEnabled}}'` | `true` |
| `log-driver`, `log-opts` | `AU-09`-adjacent (logs do not fill the disk) | `docker info --format '{{.LoggingDriver}}'` | `local` or `journald`, with rotation |
| `icc: false` | `SC-07` | `docker network inspect bridge --format '{{index .Options "com.docker.network.bridge.enable_icc"}}'` | `false` |
| no TCP without TLS | `SC-08`, `AC-17` | `ss -tlnp \| grep -E ':(2375\|2376)'` | Nothing, or 2376 with `tlsverify` |

> **Gotcha.** Most keys apply only to containers **created after** the daemon restart. `docker info` proving `no-new-privileges` is the default says nothing about containers created last month. Pair the daemon evidence with the per-container inspect results.

For Podman the baseline is `/etc/containers/containers.conf` and each user's `~/.config/containers/containers.conf`; `podman info --format '{{json .Host.Security}}'` is the equivalent evidence line.

### auditd for the engine

The rule file (watches on `dockerd`, `containerd`, `runc`, `/etc/docker`, `daemon.json`, the socket and the units) is in the Docker Field Manual, chapter 08, and rule-writing in general is chapter 08 of this manual. The evidence:

```bash
sudo auditctl -l | grep -E 'docker|containerd|runc|podman|containers'
sudo ausearch -k docker-sock -ts today -i | aureport -f -i --summary
docker events --since 24h --until "$(date +%s)" --format '{{.Time}} {{.Action}} {{.Actor.Attributes.name}}'
```

auditd records which process touched the socket; `docker events` records what it asked the API to do. You need both, because a container with the socket mounted connects as a process you did not expect and then creates containers you did not approve. For Podman, add watches on `/usr/bin/podman` and `/etc/containers`; Podman writes its events to the journal by default (`events_logger = "journald"` in the shipped `containers.conf`), so `journalctl` with the Podman identifier is the API-level record.

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `AU-02` | Engine binaries, config and socket watched | `auditctl -l` | Rules for each path in the Docker Field Manual chapter 08 list |
| `AU-12` | Records generated | `ausearch -k docker -ts today` | Events present |
| `AU-12` | API actions recorded | `docker events` shipped to the log pipeline | Create, exec and pull events visible centrally |

### The audit script

Read-only: it runs `inspect`, `info`, `stat`, `ss` and `auditctl -l`, and writes only to its output directory. It starts, stops and pulls nothing. Checked with `shellcheck` and run on Fedora 43 against Docker 29.8 (74 containers) and rootless Podman 5.8.

```bash
./container-audit.sh -o /var/tmp/container-audit-$(date +%F)        # your engines
sudo ./container-audit.sh -o /var/tmp/container-audit-root-$(date +%F)  # rootful Podman, auditd, daemon.json
```

```bash
#!/usr/bin/env bash
# container-audit.sh: read-only audit of container isolation on one host (Docker and Podman).
# Uses only inspect/info/stat/ss/auditctl; starts, stops and pulls nothing.
#
#   ./container-audit.sh                    # current user's engines (docker needs socket access)
#   sudo ./container-audit.sh -o DIR        # adds rootful Podman, auditd rules, daemon files
#
# Output: DIR/REPORT.txt, DIR/containers.tsv, raw inspect JSON per engine, SHA256SUMS.
set -uo pipefail
export LC_ALL=C

OUT="./container-audit-$(hostname -s)-$(date +%Y%m%d-%H%M%S)"
while getopts "o:h" opt; do
  case "$opt" in o) OUT=$OPTARG ;; *) sed -n '2,9p' "$0"; exit 0 ;; esac
done
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
umask 077; mkdir -p "$OUT" || exit 1
R="$OUT/REPORT.txt"; : >"$R"
say()  { printf '%s\n' "$*" >>"$R"; }
flag() { printf 'FLAG  %s\n' "$*" >>"$R"; }
sect() { printf '\n== %s\n' "$*" >>"$R"; }
say "host=$(hostname -f 2>/dev/null || hostname) date=$(date -Is) uid=$EUID selinux=$(getenforce 2>/dev/null || echo n/a)"

# One jq program for both engines: emits "name<TAB>finding" per problem.
read -r -d '' JQ <<'EOF'
def sensitive: test("^/$|^/(etc|root|boot|dev|proc|sys|usr|lib|lib64|bin|sbin)(/|$)|^/var/lib/(docker|containers|kubelet)(/|$)|^/(var/)?run/?$|^/(var/)?run/(dbus|systemd|containerd|docker|podman)(/|$)|^/home(/[^/]+)?/?$");
.[] | (.Name | ltrimstr("/")) as $n
| .HostConfig as $h
| [
    (if $h.Privileged then "privileged (AC-06, SC-39)" else empty end),
    (if $h.NetworkMode == "host" then "host network namespace (SC-39, SC-07)" else empty end),
    (if $h.PidMode == "host" then "host PID namespace (SC-39)" else empty end),
    (if $h.IpcMode == "host" then "host IPC namespace (SC-39)" else empty end),
    (if $h.UTSMode == "host" then "host UTS namespace" else empty end),
    (if $h.UsernsMode == "host" then "user namespace disabled for this container" else empty end),
    (($h.CapAdd // []) | select(length > 0) | "capabilities added: \(join(",")) (AC-06)"),
    (if ((($h.CapDrop // []) | map(ascii_upcase) | index("ALL")) == null) then "capabilities not dropped to ALL (AC-06)" else empty end),
    (($h.SecurityOpt // []) | map(select(test("seccomp[=:]unconfined|label[=:]disable|apparmor[=:]unconfined|label[=:]type:spc_t"))) | .[] | "security opt weakens isolation: \(.) (SC-39)"),
    (if ((($h.SecurityOpt // []) | map(select(test("no-new-privileges(=true|:true)?$"))) | length) == 0) then "no-new-privileges not set on the container (check daemon default)" else empty end),
    ((.Mounts // [])[] | select(.Source | test("(docker|podman|containerd|crio)\\.sock$")) | "engine socket mounted: \(.Source) -> \(.Destination) (AC-06: root on host)"),
    ((.Mounts // [])[] | select(.Type == "bind" and (.Source | sensitive) and (.Source | test("\\.sock$") | not)) | "sensitive host path mounted \(if .RW then "RW" else "RO" end): \(.Source) -> \(.Destination) (AC-03)"),
    (($h.Devices // []) | select(length > 0) | "host devices passed: \(map(.PathOnHost) | join(","))"),
    (if (($h.Memory // 0) == 0) then "no memory limit (SC-06)" else empty end),
    (if (($h.PidsLimit // 0) <= 0) then "no pids limit" else empty end),
    (if (($h.NanoCpus // 0) == 0 and ($h.CpuQuota // 0) == 0) then "no CPU limit" else empty end),
    (if ((.Config.User // "") | test("^(|root|0)(:.*)?$")) then "runs as root inside the container (AC-06)" else empty end),
    (if ($h.ReadonlyRootfs | not) then "root filesystem writable (CM-07, SI-07)" else empty end),
    (if ((.ProcessLabel // "") == "" or ((.ProcessLabel // "") | test(":spc_t:"))) then "SELinux unconfined (spc_t or no label)" else empty end),
    (($h.PortBindings // {}) | to_entries[] | .key as $p | (.value // [])[] | select((.HostIp // "") == "" or .HostIp == "0.0.0.0" or .HostIp == "::") | "port \($p) published on all interfaces (SC-07)"),
    (if ((.Config.Image // "") | test("@sha256:") | not) then "image not pinned by digest: \(.Config.Image) (CM-02, SI-07)" else empty end)
  ][] | "\($n)\t\(.)"
EOF

audit_engine() { # engine label
  local eng=$1 label=$2 ids json
  ids=$($eng ps -aq 2>/dev/null) || { say "$label: not reachable"; return; }
  [[ -n $ids ]] || { say "$label: no containers"; return; }
  json="$OUT/inspect-$label.json"
  # shellcheck disable=SC2086
  $eng inspect $ids >"$json" 2>/dev/null || { say "$label: inspect failed"; return; }
  sect "$label containers ($(jq length "$json"))"
  jq -r "$JQ" "$json" | sed "s/^/$label\t/" >>"$OUT/containers.tsv"
  jq -r '.[] | [(.Name|ltrimstr("/")), .Config.Image, (.State.Status)] | @tsv' "$json" >"$OUT/list-$label.tsv"
  local n
  for pat in privileged "host network" "host PID" "engine socket" "sensitive host path" "capabilities added" \
             "runs as root" "no memory limit" "no pids limit" "SELinux unconfined" "all interfaces" "not pinned"; do
    n=$(grep -c "^$label	[^	]*	.*$pat" "$OUT/containers.tsv")
    say "$(printf '%-22s %s' "$pat" "$n")"
  done
  grep "^$label	" "$OUT/containers.tsv" | grep -E 'privileged|engine socket|host PID|host network|mounted RW|SYS_ADMIN|capabilities added: ALL|security opt weakens' \
    | while IFS=$'\t' read -r _ n f; do flag "$label/$n: $f"; done
}

: >"$OUT/containers.tsv"
command -v docker >/dev/null && audit_engine docker docker
if command -v podman >/dev/null; then
  if [[ $EUID -eq 0 ]]; then audit_engine podman podman-rootful; else audit_engine podman "podman-rootless-$USER"; fi
fi

sect "Docker daemon (CM-06, AC-06)"
if docker info >/dev/null 2>&1; then
  docker info --format '{{json .}}' >"$OUT/docker-info.json"
  jq -r '"version=\(.ServerVersion) cgroup=v\(.CgroupVersion) security=\(.SecurityOptions|join(" ")) live-restore=\(.LiveRestoreEnabled) logdriver=\(.LoggingDriver)"' "$OUT/docker-info.json" >>"$R"
  so=$(jq -r '.SecurityOptions|join(" ")' "$OUT/docker-info.json")
  [[ $so == *selinux* ]] || flag "dockerd without selinux-enabled: containers run as spc_t"
  [[ $so == *rootless* || $so == *userns* ]] || say "dockerd is rootful with no userns-remap: container root is host root"
  [[ $so == *no-new-privileges* ]] || say "no-new-privileges is not a daemon default"
  [[ $(jq -r .LiveRestoreEnabled "$OUT/docker-info.json") == true ]] || say "live-restore off"
else
  say "docker daemon not reachable by this user"
fi
if [[ -r /etc/docker/daemon.json ]]; then
  cp /etc/docker/daemon.json "$OUT/daemon.json"
  for k in no-new-privileges icc userland-proxy live-restore selinux-enabled log-opts; do
    jq -e --arg k "$k" 'has($k)' /etc/docker/daemon.json >/dev/null || say "daemon.json lacks $k"
  done
  jq -e '(.hosts // []) | map(select(test("^tcp://"))) | length > 0' /etc/docker/daemon.json >/dev/null \
    && ! jq -e '.tlsverify == true' /etc/docker/daemon.json >/dev/null && flag "daemon listens on TCP without tlsverify"
else
  say "no /etc/docker/daemon.json (all defaults)"
fi
ss -Htlnp 2>/dev/null | grep -E ':(2375|2376)\b' | while read -r l; do flag "Docker API port listening: $l"; done

sect "Socket and group (AC-06(05))"
for s in /run/docker.sock /run/podman/podman.sock /run/containerd/containerd.sock; do
  [[ -S $s ]] && say "$(stat -c '%a %U:%G %n' "$s")"
  [[ -S $s ]] && (( 8#$(stat -c %a "$s") & 8#006 )) && flag "$s is world-accessible"
done
say "docker group: $(getent group docker | cut -d: -f4)"

sect "auditd rules for the engine (AU-02, AU-12)"
if [[ $EUID -eq 0 ]]; then
  auditctl -l >"$OUT/auditctl.txt" 2>&1
  for p in /usr/bin/dockerd /usr/bin/containerd /usr/bin/runc /etc/docker /run/docker.sock /var/lib/docker /usr/bin/podman /etc/containers; do
    [[ -e $p ]] || continue
    grep -qF -- "$p" "$OUT/auditctl.txt" && say "watched: $p" || flag "no audit watch on $p"
  done
else
  say "auditctl -l needs root"
fi

sect "Summary"
say "containers with findings: $(cut -f1,2 "$OUT/containers.tsv" | sort -u | wc -l)  findings: $(wc -l <"$OUT/containers.tsv")  flags: $(grep -c '^FLAG' "$R")"
( cd "$OUT" && sha256sum -- * 2>/dev/null | grep -v SHA256SUMS >SHA256SUMS )
echo "report: $R"
```

| Output | Contents | Control evidence |
|---|---|---|
| `REPORT.txt` | Per-engine counts, `FLAG` lines for the worst findings, daemon posture | Summary for the review record |
| `containers.tsv` | `engine  container  finding` for every finding | `AC-06`, `SC-39`, `CM-07`, `SI-07` |
| `inspect-*.json` | Raw inspect output as captured | The primary record; re-query it later |
| `docker-info.json`, `daemon.json` | Daemon state and config | `CM-06` |
| `auditctl.txt` | Loaded audit rules (as root) | `AU-02` |
| `SHA256SUMS` | Hashes of every file | Integrity of the evidence |

Copy the directory off the host the same day, into the evidence pipeline of chapter 17, as with chapter 14's script. The raw inspect JSON is worth more than the report: a question an assessor asks next year can be answered by re-running `jq` over it.

### Traps

- One kernel serves every container. Segment by sensitivity first (ITSP.80.023); hardening does not replace it.
- Docker on Fedora is **unconfined by SELinux** until `"selinux-enabled": true`, even with SELinux enforcing.
- `--privileged` silently disables seccomp and SELinux confinement too, not just capabilities.
- Rootful Docker has no user namespace: container root is host root.
- Inspect shows what was requested; `/proc/PID/status` and `ps -Z` show what the kernel did.
- Root cannot see rootless Podman containers; audit per user.
- `daemon.json` defaults apply only to containers created after the restart.
- docker-bench checks CIS 1.6.0, CIS is at 1.8.0, and older standards cite 1.2 numbering that shifted by one in section 5.
- Scan reports keyed by tag prove nothing; key everything by digest.
- A signing and SBOM gate that exists on paper but not in the as-built CI is no evidence.


---


<a id="16-kubernetes-security-audit-and-hardening"></a>

## 16 · Kubernetes security audit and hardening

*An assessor does not want to hear that the cluster is hardened. They want the control, the setting that implements it, and a dated file that proves it. So pick one baseline, map each control to one Kubernetes setting, and let scheduled tools write the evidence.*

The Kubernetes Field Manual's chapter 10 ("Security audit you can run") takes the attacker's view. This chapter takes the assessor's: which baseline supplies the ITSP.10.033 `CM-06` values, which tool measures each control, and what to save for an IATO package or a CPCSC self-assessment. Where the manual already has the YAML, this chapter links to it and adds the evidence step. Node controls are in chapters 02 to 08.

### Pick the baseline

None of the candidate baselines is Canadian. **CCCS publishes no container or Kubernetes hardening guide.** Its ITSM.10.090 points to CIS Benchmarks and DISA STIGs for settings. Whichever baseline you pick therefore becomes your `CM-06` value set, and the SSP should name it.

| Baseline | Version (Sept 2026) | Good for |
|---|---|---|
| CIS Kubernetes Benchmark | **2.0.1** (Kubernetes 1.34, 1.35) | The best-tooled config baseline. kube-bench implements it as `cis-2.0` |
| CIS managed variants | GKE, GKE Autopilot, EKS, AKS, OKE and OpenShift **2.0.0**; EKS Auto Mode 1.0.0 | Only the parts the customer controls |
| DISA Kubernetes STIG | **V2R6**, 1 April 2026, 92 rules (18 high) | Contracts that name STIGs. Each rule has literal check and fix text |
| DISA Container Platform SRG | **V2R4**, 28 October 2025, 188 requirements | The source STIGs are written from. Use it when your distribution has no STIG |
| NSA/CISA Kubernetes Hardening Guide | **v1.2**, August 2022 | A threat checklist, not a config baseline. It still describes PodSecurityPolicy |

DISA also publishes an RKE2 STIG (V2R6, 21 rules). **Current OpenShift and Docker STIG versions could not be confirmed.**

#### Which one when

**Default: CIS Kubernetes 2.0.1 as the baseline, measured by kube-bench, with a STIG overlay only when a contract names DISA STIGs.** The reason is tooling. CIS has a maintained scanner that matches its version exactly. The STIG has none for upstream Kubernetes: kube-bench's only STIG profile is `eks-stig-kubernetes-v1r6`, which is EKS-only and five releases old. That makes a STIG a manual checklist, and you should pay for it only when the contract requires it.

| Situation | Baseline | Measured by |
|---|---|---|
| Self-managed (kubeadm, the air-gapped appliance) | CIS 2.0.1 | kube-bench `--benchmark cis-2.0` |
| Contract names STIGs, or DND asks for a checklist | STIG V2R6 on top of CIS | kube-bench for the overlap, STIG Viewer checklist for the rest |
| Distribution with no STIG, DoD-style requirement | Container Platform SRG V2R4 | Manual implementation statements |
| GKE or EKS (e.g. per-MR clusters) | CIS GKE/EKS 2.0.0 | kubescape `cis-gke-v1.9.0` / `cis-eks-t1.8.0` or kube-bench `gke-1.9.0` / `eks-1.8.0` |

> **One-way door.** Naming a baseline in an SSP, IATO package or contract response takes one line, but the customer then assesses you against it for the life of the authorization. The tool choice is reversible and the baseline is not. Name the version as well ("CIS Kubernetes 2.0.1", not "CIS").

> **Version-sensitive.** No scanner measures CIS GKE or EKS 2.0.0. kube-bench stops at `gke-1.9.0` and `eks-1.8.0`, and Kubescape at `cis-gke-v1.9.0` and `cis-eks-t1.8.0`. State the version you actually measured.

#### Where they disagree

| Topic | STIG V2R6 | CIS, upstream docs, Canada | Resolution |
|---|---|---|---|
| Audit policy | V-242403 says the policy "must look like" one rule, `level: RequestResponse` | That level writes Secret values and minted tokens into the log | Tiered policy (below), recorded as a documented deviation |
| Audit retention | V-242464 maxage ≥ 30 days, V-242463 maxbackup ≥ 10, V-242462 maxsize ≥ 100 MB | TBS: ≥ 3 months online and 6 months in storage; incidents 2 years | Apply the STIG values on the node and the TBS values in the central store |
| Encryption provider | V-274882's fix example uses `aescbc` | Kubernetes docs call `aescbc` "Weak ... vulnerability to padding oracle attacks" | KMS v2 or `aesgcm`. Both pass V-274882, which only rejects `identity` in first place |
| TLS | V-242418: four ECDHE AES-GCM TLS 1.2 suites | ITSP.40.062: TLS 1.3 recommended, 1.2 acceptable | TLS 1.2 minimum with exactly the STIG list |

### One tool per job

| Job | Default | Why | Alternative only if |
|---|---|---|---|
| CIS on nodes and control plane | **kube-bench v0.16.0** | Only scanner with `cis-2.0` | — |
| Frameworks (NSA, MITRE, CIS) | **Kubescape v4.0.14** | Real offline mode; also scans charts in CI | Trivy `--compliance`, if you accept older specs |
| Continuous in-cluster scans | **Trivy Operator v0.34.0** | Dated CRD reports on a cron | Kubescape operator, if Kubescape is already everywhere |
| Manifest lint | **Polaris v10.2.5** | Maintained, score threshold, optional webhook | kube-score has had no release since April 2025 |
| RBAC | **rbac-tool v1.20.0** | Reads RBAC objects only; no `impersonate` needed | `kubectl auth can-i --list --as=` for one subject, run by an admin |
| Continuous admission evidence | **Kyverno v1.19.1** policy reports | Every result is an exportable object | Gatekeeper audit, if you already write Rego |
| Runtime | **Falco 0.45.0** | Chapter 10's host default; the same DaemonSet covers nodes | Tetragon, if you need enforcement |

kubectl-who-can's last release was v0.4.0 in February 2022, so use `rbac-tool who-can` instead.

> **Gotcha.** Scanners run with broad read or host access, and Trivy shipped a compromised release in March 2026 (chapter 11). Mirror every scanner image, **pin it by version and digest**, and give each scanner its own narrow ServiceAccount. A scanner with cluster-admin is the best lateral-movement tool on the cluster.

#### Kubescape offline

Kubescape fetches its controls on every run unless you stop it. Download on the connected side, carry the directory across in the offline bundle, and point the scan at it:

```bash
kubescape download artifacts --output ./kubescape-artifacts          # connected side
kubescape scan framework nsa,mitre,cis-v1.12.0 \
  --use-artifacts-from ./kubescape-artifacts --keep-local \
  --format json --output kubescape.json                              # air-gapped side
kubescape scan framework nsa ./deploy/chart --use-artifacts-from ./kubescape-artifacts   # CI, pre-merge
```

The newest CIS framework in Kubescape is `cis-v1.12.0`. **There is no CIS 2.0 framework**, which is why kube-bench stays the CIS default. `--compliance-threshold` sets the exit code only for `framework` and `control` scans.

#### kube-bench and Trivy

kube-bench reads node files, so it runs on the node: either the binary over SSH, or the upstream `job-master.yaml` / `job-node.yaml` (`hostPID`, read-only `hostPath`). Pin the benchmark rather than trusting auto-detection:

```bash
kube-bench run --targets master,etcd,controlplane,node,policies --benchmark cis-2.0 --json --outputfile kube-bench-NODE.json
```

The Job needs a namespace with the PSA label `privileged`. **Document it as an exemption, and delete the Job after each run.**

The Trivy Operator's Helm defaults run `k8s-cis-1.23`, `k8s-nsa-1.0` and both PSS specs every six hours, writing `clustercompliancereports`. In an air gap, point `trivy.dbRepository` and `trivy.javaDbRepository` at internal mirrors, or every scan fails quietly on the DB download.

### Control map

Control IDs are ITSP.10.033. The CPCSC column lists only the ITSP.10.171 Level 1 IDs that apply.

| Control | Kubernetes setting | CPCSC L1 |
|---|---|---|
| `AC-02`, `AC-06` | One SA per workload, automount off, no workload cluster-admin | `03.01.01`, `03.01.02` |
| `AU-02`, `AU-03`, `AU-12` | `--audit-policy-file` with a tiered policy | — |
| `AU-09`, `AU-11` | Logs shipped off-node to write-once storage | — |
| `CM-06`, `CM-07` | CIS 2.0.1; PSA `restricted`; Kyverno baseline | — |
| `SC-07` | Default-deny NetworkPolicy on an enforcing CNI | `03.13.01` |
| `SC-08`, `SC-13` | TLS 1.2+ with the STIG suites; certificate auth between components | `03.05.02` |
| `SC-12`, `SC-28` | EncryptionConfiguration with KMS v2 or `aesgcm` | — |
| `SI-07`, SR family | cosign signatures, `ImageValidatingPolicy`, digest pinning | — |
| `SI-04` | Falco plus `k8saudit` | `03.14.02` (partial) |
| `RA-05`, `CA-07` | Trivy Operator, scheduled Kubescape | `03.14.01` |

### AC-02 and AC-06: identities

**Requirement.** Every account is known and owned (`AC-02`), and each holds only what it needs (`AC-06`). In Kubernetes, the accounts are ServiceAccounts and the subjects of bindings.

**Setting.**

- One ServiceAccount per workload, never `default`, and `--use-service-account-credentials=true` on the controller manager (STIG V-242381, high).
- `automountServiceAccountToken: false` on the ServiceAccount (YAML in the manual's chapter 10).
- Nothing bound to `cluster-admin` except `system:masters`. Humans get OIDC groups bound to namespaced roles.
- No `get`, `list` or `watch` on `secrets` without a documented need (V-274884).
- Workloads in dedicated namespaces (V-242383, high).

**The auditor identity.** The audit must not need admin. Give the scanner a read role that omits Secrets and every escalation verb:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: security-auditor}
rules:
  - apiGroups: [""]
    resources: [pods, services, serviceaccounts, namespaces, nodes, configmaps, endpoints,
                persistentvolumes, persistentvolumeclaims, resourcequotas, limitranges, events]
    verbs: [get, list, watch]
  - apiGroups: [apps, batch, networking.k8s.io, policy, storage.k8s.io, rbac.authorization.k8s.io,
                admissionregistration.k8s.io, apiextensions.k8s.io, certificates.k8s.io,
                wgpolicyk8s.io, policies.kyverno.io, aquasecurity.github.io]
    resources: ["*"]
    verbs: [get, list, watch]
```

Listing legacy token Secrets and `kubectl auth can-i --as=` (which needs `impersonate`) fall outside this role, so an admin runs them. **This is why rbac-tool is the default**: it computes permissions from Role and Binding objects, so the auditor never needs `impersonate`, which is a cluster-admin-equivalent grant.

**Evidence.**

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `AC-06` | cluster-admin bindings | the manual's chapter 10 `jq` | Only `Group:system:masters` |
| `AC-06` | Risky rules | `kubectl rbac-tool analysis -o json` | Each finding justified or removed |
| `AC-06` | Who reads Secrets | `kubectl rbac-tool who-can list secrets -A` | Named controllers only |
| `AC-02` | Subject inventory | `kubectl rbac-tool lookup -e '.*' -o json` | Every subject has an owner in the account register |
| `AC-06` | Token automount | `kubectl get pods -A -o json \| jq '[.items[] \| select(.spec.automountServiceAccountToken != false)] \| length'` | 0, or a listed set of API clients |
| `AC-02` | Legacy tokens (admin) | `kubectl get secrets -A --field-selector type=kubernetes.io/service-account-token -o name` | Empty on 1.24+ |

Before tightening a workload's role, run `kubectl rbac-tool auditgen -f audit.log` over a week of the API audit log. It generates least-privilege Roles from calls the workload actually made.

### AU-02 and AU-12: API audit

**Requirement.** Generate records for defined events (`AU-02`, `AU-12`) that carry what, when, who and outcome (`AU-03`), protected from tampering (`AU-09`). DAOD 6003-3 adds "accurate and time-stamped". A typical security NFR also requires every authentication and authorization decision to be logged. **Without `--audit-policy-file`, the API server writes no audit log at all.**

#### The policy

This fixes one thing in the manual's version. `serviceaccounts/token` is a TokenRequest, and its **response body is a bearer token**. Logging it at `RequestResponse` writes live credentials into the log store. `tokenreviews` has the same problem, in the request body.

```yaml
# /etc/kubernetes/audit/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages: [RequestReceived]
omitManagedFields: true
rules:
  # 1. Noise with no security value
  - level: None
    nonResourceURLs: ["/healthz*", "/livez*", "/readyz*", "/version", "/openapi/*"]
  - level: None
    users: ["system:kube-proxy"]
    verbs: [watch]
    resources: [{group: "", resources: [endpoints, services]},
                {group: discovery.k8s.io, resources: [endpointslices]}]
  - level: None
    userGroups: ["system:nodes"]
    verbs: [get, update, patch]
    resources: [{group: coordination.k8s.io, resources: [leases]},
                {group: "", resources: [nodes/status]}]
  - level: None
    resources: [{group: "", resources: [events]}, {group: events.k8s.io, resources: [events]}]

  # 2. Credential-bearing objects: who touched what, never the payload
  - level: Metadata
    resources:
      - {group: "", resources: [secrets, configmaps, serviceaccounts/token]}
      - {group: authentication.k8s.io, resources: [tokenreviews]}
      - {group: certificates.k8s.io, resources: [certificatesigningrequests]}

  # 3. Interactive access into workloads and nodes: full detail
  - level: RequestResponse
    resources:
      - {group: "", resources: [pods/exec, pods/attach, pods/portforward,
                                pods/ephemeralcontainers, nodes/proxy]}

  # 4. Changes to permissions and to what admission enforces
  - level: RequestResponse
    verbs: [create, update, patch, delete, deletecollection]
    resources:
      - {group: rbac.authorization.k8s.io}
      - {group: admissionregistration.k8s.io}
      - {group: apiextensions.k8s.io}
      - {group: policies.kyverno.io}
      - {group: networking.k8s.io, resources: [networkpolicies]}
      - {group: "", resources: [namespaces, serviceaccounts]}

  # 5. Every other write: request body. 6. Everything else: metadata.
  - level: Request
    verbs: [create, update, patch, delete, deletecollection]
  - level: Metadata
```

The first matching rule wins, so rule order is the policy. Keep the `None` rules narrow: a broad `None` on `system:authenticated` hides every attacker who matters.

> **Gotcha.** This policy fails STIG V-242403's literal check. For STIG deliveries, record a **documented deviation**. It still captures the content the rule's CCIs require (type, source, outcome, user, container), and it keeps Secret values and bearer tokens out of a log store that more people can read than can read Secrets. If the customer insists on the literal rule, the audit store then holds Protected B credentials and needs that classification's access controls and retention.

#### Flags and destination

```yaml
# kube-apiserver static pod (excerpt); both paths also need hostPath mounts
    - --audit-policy-file=/etc/kubernetes/audit/audit-policy.yaml
    - --audit-log-path=/var/log/kubernetes/audit/audit.log
    - --audit-log-format=json
    - --audit-log-maxage=30
    - --audit-log-maxbackup=10
    - --audit-log-maxsize=100
```

**Forget the policy file's `hostPath` mount and the API server does not start.** On kubeadm, the control plane then stays down until someone fixes the manifest on the node.

Default destination: **the file backend, shipped by the node's existing log agent** to the in-perimeter log store. The file survives a store outage. Add the webhook backend (`--audit-webhook-config-file`, default `batch` mode) only for a stream consumer such as Falco's `k8saudit` plugin. Chapter 08 covers time sync (`AU-08`). On GKE and EKS the provider owns the policy, so the evidence is the enabled audit-log setting.

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `AU-12` | Enabled | `kubectl -n kube-system get pod -l component=kube-apiserver -o yaml \| grep -E -- '--audit-'` | All six flags, at or above STIG minimums |
| `AU-02` | Policy content | `sudo sha256sum /etc/kubernetes/audit/audit-policy.yaml` per control-plane node | Matches the reviewed file in Git |
| `AU-03` | Records are real | after a test exec: `sudo jq -c 'select(.objectRef.subresource=="exec") \| {u:.user.username, pod:.objectRef.name, code:.responseStatus.code, ts:.requestReceivedTimestamp}' /var/log/kubernetes/audit/audit.log \| tail -3` | Your exec, with user, pod and result |
| `AU-11` | Retention | exported log-store retention setting | ≥ 90 days online, ≥ 6 months total |

### CM-06 and CM-07: admission

**Requirement.** Settings follow the baseline (`CM-06`), and only essential capability is allowed (`CM-07`): no privileged pods, host namespaces or root. **Pod Security Admission** enforces the Pod Security Standards natively, with no webhook that can fail open. **Kyverno** covers what PSA cannot express. Do not rebuild PSA in Kyverno: the built-in plugin has no availability dependency, and it is what STIG V-254800 checks for.

#### PSA as the cluster default

The manual labels namespaces one at a time. A baseline should set the **cluster default**, so every new namespace starts `restricted` and the exemptions sit in one reviewed file:

```yaml
# /etc/kubernetes/admission/admission-config.yaml
# kube-apiserver: --admission-control-config-file=/etc/kubernetes/admission/admission-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
  - name: PodSecurity
    configuration:
      apiVersion: pod-security.admission.config.k8s.io/v1
      kind: PodSecurityConfiguration
      defaults:
        enforce: "restricted"
        enforce-version: "v1.35"
        audit: "restricted"
        audit-version: "v1.35"
        warn: "restricted"
        warn-version: "v1.35"
      exemptions:
        usernames: []
        runtimeClasses: []
        namespaces: [kube-system]
```

Namespaces that genuinely need more (the CNI, CSI, Falco, the kube-bench Job) get the label `pod-security.kubernetes.io/enforce=privileged`, committed to Git with the reason. An assessor reads that list as your accepted risks.

> **Version-sensitive.** `pod-security.admission.config.k8s.io/v1` is the GA API (1.25+). The fix text for STIG V-254800 still shows `v1beta1`. Pin `enforce-version` to your minor version and bump it on purpose when you upgrade.

#### The Kyverno baseline

> **Version-sensitive.** Kyverno 1.17 made the CEL policy types (`ValidatingPolicy`, `ImageValidatingPolicy` and others) `policies.kyverno.io/v1` and deprecated `ClusterPolicy`. The migration guide says `ClusterPolicy` **will be removed in 1.20**. The `ClusterPolicy` examples in the Field Manual's chapter 10 need migrating before that upgrade.

Install the upstream policy chart, which now ships CEL policies by default. Start it in `Audit`: warn before blocking. It duplicates PSA on purpose, to turn PSS results into reports:

```bash
helm install kyverno-policies kyverno/kyverno-policies -n kyverno \
  --set podSecurityStandard=restricted --set validationFailureAction=Audit
```

Then add the controls PSA lacks:

```yaml
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata: {name: workload-baseline}
spec:
  validationActions: [Audit]          # [Deny] once reports are clean
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [pods]
  variables:
    - name: containers
      expression: "object.spec.containers + object.spec.?initContainers.orValue([])"
  validations:
    - expression: >-
        variables.containers.all(c, c.image.startsWith('REGISTRY/') && c.image.contains('@sha256:'))
      message: "Images must come from REGISTRY, pinned by digest (CM-06, SR)."
    - expression: >-
        variables.containers.all(c, c.?securityContext.?readOnlyRootFilesystem.orValue(false) == true)
      message: "readOnlyRootFilesystem must be true (CM-07)."
    - expression: >-
        object.spec.?automountServiceAccountToken.orValue(true) == false ||
        object.metadata.?labels['security.example.com/api-client'].orValue('') == 'true'
      message: "automountServiceAccountToken: false, or label the pod as an API client (AC-06)."
```

> **Gotcha.** A policy that matches only `pods` blocks the Pod, not the Deployment. `kubectl apply` succeeds, and the denial shows up in `kubectl describe rs`. Kyverno's autogen creates matching rules for pod controllers, but check how your version handles `spec.autogen` for CEL policies before you tell developers where to look.

Kyverno writes a `PolicyReport` per namespace (`wgpolicyk8s.io/v1alpha2`) and re-evaluates it in the background. That is continuous `CM-06` evidence at no extra cost. **Export it on a schedule rather than screenshotting it**, with `kubectl get policyreports -A -o json`. The alpha `openreports.io` output (Kyverno 1.15+) will eventually replace it, so keep the export job matched to whichever one you enable.

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `CM-06` | Baseline | `kube-bench run --benchmark cis-2.0 --json` | No FAIL without a recorded deviation |
| `CM-07` | PSA default | the admission config file, hashed | `enforce: restricted` |
| `CM-07` | Weaker namespaces | `kubectl get ns -L pod-security.kubernetes.io/enforce` | Only documented exemptions |
| `CM-06` | Admission results | `jq '[.items[].results[]? \| select(.result=="fail")] \| length' policyreports.json` | 0 for `Deny` policies, falling for `Audit` ones |

### SC-07: default deny

**Requirement.** `SC-07` and CPCSC `03.13.01`. ITSP.80.023 is the only CCCS text on containers, and it is explicit: "By default, an explicit deny-all rule should be enforced and access should be granted by exception." It also says containers should be segmented by security context.

**Setting.** The manual's chapter 10 has the policies (deny both directions, the DNS exception, one allow per flow) and explains why the CNI must enforce them. Two things to add for compliance. The deny must exist in **every** namespace, including future ones, so ship it in the namespace template. And ITSP.80.023's segmentation is a **node-pool** decision: Protected B workloads get their own tainted nodes, not merely their own namespace.

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `SC-07` | Coverage | `comm -23 <(kubectl get ns -o name \| cut -d/ -f2 \| sort) <(kubectl get netpol -A -o json \| jq -r '.items[] \| select(.spec.podSelector=={}) \| .metadata.namespace' \| sort -u)` | Empty |
| `SC-07` | Enforcement | the manual's netshoot probe | Allowed flow open, all else refused |
| `SC-07` | Segmentation | `kubectl get nodes -L NODE_POOL_LABEL` plus taints | Protected B pods only on their pool |

Save a per-pod blast-radius write-up next to the probe output. It is your record of why you chose each allow rule.

### SC-08 and SC-13: TLS

**Requirement.** Protect data in transit (`SC-08`) with approved cryptography (`SC-13`). For Protected B, ITSP.40.062 covers protocols (TLS 1.3 recommended, 1.2 acceptable) and ITSP.40.111 covers algorithms (AES only for symmetric; SHA-2/3; RSA ≥ 2048; P-256/384/521).

```yaml
# kube-apiserver (etcd takes the same list via --cipher-suites)
    - --tls-min-version=VersionTLS12
    - --tls-cipher-suites=TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
    - --anonymous-auth=false                    # V-242390, high
# KubeletConfiguration
tlsMinVersion: VersionTLS12
tlsCipherSuites: [SAME_FOUR_SUITES]
readOnlyPort: 0                                 # V-242387, high
authentication: {anonymous: {enabled: false}, webhook: {enabled: true}}
authorization: {mode: Webhook}                  # V-242392, high
```

Every suite in the STIG list is ECDHE + AES-GCM + SHA-2, which fits ITSP.40.111.

> **Note.** TLS 1.3 suites are not configurable in Go, and the fixed set includes ChaCha20 (not AES). Go prefers AES-GCM on AES-capable CPUs. A hard guarantee needs a FIPS-mode build. (Inferred from Go's documented behaviour.)

> **Gotcha.** ITSP.10.033-01 requires CMVP-validated crypto modules, and upstream Kubernetes binaries are not built on one. A distribution's "FIPS build" is a vendor claim until you hold the CMVP certificate number. **Couldn't determine** a validated option for upstream kubeadm, so record it as an open item.

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `SC-08` | No old TLS | `openssl s_client -connect APISERVER:6443 -tls1_1 </dev/null` | Handshake failure |
| `SC-13` | CBC refused | `openssl s_client -connect APISERVER:6443 -tls1_2 -cipher ECDHE-RSA-AES256-SHA </dev/null` | Handshake failure |
| `SC-08` | No plaintext kubelet | `ss -lnt 'sport = :10255'` on each node | Nothing listening |

### SC-28: etcd encryption

**Requirement.** Protect data at rest (`SC-28`) and manage the keys (`SC-12`). STIG V-274882 (high) requires Secrets to be encrypted with `identity` not listed first. A typical "encrypted at rest" NFR states the intent but not the method.

| Provider | Algorithm | Kubernetes docs | ITSP.40.111 | Verdict |
|---|---|---|---|---|
| `aescbc` | AES-CBC | "Weak", padding oracle | AES, but advised against | Not for new clusters, even though the STIG example uses it |
| `aesgcm` | AES-GCM | "Must be rotated every 200,000 writes" | Fits (GCM is NIST SP 800-38D; inferred) | **Air-gap default**, with scripted rotation |
| `secretbox` | XSalsa20-Poly1305 | "Strong" | **Fails: not AES** | Never for Protected B |
| `kms` v2 | AES-GCM DEKs, external KEK | "Strongest", stable since 1.29 | Fits, and the key stays off the host | **Default wherever a production plugin exists** (GKE, EKS) |
| `kms` v1 | envelope | deprecated in 1.28, off by default in 1.29 | — | Migrate off it |

The local providers keep the key in a file on the control-plane host. So `aesgcm` protects etcd and its backups, but **not** a compromised control-plane node. An OpenBao Transit KMS v2 provider exists, but it describes itself as a **preview for labs and evaluation**.

> **Note.** Close call for the air-gapped appliance: `aesgcm` now, or wait for an OpenBao KMS v2 plugin. The tiebreaker is whether the threat model puts control-plane host compromise in scope for `SC-28`. If it does, `aesgcm` leaves the finding open whichever you choose, so write that down.

```yaml
# /etc/kubernetes/enc/encryption-config.yaml   (0600 root)
# kube-apiserver: --encryption-provider-config=/etc/kubernetes/enc/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources: [secrets]
    providers:
      # With a production KMS v2 plugin, this goes first instead:
      # - kms: {apiVersion: v2, name: KMS_NAME, endpoint: unix:///var/run/kmsplugin/socket.sock, timeout: 3s}
      - aesgcm:
          keys:
            - name: key-2026-09            # current: encrypts new writes
              secret: BASE64_32_BYTE_KEY
            - name: key-2026-06            # previous: decrypts until re-encryption completes
              secret: BASE64_32_BYTE_KEY_PREVIOUS
      - identity: {}                       # last: reads data written before encryption
```

Generate each key with `head -c 32 /dev/urandom | base64`. **Rotation** follows the upstream procedure on every control-plane node:

1. Add the new key second, then restart all API servers.
2. Move it to first, then restart again.
3. Rewrite every Secret with `kubectl get secrets -A -o json | kubectl replace -f -`.
4. Remove the old key, then restart.

> **One-way door.** Removing the old key before step 3 finishes makes every Secret still written with it unreadable. Recovery needs an etcd backup **and** the old key. Keep retired keys in offline escrow, never next to the etcd snapshots they unlock.

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `SC-28` | Provider order | `sudo cat` of the config, hashed | `kms` or `aesgcm` first, `identity` last |
| `SC-28` | Really encrypted | `sudo ETCDCTL_API=3 etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key get /registry/secrets/NAMESPACE/audit-canary \| hexdump -C \| head -3` | `k8s:enc:aesgcm:v1:key-2026-09:` or `k8s:enc:kms:v2:` |
| `SC-12` | Key file | `stat -c '%a %U' /etc/kubernetes/enc/encryption-config.yaml` | `600 root` |

`audit-canary` is a throwaway Secret, so the audit never reads a real one. On GKE check `databaseEncryption.state` (`gcloud container clusters describe`); on EKS, `cluster.encryptionConfig` (`aws eks describe-cluster`). V-242437 (PodSecurityPolicy) is not applicable on 1.25+; answer it with V-254800.

### Secrets from OpenBao

**Requirement.** Store sensitive data in Secrets or an external store (V-274883, high), never as environment variables (V-242415, high), and on a need-to-know basis (V-274884). Prefer dynamic issuance with bounded TTLs; OpenBao (or Vault) provides it.

**Setting.** External Secrets Operator v2.11.0 syncs from OpenBao through its Vault provider, which ESO documents as the OpenBao integration. Authenticate with an audience-bound projected token, never a static OpenBao token held in a Secret:

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata: {name: openbao}
spec:
  provider:
    vault:
      server: "https://OPENBAO_ADDR:8200"
      path: "kv"
      version: "v2"
      caProvider: {type: ConfigMap, name: openbao-ca, key: ca.crt, namespace: external-secrets}
      auth:
        kubernetes:
          mountPath: "kubernetes/CLUSTER_NAME"
          role: "eso-reader"
          serviceAccountRef: {name: external-secrets, namespace: external-secrets, audiences: ["openbao"]}
```

Mount the synced Secret as a **file**. `secretKeyRef` in `env` fails V-242415 and leaks through `/proc/PID/environ`. The remaining evidence (which role maps to which policy) comes from OpenBao's audit device and a policy export.

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| V-242415 | Secrets in env | `kubectl get pods -A -o json \| jq -r '.items[] \| .metadata as $m \| .spec.containers[] \| select(any(.env[]?; .valueFrom.secretKeyRef)) \| "\($m.namespace)/\($m.name)"'` | Empty |
| `IA-05` | Sync health | `kubectl get externalsecrets -A` | All `SecretSynced` |

### SI-07 and SR: signed images

**Requirement.** Detect unauthorized software changes (`SI-07`) and prove provenance (SR family). For air-gapped delivery, **the offline media handoff is usually the dominant supply-chain risk**. Its mitigation is signed images plus digest pinning, verified at load.

**Signing.** An air gap has no Rekor, so sign with a key and skip the transparency log (cosign v3.1.3):

```bash
cosign sign --key hashivault://app-release --tlog-upload=false REGISTRY/team/api@sha256:DIGEST
cosign verify --key cosign.pub --insecure-ignore-tlog REGISTRY/team/api@sha256:DIGEST
```

> **Version-sensitive.** `hashivault://` is cosign's Vault scheme. That it works against OpenBao Transit is inferred from API compatibility, not verified, so test it or use a hardware-token key.

**Admission.** `ImageValidatingPolicy` replaces `ClusterPolicy` `verifyImages`. A rule that a trust store must hold more than one anchor becomes two attestors:

```yaml
apiVersion: policies.kyverno.io/v1
kind: ImageValidatingPolicy
metadata: {name: verify-team-images}
spec:
  validationActions: [Deny]
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [pods]
  matchImageReferences:
    - glob: "REGISTRY/team/*"
  validationConfigurations: {mutateDigest: true, verifyDigest: true, required: true}
  attestors:
    - name: release
      cosign:
        key: {data: "RELEASE_PUBLIC_KEY_PEM"}
        ctlog: {insecureIgnoreTlog: true, insecureIgnoreSCT: true}   # air gap: never uploaded
    - name: standby
      cosign:
        key: {data: "STANDBY_PUBLIC_KEY_PEM"}
        ctlog: {insecureIgnoreTlog: true, insecureIgnoreSCT: true}
  validations:
    - expression: >-
        images.containers.map(image, verifyImageSignatures(image, [attestors.release, attestors.standby])).all(e, e > 0)
      message: "Image must be signed by the release or standby key."
```

> **Version-sensitive.** The field names above are from the Kyverno 1.19 docs, which label `insecureIgnoreTlog` "for testing only" because they assume public Sigstore. With key-based signing in an air gap it is correct, so write that reasoning down for the assessor. Confirm how `verifyImageSignatures` counts matches across a list of attestors in your version.

The glob covers only your own images. Third-party images (the CNI, operators, `pause`) need either re-signing when they enter the internal registry or a digest-pin policy. **Unsigned third-party images are the usual gap.**

| Control | Check | Command | Pass looks like |
|---|---|---|---|
| `SI-07` | Unpinned images | `kubectl get pods -A -o json \| jq -r '.items[].spec.containers[].image' \| sort -u \| grep -v '@sha256:'` | Empty |
| SR | Spot check | `cosign verify --key cosign.pub --insecure-ignore-tlog IMAGE@sha256:DIGEST` on three running images | Verified |
| SR | Refusal works | apply an unsigned test pod in a scratch namespace | Denied, and the denial is in the audit log |

> **Gotcha.** If signing is required on paper but the as-built CI has **no image signing and no SBOM** yet, a `Deny` policy would freeze every deployment. Build signing first, prove coverage in `Audit`, then switch to `Deny`.

### SI-04: runtime

Chapter 10 covers Falco itself. For evidence, run the chart in an exempted PSA-`privileged` namespace and feed the audit webhook into the `k8saudit` plugin, so an exec alert carries the **user**, not just the pod. That gives DAOD 6003-3's timely review its record: alert, user, time, response.

> **Version-sensitive.** `k8saudit` plugin configuration has changed across Falco releases. Take it from the chart version you install.

### Read-only audit runbook

Run the steps in this order. Each one writes into a single dated directory. **Everything is read-only except step 7**, which creates one Job and then deletes it. Say so in the report.

```bash
# 0. scope: who, against what, when
EV="k8s-audit-$(kubectl config current-context | tr '/:' '__')-$(date -u +%Y%m%dT%H%MZ)"; mkdir -p "$EV" && cd "$EV"
kubectl auth whoami -o yaml > 00-whoami.yaml
kubectl version -o json > 00-version.json
kubectl get nodes -o wide > 00-nodes.txt
kubectl get ns --show-labels > 00-namespaces.txt

# 1. RBAC (AC-02, AC-06)
kubectl get clusterroles,clusterrolebindings,roles,rolebindings -A -o json > 10-rbac-objects.json
kubectl rbac-tool analysis -o json > 11-rbac-analysis.json
kubectl rbac-tool who-can list secrets -A > 12-who-can-list-secrets.txt
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.automountServiceAccountToken != false)
  | "\(.metadata.namespace)/\(.metadata.name)\t\(.spec.serviceAccountName)"' > 13-token-automount.tsv

# 2. admission (CM-06, CM-07)
kubectl get ns -L pod-security.kubernetes.io/enforce,pod-security.kubernetes.io/enforce-version > 20-psa-labels.txt
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do echo "== $ns"
  kubectl label --dry-run=server --overwrite ns "$ns" pod-security.kubernetes.io/enforce=restricted 2>&1 | grep -i warn
done > 21-psa-dryrun.txt
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations -o yaml > 22-webhooks.yaml
kubectl get validatingpolicies,imagevalidatingpolicies -o yaml > 23-kyverno-policies.yaml
kubectl get policyreports -A -o json > 24-policyreports.json

# 3. network (SC-07)
kubectl get netpol -A -o yaml > 30-networkpolicies.yaml
comm -23 <(kubectl get ns -o name | cut -d/ -f2 | sort) \
  <(kubectl get netpol -A -o json | jq -r '.items[] | select(.spec.podSelector=={}) | .metadata.namespace' | sort -u) > 31-ns-without-deny.txt

# 4. control plane (AU-12, SC-08, SC-28); self-managed only
for c in kube-apiserver kube-controller-manager etcd; do
  kubectl -n kube-system get pod -l component=$c -o yaml > 40-$c.yaml; done
grep -hoE -- '--(anonymous-auth|authorization-mode|audit-[a-z-]+|encryption-provider-config|admission-control-config-file|tls-[a-z-]+)=[^"]*' \
  40-kube-apiserver.yaml | sort -u > 41-apiserver-flags.txt

# 5. workloads (SI-07); add the V-242415 secret-env jq from the Secrets section
kubectl get pods -A -o json | jq -r '.items[].spec.containers[].image' | sort -u > 50-images.txt
grep -v '@sha256:' 50-images.txt > 51-unpinned-images.txt

# 6. frameworks and continuous scanner output
kubescape scan framework nsa,mitre,cis-v1.12.0 --use-artifacts-from ../kubescape-artifacts \
  --keep-local --format json --output 60-kubescape.json
kubectl get clustercompliancereports,configauditreports,rbacassessmentreports -A -o json > 61-trivy-operator.json

# 7. CIS on nodes: the only write, in namespace k8s-audit
kubectl -n k8s-audit apply -f ../kube-bench-master-job.yaml
kubectl -n k8s-audit wait --for=condition=complete job/kube-bench-master --timeout=10m
kubectl -n k8s-audit logs job/kube-bench-master > 70-kube-bench-master.json
kubectl -n k8s-audit delete job kube-bench-master

# 8. seal
sha256sum ./* > SHA256SUMS
```

Record the node-side checks by hand: the `etcdctl` canary, `stat` on the encryption config and PKI keys, the `openssl` probes and the audit-policy hash. On a managed cluster, replace steps 4 and 7 with the provider's node-only kube-bench Job and an export of its audit and encryption settings.

The auditor keeps the directory, `SHA256SUMS`, and a one-page summary (baseline, tool versions, counts per control, each FAIL as a finding in the Field Manual's template). CPCSC Level 1 expects evidence kept **for the attestation cycle, or at least one year**.

### Scheduled audit in GitLab CI

TBS asks for configuration checks "monthly and after configuration changes". A VMP may also want a scan within hours of a CCCS advisory. A weekly schedule covers the first, and `glab schedule run` covers the second. The job reaches the cluster through the GitLab agent. Set the agent's `ci_access` to impersonate `security-auditor`, so the job never inherits the agent's own identity.

```yaml
# .gitlab-ci.yml (audit project)
variables:
  KUBE_CONTEXT: "GROUP/cluster-agents:CLUSTER_NAME"

.k8s-audit:
  rules:
    - if: '$AUDIT == "k8s" && ($CI_PIPELINE_SOURCE == "schedule" || $CI_PIPELINE_SOURCE == "web")'
  before_script:
    - kubectl config use-context "$KUBE_CONTEXT"
    - mkdir -p evidence
  artifacts: {when: always, expire_in: 13 mos, paths: [evidence/]}

kubescape:
  extends: .k8s-audit
  image: REGISTRY/tools/kubescape:v4.0.14@sha256:DIGEST
  allow_failure: true                              # warn-first, per the gate policy
  script:
    - kubescape scan framework nsa,mitre,cis-v1.12.0 --use-artifacts-from kubescape-artifacts
        --keep-local --format json --output evidence/kubescape.json

kube-bench-and-state:
  extends: .k8s-audit
  image: REGISTRY/tools/kubectl:v1.35.2@sha256:DIGEST
  script:
    - kubectl -n k8s-audit delete job kube-bench-master --ignore-not-found
    - kubectl -n k8s-audit apply -f audit/kube-bench-master-job.yaml
    - kubectl -n k8s-audit wait --for=condition=complete job/kube-bench-master --timeout=10m
    - kubectl -n k8s-audit logs job/kube-bench-master > evidence/kube-bench-master.json
    - kubectl -n k8s-audit delete job kube-bench-master
    - kubectl get policyreports -A -o json > evidence/policyreports.json

seal:
  extends: .k8s-audit
  stage: .post
  image: REGISTRY/tools/cosign:v3.1.3@sha256:DIGEST
  needs: [kubescape, kube-bench-and-state]
  script:
    - cd evidence && sha256sum ./* > SHA256SUMS
    - cosign sign-blob --key "$EVIDENCE_SIGNING_KEY" --tlog-upload=false --bundle SHA256SUMS.bundle SHA256SUMS --yes
```

`kube-bench-master-job.yaml` is upstream's `job-master.yaml` with the image pinned to your mirror, the command set to `kube-bench run --targets master,etcd,controlplane,policies --benchmark cis-2.0 --json`, and namespace `k8s-audit`. A namespaced Role there grants the auditor `jobs` (create, delete, get) and `pods/log`.

```bash
glab schedule create --cron "0 6 * * 1" --cronTimeZone "America/Toronto" \
  --description "Weekly Kubernetes compliance audit" --ref main --variable "AUDIT:k8s"
glab schedule run SCHEDULE_ID        # the CCCS-advisory scan
```

> **Gotcha.** GitLab artifacts are not tamper-evident evidence. A Maintainer can delete them, and `expire_in` deletes them automatically. For `AU-09` and the one-year CPCSC retention, copy the sealed `evidence/` directory to write-once storage. The signature proves integrity, but it cannot bring back a deleted file.

> **Version-sensitive.** The agent's `ci_access` impersonation block depends on your GitLab and agent versions. Without impersonation, the job runs as the agent's own ServiceAccount, which usually holds far more than an auditor should.

### Gaps against the record

> **Gotcha.** **If no Kubernetes baseline is named** (no CIS Kubernetes, STIG or NSA/CISA guide), then `CM-06` has no organization-defined values, and every kube-bench FAIL is an opinion rather than a finding. Fix: one SSP line naming CIS Kubernetes 2.0.1, plus STIG V2R6 for deliveries that require it.

> **Gotcha.** If your organization keeps a technology adoption list, Kyverno and Kubescape need to be on it: this chapter puts Kyverno in the admission path. Propose Kyverno, Kubescape, kube-bench and the Trivy Operator together, and flag Kyverno 1.20's `ClusterPolicy` removal as an out-of-cycle review trigger.

> **Gotcha.** Security NFRs and release checklists usually state intent ("log authn decisions", "encrypt at rest") without **setting an audit policy, log retention, etcd encryption, PSA level or crypto standard** (ITSP.40.111, ITSP.40.062, CMVP). The files above are drop-in candidates.

### Checklist

- The SSP names CIS Kubernetes 2.0.1 (plus STIG V2R6 where the contract requires it), with deviations recorded.
- Scanners are mirrored and pinned by digest, and run as `security-auditor` (no Secrets, no `impersonate`).
- The tiered audit policy is in place, the STIG rotation values are set on the node, and TBS retention is set in the store.
- PSA `restricted` is the cluster default. Kyverno runs on `policies.kyverno.io/v1` only and its reports are exported weekly.
- Every namespace has a default-deny policy. TLS 1.2 minimum uses the STIG suites.
- etcd uses KMS v2 or `aesgcm`, never `secretbox`, and the canary shows `k8s:enc:`.
- Images are signed and verified with two attestors. The weekly evidence is sealed and kept for at least one year.


---


<a id="17-running-an-audit-end-to-end"></a>

## 17 · Running an audit end to end

*An audit is not a scan. It is a scoped system, a repeatable collection run, a sealed bundle of dated evidence, and a POA&M that turns every failure into an owner and a date. Build the pipeline once and every assessment after that is a download.*

### The shape of the work

```text
  scope ──> collect ──> seal ──> ship ──> triage ──> POA&M ──> fix ──> re-collect
  (who,     (read-only  (sha256, (off the (map to    (owner,    (via     (same
   what,     tools, one  tar)     host)    controls)  due date,  config   script,
   class)    run)                                     milestone) mgmt)    diff)
```

Three rules hold the whole thing together:

1. **Collection is read-only.** Nothing in the evidence run changes the system. Remediation goes through config management (chapter 07, *Generate a remediation script, don't run one blind*), and the next run proves it.
2. **One run, one bundle, one date.** An assessor wants to see the state of the system at a point in time, not a folder of files from different weeks.
3. **Evidence leaves the host.** A bundle stored on the host it describes can be rewritten by whoever compromises that host (the same argument as chapter 09 makes for the AIDE database).

Chapter 13 covers which controls and values apply. This chapter is the machinery.

### Scope first

Every finding and every piece of evidence is "for system X". If X is not written down, the assessor defines it for you, usually larger.

#### The system boundary

Write a one-page boundary statement before you run anything. It holds:

| Item | What to record | How to produce it |
|---|---|---|
| Components | Hosts, clusters, registries, CI runners, the media handoff | Inventory below |
| Interconnections | Every flow in and out, with protocol and port | Data flow diagram (the PSPC IT security inspection asks for one too) |
| Data | Classification of what is processed and stored | Security categorization |
| Profile | Which control set applies | ITSP.10.033-01 Medium, and/or CPCSC level |
| Exclusions | What is out, and why | Named, with the compensating boundary control |
| Owner | Who signs the POA&M | A name, not a team |

Inventory commands that feed it (read-only):

```bash
# hosts
hostnamectl
ip -brief address
ss -tulpnH

# containers
docker ps --all --format '{{.Image}}\t{{.Names}}\t{{.Ports}}'
podman ps --all --format '{{.Image}}\t{{.Names}}\t{{.Ports}}'

# clusters
kubectl get nodes -o wide
kubectl get ns --show-labels
kubectl get svc -A -o wide | grep -E 'LoadBalancer|NodePort'
kubectl get ingress,gateway,httproute -A

# every image actually running, the SBOM/scan target list
kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -u
```

> **Gotcha.** The CI runners that build what you ship are in scope. The SR family and any secure-SDLC pre-release gate are about the build, and for air-gapped delivery the offline media handoff is usually the dominant supply-chain risk. A boundary that stops at the production cluster leaves out the part an assessor is most interested in.

#### Data classification

Classification decides the profile, the SLA tier and how strictly the evidence itself is handled.

| Data in the system | Profile | VMP SLA effect | Evidence handling |
|---|---|---|---|
| Unclassified, no contract clause | internal baseline | as scored | normal |
| Specified information (CPCSC contract) | ITSP.10.171 at the contract's level | as scored | keep ≥1 year |
| Protected B candidate | ITSP.10.033-01 Medium | **one tier stricter** (VMP uplift) | the bundle may itself be sensitive |
| DND/CAF-connected | per the contract and DAOD 6003-series | one tier stricter | per contract |

> **Gotcha.** An evidence bundle contains `getent passwd`, the full package list with versions, listening ports, the firewall ruleset and every unpatched CVE. For a Protected B system that is a map for an attacker. Treat the bundle at the system's classification: encrypted at rest, access-controlled, and never attached to a ticket in a tool outside the boundary.

### The evidence pipeline

One default tool per question. Chapters 07 to 11 cover each tool in depth; this is where they fit together.

| Question | Default tool | Controls | Output kept | Needs |
|---|---|---|---|---|
| What's weak on this host? | Lynis (ch. 07) | `CM-06` | `lynis-report.dat`, log | root |
| Do we meet the named baseline? | OpenSCAP, `cis_server_l1` or your tailoring (ch. 07) | `CM-06`, `CM-07`, `AC-*`, `AU-*` | ARF, HTML report, per-rule results | root, matching data stream |
| Is auditing on, and what did it record? | `auditctl`, `aureport` (ch. 08) | `AU-02`, `AU-03`, `AU-12` | status, loaded rules, monthly reports | root |
| Did protected files change? | AIDE, `rpm -Va` (ch. 09) | `SI-07` | check output with exit code | root, a baseline DB |
| Is the container host configured to CIS Docker? | docker-bench-security (ch. 15) | `CM-06`, `AC-06`, `SC-07` | log and JSON | root, docker socket |
| Are the cluster components configured to CIS Kubernetes? | kube-bench (ch. 16) | `CM-06`, `AU-*`, `SC-*` | JSON | runs on a node or as a Job |
| Is the cluster posture sound (RBAC, pods, network)? | Kubescape, `nsa` framework (ch. 16) | `AC-06`, `SC-07`, `CM-07` | JSON | read-only kubeconfig |
| What is in each image, and what is vulnerable? | Syft SBOM + Grype (ch. 11); Trivy where only one binary is allowed | `RA-05`, `SI-02`, SR | CycloneDX SBOM, findings JSON | registry read access, vuln DB |
| What OS patches are outstanding? | `dnf updateinfo list --security` (ch. 11) | `SI-02`, `03.14.01` | list with advisory dates | repo metadata |

Why these defaults, briefly: **kube-bench over Kubescape for CIS**, because kube-bench v0.16.0 implements CIS Kubernetes 2.0 and Kubescape tops out at `cis-v1.12.0` (chapter 13, *The tool-lag problem*); Kubescape stays for the NSA/CISA and RBAC view kube-bench does not give. **Syft + Grype over Trivy for images**, because you keep the SBOM and re-scan it daily without touching the registry again, and because the SBOM is itself the SR evidence. **dnf over Trivy for Fedora OS packages**, because Trivy has no Fedora data (chapter 11).

#### Air-gapped vulnerability data

Grype and Trivy fetch their databases from the internet by default. Inside the perimeter they either fail or, worse, scan against a stale database and report "clean".

```bash
# outside: fetch and checksum the DB, carry it across with the release media
grype db list                      # available DB builds
# inside: import, disable auto-update, and record the DB build date in the bundle
grype db import vulnerability-db_VERSION.tar.zst
export GRYPE_DB_AUTO_UPDATE=false
grype db status

# Trivy equivalent: a mirrored DB in the internal registry
trivy image --db-repository REGISTRY/trivy-db --skip-db-update --offline-scan IMAGE
```

> **Version-sensitive.** `grype db import`, `GRYPE_DB_AUTO_UPDATE` and Trivy's `--db-repository`, `--skip-db-update` and `--offline-scan` are from the upstream docs for Grype 0.11x and Trivy 0.7x; neither tool is installed on the reference machine. Check `--help` on the version you mirror.

> **Gotcha.** A vulnerability scan is only as current as its database. **Record `grype db status` (or Trivy's DB metadata) in every bundle.** A report that says "0 Critical" against a 40-day-old DB is not `RA-05` evidence, and an assessor who knows the tools will ask for the DB date.

### The collection script

A complete, read-only collector. It runs every check whose tool is present, records every skip, captures stdout, stderr and exit code per check, and seals the result with SHA-256 sums. Non-zero exit codes are recorded as data, because scanners exit non-zero on findings (OpenSCAP 2, AIDE 1–7, kube-bench configurable).

Tested on Fedora 43 unprivileged with the slow checks skipped (the non-root checks fail and are recorded as such, which is the intended behaviour); `shellcheck` clean. The Kubernetes, docker-bench and SBOM branches were not exercised because those tools are not installed on the reference machine.

```bash
#!/usr/bin/env bash
# collect-evidence.sh: read-only audit evidence collection into one dated bundle.
# Runs every check it can, skips tools that are not installed, never remediates.
# Usage: sudo ./collect-evidence.sh [OUTPUT_ROOT]
# Env:   OSCAP_DS, OSCAP_PROFILE, OSCAP_TAILORING, IMAGES="img1 img2",
#        DOCKER_BENCH_DIR, KUBE_BENCH_TARGETS, KUBESCAPE_FRAMEWORK,
#        SKIP="lynis,oscap"  (comma list of check names to skip)
set -uo pipefail
umask 077

OUT_ROOT=${1:-/var/lib/evidence}
HOST=$(hostname -s)
STAMP=$(date -u +%Y-%m-%dT%H%M%SZ)
BUNDLE="$OUT_ROOT/${STAMP}_${HOST}"
OSCAP_PROFILE=${OSCAP_PROFILE:-cis_server_l1}
OSCAP_TAILORING=${OSCAP_TAILORING:-}
IMAGES=${IMAGES:-}
DOCKER_BENCH_DIR=${DOCKER_BENCH_DIR:-/opt/docker-bench-security}
KUBE_BENCH_TARGETS=${KUBE_BENCH_TARGETS:-node}
KUBESCAPE_FRAMEWORK=${KUBESCAPE_FRAMEWORK:-nsa}
SKIP=${SKIP:-}
TIMEOUT=${TIMEOUT:-3600}

mkdir -p "$BUNDLE"/{host,audit,integrity,containers,kubernetes,sbom,meta} || exit 1
INDEX="$BUNDLE/meta/index.tsv"
printf 'check\tfile\texit\tstarted_utc\tnote\n' > "$INDEX"
LOG="$BUNDLE/meta/run.log"

log()  { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$LOG" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
skipped() { [[ ",$SKIP," == *",$1,"* ]]; }
record() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "${5:-}" >> "$INDEX"; }

# run NAME OUTFILE CMD...: capture stdout to OUTFILE, stderr to OUTFILE.err,
# record the exit code. Non-zero is data (scanners exit 2 on findings), not failure.
run() {
  local name=$1 out=$2; shift 2
  local started; started=$(date -u +%FT%TZ)
  if skipped "$name"; then log "SKIP $name (SKIP list)"; record "$name" "-" "-" "$started" "skipped by SKIP"; return 0; fi
  log "RUN  $name"
  timeout "$TIMEOUT" "$@" > "$BUNDLE/$out" 2> "$BUNDLE/$out.err"
  local rc=$?
  [[ -s "$BUNDLE/$out.err" ]] || rm -f "$BUNDLE/$out.err"
  record "$name" "$out" "$rc" "$started"
  return 0
}
missing() { log "SKIP $1 ($2 not installed)"; record "$1" "-" "-" "$(date -u +%FT%TZ)" "$2 not installed"; }

# ---------- metadata ----------
{
  echo "host=$HOST"
  echo "bundle_utc=$STAMP"
  echo "uid=$(id -u)"
  echo "kernel=$(uname -r)"
  grep -E '^(NAME|VERSION_ID|VARIANT_ID)=' /etc/os-release
  echo "oscap_profile=$OSCAP_PROFILE"
  echo "oscap_tailoring=${OSCAP_TAILORING:-none}"
} > "$BUNDLE/meta/context.txt"
[[ $(id -u) -eq 0 ]] || log "WARN not root: auditd, AIDE and OpenSCAP results will be incomplete or wrong"

for t in lynis oscap aide auditctl docker podman trivy grype syft kube-bench kubescape kubectl; do
  if have "$t"; then printf '%s\t%s\n' "$t" "$("$t" --version 2>&1 | head -1)"; else printf '%s\tnot installed\n' "$t"; fi
done > "$BUNDLE/meta/tool-versions.tsv"
rpm -q openscap-scanner scap-security-guide aide audit >> "$BUNDLE/meta/tool-versions.tsv" 2>/dev/null

# ---------- host inventory and configuration (CM-08, CM-06, AC, SC) ----------
run os-release        host/os-release.txt       cat /etc/os-release
run packages          host/packages.txt         rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\t%{SIGPGP:pgpsig}\n'
run listening         host/listening.txt        ss -tulpnH
run enabled-units     host/enabled-units.txt    systemctl list-unit-files --state=enabled --no-pager
run accounts          host/accounts.txt         getent passwd
if have lastlog2; then run lastlog host/lastlog.txt lastlog2
elif have lastlog; then run lastlog host/lastlog.txt lastlog; fi
run selinux           host/selinux.txt          sestatus
run crypto-policy     host/crypto-policy.txt    update-crypto-policies --show
run fips-enabled      host/fips-enabled.txt     cat /proc/sys/crypto/fips_enabled
run repos-gpgcheck    host/repos.txt            sh -c 'grep -H -E "^(\[|gpgcheck|repo_gpgcheck|enabled)" /etc/yum.repos.d/*.repo'
if have sshd; then run sshd-effective host/sshd-effective.txt sshd -T; else missing sshd-effective sshd; fi
if have nft;  then run nft-ruleset   host/nft-ruleset.txt   nft list ruleset; else missing nft-ruleset nft; fi
if have firewall-cmd; then run firewalld host/firewalld.txt firewall-cmd --list-all-zones; fi
if have dnf;  then run security-updates host/security-updates.txt dnf -C -q updateinfo list --security; fi

# ---------- Lynis (CM-06, broad hardening) ----------
if have lynis; then
  run lynis host/lynis-stdout.txt lynis audit system --cronjob \
      --log-file "$BUNDLE/host/lynis.log" --report-file "$BUNDLE/host/lynis-report.dat"
else missing lynis lynis; fi

# ---------- OpenSCAP (CM-06 against a named benchmark) ----------
if have oscap; then
  if [[ -z "${OSCAP_DS:-}" ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "$ID" in
      rhel|centos|almalinux|rocky) OSCAP_DS=/usr/share/xml/scap/ssg/content/ssg-rhel${VERSION_ID%%.*}-ds.xml ;;
      fedora) OSCAP_DS=/usr/share/xml/scap/ssg/content/ssg-fedora-ds.xml ;;
      *) OSCAP_DS=/usr/share/xml/scap/ssg/content/ssg-${ID}${VERSION_ID//./}-ds.xml ;;
    esac
  fi
  if [[ -r "$OSCAP_DS" ]]; then
    oscap info --profile "$OSCAP_PROFILE" "$OSCAP_DS" > "$BUNDLE/host/oscap-profile-info.txt" 2>&1
    tailor=(); [[ -n "$OSCAP_TAILORING" ]] && tailor=(--tailoring-file "$OSCAP_TAILORING")
    run oscap host/oscap-rules.txt oscap xccdf eval "${tailor[@]}" --profile "$OSCAP_PROFILE" \
        --progress --thin-results \
        --results-arf "$BUNDLE/host/oscap-arf.xml" --report "$BUNDLE/host/oscap-report.html" "$OSCAP_DS"
  else missing oscap "data stream $OSCAP_DS"; fi
else missing oscap oscap; fi

# ---------- auditd (AU-02, AU-03, AU-12) ----------
if have auditctl; then
  run auditd-status audit/auditctl-status.txt auditctl -s
  run auditd-rules  audit/auditctl-rules.txt  auditctl -l
  cp /etc/audit/auditd.conf "$BUNDLE/audit/auditd.conf" 2>/dev/null && record auditd-conf audit/auditd.conf 0 "$(date -u +%FT%TZ)"
  # --input-logs: read the log files even though stdin is not a terminal (cron, systemd, CI)
  run aureport-summary audit/aureport-summary.txt aureport --input-logs --summary -i -ts this-month
  run aureport-auth    audit/aureport-auth.txt    aureport --input-logs -au --failed -i -ts this-month
  run aureport-mods    audit/aureport-mods.txt    aureport --input-logs -m -i -ts this-month
  run aureport-config  audit/aureport-config.txt  aureport --input-logs -c -i -ts this-month
  run aureport-keys    audit/aureport-keys.txt    aureport --input-logs -k --summary -i -ts this-month
else missing auditd auditctl; fi

# ---------- AIDE (SI-07) and package verification ----------
if have aide; then
  run aide-check integrity/aide-check.txt aide --check --no-color --no-progress
else missing aide-check aide; fi
run rpm-verify integrity/rpm-Va.txt rpm -Va --nomtime

# ---------- Docker / Podman (CIS Docker, AC, CM) ----------
if have docker && docker info >/dev/null 2>&1; then
  run docker-info    containers/docker-info.json    docker info --format '{{json .}}'
  run docker-ps      containers/docker-ps.txt       docker ps --all --no-trunc --format '{{.ID}}\t{{.Image}}\t{{.Names}}\t{{.Status}}'
  if [[ -r "$DOCKER_BENCH_DIR/docker-bench-security.sh" ]]; then
    run docker-bench containers/docker-bench.txt \
        sh -c "cd '$DOCKER_BENCH_DIR' && sh ./docker-bench-security.sh -b -l '$BUNDLE/containers/docker-bench.log'"
  else missing docker-bench "docker-bench-security in $DOCKER_BENCH_DIR"; fi
else missing docker "docker daemon"; fi
if have podman; then run podman-ps containers/podman-ps.txt podman ps --all --no-trunc; fi

# ---------- Kubernetes (CIS Kubernetes, NSA/CISA) ----------
if have kube-bench; then
  run kube-bench kubernetes/kube-bench.json kube-bench run --targets "$KUBE_BENCH_TARGETS" --json
else missing kube-bench kube-bench; fi
if have kubescape; then
  run kubescape kubernetes/kubescape-stdout.txt kubescape scan framework "$KUBESCAPE_FRAMEWORK" \
      --format json --output "$BUNDLE/kubernetes/kubescape-$KUBESCAPE_FRAMEWORK.json"
else missing kubescape kubescape; fi

# ---------- SBOMs and vulnerability matching (RA-05, SR) ----------
for img in $IMAGES; do
  safe=${img//[\/:@]/_}
  if have syft; then
    run "sbom:$img" "sbom/$safe.cdx.json" syft scan "$img" -o cyclonedx-json
  elif have trivy; then
    run "sbom:$img" "sbom/$safe.cdx.json" trivy image --quiet --format cyclonedx "$img"
  else missing "sbom:$img" "syft/trivy"; continue; fi
  if have grype; then
    run "vulns:$img" "sbom/$safe.grype.json" grype "sbom:$BUNDLE/sbom/$safe.cdx.json" -o json
  elif have trivy; then
    run "vulns:$img" "sbom/$safe.trivy.json" trivy sbom --quiet --format json "$BUNDLE/sbom/$safe.cdx.json"
  else missing "vulns:$img" "grype/trivy"; fi
done

# ---------- seal the bundle ----------
log "SEAL $BUNDLE"    # last line written inside the bundle; nothing may change after the sums
SUMS=$(mktemp)
( cd "$BUNDLE" && find . -type f -print0 | sort -z | xargs -0 sha256sum ) > "$SUMS"
mv "$SUMS" "$BUNDLE/SHA256SUMS"
tar -C "$OUT_ROOT" -czf "$BUNDLE.tar.gz" "$(basename "$BUNDLE")"
sha256sum "$BUNDLE.tar.gz" > "$BUNDLE.tar.gz.sha256"
echo "DONE $BUNDLE.tar.gz" >&2
cat "$BUNDLE.tar.gz.sha256"
```

Run it:

```bash
# full run, RHEL 9 host, tailored CIS L1, two images
sudo OSCAP_PROFILE=cis_l1_ours OSCAP_TAILORING=/etc/evidence/tailoring.xml \
     IMAGES="REGISTRY/app:TAG REGISTRY/worker:TAG" \
     ./collect-evidence.sh /var/lib/evidence

# quick smoke run: skip the minutes-long checks
sudo SKIP=oscap,aide-check,rpm-verify ./collect-evidence.sh /var/tmp/evidence

# verify a bundle later, anywhere
cd 2026-09-23T165312Z_HOST && sha256sum -c --quiet SHA256SUMS && echo intact
```

What the design choices buy:

| Choice | Why |
|---|---|
| `set -uo pipefail`, no `-e` | One failing check must not abort the run; the exit code goes in the index instead |
| `umask 077` | The bundle is sensitive (see Data classification) |
| UTC timestamp in the directory name | Bundles from different time zones sort and compare |
| `--input-logs` on every `aureport` | Without it, aureport reads **stdin** when stdin is not a terminal, so under cron, systemd or CI it reports nothing (verified in `aureport --help`: "Use the logs even if stdin is a pipe") |
| `--thin-results` on OpenSCAP | Full ARF is ~30 MB per run (chapter 07); keep a full one only for the formal assessment |
| `oscap info --profile` captured | Records which benchmark version the profile implements, answering the tool-lag question in the bundle itself |
| Tool versions in `meta/` | An assessor asks "which version of the scanner?"; the answer is in the bundle |
| Sums computed last, `SEAL` logged first | Any file written after the sums breaks verification; the first test run caught exactly that |

> **Gotcha.** `lastlog` is gone on Fedora 43; `lastlog2` replaces it (verified: only `/usr/bin/lastlog2` exists). The script tries both. Anything that parses the old `lastlog` format will break on newer hosts.

> **Gotcha.** Run as root, or the evidence is wrong rather than partial. Unprivileged, `auditctl` exits 4, `aureport` cannot open the log, and OpenSCAP marks unreadable checks `fail` (chapter 07). The script warns in `run.log`; an assessor reading a bundle with `uid=1000` in `meta/context.txt` should reject it.

#### Unattended runs

A systemd timer, monthly to match TBS's "configuration checking monthly", plus on demand after a change.

```ini
# /etc/systemd/system/evidence-collect.service
[Unit]
Description=Collect read-only audit evidence bundle
After=network-online.target auditd.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/collect-evidence.sh /var/lib/evidence
Nice=10
IOSchedulingClass=idle
# read-mostly: the collector only needs to write its bundle
ProtectSystem=full
ReadWritePaths=/var/lib/evidence
PrivateTmp=yes
```

```ini
# /etc/systemd/system/evidence-collect.timer
[Unit]
Description=Monthly audit evidence collection

[Timer]
OnCalendar=*-*-01 03:00:00
RandomizedDelaySec=2h
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now evidence-collect.timer
systemctl list-timers evidence-collect.timer
journalctl -u evidence-collect.service -n 50
```

> **Note.** Do not add `ProtectHome=yes` or `PrivateDevices=yes`: AIDE and OpenSCAP read home directories and device nodes as part of their checks, and a sandboxed collector silently reports a cleaner system than the real one. This is one unit where the chapter 06 sandboxing advice does not apply.

#### Getting the bundle off the host

Ship the tarball and its `.sha256` to a store the host cannot modify. In order of preference:

1. **Pulled by the evidence store** over SSH with a forced command that only allows reading `/var/lib/evidence` (chapter 03). The host never holds credentials to the store.
2. **Pushed to the GitLab generic package registry** from a CI job (below), where package files are immutable once published.
3. **Written to the log host** alongside audit logs, under the same retention.

Record the tarball's SHA-256 somewhere separate from the tarball, such as the CI job log or the POA&M row. Sums stored beside the file protect against corruption, not against an attacker who can rewrite both.

> **One-way door.** Deleting an evidence bundle is not recoverable, and CPCSC asks you to keep evidence for the attestation cycle or at least one year; TBS keeps incident records two years. Set retention at the store to **13 months minimum**, 2 years for anything tied to an incident, and make deletion a named person's action, not a cron job.

### The evidence index

The index is what an assessor reads first. `meta/index.tsv` is the machine version; the human version maps each file to a control and a verdict. A sample for one host run:

| # | Control | Check | File | Exit | Result | Notes |
|---|---|---|---|---|---|---|
| E-01 | `CM-08` | Installed packages with signatures | `host/packages.txt` | 0 | 1,412 packages, all signed | |
| E-02 | `CM-06` | CIS RHEL 9 L1 Server v2.0.0 (SSG 0.1.82), tailored | `host/oscap-report.html`, `host/oscap-arf.xml` | 2 | 214 pass, 9 fail, 3 N/A | Fails → POA&M-0042..0050 |
| E-03 | `CM-06` | Lynis hardening index | `host/lynis-report.dat` | 0 | index 78 | 12 suggestions triaged |
| E-04 | `AU-02`, `AU-12` | auditd enabled, rules loaded | `audit/auditctl-status.txt`, `audit/auditctl-rules.txt` | 0 | `enabled 2`, 61 rules | Immutable mode on |
| E-05 | `AU-03` | Failed authentication, month to date | `audit/aureport-auth.txt` | 0 | 17 failures, 1 source | Reviewed by NAME, DATE |
| E-06 | `AU-11` | Log host retention config | `records/loghost-retention.txt` | n/a | 95 d online, 200 d archive | Manual, from the log host |
| E-07 | `SI-07` | AIDE check | `integrity/aide-check.txt` | 4 | 3 changed files | All in change CHG-NNN |
| E-08 | `SC-13` | Crypto policy and FIPS | `host/crypto-policy.txt`, `host/fips-enabled.txt` | 0 | `FIPS`, `1` | |
| E-09 | `SC-07`, `03.13.01` | Host firewall ruleset | `host/nft-ruleset.txt` | 0 | default drop inbound | |
| E-10 | `IA-02`, `03.05.03` | sshd effective config | `host/sshd-effective.txt` | 0 | keys only, root denied | |
| E-11 | `SI-02`, `03.14.01` | Outstanding security advisories | `host/security-updates.txt` | 0 | 2 Important | Within SLA; POA&M-0051 |
| E-12 | `CM-06` | CIS Docker 1.6.0 (docker-bench) | `containers/docker-bench.log.json` | 0 | 6 WARN | CIS 1.8.0 delta checked manually, E-12a |
| E-13 | `CM-06` | CIS Kubernetes 2.0 node checks | `kubernetes/kube-bench.json` | 0 | 2 FAIL | POA&M-0052, 0053 |
| E-14 | `AC-06`, `SC-07` | Kubescape NSA framework | `kubernetes/kubescape-nsa.json` | 0 | compliance 81% | |
| E-15 | `RA-05`, SR | SBOM + vulnerability scan, per image | `sbom/*.cdx.json`, `sbom/*.grype.json` | 0 | 1 High (fixed upstream) | DB built 2026-09-22 |
| E-16 | all | Bundle integrity | `SHA256SUMS`, tarball `.sha256` | 0 | verified at the store | Hash in CI job log |

Rules for the index:

- **Every row has a control ID**, in ITSP.10.033 or ITSP.10.171 form. A file that maps to no control is noise; a control with no row is a gap.
- **Every failure has a POA&M reference** or a tailoring reference. "Known" is not a status.
- **Manual evidence gets a row too** (E-06): the log host's retention, restore tests, access reviews. Most of CPCSC Level 1 is this kind of row.
- **The benchmark version is in the Check column**, as implemented by the tool.

### From findings to a POA&M

A POA&M (plan of action and milestones) is the list of every known weakness with an owner, a plan and a date. Under ITSG-33 (Annex 2), IATO/ATO reporting runs through the POA&M; this is how the scan output gets there.

#### The fields

| Field | Content | Source |
|---|---|---|
| ID | `SYSTEM-DATE-N`, stable forever | generated |
| Control | ITSP.10.033 / ITSP.10.171 ID | evidence index |
| Weakness | Rule ID, CVE or manual finding | scanner output |
| Evidence | Bundle and file | index |
| Severity | CVSS / scanner severity as reported | scanner |
| Tier | Severity after the VMP Protected B uplift | classification |
| Detected | Date first seen, never reset | first bundle containing it |
| Due (target / hard) | From the VMP SLA table on the tier | computed |
| Milestones | Dated steps: fix merged, image rebuilt, deployed, re-scan clean | owner |
| Owner | One named person | triage |
| Verifier | Not the owner, for Critical and High | triage |
| Status | open, in progress, risk accepted, closed | owner |
| Risk acceptance | Reference, approver, expiry | your risk-acceptance matrix |

#### Due dates from the SLAs

Your VMP SLAs (the example policy from chapter 13), with the Protected B uplift (one tier stricter for Protected B candidate data, DND/CAF-connected systems and auth or crypto components) and, for systems under a DND contract, the TBS guideline as a cap on the hard deadline (chapter 13, *Patch timelines*):

| Tier | VMP target | VMP hard | Hard, capped by TBS |
|---|---|---|---|
| Critical | 24 h | 72 h | 48 h |
| High | 7 d | 14 d | 14 d |
| Medium | 30 d | 60 d | 30 d |
| Low | 90 d | 180 d | 90 d |

A converter from Grype JSON to POA&M rows (tested with `jq` against sample Grype output; `shellcheck` clean):

```bash
#!/usr/bin/env bash
# grype-to-poam.sh: Grype JSON -> POA&M CSV rows with due dates from the VMP SLAs.
# Usage: grype-to-poam.sh FINDINGS.json SYSTEM DETECTED_DATE [PROTECTED_B=0|1] [TBS_SCOPE=0|1]
set -euo pipefail
in=$1 system=$2 detected=$3 pb=${4:-0} tbs=${5:-0}

jq -r --arg sys "$system" --arg det "$detected" --argjson pb "$pb" --argjson tbs "$tbs" '
  def tiers:  ["Negligible","Low","Medium","High","Critical"];
  def uplift(s): if $pb == 1 and s != "Critical" and s != "Negligible" and s != "Unknown"
                 then tiers[(tiers | index(s)) + 1] else s end;
  # VMP target / hard deadline in days; TBS guideline caps the hard deadline when in scope
  def target(s): {"Critical":1,"High":7,"Medium":30,"Low":90}[s] // 180;
  def hard(s):   ({"Critical":3,"High":14,"Medium":60,"Low":180}[s] // 365) as $v
                 | if $tbs == 1 then ([$v, ({"Critical":2,"High":14,"Medium":30,"Low":90}[s] // $v)] | min) else $v end;
  def due(d): ($det + "T00:00:00Z" | fromdateiso8601) + d * 86400 | strftime("%Y-%m-%d");
  ["poam_id","system","control","source","finding","component","severity","tier","detected","due_target","due_hard","fix","status"],
  ( .matches
    | map(select(.vulnerability.fix.state == "fixed"))
    | unique_by(.vulnerability.id + .artifact.name + .artifact.version)
    | to_entries[]
    | .value as $m | uplift($m.vulnerability.severity) as $t
    | [ "\($sys)-\($det)-\(.key + 1)", $sys, "RA-05 / SI-02", "grype",
        $m.vulnerability.id, "\($m.artifact.name) \($m.artifact.version)",
        $m.vulnerability.severity, $t, $det, due(target($t)), due(hard($t)),
        ($m.vulnerability.fix.versions | join(" ")), "open" ] )
  | @csv' "$in"
```

```bash
# unclassified system, VMP SLAs only
grype-to-poam.sh sbom/app.grype.json appliance 2026-09-23 > poam-new.csv

# Protected B candidate under a DND contract: uplift on, TBS cap on
grype-to-poam.sh sbom/app.grype.json appliance 2026-09-23 1 1 > poam-new.csv
```

On the test data, a Medium became tier High with a target 7 days out, and a High became Critical with a hard deadline 2 days out. The script keeps only findings with a fix available; **unfixed findings still go on the POA&M**, as risk-acceptance rows with a review date, because "no fix exists" is a decision someone has to own.

OpenSCAP failures come from the per-rule results the collector keeps:

```bash
# one line per failed rule: these become POA&M rows or tailoring entries
grep -E ':fail$' host/oscap-rules.txt | cut -d: -f1 | sed 's/^xccdf_org.ssgproject.content_rule_//'

# what changed since last month's bundle
diff <(grep -E ':fail$' PREV/host/oscap-rules.txt | sort) \
     <(grep -E ':fail$' CURR/host/oscap-rules.txt | sort)
```

Each failed rule ends one of three ways: **fixed** (through config management, verified by the next bundle), **tailored out** (with the reason, in the committed tailoring file, which is then itself evidence), or **POA&M** with a date. Nothing stays failed without one of those three.

> **Gotcha.** "Detected" must be the date the finding **first** appeared, not the date of the bundle you are looking at. Regenerating the POA&M from each new scan resets every clock and makes every overdue item look new. Join new findings against the existing POA&M on (control, weakness, component) and keep the original date.

> **Gotcha.** A sound VMP requires Critical and High acceptances to be disclosed in the IATO package, and forbids the remediating developer from self-verifying a Critical or High fix. Put the verifier in the POA&M row. A row closed by its owner, with no second name, is the first thing an assessor samples.

### Continuous compliance in GitLab CI

The host timer covers hosts. A scheduled pipeline covers what CI can reach: registry images, SBOMs, the cluster through a read-only kubeconfig, and the POA&M diff. The same job output doubles as the pre-release gate's evidence, which secure-SDLC standards require and many pipelines do not yet produce.

```yaml
# .gitlab-ci.yml (audit project)
stages: [collect, report, publish]

variables:
  EVIDENCE_DATE: ""          # set in before_script
  GRYPE_DB_AUTO_UPDATE: "false"

.audit:
  rules:
    - if: '$CI_PIPELINE_SOURCE == "schedule" && $AUDIT == "1"'
    - if: '$CI_PIPELINE_SOURCE == "web"'
  before_script:
    - export EVIDENCE_DATE=$(date -u +%Y-%m-%d)
    - mkdir -p evidence/sbom evidence/kubernetes evidence/meta

images:sbom-and-scan:
  extends: .audit
  stage: collect
  image: REGISTRY/tools/syft-grype:PINNED_DIGEST
  script:
    - grype db import "$GRYPE_DB_FILE"          # DB carried in with the release media
    - grype db status > evidence/meta/grype-db-status.txt
    - |
      for img in $(cat images.txt); do
        safe=$(echo "$img" | tr '/:@' '___')
        syft scan "registry:$img" -o cyclonedx-json="evidence/sbom/$safe.cdx.json"
        grype "sbom:evidence/sbom/$safe.cdx.json" -o json > "evidence/sbom/$safe.grype.json" || true
      done
  artifacts:
    paths: [evidence/]
    expire_in: 13 mos

cluster:posture:
  extends: .audit
  stage: collect
  image: REGISTRY/tools/kubescape:PINNED_DIGEST
  script:
    - kubescape scan framework nsa --kubeconfig "$AUDIT_KUBECONFIG" --format json --output evidence/kubernetes/kubescape-nsa.json
  artifacts:
    paths: [evidence/]
    expire_in: 13 mos

cluster:kube-bench:
  extends: .audit
  stage: collect
  image: REGISTRY/tools/kubectl:PINNED_DIGEST
  script:
    # kube-bench must run on a node: launch the upstream Job manifest, wait, collect its log
    - kubectl --kubeconfig "$AUDIT_KUBECONFIG" apply -f kube-bench-job.yaml
    - kubectl --kubeconfig "$AUDIT_KUBECONFIG" wait --for=condition=complete job/kube-bench --timeout=10m
    - kubectl --kubeconfig "$AUDIT_KUBECONFIG" logs job/kube-bench > evidence/kubernetes/kube-bench.txt
    - kubectl --kubeconfig "$AUDIT_KUBECONFIG" delete job/kube-bench
  artifacts:
    paths: [evidence/]
    expire_in: 13 mos

poam:diff:
  extends: .audit
  stage: report
  image: REGISTRY/tools/jq:PINNED_DIGEST
  script:
    - for f in evidence/sbom/*.grype.json; do ./grype-to-poam.sh "$f" "${f##*/}" "$EVIDENCE_DATE" "$PROTECTED_B" "$TBS_SCOPE"; done > evidence/poam-new.csv
  artifacts:
    paths: [evidence/]
    expire_in: 13 mos

publish:bundle:
  extends: .audit
  stage: publish
  image: REGISTRY/tools/curl:PINNED_DIGEST
  script:
    - (cd evidence && find . -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
    - tar -czf "evidence-$EVIDENCE_DATE.tar.gz" evidence
    - sha256sum "evidence-$EVIDENCE_DATE.tar.gz" | tee "evidence-$EVIDENCE_DATE.tar.gz.sha256"
    - |
      for f in "evidence-$EVIDENCE_DATE.tar.gz" "evidence-$EVIDENCE_DATE.tar.gz.sha256"; do
        curl --fail --header "JOB-TOKEN: $CI_JOB_TOKEN" --upload-file "$f" \
          "$CI_API_V4_URL/projects/$CI_PROJECT_ID/packages/generic/evidence/$EVIDENCE_DATE/$f"
      done
```

Create the schedule (verified flags, `glab` 1.108):

```bash
glab schedule create --cron "0 4 1 * *" --cronTimeZone "UTC" \
  --description "Monthly audit evidence" --ref main --variable "AUDIT:1"
glab schedule list
glab schedule run SCHEDULE_ID     # an on-demand run, e.g. after a change
```

Why it is shaped this way:

- **Scanner images pinned by digest from the internal registry**, because the audit job is part of the supply chain it audits, and an air-gapped deployment forbids external pulls anyway.
- **`AUDIT_KUBECONFIG` is a read-only identity** (a `view`-style ClusterRole plus read on RBAC objects), stored as a file-type CI/CD variable, protected and masked. The one write it needs is the kube-bench Job; give that its own namespace-scoped role, or run kube-bench from the host collector instead.
- **`|| true` on Grype** so findings do not fail the collect job; blocking belongs in the MR pipeline, where warn-then-block rules apply, not in the audit schedule.
- **The generic package registry for the bundle**, because job artefacts expire and can be deleted with the pipeline; published package files are the durable copy.

> **Gotcha.** Job artefacts are not an archive. They expire (the instance default is often 30 days), they vanish when someone deletes the pipeline, and "keep latest artefacts" keeps only the most recent. `expire_in: 13 mos` covers the CPCSC year for convenience; the generic package upload is the retained copy.

> **Gotcha.** The pinned scanner images drift behind the benchmark (chapter 13, *The tool-lag problem*) and the vuln DB goes stale between media drops. Put "scanner image digest" and "DB build date" in `evidence/meta/` and review them quarterly, or the pipeline keeps producing confident, outdated green.

### What an assessor asks for

The two CPCSC paths want different things. What follows combines the published program pages with what 800-171A-style assessments normally examine; items marked inferred are not stated on the CPCSC pages.

#### Level 1: self-assessment

You answer the CCCS online self-assessment for the 13 controls, then upload proof and the expiry date to your CanadaBuys profile. Nobody visits. The risk is not failing an interview; it is **attesting to something you cannot later show**, because the evidence must be kept for the attestation cycle or at least a year and can be requested.

| Practice area | Controls | What to have on file |
|---|---|---|
| Accounts and access | `03.01.01`, `03.01.02` | Account list per system with owners; last access review, dated and signed; RBAC binding export |
| External systems and public content | `03.01.20`, `03.01.22` | Approved registries and SaaS list; public repo and image review |
| Authentication | `03.05.01`, `03.05.02`, `03.05.03` | `sshd -T` output; IdP MFA policy; device and host key inventory |
| Media | `03.08.03` | Sanitization records with serial numbers and method |
| Physical | `03.10.01`, `03.10.07` | Authorized access list; visitor logs |
| Boundary, patching, malware | `03.13.01`, `03.14.01`, `03.14.02` | Firewall and NetworkPolicy exports; monthly update logs and POA&M; EDR coverage report |

The monthly host bundle plus the CI bundle covers every technical row. The rest are records someone has to keep on a calendar.

#### Level 2: third-party assessment

An SCC-accredited certification body assesses 98 controls against ITSP.10.171 using ITSP.10.171-01. Expect (inferred from 800-171A practice, which ITSP.10.171-01 adapts):

- **A system security plan** with an implementation statement per control, and the boundary from Scope first. There is no SSP today; this is the longest lead item.
- **Examine, interview, test.** They read the policy, ask the engineer how it works, and then ask you to show it live: "show me the failed logins for last Tuesday", "add a user and show me the audit record", "show me this image's SBOM and its scan date".
- **History, not a snapshot.** Twelve months of monthly bundles show a control operating; one bundle made last week shows a control that exists. This is why the pipeline has to start well before Level 2 appears in a contract.
- **Sampling.** They pick a few hosts, images and POA&M rows and trace each end to end: finding, owner, fix commit, rebuilt image digest, re-scan.
- **Organization-defined values.** Every `[Assignment: ...]` parameter filled and justified: retention periods, lockout thresholds, scan frequency. The named baseline (chapter 13) supplies most of them.
- **POA&M discipline.** Whether overdue items exist and whether risk acceptances are current. How many open POA&M items a Level 2 certification tolerates is not published (unconfirmed).

| Asked for | Level 1 | Level 2 |
|---|---|---|
| Who judges | You | SCC-accredited body |
| Scope statement | Implicit | Written, with data flows |
| SSP | Not required | Expected |
| Evidence depth | Exists, dated, kept ≥1 year | Operating over time, sampled, demonstrated live |
| Technical scans | Supporting | Central to `03.04`, `03.11`, `03.13`, `03.14` families |
| POA&M | Good practice | Examined row by row |

### Checklist

- [ ] Boundary statement written, with components, flows, data classification, profile and owner
- [ ] CI runners and the media handoff inside the boundary
- [ ] One named baseline and a committed tailoring file per host role
- [ ] `collect-evidence.sh` installed on every in-scope host, running monthly from a timer, as root
- [ ] Bundles shipped off-host; tarball hash recorded separately; retention 13 months minimum
- [ ] Vulnerability DB imported with each media drop; DB date in every bundle
- [ ] Scheduled GitLab pipeline for images, SBOMs and cluster posture; bundle published to the package registry
- [ ] Evidence index per bundle, every row with a control ID, every failure with a POA&M or tailoring reference
- [ ] POA&M keyed on first-detected date, with owner, verifier and SLA due dates including the Protected B uplift
- [ ] Manual evidence (access reviews, restore tests, sanitization records, log host retention) on a calendar

### Traps

- **Scanning unprivileged.** OpenSCAP marks unreadable checks as failures, `auditctl` exits 4, `aureport` reads nothing. Evidence from a non-root run is wrong, not partial.
- **`aureport` without `--input-logs` under cron or CI.** Reads stdin, reports nothing, exits cleanly.
- **Stale vulnerability DB in the air gap.** "0 Critical" means nothing without the DB date.
- **Evidence stored on the host it describes.** Whoever owns the host owns the evidence.
- **Sums written before the last file.** Verification fails later and looks like tampering.
- **Resetting "detected" dates** by regenerating the POA&M from each scan.
- **Artefacts as archive.** They expire; the package registry copy is the record.
- **Remediating from the audit run.** Collection is read-only; fixes go through config management and the next bundle proves them.
- **Quoting the benchmark without the version the tool implements.**
- **Starting the evidence history when Level 2 appears in a contract.** An assessor wants to see controls operating over months.


---
