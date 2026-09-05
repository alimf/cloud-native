# 001 — Terraform silently discarding all injected variables

**Category:** Terraform / templating
**Severity:** Critical — blocked cluster bootstrap entirely until fixed

## Symptom

`terraform apply` completed and provisioned EC2 instances, but every
instance failed its bootstrap script within the first few lines with:

```
bash: line 1: cluster_name: unbound variable
```

under `set -Eeuo pipefail`. None of the Terraform-supplied configuration —
cluster name, Kubernetes version, Calico version, API endpoint, CIDRs,
region, SSM path — ever reached the instance in usable form.

A second, related symptom surfaced on a separate line: `terraform apply`
itself failed at render time, before any instance was even created:

```
Error: Invalid template interpolation value at line 26
  There is no variable named "LOG_FILE".
```

## Root cause

The bootstrap script is rendered via Terraform's `templatefile()` function,
which uses `${...}` for real interpolation and `$${...}` as the escape
sequence for a literal `${...}` in the output. The script had this
backwards in two ways at once:

- **The 8 real Terraform variables** (`cluster_name`, `kubernetes_version`,
  etc.) were written as `$${cluster_name}` — the *escaped* form. Terraform
  correctly left them as literal text, so the rendered script contained
  `CLUSTER_NAME="${cluster_name}"` — bash syntax referencing an unset local
  variable, not the actual value.
- **One bash-local variable**, `LOG_FILE`, was written as `${LOG_FILE}` —
  a single dollar sign, meaning Terraform tried to genuinely interpolate
  it as if it were a declared Terraform variable. Since `LOG_FILE` isn't
  one, this failed the render outright.

Verified by simulating Terraform's actual escaping rules against the file
with Python (`$${` → literal `${`, single `${var}` → resolved against mock
variables or flagged as a render error), then confirming under real
`bash -Eeuo pipefail` execution that an unresolved `${cluster_name}`
throws exactly `unbound variable`, matching the reported symptom exactly.

A third, related class of the same underlying confusion: command
substitutions like `$$(date)` and `$$(ip -4 route show default | ...)`
were also over-escaped. Since Terraform only treats `${` (not `$(`) as a
template marker, `$$(...)` passes through completely untouched — either
producing garbage output (`$$` resolves to the shell's PID, e.g.
`Time: 630(date)`) inside quotes, or a hard `syntax error near unexpected
token '('` in unquoted assignments like `PRIMARY_INTERFACE=$$(ip ...)`.

## Fix

Established and applied one rule, consistently, across every `$`
occurrence in both the control-plane and worker templates:

| Reference type | Correct form | Reason |
|---|---|---|
| A real Terraform variable (`cluster_name`, `aws_region`, etc.) | `${var}` — single `$` | Terraform must actually substitute it |
| A bash-local variable (`LOG_FILE`, `NODE_IP`, `LINENO`, `BASH_COMMAND`, etc.) | `$${var}` — double `$` | Terraform must leave it untouched for bash to resolve at runtime |
| Command substitution `$(...)` | `$(...)` — never escaped | `$(` is not a Terraform template marker at all; escaping it breaks it |

Verified the fix by re-running the same mock-value render simulation
(zero render errors) followed by `bash -n` against the fully rendered
output (clean parse, no syntax errors anywhere in either file).

## Why it matters

This bug is a good example of how a single, mechanical misunderstanding
(one escaping rule, applied uniformly instead of case-by-case) can produce
two opposite-looking failure modes — a render-time Terraform error and a
runtime bash error — from the same root cause. Fixing it required tracing
both failure points back to the same rule rather than patching each
symptom independently, and verifying the fix against the actual rendering
engine's behavior (not just visual inspection of the template) before
ever deploying it again.