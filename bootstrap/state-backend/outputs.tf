output "state_bucket_name" {
  description = "Name of the S3 bucket storing Terraform state."
  value       = aws_s3_bucket.tf_state.bucket
}

output "backend_config_example" {
  description = "Example content for backend.hcl in the root module."
  value = join("\n", [
    "bucket = \"${aws_s3_bucket.tf_state.bucket}\""
  ])
}
