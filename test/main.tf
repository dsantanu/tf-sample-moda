##
variable "kb_item" {
  type        = string
  description = "Imported value"
}

resource "local_file" "this" {
  content  = "This is content of moda"
  filename = "${path.module}/${var.kb_item}_moda.txt"
}

output "file_name" {
  value = split("/", local_file.this.filename)[1]
}
