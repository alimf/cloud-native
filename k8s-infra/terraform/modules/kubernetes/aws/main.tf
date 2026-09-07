data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  ssm_join_command_path = "/k8s/${var.cluster_name}/worker-join-command"
}

# ──────────────────────────────────────────────────────────────
# IAM — Control Plane
# ──────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "control_plane" {
  statement {
    sid    = "SSMJoinCommand"
    effect = "Allow"

    actions = [
      "ssm:PutParameter",
      "ssm:GetParameter",
      "ssm:DeleteParameter",
    ]

    resources = [
      "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/k8s/${var.cluster_name}/*",
    ]
  }

  statement {
    sid    = "EC2CloudProvider"
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVolumes",
      "ec2:DescribeAvailabilityZones",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:AttachVolume",
      "ec2:DetachVolume",
      "ec2:ModifyInstanceAttribute",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role" "control_plane" {
  name               = "${var.cluster_name}-control-plane"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "control_plane" {
  name   = "${var.cluster_name}-control-plane"
  role   = aws_iam_role.control_plane.id
  policy = data.aws_iam_policy_document.control_plane.json
}

resource "aws_iam_role_policy_attachment" "control_plane_ssm_core" {
  role       = aws_iam_role.control_plane.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "control_plane" {
  name = "${var.cluster_name}-control-plane"
  role = aws_iam_role.control_plane.name
  tags = var.tags
}

# ──────────────────────────────────────────────────────────────
# IAM — Workers
# ──────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "worker" {
  statement {
    sid    = "SSMGetJoinCommand"
    effect = "Allow"
    actions = ["ssm:GetParameter"]

    resources = [
      "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/k8s/${var.cluster_name}/*",
    ]
  }

  statement {
    sid    = "EC2CloudProvider"
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVolumes",
      "ec2:DescribeAvailabilityZones",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "ECRReadOnly"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role" "worker" {
  name               = "${var.cluster_name}-worker"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "worker" {
  name   = "${var.cluster_name}-worker"
  role   = aws_iam_role.worker.id
  policy = data.aws_iam_policy_document.worker.json
}

resource "aws_iam_role_policy_attachment" "worker_ssm_core" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.cluster_name}-worker"
  role = aws_iam_role.worker.name
  tags = var.tags
}

# ──────────────────────────────────────────────────────────────
# Security Groups
# ──────────────────────────────────────────────────────────────

resource "aws_security_group" "control_plane" {
  name        = "${var.cluster_name}-control-plane"
  description = "Kubernetes control plane nodes"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-control-plane-sg"
  })
}

resource "aws_security_group" "worker" {
  name        = "${var.cluster_name}-worker"
  description = "Kubernetes worker nodes"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-worker-sg"
  })
}

# API server inbound from allowed CIDRs
resource "aws_security_group_rule" "cp_api_ingress" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = var.api_server_allowed_cidrs
  security_group_id = aws_security_group.control_plane.id
  description       = "Kubernetes API server"
}

# Full mesh between control plane nodes (etcd, scheduler, controller-manager)
resource "aws_security_group_rule" "cp_self_ingress" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.control_plane.id
  description       = "All traffic between control plane nodes"
}

# Control plane ← workers (kubelet, CNI)
resource "aws_security_group_rule" "cp_from_worker_ingress" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.worker.id
  security_group_id        = aws_security_group.control_plane.id
  description              = "All traffic from worker nodes"
}

resource "aws_security_group_rule" "cp_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.control_plane.id
  description       = "All outbound traffic"
}

# Full mesh between worker nodes (pod networking / VXLAN)
resource "aws_security_group_rule" "worker_self_ingress" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.worker.id
  description       = "All traffic between worker nodes (pod networking)"
}

# Workers ← control plane (kubelet API, CNI)
resource "aws_security_group_rule" "worker_from_cp_ingress" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.control_plane.id
  security_group_id        = aws_security_group.worker.id
  description              = "All traffic from control plane nodes"
}

# NodePort range
resource "aws_security_group_rule" "worker_nodeport_ingress" {
  type              = "ingress"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.worker.id
  description       = "NodePort services"
}

