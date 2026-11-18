# Fedora Blue

kays eigenes bootc-Image: `ghcr.io/ublue-os/silverblue-main:45` plus eigene Pakete. Gebaut per GitHub Actions (montags 10:05 UTC und bei Push) nach `ghcr.io/kay-ki/fedora-blue:latest`, signiert mit cosign.

## Struktur
- `build_files/packages.json`: einzige Stelle für Pakete (install/exclude/remove), Repos, Coprs, Dienste (system + user), /opt-Ordner, Kernelmodule und Pflichtdateien. Ein neues Paket = eine Zeile.
- `build_files/kmods/88x2bu/`: kays bewährter rtl88x2bu-Stand (lokale Abweichungen von morrownr upstream) plus Kernel-7.3-Patch (`cookie` als Wert). Wird im Build gegen den Image-Kernel gebaut und per modules-load.d geladen; scheitert er, entsteht kein Image (Torwächter gegen Kernel-Sprünge).
- `build_files/repos/*.repo`: Drittanbieter-Repos, nur während des Builds aktiv.
- `build_files/build.sh`: liest nur `packages.json`.
- `system_files/`: wird 1:1 nach `/` kopiert (brew-PATH, Registry-Signaturconfig).
- `cosign.pub` im Repo, `cosign.key` nur lokal (gitignored) und als GitHub-Secret `SIGNING_SECRET`.

## Befehle
Das System läuft von `ostree-image-signed:docker://ghcr.io/kay-ki/fedora-blue:latest` (öffentliches Repo, seit 18.11.). Updates holt `rpm-ostreed-automatic` (stage), aktiv nach Neustart.
- Neu bauen: Push auf `main` oder `gh workflow run build.yml --repo kay-ki/fedora-blue`.
- Lokal bauen (ohne GitHub): `podman build -t localhost/fedora-blue:test .`, dann `podman save --format oci-dir -o /var/mnt/storage/fedora-blue-oci localhost/fedora-blue:test` und `sudo rpm-ostree rebase ostree-unverified-image:oci:/var/mnt/storage/fedora-blue-oci`.
- Zurück: Bootmenü oder `rpm-ostree rollback`. Die Bluefin-Deployments sind nicht mehr gepinnt und verschwinden beim nächsten Deployment.

## Fallen
- zsh ist kays Login-Shell: muss im Image bleiben (`required` prüft das).
- WLAN-Stick: Modul kommt aus dem Image. `/etc/rtl88x2bu-fix.sh` baut nur noch, wenn `88x2bu` nicht geladen ist (Fallback, braucht `kernel-devel` + gcc/make), und kümmert sich ums Rebinding.
- Chrome und Mullvad schreiben nach `/opt`: werden nach `/usr/lib/opt` verschoben, tmpfiles verlinkt `/var/opt/<name>` dorthin. `/opt` selbst bleibt beschreibbar (charon, TickTick liegen dort).
- Kernel-Parameter (`threadirqs`, amdgpu) sind lokal per `rpm-ostree kargs` gesetzt und überleben den Rebase; nicht zusätzlich in kargs.d eintragen (sonst doppelt).
- Spotify: Flatpak `com.spotify.Client`, nicht im Image.
- blur-my-shell: Fedora-RPM ist kaputt, kay nutzt die Upstream-Kopie in ~/.local (Extension Manager).
- Update-Mechanik: ublue-os-update-services (Flatpak-Updates, rpm-ostree stage) kommt von silverblue-main und ist gewollt. Bluefins `uupd` ist in /etc maskiert. brew aktualisiert `brew-upgrade.timer` (user, global aktiviert).
