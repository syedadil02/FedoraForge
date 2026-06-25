<div align="center">
  <h1>🚀 FedoraForge: Bare-Metal Orchestrator</h1>
  <p><strong>An Idempotent, Infrastructure-as-Code Deployment Engine for Fedora Server</strong></p>
  <p>
    <code>Bash</code> · <code>Docker</code> · <code>ZFS</code> · <code>Nginx</code> · <code>Tailscale</code> · <code>Fedora</code> · <code>SELinux</code> · <code>Firewalld</code>
  </p>
</div>

---

**FedoraForge** is a highly resilient, state-tracked shell orchestration engine designed to transform a fresh Fedora Linux installation into a fully configured, production-grade FedoraForge deployment.

Rather than relying on massive single-point-of-failure deployment scripts, this engine uses a **Phase-based architecture** (`run_phase`). It tracks successful deployments via a `.deploy_state` file, meaning if the script is interrupted, the server reboots, or an error occurs, the orchestrator will seamlessly resume exactly where it left off without duplicating containers or corrupting data.

---

## 🎯 Design Decisions

- **Phase-based over a monolithic script:** A single 500-line script failing halfway through a 40-minute deployment means starting over from scratch. Phases with state tracking mean failures are recoverable in seconds, not minutes, and each phase can be re-run, debugged, or extended in isolation.
- **ZFS over plain LVM:** Needed copy-on-write snapshots and reliable handling of mixed NVMe/HDD pools for hot and cold data, without manually tiering storage by hand.
- **Tailscale over public exposure:** Zero attack surface from the public internet by default. Every service is reachable only over the tailnet, with Nginx handling internal TLS termination and routing.
- **Dynamic hardware detection over hardcoded configs:** Bare-metal and VM deployments shouldn't need separate codepaths maintained by hand. The orchestrator detects what's actually present (GPU via `lspci`, disk layout) and adapts at runtime.

---

## ⚙️ Core Features

- **Stateful Resumption:** Built-in caching and deployment tracking via `.deploy_state`.
- **Dynamic Hardware Detection:** Automatically scans the PCI bus (`lspci`) for physical GPUs. If a bare-metal GPU is found, it dynamically auto-injects hardware passthrough (`/dev/dri`) into resource-heavy containers (like Wolf and Immich). Safely bypasses passthrough on VMs to prevent DRM crashes.
- **Storage Offloading:** Automatically expands Fedora LVM volumes (`xfs_growfs`) and relocates Docker/Containerd image extraction layers to an NVMe ZFS pool to prevent root disk exhaustion.
- **Secure by Default:** Integrates tightly with Tailscale (MagicDNS via `systemd-resolved`), ensuring no services are exposed to the public internet. All web traffic is routed internally via an Nginx reverse proxy using secure TLS certificates.
- **Disaster Recovery:** Includes a fully automated backup engine using Duplicati. Read-only volume mounts protect the system from ransomware, while live Postgres/MySQL databases are automatically exported to static `.sql` dumps via nightly cronjobs before being encrypted and sent offsite.

---

## 🛠️ Services Deployed

The orchestrator configures the host operating system, establishes ZFS storage pools, configures the network firewall, and deploys the following microservices:

