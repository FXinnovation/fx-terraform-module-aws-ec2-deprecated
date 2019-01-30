module "this" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "1.14.0"

  name           = "${var.name}"
  instance_count = 1

  ami                    = "${var.ami}"
  instance_type          = "${var.instance_type}"
  user_data              = "${var.user_data}"
  subnet_id              = "${var.subnet_id}"
  key_name               = "${var.key_name}"
  monitoring             = "${var.monitoring}"
  vpc_security_group_ids = "${var.vpc_security_group_ids}"
  iam_instance_profile   = "${var.iam_instance_profile}"

  associate_public_ip_address = "${var.associate_public_ip_address}"
  private_ip                  = "${var.private_ip}"

  source_dest_check       = "${var.source_dest_check}"
  disable_api_termination = "${var.disable_api_termination}"

  ebs_optimized     = "${var.ebs_optimized}"
  volume_tags       = "${merge(map("Name", format("%s", var.name)), map("Terraform", "true"), var.tags, var.volume_tags)}"
  ebs_block_device  = "${var.ebs_block_device}"
  root_block_device = "${var.root_block_device}"

  tags = "${merge(map("Name", format("%s", var.name)), map("Terraform", "true"), var.tags)}"
}

// This is needed to circumvent:
// https://github.com/terraform-providers/terraform-provider-aws/issues/1352
data "aws_subnet" "instance_subnet" {
  id = "${var.subnet_id}"
}

resource "aws_volume_attachment" "this_ec2" {
  count = "${var.external_volume_create ? 1 : 0}"

  device_name = "${var.external_volume_device_name}"
  volume_id   = "${aws_ebs_volume.this.id}"
  instance_id = "${module.this.id[0]}"
}

resource "aws_ebs_volume" "this" {
  count = "${var.external_volume_create ? 1 : 0}"

  availability_zone = "${data.aws_subnet.instance_subnet.availability_zone}"
  size              = "${var.external_volume_size}"

  encrypted  = true
  kms_key_id = "${element(coalescelist(list(var.external_volume_kms_key_arn), aws_kms_key.this.*.arn), 0)}"

  tags = "${merge(map("Name", format("%s", var.name)), map("Terraform", "true"), var.tags, var.volume_tags, var.external_volume_tags)}"
}

resource "aws_kms_key" "this" {
  count = "${var.external_volume_create && var.external_volume_kms_key_arn == "" ? 1 : 0}"

  description = "KMS key for ${var.name} external volume."

  tags = "${merge(map("Name", format("%s", var.name)), map("Terraform", "true"), var.tags, var.external_volume_kms_key_tags)}"
}
