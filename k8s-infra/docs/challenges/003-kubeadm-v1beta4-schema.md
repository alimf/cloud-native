# 003 — kubeadm init failed on kubelet config (v1beta4 schema change)

**Category:** Kubernetes / kubeadm API
**Severity:** High — blocked control-plane initialization after all prior
bugs (Terraform escaping, double base64 encoding) were already resolved
and the instance had successfully reached the `kubeadm init` stage

## Symptom

The bootstrap log showed the instance had progressed correctly through
network detection, package installation, and containerd configuration,
then failed during kubeadm's own preflight validation:

```
W0831 18:28:47.800834    4476 initconfiguration.go:332] error unmarshaling
configuration schema.GroupVersionKind{Group:"kubeadm.k8s.io",
Version:"v1beta4", Kind:"InitConfiguration"}: json: cannot unmarshal
object into Go struct field NodeRegistrationOptions.nodeRegistration.
kubeletExtraArgs of type []v1beta4.Arg
[bootstrap][ERROR] Failed at line 394: kubeadm init phase preflight --config "${KUBEADM_CONFIG}"
```

## Root cause

Not a scripting or templating bug — a genuine breaking change in
kubeadm's own configuration API. Starting with Kubernetes 1.31, the
`kubeadm.k8s.io/v1beta4` config API changed `kubeletExtraArgs` (and the
equivalent `extraArgs` fields on `apiServer`/`controllerManager`/
`scheduler`/`etcd`) from a `map[string]string` to a list of `{name,
value}` objects, specifically to allow the same flag to be passed more
than once — something a map couldn't represent. The generated kubeadm
config still used the older `v1beta3` map-style syntax:

```yaml
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
    node-ip: "${NODE_IP}"
```

which is no longer valid once the config's `apiVersion` is `v1beta4`.

Confirmed via kubeadm/Kubernetes 1.31 release documentation that this is
an intentional, documented API change rather than a local misconfiguration.

## Fix

Converted the affected field to the list form required by `v1beta4`:

```yaml
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
    - name: "node-ip"
      value: "${NODE_IP}"
```

No other fields in the generated `ClusterConfiguration` used the old
map-style `extraArgs` pattern at the time, so this was the only site
affected — but any future `apiServer.extraArgs` / `controllerManager.
extraArgs` / etc. added later must use the same list form, not the old
map form.

## Why it matters

This is a useful contrast to the earlier Terraform bugs: it wasn't
introduced by any mistake in this project's own code — it's exactly the
kind of breaking change you inherit for free by pinning to a recent
Kubernetes minor version (1.31) while following an existing script
pattern written against an older one (`v1beta3`). It's a concrete example
of why "the script matched the tutorial/reference I copied it from"
isn't sufficient validation — the reference material has to match the
actual target version, and version-specific schema changes need to be
checked explicitly rather than assumed stable across releases.