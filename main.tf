terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
      version = "3.0.1-rc3"
    }
  }
}

resource "proxmox_vm_qemu" "k8s-master" {
  name        = "k8s-master"
  target_node = "server2-lab"
  vmid       = 127
  clone      = "ubuntu-template"
  full_clone = true

  ciuser    = var.ci_user
  cipassword = var.ci_password
  sshkeys   = file(var.ci_ssh_public_key)

  agent     = 1
  cores     = 4
  memory    = 8192
  os_type   = "cloud-init"
  bootdisk  = "scsi0"
  scsihw    = "virtio-scsi-pci"

  disks {
    ide {
      ide0 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size    = 40
          storage = "local-lvm"
        }
      }
    }
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  boot     = "order=scsi0"
  ipconfig0 = "ip=192.168.202.127/24,gw=192.168.202.2"
  
  lifecycle {
    ignore_changes = [ 
      network
    ]
  }
}

resource "proxmox_vm_qemu" "k8s-workers" {
  count       = var.vm_count
  name        = "k8s-worker-${count.index + 1}"
  target_node = "server2-lab"
  vmid        = 128 + count.index
  clone       = "ubuntu-template"
  full_clone  = true

  ciuser    = var.ci_user
  cipassword = var.ci_password
  sshkeys   = file(var.ci_ssh_public_key)

  agent     = 1
  cores     = 2
  memory    = 8192
  os_type   = "cloud-init"
  bootdisk  = "scsi0"
  scsihw    = "virtio-scsi-pci"

  disks {
    ide {
      ide0 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size    = 30
          storage = "local-lvm"
        }
      }
    }
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  boot     = "order=scsi0"
  ipconfig0 = "ip=192.168.202.${128 + count.index}/24,gw=192.168.202.2"
  
  lifecycle {
    ignore_changes = [ 
      network
    ]
  }
}

output "vm_info" {
  value = {
    master = {
      hostname = proxmox_vm_qemu.k8s-master.name
      ip_addr  = "192.168.202.127"
    },
    workers = [
      for i in range(var.vm_count) : {
        hostname = "k8s-worker-${i + 1}"
        ip_addr  = "192.168.202.${128 + i}"
      }
    ]
  }
}

resource "local_file" "create_ansible_inventory" {
  depends_on = [
    proxmox_vm_qemu.k8s-master,
    proxmox_vm_qemu.k8s-workers
  ]

  content = <<EOT
[master-node]
192.168.202.127

[worker-node]
${join("\n", [for i in range(var.vm_count) : "192.168.202.${128 + i}"])}
EOT

  filename = "./inventory.ini"
}


resource "null_resource" "ansible_playbook" {
    depends_on = [local_file.create_ansible_inventory]
    provisioner "local-exec" {
        command = "sleep 60;ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ./inventory.ini playbook-create-k8s-cluster.yml -u ${var.ci_user}"
    }
}
