output "control_plane_public_ips" {
  value = concat(
    [aws_instance.control_plane.public_ip],
    aws_instance.control_plane_join[*].public_ip
  )
}

output "control_plane_private_ips" {
  value = concat(
    [aws_instance.control_plane.private_ip],
    aws_instance.control_plane_join[*].private_ip
  )
}

output "ceph_osd_private_ips" {
  value = aws_instance.ceph_osd[*].private_ip
}

output "worker_private_ips" {
  value = aws_instance.worker[*].private_ip
}

output "kubeconfig_command" {
  description = "SSH command to retrieve kubeconfig from first control-plane node"
  value       = "ssh ubuntu@${aws_instance.control_plane.public_ip} 'sudo cat /etc/rancher/rke2/rke2.yaml' | sed 's/127.0.0.1/${aws_instance.control_plane.public_ip}/g' > ~/.kube/config-${var.cluster_name}"
}

output "first_cp_public_ip" {
  value = aws_instance.control_plane.public_ip
}

output "ingress_eip" {
  value = aws_eip.ingress.public_ip
}

output "nip_io_domain" {
  description = "Use this as DOMAIN_PLACEHOLDER in helm values"
  value       = "${aws_eip.ingress.public_ip}.nip.io"
}
