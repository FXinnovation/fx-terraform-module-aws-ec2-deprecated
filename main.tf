####
# EC2
####

locals {
  is_t_instance_type = "${replace(var.instance_type, "/^t[23]{1}\\..*$/", "1") == "1" ? "1" : "0"}"

  use_default_subnets = "${var.subnet_ids_count == 0}"

  used_subnet_count = "${floor(min(local.subnet_count, var.instance_count))}"

  subnet_count = "${local.use_default_subnets ? length(data.aws_subnet_ids.default.ids) : var.subnet_ids_count}"
  subnet_ids   = "${split(",", local.use_default_subnets ? join(",", data.aws_subnet_ids.default.ids) : join(",", distinct(compact(concat(list(var.subnet_id), var.subnet_ids)))))}"
}

resource "aws_instance" "this" {
  count = "${var.instance_count * (1 - local.is_t_instance_type)}"

  ami                    = "${var.ami}"
  instance_type          = "${var.instance_type}"
  user_data              = "${var.user_data}"
  subnet_id              = "${element(data.aws_subnet.subnets.*.id, count.index % local.subnet_count)}"
  key_name               = "${var.key_name}"
  monitoring             = "${var.monitoring}"
  vpc_security_group_ids = ["${var.vpc_security_group_ids[count.index % length(var.vpc_security_group_ids)]}"]
  iam_instance_profile   = "${var.iam_instance_profile}"

  associate_public_ip_address = "${var.associate_public_ip_address}"
  private_ip                  = "${length(var.private_ips) != 0 ? element(concat(var.private_ips, list("")), count.index) : ""}"
  ipv6_address_count          = "${var.ipv6_address_count}"
  ipv6_addresses              = "${var.ipv6_addresses}"

  ebs_optimized          = "${var.ebs_optimized}"
  volume_tags            = "${var.volume_tags}"
  root_block_device      = "${var.root_block_device}"
  ebs_block_device       = "${var.ebs_block_device}"
  ephemeral_block_device = "${var.ephemeral_block_device}"

  source_dest_check                    = "${var.source_dest_check}"
  disable_api_termination              = "${var.disable_api_termination}"
  instance_initiated_shutdown_behavior = "${var.instance_initiated_shutdown_behavior}"
  placement_group                      = "${var.placement_group}"
  tenancy                              = "${var.tenancy}"

  tags = "${merge(
    map("Name", (var.instance_count > 1) || var.use_num_suffix ? format("%s-%${var.num_suffix_digits}d", var.name, count.index + 1) : var.name),
    var.tags,
    var.instance_tags
  )}"

  lifecycle {
    # Due to several known issues in Terraform AWS provider related to arguments of aws_instance:
    # (eg, https://github.com/terraform-providers/terraform-provider-aws/issues/2036)
    # we have to ignore changes in the following arguments
    ignore_changes = ["private_ip", "root_block_device", "ebs_block_device", "volume_tags"]
  }
}

resource "aws_instance" "this_t" {
  count = "${var.instance_count * local.is_t_instance_type}"

  ami                    = "${var.ami}"
  instance_type          = "${var.instance_type}"
  user_data              = "${var.user_data}"
  subnet_id              = "${element(data.aws_subnet.subnets.*.id, count.index % local.subnet_count)}"
  key_name               = "${var.key_name}"
  monitoring             = "${var.monitoring}"
  vpc_security_group_ids = ["${var.vpc_security_group_ids[count.index % length(var.vpc_security_group_ids)]}"]
  iam_instance_profile   = "${var.iam_instance_profile}"

  associate_public_ip_address = "${var.associate_public_ip_address}"
  private_ip                  = "${length(var.private_ips) != 0 ? element(concat(var.private_ips, list("")), count.index) : ""}"
  ipv6_address_count          = "${var.ipv6_address_count}"
  ipv6_addresses              = "${var.ipv6_addresses}"

  ebs_optimized          = "${var.ebs_optimized}"
  volume_tags            = "${var.volume_tags}"
  root_block_device      = "${var.root_block_device}"
  ebs_block_device       = "${var.ebs_block_device}"
  ephemeral_block_device = "${var.ephemeral_block_device}"

  source_dest_check                    = "${var.source_dest_check}"
  disable_api_termination              = "${var.disable_api_termination}"
  instance_initiated_shutdown_behavior = "${var.instance_initiated_shutdown_behavior}"
  placement_group                      = "${var.placement_group}"
  tenancy                              = "${var.tenancy}"

  credit_specification {
    cpu_credits = "${var.cpu_credits}"
  }

  tags = "${merge(
  map("Name", (var.instance_count > 1) || var.use_num_suffix ? format("%s-%${var.num_suffix_digits}d", var.name, count.index + 1) : var.name),

var.tags,
    var.instance_tags
  )}"

  lifecycle {
    # Due to several known issues in Terraform AWS provider related to arguments of aws_instance:
    # (eg, https://github.com/terraform-providers/terraform-provider-aws/issues/2036)
    # we have to ignore changes in the following arguments
    ignore_changes = ["private_ip", "root_block_device", "ebs_block_device", "volume_tags"]
  }
}

####
# Extra volumes
####

locals {
  instance_ids = "${compact(concat(aws_instance.this.*.id, aws_instance.this_t.*.id, list("")))}"
}

resource "aws_volume_attachment" "this_ec2" {
  count = "${var.instance_count > 0 ? var.external_volume_count * var.instance_count : 0}"

  device_name = "${element(var.external_volume_device_names, floor(count.index / var.instance_count) % var.external_volume_count)}"
  volume_id   = "${element(aws_ebs_volume.this.*.id, count.index)}"
  instance_id = "${element(local.instance_ids, count.index % var.instance_count)}"
}

resource "aws_ebs_volume" "this" {
  count = "${var.instance_count > 0 ? var.external_volume_count * var.instance_count : 0}"

  availability_zone = "${element(data.aws_subnet.subnets.*.availability_zone, count.index % local.used_subnet_count)}"
  size              = "${element(var.external_volume_sizes, floor(count.index / var.instance_count) % var.external_volume_count)}"

  encrypted  = true
  kms_key_id = "${var.external_volume_kms_key_create ? element(aws_kms_key.this.*.arn, 0) : var.external_volume_kms_key_arn}"

  tags = "${merge(
    map("Name", (var.external_volume_count * var.instance_count > 1) || (var.use_num_suffix == "true") ? format("%s-%0${var.num_suffix_digits}d", var.external_volume_name, count.index + 1) : var.external_volume_name),
    map("Terraform", "true"),
    var.tags,
    var.external_volume_tags
  )}"
}

resource "aws_kms_key" "this" {
  count = "${var.instance_count > 0 && var.external_volume_kms_key_create ? 1 : 0}"

  description = "KMS key for ${var.name} external volume."

  tags = "${merge(
    map("Name", var.use_num_suffix == "true" ? format("%s-%0${var.num_suffix_digits}d", var.external_volume_kms_key_name, count.index + 1) : var.external_volume_kms_key_name),
    map("Terraform", "true"),
    var.tags,
    var.external_volume_kms_key_tags
  )}"
}

resource "aws_kms_alias" "this" {
  count = "${var.instance_count > 0 && var.external_volume_kms_key_create ? 1 : 0}"

  name          = "${var.external_volume_kms_key_alias}"
  target_key_id = "${aws_kms_key.this.key_id}"
}