### 🎮 Compute & Media
- **[Wolf](https://gamesonwhales.github.io/wolf/)**: Ultra-low latency Cloud Gaming & Desktop streaming (GPU Accelerated).
- **[Immich](https://immich.app/)**: Self-hosted photo and video backup (Postgres `pgvecto-rs` + Redis + Hardware Accelerated Machine Learning).
- **[Kavita](https://www.kavitareader.com/)**: Fast, feature-rich reading server for comics and books.

### 🛡️ Security & Network
- **[Tailscale](https://tailscale.com/)**: Zero-trust mesh VPN.
- **[Snort 3](https://www.snort.org/)**: Bare-metal Network/Host Intrusion Detection System (IDS).
- **[AdGuard Home](https://adguard.com/)**: Network-wide ad blocking and DNS sinkholing.
- **[Vaultwarden](https://github.com/dani-garcia/vaultwarden)**: Self-hosted Bitwarden password manager API.
- **[Nginx](https://nginx.org/)**: Modular Reverse Proxy handling internal Tailnet routing.

### 📊 Monitoring & Dashboard
- **[Homepage](https://gethomepage.dev/)**: Highly customizable, dynamic application dashboard.
- **[Prometheus](https://prometheus.io/)**: Time-series metrics aggregator.
- **[cAdvisor](https://github.com/google/cadvisor) & Node Exporter**: Container and host-level resource telemetry.

### 🗄️ Utilities & Storage
- **[Gitea](https://gitea.io/)**: Self-hosted Git service.
- **[Samba](https://www.samba.org/)**: High-speed network file sharing.
- **[SearXNG](https://docs.searxng.org/)**: Privacy-respecting metasearch engine.
- **[FreshRSS](https://freshrss.org/)**: Self-hosted RSS feed aggregator.

---

## ⚠️ Requirements & Disclaimers

> [!WARNING]
> **OS Limitation:** This script is currently strictly engineered for **Fedora 44 (Server/Workstation)**. It relies heavily on `dnf5`, `systemd-resolved`, and Fedora's default Firewalld/SELinux architecture.
>
> [!IMPORTANT]
> **Storage Assumptions:** The script assumes a **3-Disk Architecture**:
> 1. OS Root Drive
> 2. NVMe Drive (ZFS `fastpool` for high-I/O databases/VMs)
> 3. HDD Drive (ZFS `datapool` for bulk media/backups)
>
> *(Note: The script is fully modular, so you can easily alter `deploy.sh` to map everything to a single drive according to your specific needs).*

> [!NOTE]
> **Idempotency:** Because this orchestrator pulls large Docker images and compiles kernel modules, network timeouts can happen. Do not panic if a phase fails! Simply re-run `sudo bash deploy.sh`. The orchestrator will clean up orphaned containers from the failed phase and gracefully resume.
>
> **Failsafe:** Add custom DNS (1.1.1.1 or your preferred DNS) under the Tailscale DNS settings and set it to override to avoid name resolution errors.

---

## 🚀 How to Use

1. Clone the repository to your Fedora bare-metal machine.
2. Make the orchestrator executable:
   ```bash
   chmod +x deploy.sh
   ```
3. Run the interactive deployment wizard (requires `sudo`):
   ```bash
   sudo bash deploy.sh
   ```
4. Follow the on-screen prompts to select your storage disks, configure your Tailscale Auth Key, and set your administrative passwords.
   * *Note: The wizard securely saves your passwords and configuration to `environment/active.env`. This file is git-ignored to prevent accidental credential leaks. If you ever need to change your database passwords or Tailscale settings, you can edit that file directly.*
5. The orchestrator will compile ZFS, pull Docker images, and initialize the databases.

Once finished, navigate to your server's Tailscale domain in your browser to view your Homepage dashboard!

---

## 🛠️ Guide: Adding Custom Services

**FedoraForge** is designed to be highly extensible. If you want to add a new service (e.g., Plex, Nextcloud, HomeAssistant), you can do it in under two minutes using the built-in template system.

1. **Copy the Template:** Duplicate the `99_template_module` to create your new module.
   ```bash
   cp -r modules/99_template_module modules/18_my_custom_service
   ```
2. **Tweak the Configurations:**
   - Edit `docker-compose.yml` and replace the `hello-world` image with your desired Docker image.
   - Edit `configure.sh` to update the internal port mapping and Nginx proxy location.
3. **Register the Module:** Open `deploy.sh`, scroll to the bottom execution list, and register your module as a new deployment phase:
   ```bash
   run_phase "18" "My Custom Service" "./modules/18_my_custom_service/install.sh && ./modules/18_my_custom_service/configure.sh"
   ```

Because FedoraForge globally handles Nginx hot-reloading, rollback trapping, TLS provisioning, and state tracking, your custom module instantly gains all of these features automatically!

---
<img width="2560" height="973" alt="Screenshot From 2026-06-25 23-03-49 (Edited)" src="https://github.com/user-attachments/assets/daa96ee4-f0f8-4a08-b6ee-53120d9d7bd9" />
---

## 📄 License

This project is licensed under the MIT License.
