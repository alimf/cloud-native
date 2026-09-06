# Engineering Challenges Log

Real issues encountered and root-caused while building this platform.
Each entry links to a full postmortem: symptom, root cause, fix, and why
it mattered.

| #   | Issue | Category    | Root Cause | Link                                           |
|-----|---|-------------|--|------------------------------------------------|
| 001 | Terraform silently discarding all injected vars | Terraform   | Over-escaped template syntax | [detail](001-terraform-escaping.md)            |
| 002 | user_data exceeded AWS 16KB limit | AWS         | Double base64 encoding | [detail](002-double-base64-userdata.md)        |
| 003 | kubeadm init failed on kubelet config | Kubernetes  | v1beta4 schema breaking change | [detail](003-kubeadm-v1beta4-schema.md)        |
| 003 | kubeadm init failed on kubelet config | Kubernetes  | v1beta4 schema breaking change | [detail](003-kubeadm-v1beta4-schema.md)        |
| 004 | Private Subnet Connectivity Timeouts (i/o timeout / Network is unreachable) | Worker Node | [detail](004-private-subnet-timeouts.md) |
| 005 | containerd config failed to enable SystemdCgroup | Kubernetes  | Misconfigured containerd config | [detail](005-containerd-systemdcgroup.md)      |
| 006 | Worker Node Bootstrap Race Condition & Join Failures | Kubernetes  | Misconfigured containerd config | [detail](006-node-bootstrap-race-condition.md) |