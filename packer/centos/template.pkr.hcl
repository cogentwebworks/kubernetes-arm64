source "amazon-ebssurrogate" "arm64" {
  # Unable to use "source_ami_filter" safely with the correct wildcards for getting arm64 without potentially matching a beta
  # Use https://ap-northeast-1.console.aws.amazon.com/ec2/v2/home?region=ap-northeast-1#Images:visibility=public-images;ownerAlias=125523088429;architecture=arm64;sort=name
  # when ready to bump to a newer AMI.
  source_ami = "ami-0c54e9b4dd47f7208"

  instance_type = "m6g.large"
  region = "ap-northeast-1"

  launch_block_device_mappings {
    device_name = "/dev/sdf"
    delete_on_termination = true
    volume_size = 8
    volume_type = "gp2"
  }

  communicator = "ssh"
  ssh_pty = true
  ssh_username = "centos"
  ssh_timeout = "5m"
  profile = "sysops"

  ssh_keypair_name = "ec2-access"
  ssh_private_key_file =  "ec2-access.pem"

  ami_name = "centos-8-arm64"
  ami_description = "CentOS 8 (arm64)"
  ami_virtualization_type = "hvm"
  ami_architecture = "arm64"
  ena_support = true
  ami_regions = []
  ami_root_device {
    source_device_name = "/dev/sdf"
    device_name = "/dev/sda1"
    delete_on_termination = true
    volume_size = 8
    volume_type = "gp2"
  }

  tags = {
    Name = "CentOS 8 (arm64)"
    BuildTime = timestamp()
  }
}
build {
  sources = [
    "source.amazon-ebssurrogate.arm64"
  ]

  provisioner "shell" {
    script = "scripts/chroot-bootstrap.sh"
    execute_command = "sudo -S sh -c '{{ .Vars }} {{ .Path }}'"

    start_retry_timeout = "5m"
    skip_clean = true
  }
}