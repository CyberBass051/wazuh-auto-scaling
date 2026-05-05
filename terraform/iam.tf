# IAM Role for EC2
resource "aws_iam_role" "wazuh_instance_role" {
    name = "wazuh-instance-role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Action = "sts:AssumeRole"
            Effect = "Allow"
            Principal = {
                Service = "ec2.amazonaws.com"
            }
        }]
    })
}

# Policy to allow KSM Decryption (For the Registration Password)
resource "aws_iam_role_policy" "kms_policy" {
    name = "wazuh-kms-decrypt"
    role = aws_iam_role.wazuh_instance_role.id

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Effect = "Allow"
            Action = [
                "kms:Decrypt"
            ]
            Resource = [var.kms_key_arn]
        }]
    })
}

resource "aws_iam_instance_profile" "wazuh-profile" {
    name = "wazuh-instance-profile"
    role = aws_iam_role.wazuh_instance_role.name

}