provider "aws" {
    profile = "terra1"
    region  = "ap-south-1"
}



#Creating Key-Pair


resource "tls_private_key" "task1_key" {
    algorithm   =  "RSA"
    rsa_bits    =  4096
}
resource "local_file" "private_key" {
    content         =  tls_private_key.task1_key.private_key_pem
    filename        =  "webserver.pem"
    file_permission =  0400
}
resource "aws_key_pair" "webserver_key" {
    key_name   = "webserver"
    public_key = tls_private_key.task1_key.public_key_openssh
}



#Creating security group

resource "aws_security_group" "web_SG" {
    name        = "webserver"
    description = "https, ssh, icmp"
   
ingress {
        description = "http"
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    
    ingress {
        description = "ssh"
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
ingress {
        description = "ping-icmp"
        from_port   = -1
        to_port     = -1
        protocol    = "icmp"
        cidr_blocks = ["0.0.0.0/0"]
    }
egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
tags = {
        Name = "web_SG"
    }
}


//Creating a S3 Bucket
resource "aws_s3_bucket" "neel12345-bucket" {
  bucket = "web-static-data-bucket"
  acl    = "public-read"
}

resource "aws_s3_bucket_object" "image-upload" {
  for_each = fileset("C:/Users/Neelaksh Singh/Desktop/terra/task1/", "*" ) 
  bucket = "${aws_s3_bucket.neel12345-bucket.bucket}"
  key    =  each.value
  source = "C:/Users/Neelaksh Singh/Desktop/terra/task1/${each.value}"
  etag = filemd5("C:/Users/Neelaksh Singh/Desktop/terra/task1/${each.value}")
  acl    = "public-read"
}


//Creating CloutFront with S3 Bucket Origin

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.neel12345-bucket.bucket_regional_domain_name}"
    origin_id   = "${aws_s3_bucket.neel12345-bucket.id}"
  }


  enabled             = true
  is_ipv6_enabled     = true
  comment             = "S3 Web Distribution"


  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${aws_s3_bucket.neel12345-bucket.id}"


    forwarded_values {
      query_string = false


      cookies {
        forward = "none"
      }
    }
  viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }


  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["IN"]
    }
  }


  tags = {
    Name        = "Web-CF-Distribution"
    Environment = "Production"
  }


  viewer_certificate {
    cloudfront_default_certificate = true
  }


  depends_on = [
    aws_s3_bucket.neel12345-bucket
  ]
}

#EC2 INSTANCE

resource "aws_instance" "inst1" {
    ami                     = "ami-052c08d70def0ac62"
    instance_type           = "t2.micro"
    key_name                = "${aws_key_pair.webserver_key.key_name}"
    vpc_security_group_ids  = ["${aws_security_group.web_SG.id}", "default"]
 
    root_block_device {
        volume_type     = "gp2"
        volume_size     = 12
        delete_on_termination   = true
    }
tags = {
        Name = "inst1"
    }

 
  
  //Copy our Wesite Code i.e. HTML File in Instance Webserver Document Rule
  provisioner "file" {
    connection {
      agent       = false
      type        = "ssh"
      user        = "ec2-user"
      private_key = "${tls_private_key.task1_key.private_key_pem}"
      host        = "${aws_instance.inst1.public_ip}"
    }


    source      = "index.html"
    destination = "/home/ec2-user/index.html" 
  }


connection {
        type    = "ssh"
        user    = "ec2-user"
        host    = aws_instance.inst1.public_ip
        port    = 22
        private_key = tls_private_key.task1_key.private_key_pem
    }
provisioner "remote-exec" {
        inline = [
        "sudo yum install httpd -y",
        "sudo systemctl start httpd",
        "sudo systemctl enable httpd",
        "sudo yum install git -y"
        ]
    }
}


#EBS Volume and Attachment

resource "aws_ebs_volume" "ebs1" {
    availability_zone = aws_instance.inst1.availability_zone
    size              = 1
    type = "gp2"
    tags = {
        Name = "ebs1"
    }
}
resource "aws_volume_attachment" "ebs1_mount" {
  device_name = "/dev/xvdb"
  volume_id   = aws_ebs_volume.ebs1.id
  instance_id = aws_instance.inst1.id
  force_detach = true
}
resource "null_resource" "nulllocal"  {
  provisioner "local-exec" {
    command = "echo  ${aws_instance.inst1.public_ip} > publicip.txt"
  }
}
resource "null_resource" "nullremote1"  {
  depends_on = [
    aws_volume_attachment.ebs1_mount,
  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.task1_key.private_key_pem
    host     = aws_instance.inst1.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Neelaksh-Singh/terratask1.git /var/www/html"
    ]
  }
}






#Snapshot

resource "aws_ebs_snapshot" "ebs_snapshot" {
  volume_id     = "${aws_ebs_volume.ebs1.id}"
  description    = "Snapshot of our EBS volume"
  
  tags = {
    env = "Production"
  }



  depends_on = [
    aws_volume_attachment.ebs1_mount
  ]
}


