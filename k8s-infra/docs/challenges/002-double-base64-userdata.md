# 002 — user_data exceeded AWS's 16 KB limit

**Category:** AWS / Terraform provider behavior
**Severity:** High — blocked instance creation for the larger of the two
bootstrap scripts, and silently wasted capacity on the smaller one

## Symptom

```
Error: expected length of user_data to be in the range (0 - 16384)
```

thrown by the `aws_instance` resource for the control-plane node at
`terraform apply` time, before any instance was created.

## Root cause

The `aws_instance.user_data` argument is special-cased by the AWS
provider: whatever string is assigned to it is base64-encoded
automatically before being sent to the AWS API. The Terraform
configuration wrapped the rendered template in `base64encode(...)` on top
of that:

```hcl
user_data = base64encode(templatefile("${path.module}/templates/control_plane.sh.tftpl", { ... }))
```

This encodes the script twice — once explicitly, once by the provider —
and the *string handed to the `user_data` argument itself* (i.e. the
once-encoded value) is what gets validated against AWS's 16 KB limit, not
the final doubly-encoded payload. Since base64 inflates size by roughly
33% per pass, two passes compound.

Measured directly against both actual template files:

| File | Raw script | Base64 ×1 | Base64 ×2 (as configured) |
|---|---:|---:|---:|
| `control_plane.sh.tftpl` | 16,205 B | 21,608 B — already over 16,384 | 28,812 B |
| `worker.sh.tftpl` | 10,683 B | 14,244 B — fits | 18,992 B — over 16,384 |

The worker script would have fit comfortably under the limit encoded
correctly once; the control-plane script would still have exceeded it
even encoded once, meaning this was actually two separate problems
wearing one error message.

## Fix

- Removed the `base64encode(...)` wrapper from both `aws_instance`
  resources' `user_data` arguments, letting the provider encode exactly
  once:
  ```hcl
  user_data = templatefile("${path.module}/templates/control_plane.sh.tftpl", { ... })
  ```
  This alone resolved the worker instance, whose script fits well within
  16 KB encoded once.
- For the control-plane script, removing the double encoding was
  necessary but not sufficient — the raw script itself needed to shrink,
  or move off `user_data` entirely (e.g. a small stub script that fetches
  the full bootstrap script from S3/SSM at boot) once it grows further,
  since it was already over the raw-script-equivalent limit even with
  correct single encoding.

## Why it matters

The error message pointed at a single symptom ("string too long") but
the actual cause spanned two independent issues — a provider-behavior
misunderstanding affecting both resources, and a genuine size problem
affecting only one of them. Measuring the actual byte counts before
proposing a fix (rather than assuming "remove the double-encode and it's
solved") was what surfaced that the control-plane script needed a second,
different remediation.