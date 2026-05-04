resource "aws_launch_template" "wazuh_lt" {
    metadata_options {
      http_endpoint = "enabled"
      http_tokens   = "required"
      http_put_response_hop_limit = 1
    }

    

  
    name_prefix    = "wazuh-agent-template"
    image_id       = var.ami_id
    instance_type = "t2.micro"

    vpc_security_group_ids = [aws_security_group.wazuh_app_sg.id]

    

    user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install docker -y
    yum install -y aws-cli
    service docker start
    systemctl enable docker

    # SECURE: Fetching encrypted Wazuh Registration Password from KMS
    ENCRYPTED_PASS="${var.encrypted_wazuh_pass}"
    WAZUH_PASS=$(aws kms decrypt --ciphertext-blob fileb://<(echo "$ENCRYPTED_PASS" | base64 -d) --query Plaintext --output text | base64 -d)

    # Start the App
    docker run -d -p 80:80 --name my-app nginx

    # SECURE: Starting Wazuh Agent WITHOUT --privileged
    # We grant only the specific capabilities needed for File Integrity Monitoring
    docker run -d --name wazuh-agent \
      --restart always \
      --network host \
      --cap-add=SYS_ADMIN \
      --cap-add=SYS_PTRACE \
      --cap-add=NET_ADMIN \
      -e WAZUH_MANAGER="YOUR_MANAGER_PRIVATE_IP" \
      -e WAZUH_AGENT_NAME="$(hostname)" \
      -e WAZUH_PASSWORD="$WAZUH_PASS" \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v /dev:/dev -v /etc:/etc -v /var/log:/var/log \
      -v /:/rootfs:ro \
      wazuh/wazuh-agent:latest
  EOF
  )
}