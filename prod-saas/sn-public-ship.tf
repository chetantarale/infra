# Web Security group
resource "aws_security_group" "sg_public_lb" {
  name = "sg_public_lb_${var.install_version}"
  description = "LB traffic security group"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"]
  }
  ingress {
    from_port = 5671
    to_port = 5671
    protocol = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"]
  }
  ingress {
    from_port = 15671
    to_port = 15671
    protocol = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"]
  }
  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"]
  }
  ingress {
    from_port = -1
    to_port = -1
    protocol = "icmp"
    cidr_blocks = [
      "0.0.0.0/0"]
  }

  egress {
    # allow all traffic to private SN
    from_port = "0"
    to_port = "0"
    protocol = "-1"
    cidr_blocks = [
      "${var.cidr_private_ship_install}",
      "${var.cidr_public_ship}"
    ]
  }

  tags {
    Name = "sg_public_lb_${var.install_version}"
  }
}

# RP Server
resource "aws_instance" "rp" {
  ami = "${var.ami_us_east_1_ubuntu1404}"
  availability_zone = "${var.avl-zone}"
  instance_type = "${var.in_type_rp}"
  key_name = "${var.aws_key_name}"

  subnet_id = "${var.sn_public_ship_id}"
  vpc_security_group_ids = [
    "${aws_security_group.sg_public_nat.id}"]

  provisioner "file" {
    source = "setupNGINX.sh"
    destination = "~/setupNGINX.sh"

    connection {
      type = "ssh"
      user = "ubuntu"
      private_key = "${file(null_resource.pemfile.triggers.fileName)}"
      agent = true
    }
  }

  provisioner "file" {
    source = "default"
    destination = "~/default"

    connection {
      type = "ssh"
      user = "ubuntu"
      private_key = "${file(null_resource.pemfile.triggers.fileName)}"
      agent = true
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo su root && . setupNGINX.sh"
    ]

    connection {
      type = "ssh"
      user = "ubuntu"
      private_key = "${var.aws_key_filename}"
      agent = true
    }
  }

  associate_public_ip_address = true
  source_dest_check = false

  tags = {
    Name = "rp_${var.install_version}"
  }
}

# Associate EIP, without this private TF remote wont work
resource "aws_eip" "rp_eip" {
  instance = "${aws_instance.rp.id}"
  vpc = true
}

# ========================Load Balancers=======================

# WWW Load balancer
resource "aws_elb" "lb_www" {
  name = "lb-www-${var.install_version}"
  connection_draining = true
  subnets = [
    "${var.sn_public_ship_id}"]
  security_groups = [
    "${aws_security_group.sg_public_lb.id}"]

  listener {
    lb_port = 443
    lb_protocol = "https"
    instance_port = 80
    instance_protocol = "http"
    ssl_certificate_id = "${var.acm_cert_arn}"
  }

  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = 80
    instance_protocol = "http"
  }

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 10
    target = "TCP:80"
    interval = 30
  }

  instances = [
    "${aws_instance.rp.id}"
  ]
}

# APP Load balancer
resource "aws_elb" "lb_app" {
  name = "lb-app-${var.install_version}"
  connection_draining = true
  subnets = [
    "${var.sn_public_ship_id}"]
  security_groups = [
    "${aws_security_group.sg_public_lb.id}"]

  listener {
    lb_port = 443
    lb_protocol = "ssl"
    instance_port = 50001
    instance_protocol = "tcp"
    ssl_certificate_id = "${var.acm_cert_arn}"
  }

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    target = "HTTP:50001/"
    interval = 5
  }

  instances = [
    "${aws_instance.ms_1.id}",
    "${aws_instance.ms_2.id}",
    "${aws_instance.ms_3.id}",
    "${aws_instance.ms_4.id}",
    "${aws_instance.ms_5.id}",
    "${aws_instance.ms_6.id}"
  ]
}

//# API Load balancer
resource "aws_elb" "lb_api" {
  name = "lb-api-${var.install_version}"
  connection_draining = true
  subnets = [
    "${var.sn_public_ship_id}"]
  security_groups = [
    "${aws_security_group.sg_public_lb.id}"]

  listener {
    lb_port = 443
    lb_protocol = "https"
    instance_port = 50000
    instance_protocol = "http"
    ssl_certificate_id = "${var.acm_cert_arn}"
  }

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 5
    timeout = 3
    target = "HTTP:50000/"
    interval = 5
  }

  instances = [
    "${aws_instance.ms_1.id}",
    "${aws_instance.ms_2.id}",
    "${aws_instance.ms_3.id}",
    "${aws_instance.ms_4.id}",
    "${aws_instance.ms_5.id}",
    "${aws_instance.ms_6.id}"
  ]
}

# MSG Load balancer
resource "aws_elb" "lb_msg" {
  name = "lb-msg-${var.install_version}"
  idle_timeout = 3600
  connection_draining = true
  connection_draining_timeout = 3600
  subnets = [
    "${var.sn_public_ship_id}"]
  security_groups = [
    "${aws_security_group.sg_public_lb.id}"]

  listener {
    lb_port = 443
    lb_protocol = "https"
    instance_port = 15672
    instance_protocol = "http"
    ssl_certificate_id = "${var.acm_cert_arn}"
  }

  listener {
    lb_port = 5671
    lb_protocol = "ssl"
    instance_port = 5672
    instance_protocol = "tcp"
    ssl_certificate_id = "${var.acm_cert_arn}"
  }

  listener {
    lb_port = 15671
    lb_protocol = "https"
    instance_port = 15672
    instance_protocol = "http"
    ssl_certificate_id = "${var.acm_cert_arn}"
  }

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 10
    target = "HTTP:15672/"
    interval = 30
  }

  instances = [
    "${var.in_msg_id}"]
}
