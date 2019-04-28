#!/bin/bash

set -xue -o pipefail

curl -LO https://github.com/containerd/containerd/releases/download/v1.2.4/containerd-1.2.4.linux-amd64.tar.gz
tar xvf containerd-1.2.4.linux-amd64.tar.gz
sudo mv bin/* /usr/bin/

cat << EOF | sudo tee /etc/systemd/system/containerd.service
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/bin/containerd --log-level debug

Delegate=yes
KillMode=process
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=1048576
# Comment TasksMax if your systemd version does not supports it.
# Only systemd 226 and above support this version.
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

sudo mkdir -p /etc/containerd
cat << EOF | sudo tee /etc/containerd/config.toml
[plugins]
  [plugins.cri]
    [plugins.cri.registry]
      [plugins.cri.registry.mirrors]
        [plugins.cri.registry.mirrors."127.0.0.1"]
          endpoint = ["http://127.0.0.1:5000"]
EOF

sudo systemctl start containerd

curl -LO https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.14.0/crictl-v1.14.0-linux-amd64.tar.gz
tar xvf crictl-v1.14.0-linux-amd64.tar.gz crictl
sudo mv crictl /usr/local/bin/crictl