variable "table_name" {
  type = string
}

variable "artwork_bucket_name" {
  type = string
}

variable "cors_allowed_origins" {
  description = "Origins allowed to fetch artwork (the site's https origin)."
  type        = list(string)
  default     = []
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
