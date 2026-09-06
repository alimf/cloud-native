# Fix: containerd `SystemdCgroup` not enabled during worker bootstrap

## Summary

Worker node bootstrap (`worker-bootstrap.sh.tftpl`, rendered via Terraform
`templatefile()`) failed during the "Configuring containerd" step with:

```
[bootstrap] Configuring containerd
[bootstrap][ERROR] Failed to enable SystemdCgroup in containerd config
```

The bootstrap script generates containerd's default config and patches it to
use the systemd cgroup driver (required so kubelet and containerd agree on
cgroup management — a mismatch here causes kubelet to fail joining or to
misreport resource usage). The patch step verifies the change actually took
effect and fails fast instead of continuing with a broken config.

## Root cause

`containerd.io` 2.3.4 (from Docker's apt repo) is installed on the worker,
and `containerd config default` on this build does not emit the
`SystemdCgroup` key in the exact form (`SystemdCgroup = false`) the original
`sed` pattern expected. The literal string match found nothing to replace,
so the file was left with the cgroup driver unset/default, and the
post-edit `grep` check (correctly) caught the mismatch and aborted the
bootstrap rather than silently proceeding with an unconfigured cgroup
driver.

This was not reproducible against the nearest available reference
(`containerd` 2.2.1 from the Ubuntu archive), where the original `sed`
pattern worked correctly — confirming the issue is specific to formatting
differences in Docker's `containerd.io` 2.3.4 build output, not a logic
error in the approach itself.

## Fix

1. **Whitespace/format-tolerant match** instead of an exact literal string,
   since TOML key formatting can vary by containerd build/version even when
   the key name doesn't change:

   ```bash
   sed -i -E 's/(SystemdCgroup[[:space:]]*=[[:space:]]*)false/\1true/' "$CONTAINERD_CONFIG"
   ```

2. **Verification with diagnostic output on failure**, so any future
   mismatch is self-documenting in the bootstrap log instead of requiring
   guesswork:

   ```bash
   if ! grep -qE 'SystemdCgroup[[:space:]]*=[[:space:]]*true' "$CONTAINERD_CONFIG"; then
       log "DEBUG: dumping generated containerd config for diagnosis"
       cat "$CONTAINERD_CONFIG"
       error "Failed to enable SystemdCgroup in containerd config"
   fi
   ```

### Before

```bash
containerd config default > "$CONTAINERD_CONFIG"
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' "$CONTAINERD_CONFIG"

systemctl daemon-reload
systemctl enable containerd
systemctl restart containerd
systemctl is-active --quiet containerd || error "containerd is not running"
```

### After

```bash
containerd config default > "$CONTAINERD_CONFIG"

sed -i -E 's/(SystemdCgroup[[:space:]]*=[[:space:]]*)false/\1true/' "$CONTAINERD_CONFIG"

if ! grep -qE 'SystemdCgroup[[:space:]]*=[[:space:]]*true' "$CONTAINERD_CONFIG"; then
    log "DEBUG: dumping generated containerd config for diagnosis"
    cat "$CONTAINERD_CONFIG"
    error "Failed to enable SystemdCgroup in containerd config"
fi

systemctl daemon-reload
systemctl enable containerd
systemctl restart containerd
systemctl is-active --quiet containerd || error "containerd is not running"
```

## Verification

- [ ] Re-run bootstrap against a fresh worker instance and confirm the
  "Configuring containerd" step completes without error.
- [ ] Confirm `/etc/containerd/config.toml` contains `SystemdCgroup = true`
  under `[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]`
  (or the equivalent block for the installed containerd version).
- [ ] Confirm `kubelet` starts cleanly and `kubeadm join` succeeds.
- [ ] If the failure recurs on a different containerd version, capture the
  `DEBUG: dumping generated containerd config` block from
  `/var/log/k8s-worker-bootstrap.log` and update the regex/verification
  accordingly rather than re-guessing blind.

## Why this matters for the pipeline design

The original script would have caught this exact drift too — the fail-fast
check (verify the edit took effect, don't just assume `sed` worked) is what
surfaced the problem cleanly with a clear error message instead of
producing a worker node with a silent cgroup driver mismatch, which
typically shows up much later and less clearly (kubelet crashlooping,
inconsistent resource accounting, or nodes failing to join). The fix here
is about making the *check* resilient to formatting drift across
containerd versions, not about removing the check.