resource "aws_security_group_rule" "worker_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.worker.id
  description       = "All outbound traffic"
}

# ──────────────────────────────────────────────────────────────
# API Server NLB — stable endpoint across control plane rotation
# ──────────────────────────────────────────────────────────────

resource "aws_lb" "api_server" {
  name               = "${var.cluster_name}-api"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-api-nlb"
  })
}

resource "aws_lb_target_group" "api_server" {
  name     = "${var.cluster_name}-api-tg"
  port     = 6443
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    protocol            = "HTTPS"
    path                = "/healthz"
    port                = "6443"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = var.tags
}

resource "aws_lb_listener" "api_server" {
  load_balancer_arn = aws_lb.api_server.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_server.arn
  }
}

resource "aws_lb_target_group_attachment" "control_plane" {
  count = var.control_plane_count

  target_group_arn = aws_lb_target_group.api_server.arn
  target_id        = aws_instance.control_plane[count.index].id
  port             = 6443
}

# ──────────────────────────────────────────────────────────────
# Control Plane EC2 Instances
# ──────────────────────────────────────────────────────────────

resource "aws_instance" "control_plane" {
  count = var.control_plane_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.control_plane_instance_type
  subnet_id              = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  vpc_security_group_ids = [aws_security_group.control_plane.id]
  iam_instance_profile   = aws_iam_instance_profile.control_plane.name
  key_name               = var.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.control_plane_volume_size
    delete_on_termination = true
    encrypted             = true
  }

    user_data_base64 = base64gzip(templatefile("${path.module}/templates/control_plane.sh.tftpl", {
    cluster_name          = var.cluster_name
    kubernetes_version    = var.kubernetes_version
    calico_version        = var.calico_version
    api_server_endpoint   = aws_lb.api_server.dns_name
    pod_cidr              = var.pod_cidr
    service_cidr          = var.service_cidr
    aws_region            = data.aws_region.current.region
    ssm_join_command_path = local.ssm_join_command_path
  }))

  tags = merge(var.tags, {
    Name                                        = "${var.cluster_name}-control-plane-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "k8s.io/role/control-plane"                = "1"
  })

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "null_resource" "wait_for_control_plane" {
  depends_on = [aws_instance.control_plane]

  provisioner "local-exec" {
    command = <<EOT
      STATUS_PATH="${local.ssm_join_command_path}_status"
      MAX_ATTEMPTS=36     # 36 attempts * 10s = 6 Minutes max wait time
      ATTEMPT=1

      echo "Waiting for K8s control plane readiness signal at $STATUS_PATH..."

      while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
        STATUS=$(aws ssm get-parameter --name "$STATUS_PATH" --region "${var.aws_region}" --query 'Parameter.Value' --output text 2>/dev/null || echo "NOT_FOUND")

        if [ "$STATUS" = "READY" ]; then
          echo "Control plane API server is confirmed READY! Starting worker deployment..."
          exit 0
        fi

        echo "Control plane not healthy yet (Status: '$STATUS') [Attempt $ATTEMPT/$MAX_ATTEMPTS]"
        sleep 10
        ATTEMPT=$((ATTEMPT + 1))
      done

      echo "[ERROR] Timed out waiting for control plane signal at $STATUS_PATH after $((MAX_ATTEMPTS * 10)) seconds." >&2
      exit 1
    EOT
  }
}

# ──────────────────────────────────────────────────────────────
# Worker EC2 Instances
# ──────────────────────────────────────────────────────────────

resource "aws_instance" "worker" {
  count                  = var.worker_count
  depends_on             = [null_resource.wait_for_control_plane]
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  subnet_id              = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  vpc_security_group_ids = [aws_security_group.worker.id]
  iam_instance_profile   = aws_iam_instance_profile.worker.name
  key_name               = var.key_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.worker_volume_size
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile("${path.module}/templates/worker.sh.tftpl", {
    kubernetes_version    = var.kubernetes_version
    aws_region            = data.aws_region.current.region
    ssm_join_command_path = local.ssm_join_command_path
  })

  tags = merge(var.tags, {
    Name                                        = "${var.cluster_name}-worker-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "k8s.io/role/worker"                       = "1"
  })

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}
