# Kubernetes-gpu-cluster
Try to write my commands to run gpu cluster


First of all, your servers must be able to bypass censorship.

I have vless url connection so use this method
##### Install Xray-core (Recommended)
```
# Download and install Xray
curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh -o install-release.sh
chmod +x install-release.sh
sudo ./install-release.sh
```

##### Parse the VLESS URL
A typical VLESS URL looks like:

```
vless://UUID@server_address:port?encryption=none&security=tls&type=ws&path=/ws#MyProxy
```
Breakdown
- UUID → your client ID
- server_address:port → host and port
- params → transport type (ws, tcp, grpc), TLS, etc.
- path (if WebSocket)
- SNI or Host sometimes required.

##### Create Client Config (config.json)
Example for WebSocket + TLS:
```
{
  "inbounds": [
    {
      "port": 1080,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": { "auth": "noauth" }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "server_address",
            "port": PORT,
            "users": [{ "id": "UUID", "encryption": "none" }]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "serverName": "YOUR_SNI_IF_ANY",
          "allowInsecure": false
        },
        "wsSettings": {
          "path": "/ws"
        }
      }
    }
  ]
}
```

###### Run Xray
```
sudo xray -config /etc/xray/config.json #replace with your direction config
```
Now you have a local SOCKS5 proxy on 127.0.0.1:1080.
You can use it:
```
export http_proxy="socks5://127.0.0.1:1080"
export https_proxy="socks5://127.0.0.1:1080"
curl --proxy socks5://127.0.0.1:1080 https://ipinfo.io
```

Recommendation: Monitor the output of the running Xray service to ensure that only the intended packets are sent outside the servers. This is important to prevent internal Kubernetes connections from being routed externally.

----

after check that your location withen last command
you must do that all your networks even dns goes through this proxy so do this

### Use privoxy 

Install privoxy:

```
sudo apt install privoxy
```

Edit /etc/privoxy/config:
```
forward-socks5 / 127.0.0.1:1080 .
```
```
sudo systemctl restart privoxy
```
Export HTTP proxy
```
export http_proxy=http://127.0.0.1:8118
export https_proxy=http://127.0.0.1:8118
```

run this and monitor proxy output and this ip
```
wget -qO- https://ipinfo.io/ip
```

after being sure about your connection lets go next step

add this 
```
export no_proxy="localhost,127.0.0.1,10.0.0.0/8,192.168.0.0/16"
```
---

## Kubeadm

Check required ports
```
nc 127.0.0.1 6443 -zv -w 2
```
must see this
```
nc 127.0.0.1 6443 -zv -w 2
nc: connect to 127.0.0.1 port 6443 (tcp) failed: Connection refused
```
it must empty if it is not
```
sudo rm -rf /etc/kubernetes/ /var/lib/kubelet/ /var/lib/etcd/ ~/.kube/
sudo systemctl stop kubelet
sudo systemctl disable kubelet
#check again
sudo ss -tulnp | grep 6443
if be any thing kill it
sudo pkill -f "kube-apiserver"
```

Swap configuration

To disable swap, sudo swapoff -a can be used to disable swapping temporarily. To make this change persistent across reboots, make sure swap is disabled in config files like /etc/fstab, systemd.swap, depending how it was configured on your system.

for check this see this
```
free -h
```

### Container runtime
I use  CRI-O

first add check kubectl version
```
kubectl version
```

and repalce with this

```
KUBERNETES_VERSION=v1.33
CRIO_VERSION=v1.33
```

Install the dependencies for adding repositories
```
apt-get update
apt-get install -y software-properties-common curl
```

Add the CRI-O repository
```
curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key |
  sudo  gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/ /" |
  sudo  tee /etc/apt/sources.list.d/cri-o.list
```

add your proxy to can connect repository

```
echo 'Acquire::http::Proxy::download.opensuse.org "http://127.0.0.1:8118";' | sudo tee -a /etc/apt/apt.conf
echo 'Acquire::https::Proxy::download.opensuse.org "http://127.0.0.1:8118";' | sudo tee -a /etc/apt/apt.conf
```
check that get new one
```
sudo apt-get update
```
and
install cri-o

```
sudo apt-get install -y cri-o
```

Start CRI-O
```
systemctl start crio.service
```

Bootstrap a cluster
```
sudo swapoff -a
sudo modprobe br_netfilter
sudo sysctl -w net.ipv4.ip_forward=1
```

to skip download lateast
```
sudo  kubeadm init --cri-socket=unix:///var/run/crio/crio.sock --kubernetes-version=v1.33.3
```

make sure this port be empty
```
sudo lsof -i :10257
```
I run init it and has this error
```
sudo kubeadm init \
  --cri-socket=unix:///var/run/crio/crio.sock \
  --kubernetes-version=v1.33.3
[init] Using Kubernetes version: v1.33.3
[preflight] Running pre-flight checks
        [WARNING Service-Kubelet]: kubelet service is not enabled, please run 'systemctl enable kubelet.service'
[preflight] Pulling images required for setting up a Kubernetes cluster
[preflight] This might take a minute or two, depending on the speed of your internet connection
[preflight] You can also perform this action beforehand using 'kubeadm config images pull'
error execution phase preflight: [preflight] Some fatal errors occurred:
        [ERROR ImagePull]: failed to pull image registry.k8s.io/kube-apiserver:v1.33.3: failed to pull image registry.k8s.io/kube-apiserver:v1.33.3: unable to try pulling possible OCI artifact: get manifest: build image source: pinging container registry registry.k8s.io: StatusCode: 403, "\n<html><head>\n<meta http-equiv=\"content-type\" cont..."
        
```



### For CRI-O (persistent)
- Edit CRI-O config:
    ```
    sudo mkdir -p /etc/systemd/system/crio.service.d
    sudo tee /etc/systemd/system/crio.service.d/proxy.conf >/dev/null <<'EOF'
    [Service]
    Environment="HTTP_PROXY=http://127.0.0.1:8118"
    Environment="HTTPS_PROXY=http://127.0.0.1:8118"
    Environment="NO_PROXY=localhost,127.0.0.1,10.96.0.0/12,10.244.0.0/16,192.168.0.0/16,.svc,.cluster.local"
    Environment="ALL_PROXY=http://127.0.0.1:8118"
    Environment="all_proxy=http://127.0.0.1:8118"
    EOF
    ```
- Reload and restart CRI-O:
    ```
    sudo systemctl daemon-reload
    sudo systemctl restart crio
    ```
    check with
    ```
    systemctl show crio -p Environment
    ```
this leads to pull images goes through your proxy


you must see thinks like this
```
sudo kubeadm init \
  --cri-socket=unix:///var/run/crio/crio.sock \
  --kubernetes-version=v1.33.3
[init] Using Kubernetes version: v1.33.3
[preflight] Running pre-flight checks
[preflight] Pulling images required for setting up a Kubernetes cluster
[preflight] This might take a minute or two, depending on the speed of your internet connection
[preflight] You can also perform this action beforehand using 'kubeadm config images pull'
[certs] Using certificateDir folder "/etc/kubernetes/pki"
[certs] Generating "ca" certificate and key
[certs] Generating "apiserver" certificate and key
[certs] apiserver serving cert is signed for DNS names [kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local ths-pc-4] and IPs [10.96.0.1 192.168.41.104]
[certs] Generating "apiserver-kubelet-client" certificate and key
[certs] Generating "front-proxy-ca" certificate and key
[certs] Generating "front-proxy-client" certificate and key
[certs] Generating "etcd/ca" certificate and key
[certs] Generating "etcd/server" certificate and key
[certs] etcd/server serving cert is signed for DNS names [localhost ths-pc-4] and IPs [192.168.41.104 127.0.0.1 ::1]
[certs] Generating "etcd/peer" certificate and key
[certs] etcd/peer serving cert is signed for DNS names [localhost ths-pc-4] and IPs [192.168.41.104 127.0.0.1 ::1]
[certs] Generating "etcd/healthcheck-client" certificate and key
[certs] Generating "apiserver-etcd-client" certificate and key
[certs] Generating "sa" key and public key
[kubeconfig] Using kubeconfig folder "/etc/kubernetes"
[kubeconfig] Writing "admin.conf" kubeconfig file
[kubeconfig] Writing "super-admin.conf" kubeconfig file
[kubeconfig] Writing "kubelet.conf" kubeconfig file
[kubeconfig] Writing "controller-manager.conf" kubeconfig file
[kubeconfig] Writing "scheduler.conf" kubeconfig file
[etcd] Creating static Pod manifest for local etcd in "/etc/kubernetes/manifests"
[control-plane] Using manifest folder "/etc/kubernetes/manifests"
[control-plane] Creating static Pod manifest for "kube-apiserver"
[control-plane] Creating static Pod manifest for "kube-controller-manager"
[control-plane] Creating static Pod manifest for "kube-scheduler"
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Starting the kubelet
[wait-control-plane] Waiting for the kubelet to boot up the control plane as static Pods from directory "/etc/kubernetes/manifests"
[kubelet-check] Waiting for a healthy kubelet at http://127.0.0.1:10248/healthz. This can take up to 4m0s
[kubelet-check] The kubelet is healthy after 502.386603ms
[control-plane-check] Waiting for healthy control plane components. This can take up to 4m0s
[control-plane-check] Checking kube-apiserver at https://192.168.41.104:6443/livez
[control-plane-check] Checking kube-controller-manager at https://127.0.0.1:10257/healthz
[control-plane-check] Checking kube-scheduler at https://127.0.0.1:10259/livez
[control-plane-check] kube-controller-manager is healthy after 1.008782868s
[control-plane-check] kube-scheduler is healthy after 2.069877731s
[control-plane-check] kube-apiserver is healthy after 4.002072038s
[upload-config] Storing the configuration used in ConfigMap "kubeadm-config" in the "kube-system" Namespace
[kubelet] Creating a ConfigMap "kubelet-config" in namespace kube-system with the configuration for the kubelets in the cluster
[upload-certs] Skipping phase. Please see --upload-certs
[mark-control-plane] Marking the node ths-pc-4 as control-plane by adding the labels: [node-role.kubernetes.io/control-plane node.kubernetes.io/exclude-from-external-load-balancers]
[mark-control-plane] Marking the node ths-pc-4 as control-plane by adding the taints [node-role.kubernetes.io/control-plane:NoSchedule]
[bootstrap-token] Using token: bdlbwb.mw177jqewo3t53ql
[bootstrap-token] Configuring bootstrap tokens, cluster-info ConfigMap, RBAC Roles
[bootstrap-token] Configured RBAC rules to allow Node Bootstrap tokens to get nodes
[bootstrap-token] Configured RBAC rules to allow Node Bootstrap tokens to post CSRs in order for nodes to get long term certificate credentials
[bootstrap-token] Configured RBAC rules to allow the csrapprover controller automatically approve CSRs from a Node Bootstrap Token
[bootstrap-token] Configured RBAC rules to allow certificate rotation for all node client certificates in the cluster
[bootstrap-token] Creating the "cluster-info" ConfigMap in the "kube-public" namespace
[kubelet-finalize] Updating "/etc/kubernetes/kubelet.conf" to point to a rotatable kubelet client certificate and key
[addons] Applied essential addon: CoreDNS
[addons] Applied essential addon: kube-proxy

Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

  export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 192.168.41.104:6443 --token bdlbwb.mw177jqewo3t53ql \
        --discovery-token-ca-cert-hash sha256:d63674b9fc5fe69816de4c511b9bfbb722128f4a1966219ed3641e6f65d434e3 
```

as mentioned run this
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

because network addon you see this
```
kubectl get nodes
NAME       STATUS     ROLES           AGE     VERSION
ths-pc-4   NotReady   control-plane   2m30s   v1.33.3
```

### Installing  network Addons
install calico
```
curl -fsSL -o calico.yaml \
  https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
```
Apply Calico
```
kubectl apply -f calico.yaml
```

Watch it come up
```
kubectl -n kube-system get pods -l k8s-app=calico-node -w
kubectl -n kube-system get pods -l k8s-app=calico-kube-controllers
kubectl get nodes
```

you must have this
```
kubectl -n kube-system get pods -l k8s-app=calico-node -w
NAME                READY   STATUS     RESTARTS   AGE
calico-node-5rd44   0/1     Init:0/3   0          7s
calico-node-5rd44   0/1     Init:1/3   0          36s
calico-node-5rd44   0/1     Init:2/3   0          37s
calico-node-5rd44   0/1     PodInitializing   0          84s
calico-node-5rd44   0/1     Running           0          85s
calico-node-5rd44   1/1     Running           0          96s
^Cths-4@THS-PC-4:~kubectl -n kube-system get pods -l k8s-app=calico-kube-controllersrs
NAME                                      READY   STATUS    RESTARTS   AGE
calico-kube-controllers-cb7c98d86-ccm8l   1/1     Running   0          118s
ths-4@THS-PC-4:~$ kubectl get nodes
NAME       STATUS   ROLES           AGE   VERSION
ths-pc-4   Ready    control-plane   22m   v1.33.3
```

Be happy you have up kubernetese clusster now

---

## Second Node


swap off (and make permanent)
```
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/' /etc/fstab
```

disable docker and containerd

setup  xray + privoxy in this one again

check kubectl version
```
kubectl version
```
it is beeter to be equal to control plane node

### install kubeadm
```
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```
I have this log that is 403 again
```
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
Hit:1 http://ir.archive.ubuntu.com/ubuntu noble InRelease
Hit:2 http://ir.archive.ubuntu.com/ubuntu noble-updates InRelease   
Hit:3 http://ir.archive.ubuntu.com/ubuntu noble-backports InRelease 
Hit:4 http://security.ubuntu.com/ubuntu noble-security InRelease    
Err:5 https://pkgs.k8s.io/core:/stable:/v1.33/deb  InRelease
  403  Forbidden [IP: 34.107.204.206 443]
Reading package lists... Done
E: Failed to fetch https://pkgs.k8s.io/core:/stable:/v1.33/deb/InRelease  403  Forbidden [IP: 34.107.204.206 443]
E: The repository 'https://pkgs.k8s.io/core:/stable:/v1.33/deb  InRelease' is no longer signed.
N: Updating from such a repository can't be done securely, and is therefore disabled by default.
N: See apt-secure(8) manpage for repository creation and user configuration details.
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
apt-transport-https is already the newest version (2.8.3).
ca-certificates is already the newest version (20240203).
curl is already the newest version (8.5.0-2ubuntu10.6).
gpg is already the newest version (2.4.4-2ubuntu17.3).
The following packages were automatically installed and are no longer required:
  libgl1-amber-dri libglapi-mesa
Use 'sudo apt autoremove' to remove them.
0 upgraded, 0 newly installed, 0 to remove and 25 not upgraded.
```

so to resolve that

```
sudo tee /etc/apt/apt.conf.d/99proxy-k8s >/dev/null <<'EOF'
Acquire::https::Proxy::pkgs.k8s.io "http://127.0.0.1:8118/";
EOF
```

now it must work
```
sudo apt-get update
Hit:1 http://ir.archive.ubuntu.com/ubuntu noble InRelease
Hit:2 http://ir.archive.ubuntu.com/ubuntu noble-updates InRelease                                         
Hit:3 http://ir.archive.ubuntu.com/ubuntu noble-backports InRelease                                       
Hit:4 http://security.ubuntu.com/ubuntu noble-security InRelease                                          
Hit:5 https://prod-cdn.packages.k8s.io/repositories/isv:/kubernetes:/core:/stable:/v1.33/deb  InRelease   
Reading package lists... Done
```

and do this
```
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

Download the public signing key for the Kubernetes package
```
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```
Add the appropriate Kubernetes apt repository.
```
 echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

```
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```
optinal enabaling kubelet
```
sudo systemctl enable --now kubelet
```

Install CRI-O again


join cluster
```
sudo kubeadm join   192.168.41.104:6443 --cri-socket unix:///var/run/crio/crio.sock  --token bdlbwb.mw177jqewo3t53ql         --discovery-token-ca-cert-hash sha256:d63674b9fc5fe69816de4c511b9bfbb722128f4a1966219ed3641e6f65d434e3 
```
if has error for existing run this 
```
sudo kubeadm reset --force
sudo rm -rf /etc/kubernetes/ /var/lib/kubelet/ /var/lib/etcd/ ~/.kube/
sudo systemctl stop kubelet
sudo systemctl disable kubelet
```

if has been connected before
```
sudo kubeadm join   192.168.41.104:6443 --cri-socket unix:///var/run/crio/crio.sock  --token bdlbwb.mw177jqewo3t53ql         --discovery-token-ca-cert-hash sha256:d63674b9fc5fe69816de4c511b9bfbb722128f4a1966219ed3641e6f65d434e3 
[preflight] Running pre-flight checks
        [WARNING Service-Kubelet]: kubelet service is not enabled, please run 'systemctl enable kubelet.service'
[preflight] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[preflight] Use 'kubeadm init phase upload-config --config your-config-file' to re-upload it.
error execution phase kubelet-start: a Node with name "ths-pc-3" and status "Ready" already exists in the cluster. You must delete the existing Node or change the name of this new joining Node
To see the stack trace of this error execute with --v=5 or higher
```

on control plane
```
kubectl drain ths-pc-3 --ignore-daemonsets --delete-emptydir-data

# Then delete the node object:
kubectl delete node ths-pc-3
```
until see this
```
sudo kubeadm join   192.168.41.104:6443 --cri-socket unix:///var/run/crio/crio.sock  --token bdlbwb.mw177jqewo3t53ql         --discovery-token-ca-cert-hash sha256:d63674b9fc5fe69816de4c511b9bfbb722128f4a1966219ed3641e6f65d434e3 
[preflight] Running pre-flight checks
[preflight] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
[preflight] Use 'kubeadm init phase upload-config --config your-config-file' to re-upload it.
[kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
[kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
[kubelet-start] Starting the kubelet
[kubelet-check] Waiting for a healthy kubelet at http://127.0.0.1:10248/healthz. This can take up to 4m0s
[kubelet-check] The kubelet is healthy after 502.334893ms
[kubelet-start] Waiting for the kubelet to perform the TLS Bootstrap

This node has joined the cluster:
* Certificate signing request was sent to apiserver and a response was received.
* The Kubelet was informed of the new secure connection details.

Run 'kubectl get nodes' on the control-plane to see this node join the cluster.
```

and you see this on you control-plane
```
kubectl get nodes
NAME       STATUS   ROLES           AGE    VERSION
ths-pc-3   Ready    <none>          29s    v1.33.3
ths-pc-4   Ready    control-plane   143m   v1.33.3
```

Be happy if you have stable clusster

---
## GPU Support

next step is check witch nodes supports gpu
```
 kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable."nvidia\.com/gpu"
NAME       GPU
ths-pc-3   <none>
ths-pc-4   <none>
```
you see know because you need install add-one

run in each node 
```
nvidia-smi
```
if does not show your gpu and not installed
install it with
```
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
```
```
sudo apt-get update
```

```
sudo apt-get install nvidia-container-toolkit
```

after that if it does not work update drivers or
```
sudo ubuntu-drivers autoinstall
```
or install specific driver
```
sudo apt install nvidia-driver-535
```
and 
```
sudo reboot
```

#### Configuring CRI-O
The nvidia-ctk command modifies the /etc/crio/crio.conf file on the host. The file is updated so that CRI-O can use the NVIDIA Container Runtime.
```
sudo nvidia-ctk runtime configure --runtime=crio --set-as-default --config=/etc/crio/crio.conf.d/99-nvidia.conf
```

```
sudo systemctl restart crio
```
I got this error
```
sudo systemctl restart crio
Job for crio.service failed because the control process exited with error code.
See "systemctl status crio.service" and "journalctl -xeu crio.service" for details.
```
I did this
```
which crun || sudo apt-get install -y crun
crun --version
```
but still has problem
```
sudo apt-get update
sudo apt-get install -y conmon
which conmon && conmon --version
```
and then it works 
```
sudo systemctl restart crio
```

in middle of that I see this 

```
kubectl get pods -n kube-system -w
NAME                                      READY   STATUS                      RESTARTS   AGE
calico-kube-controllers-cb7c98d86-r26kx   0/1     ContainerCreating           0          5m24s
calico-node-cp52m                         0/1     Init:CreateContainerError   0          5m20s
calico-node-twwcv                         0/1     Init:0/3                    0          5m20s
coredns-674b8bbfcf-nnfwl                  0/1     ContainerCreating           0          22m
coredns-674b8bbfcf-zmfzh                  0/1     ContainerCreating           0          22m
etcd-ths-pc-4                             1/1     Running                     116        3h11m
kube-apiserver-ths-pc-4                   1/1     Running                     103        3h11m
kube-controller-manager-ths-pc-4          1/1     Running                     0          3h11m
kube-proxy-njstm                          0/1     ContainerCreating           0          48m
kube-proxy-vqdsj                          1/1     Running                     0          3h11m
kube-scheduler-ths-pc-4                   1/1     Running                     118        3h11m
```

it is again proxy problem I must make it works again
although systemctl show crio -p Environment
is setted proxy
pull does not get from proxies

I do this
```sudo mkdir -p /etc/systemd/system/crio.service.d
sudo tee /etc/systemd/system/crio.service.d/proxy.conf >/dev/null <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:8118"
Environment="HTTPS_PROXY=http://127.0.0.1:8118"
Environment="NO_PROXY=localhost,127.0.0.1,::1,.svc,.svc.cluster.local,.cluster.local,10.96.0.0/12,10.244.0.0/16,192.168.0.0/16,169.254.0.0/16"
Environment="http_proxy=http://127.0.0.1:8118"
Environment="https_proxy=http://127.0.0.1:8118"
Environment="no_proxy=localhost,127.0.0.1,::1,.svc,.svc.cluster.local,.cluster.local,10.96.0.0/12,10.244.0.0/16,192.168.0.0/16,169.254.0.0/16"
Environment="ALL_PROXY=http://127.0.0.1:8118"
Environment="all_proxy=http://127.0.0.1:8118"
EOF

sudo systemctl daemon-reload
sudo systemctl restart crio
systemctl show crio -p Environment
```
but does not work

I must run it in non-control-plane nodes too


after that some has error 
which reslove with editing this 
```
# /etc/crio/crio.conf.d/99-nvidia.conf
[crio]
  [crio.runtime]
    default_runtime = "crun"   # was "nvidia"
    [crio.runtime.runtimes]
      [crio.runtime.runtimes.nvidia]
        runtime_path = "/usr/bin/nvidia-container-runtime"
        runtime_type = "oci"
```

and reload
```
sudo systemctl daemon-reload
sudo systemctl restart crio
```

now install nvidia plugin

```
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.1/deployments/static/nvidia-device-plugin.yml
```


test 
With the daemonset deployed, NVIDIA GPUs can now be requested by a container using the nvidia.com/gpu resource type:
```
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-pod
spec:
  restartPolicy: Never
  containers:
    - name: cuda-container
      image: nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda12.5.0
      resources:
        limits:
          nvidia.com/gpu: 1 # requesting 1 GPU
  tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
EOF
```
unfortunantly it is pending
```
kubectl get pods 
NAME      READY   STATUS    RESTARTS   AGE
gpu-pod   0/1     Pending   0          82s
```
its describe is
```
FailedScheduling  2m19s  default-scheduler  0/2 nodes are available: 1 Insufficient nvidia.com/gpu, 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }. preemption: 0/2 nodes are available: 1 No preemption victims found for incoming pod, 1 Preemption is not helpful for scheduling.
```

add this to 
```
# allow the plugin to run on control-plane nodes
kubectl -n kube-system patch ds nvidia-device-plugin-daemonset \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"node-role.kubernetes.io/control-plane","operator":"Exists","effect":"NoSchedule"}}]'
```
now we have this 
```
kubectl -n kube-system get pods -o wide | grep nvidia-device-plugin
nvidia-device-plugin-daemonset-h2vct      1/1     Running   0          23s     172.17.131.3     ths-pc-3   <none>           <none>
nvidia-device-plugin-daemonset-zxn5m      1/1     Running   0          91s     172.17.74.65     ths-pc-4   <none>           <none>
```

I come back to this
```
# /etc/crio/crio.conf.d/99-nvidia.conf
[crio]
  [crio.runtime]
    default_runtime = "nvidia"   
    [crio.runtime.runtimes]
      [crio.runtime.runtimes.nvidia]
        runtime_path = "/usr/bin/nvidia-container-runtime"
        runtime_type = "oci"
```
and get this error
in one podes
```
 Warning  Failed     1s (x25 over 4m54s)  kubelet            Error: container create failed: unknown version specified
```




I have coredns not runnig because 8080 permission 
Edit Corefile: add a port to health:
```
kubectl -n kube-system edit cm coredns
# change this block:
#   health {
#      lameduck 5s
#   }
# to:
#   health :8181 {
#      lameduck 5s
#   }


```
it does not work well vi
so I use this method

```
KUBE_EDITOR="nano" kubectl -n kube-system edit cm coredns

```

and 
```
kubectl -n kube-system patch deploy coredns --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/port","value":8181},
  {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":8181}
]'
```

it does not works

Disable Go’s async preemption in CoreDNS (quick + safe)

```
# Add env to CoreDNS Deployment
kubectl -n kube-system set env deploy/coredns GODEBUG=asyncpreemptoff=1

# (You already switched health to 8181; keep that)
kubectl -n kube-system rollout restart deploy coredns

# Watch it come up
kubectl -n kube-system get pods -w
```
does not works

Tell Kubernetes to run CoreDNS with unconfined AppArmor

```
kubectl -n kube-system patch deploy coredns --type='json' -p='[
  {"op":"add","path":"/spec/template/metadata/annotations","value":
    {"container.apparmor.security.beta.kubernetes.io/coredns":"unconfined"}}
]'
kubectl -n kube-system rollout restart deploy coredns
```
every thing works well now

```
kubectl -n kube-system get pods 
NAME                                      READY   STATUS    RESTARTS   AGE
calico-kube-controllers-cb7c98d86-nwr87   1/1     Running   0          38m
calico-node-s2wgq                         1/1     Running   0          38m
coredns-6dbc9768d4-2zsdr                  1/1     Running   0          18s
coredns-6dbc9768d4-vlvv6                  1/1     Running   0          18s
etcd-ths-pc-4                             1/1     Running   129        46m
kube-apiserver-ths-pc-4                   1/1     Running   116        46m
kube-controller-manager-ths-pc-4          1/1     Running   13         46m
kube-proxy-9w4rt                          1/1     Running   0          45m
kube-scheduler-ths-pc-4                   1/1     Running   131        46m
```



install again nvidia plugin
and 
do this for just control-plan
```
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
kubectl taint nodes --all node-role.kubernetes.io/master-
```

it runs but has this error in log

```
W0811 06:14:44.650124       1 factory.go:101] nvml init failed: Unknown Error
I0811 06:14:44.650133       1 main.go:381] No devices found. Waiting indefinitely.
```

I run this

```
sudo nvidia-ctk runtime configure --runtime=crio

# (Recommended) Generate CDI spec so workloads get driver libs/devices cleanly
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# Restart CRI-O to pick up hooks
sudo systemctl restart crio
```
but there is not this
```
ls /usr/share/containers/oci/hooks.d/ | grep -i nvidia
```

so 
Make sure CRI-O is configured to use hooks
```
# See where CRI-O looks for hooks
grep -R "hooks_dir" /etc/crio/crio.conf /etc/crio/crio.conf.d/* 2>/dev/null || true
grep -R "hooks_dir" /usr/share/containers/containers.conf /etc/containers/containers.conf 2>/dev/null || true
```
If you don’t see a hooks_dir list, add a drop-in:
```
sudo mkdir -p /etc/crio/crio.conf.d
sudo tee /etc/crio/crio.conf.d/99-nvidia-hooks.conf <<'EOF'
[crio.runtime]
hooks_dir = ["/usr/share/containers/oci/hooks.d", "/etc/containers/oci/hooks.d"]
EOF
```
First try with nvidia-ctk (preferred):
```
# Create the hook into a hooks_dir that CRI-O reads
sudo mkdir -p /usr/share/containers/oci/hooks.d
sudo nvidia-ctk hook configure --hook-dir=/usr/share/containers/oci/hooks.d
```
If that subcommand isn’t available, make the hook JSON manually (ensure the binary path exists):
```
command -v nvidia-container-toolkit  # should print /usr/bin/nvidia-container-toolkit

sudo tee /usr/share/containers/oci/hooks.d/oci-nvidia-hook.json <<'JSON'
{
  "version": "1.0.0",
  "hook": {
    "path": "/usr/bin/nvidia-container-toolkit",
    "args": ["nvidia-container-toolkit", "prestart"]
  },
  "when": { "always": false, "commands": [".*"] },
  "stages": ["prestart"]
}
JSON
```
```
sudo systemctl restart crio
```
and now has this
```
ls /usr/share/containers/oci/hooks.d/ | grep -i nvidia
oci-nvidia-hook.json
```
and this
```
ls /usr/share/containers/oci/hooks.d/ | grep -i nvidia
oci-nvidia-hook.json
ths-4@THS-PC-4:~$ grep -R "hooks_dir" /etc/crio/crio.conf /etc/crio/crio.conf.d/*
/etc/crio/crio.conf.d/99-nvidia-hooks.conf:hooks_dir = ["/usr/share/containers/oci/hooks.d", "/etc/containers/oci/hooks.d"]
ths-4@THS-PC-4:~$ ls /etc/cdi/nvidia.yaml
/etc/cdi/nvidia.yaml
```
 
Bounce the device plugin and verify it finds GPUs
```
kubectl -n kube-system rollout restart ds/nvidia-device-plugin-daemonset
kubectl -n kube-system logs ds/nvidia-device-plugin-daemonset --tail=100
```
still that error is exist

Create the NVIDIA OCI hook JSON yourself (either dir is fine; we’ll use /usr/share/...)
```
# Ensure the toolkit binary exists
command -v nvidia-container-toolkit

# Create the hook definition
sudo mkdir -p /usr/share/containers/oci/hooks.d
sudo tee /usr/share/containers/oci/hooks.d/oci-nvidia-hook.json <<'JSON'
{
  "version": "1.0.0",
  "hook": {
    "path": "/usr/bin/nvidia-container-toolkit",
    "args": ["nvidia-container-toolkit", "prestart"]
  },
  "when": { "always": true },
  "stages": ["prestart"]
}
JSON
```

Generate a CDI spec:
```
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```
Restart CRI-O and bounce the plugin:
```
sudo systemctl restart crio
kubectl -n kube-system rollout restart ds/nvidia-device-plugin-daemonset
kubectl -n kube-system logs ds/nvidia-device-plugin-daemonset --tail=100
```


after a lot of resaerch I solve it with this
```
cat <<'YAML' | kubectl apply -f -
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: crun
handler: crun
YAML
```

Patch the device-plugin DaemonSet to use it and ensure it’s privileged + has the right NVIDIA env:

```
# Use crun for the DS
kubectl -n kube-system patch ds nvidia-device-plugin-daemonset --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/runtimeClassName","value":"crun"}]'

# Ensure env tells the hook to inject libs/devices
kubectl -n kube-system set env ds/nvidia-device-plugin-daemonset \
  NVIDIA_VISIBLE_DEVICES=all \
  NVIDIA_DRIVER_CAPABILITIES=utility,compute \
  LIBNVIDIA_CONTAINER_LOG_LEVEL=debug \
  NVIDIA_LOG_LEVEL=debug

# Ensure privileged (if not already)
kubectl -n kube-system patch ds nvidia-device-plugin-daemonset --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/securityContext","value":{"privileged":true}}]'

# Restart it
kubectl -n kube-system rollout restart ds/nvidia-device-plugin-daemonset

```

and can Verify inside the plugin pod
```
POD=$(kubectl -n kube-system get po -l name=nvidia-device-plugin-ds -o jsonpath='{.items[0].metadata.name}')

# Devices and libs present?
kubectl -n kube-system exec "$POD" -- sh -lc '
  echo ENV:; env | grep -E "^NVIDIA_|LIBNVIDIA" || true;
  echo DEV:; ls -l /dev/nvidia* 2>/dev/null || echo "NO /dev/nvidia*";
  echo NVML:; ldconfig -p 2>/dev/null | grep nvidia-ml || echo "NO libnvidia-ml";
  echo SMI:; nvidia-smi || true'
```
no have new error
```
default                gpu-pod                                                 0/1     CreateContainerError   0                3m34s
```

```
  Warning  Failed     5s (x14 over 2m41s)  kubelet            Error: container create failed: error executing hook `/usr/bin/nvidia-container-toolkit` (exit code: 1)
  Normal   Pulled     5s (x13 over 2m40s)  kubelet            Container image "nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda12.5.0" already present on machine
```

I do these an recive error instead of creation
```
# Keep the hook file; disable CDI to avoid ambiguity
sudo mv /etc/cdi/nvidia.yaml /etc/cdi/nvidia.yaml.disabled 2>/dev/null || true

# Ensure the hook file is present
ls -l /usr/share/containers/oci/hooks.d/oci-nvidia-hook.json
sudo systemctl restart crio
```
or
```
# Force the runtime to CDI mode
sudo nvidia-ctk config --in-place --set nvidia-container-runtime.mode=cdi

# Regenerate the CDI spec
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# Disable the OCI hook so it doesn't run
sudo mv /usr/share/containers/oci/hooks.d/oci-nvidia-hook.json \
        /usr/share/containers/oci/hooks.d/oci-nvidia-hook.json.disabled

sudo systemctl restart crio
```
 Recreate the /dev/char symlinks (safe to repeat)
```
sudo nvidia-ctk system create-dev-char-symlinks --create-all
sudo udevadm control --reload && sudo udevadm trigger
ls -l /dev/char | grep nvidia | head
```

and see this 
```
kubectl logs gpu-pod
Failed to allocate device vector A (error code CUDA driver version is insufficient for CUDA runtime version)!
[Vector addition of 50000 elements]
it becanms error 
```

atleast with call this 
nvcc --version
I understand we have not cuda on system


run this
from production stack
```
helm repo add vllm https://vllm-project.github.io/production-stack
helm install vllm vllm/vllm-stack -f tutorials/assets/values-01-minimal-example.yaml
```
get error
```
default                vllm-opt125m-deployment-vllm-5bcd9676f9-8zd62           0/1     Error               0              43m
```
and this log
```
  File "/usr/local/bin/vllm", line 10, in <module>
    sys.exit(main())
             ^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/entrypoints/cli/main.py", line 53, in main
    args.dispatch_function(args)
  File "/usr/local/lib/python3.12/dist-packages/vllm/entrypoints/cli/serve.py", line 27, in cmd
    uvloop.run(run_server(args))
  File "/usr/local/lib/python3.12/dist-packages/uvloop/__init__.py", line 109, in run
    return __asyncio.run(
           ^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/asyncio/runners.py", line 195, in run
    return runner.run(main)
           ^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/asyncio/runners.py", line 118, in run
    return self._loop.run_until_complete(task)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "uvloop/loop.pyx", line 1518, in uvloop.loop.Loop.run_until_complete
  File "/usr/local/lib/python3.12/dist-packages/uvloop/__init__.py", line 61, in wrapper
    return await main
           ^^^^^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/entrypoints/openai/api_server.py", line 1078, in run_server
    async with build_async_engine_client(args) as engine_client:
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/contextlib.py", line 210, in __aenter__
    return await anext(self.gen)
           ^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/entrypoints/openai/api_server.py", line 146, in build_async_engine_client
    async with build_async_engine_client_from_engine_args(
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.12/contextlib.py", line 210, in __aenter__
    return await anext(self.gen)
           ^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/entrypoints/openai/api_server.py", line 166, in build_async_engine_client_from_engine_args
    vllm_config = engine_args.create_engine_config(usage_context=usage_context)
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/dist-packages/vllm/engine/arg_utils.py", line 1098, in create_engine_config
    device_config = DeviceConfig(device=self.device)
                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "<string>", line 4, in __init__
  File "/usr/local/lib/python3.12/dist-packages/vllm/config.py", line 2119, in __post_init__
    raise RuntimeError(
RuntimeError: Failed to infer device type, please set the environment variable `VLLM_LOGGING_LEVEL=DEBUG` to turn on verbose logging to help debug the issue.

```

I tried this
```
helm upgrade vllm vllm/vllm-stack \
  -f tutorials/assets/values-01-minimal-example.yaml \
  --set servingEngineSpec.runtimeClassName=crun
Release "vllm" has been upgraded. Happy Helming!
NAME: vllm
LAST DEPLOYED: Mon Aug 11 14:35:43 2025
NAMESPACE: default
STATUS: deployed
REVISION: 2
TEST SUITE: None
```

got this error in log
```
kubectl logs vllm-opt125m-deployment-vllm-c6bb87748-g4mrv
INFO 08-11 04:15:03 [__init__.py:243] No platform detected, vLLM is running on UnspecifiedPlatform
```

I run this one
```
helm install vllm vllm/vllm-stack \
  -f tutorials/assets/values-01-minimal-example.yaml \
  --set servingEngineSpec.runtimeClassName=crun \
  --set servingEngineSpec.modelSpec[0].repository=vllm/vllm-openai \
  --set servingEngineSpec.modelSpec[0].tag=v0.8.4   # example; pick a 12.4-friendly tag
```


Keep ENVVAR mode but allow devices via the spec
Tell the device-plugin to pass device specs, so runc sets cgroup allow rules:
```
kubectl -n kube-system patch ds nvidia-device-plugin-daemonset --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args","value":["--device-list-strategy=envvar","--pass-device-specs=true"]}]' \
|| kubectl -n kube-system patch ds nvidia-device-plugin-daemonset --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/args","value":["--device-list-strategy=envvar","--pass-device-specs=true"]}]'

kubectl -n kube-system rollout restart ds/nvidia-device-plugin-daemonset
```
```
kubectl port-forward svc/vllm-router-service 30080:80 --address 0.0.0.0
```


now lets add other node
delete old added join again
it is ready in get nodes
but there is problen ib pods with that node
lets see them
it is that know error
```
 Warning  Failed     23s (x26 over 5m26s)  kubelet            Error: container create failed: unknown version specified
```
must upgrade crun first on each node
from here 
http://ftp.debian.org/debian/pool/main/c/crun/
```
sudo dpkg -i crun_1.21-1_amd64.deb
sudo apt -f install   # Fix any missing dependencies
```
to 
```
crun --version
crun version 1.21
```

now every pods works well after reload

but in node describe it does not have gpu

and thir log are diffrent 
normal one is this
```
kubectl  logs nvidia-device-plugin-daemonset-nsm8m  -n kube-system
I0811 13:24:16.371841       1 main.go:235] "Starting NVIDIA Device Plugin" version=<
        3c378193
        commit: 3c378193fcebf6e955f0d65bd6f2aeed099ad8ea
 >
I0811 13:24:16.371925       1 main.go:238] Starting FS watcher for /var/lib/kubelet/device-plugins
I0811 13:24:16.372001       1 main.go:245] Starting OS watcher.
I0811 13:24:16.372484       1 main.go:260] Starting Plugins.
I0811 13:24:16.372542       1 main.go:317] Loading configuration.
I0811 13:24:16.374467       1 main.go:342] Updating config with default resource matching patterns.
I0811 13:24:16.374979       1 main.go:353] 
Running with config:
{
  "version": "v1",
  "flags": {
    "migStrategy": "none",
    "failOnInitError": false,
    "mpsRoot": "",
    "nvidiaDriverRoot": "/",
    "nvidiaDevRoot": "/",
    "gdsEnabled": false,
    "mofedEnabled": false,
    "useNodeFeatureAPI": null,
    "deviceDiscoveryStrategy": "auto",
    "plugin": {
      "passDeviceSpecs": true,
      "deviceListStrategy": [
        "envvar"
      ],
      "deviceIDStrategy": "uuid",
      "cdiAnnotationPrefix": "cdi.k8s.io/",
      "nvidiaCTKPath": "/usr/bin/nvidia-ctk",
      "containerDriverRoot": "/driver-root"
    }
  },
  "resources": {
    "gpus": [
      {
        "pattern": "*",
        "name": "nvidia.com/gpu"
      }
    ]
  },
  "sharing": {
    "timeSlicing": {}
  },
  "imex": {}
}
I0811 13:24:16.375004       1 main.go:356] Retrieving plugins.
I0811 13:24:16.399600       1 server.go:195] Starting GRPC server for 'nvidia.com/gpu'
I0811 13:24:16.400246       1 server.go:139] Starting to serve 'nvidia.com/gpu' on /var/lib/kubelet/device-plugins/nvidia-gpu.sock
I0811 13:24:16.402167       1 server.go:146] Registered device plugin for 'nvidia.com/gpu' with Kubelet
```
unnormal one is this
```
 kubectl  logs nvidia-device-plugin-daemonset-5jtb2  -n kube-system
I0812 05:04:19.835683       1 main.go:235] "Starting NVIDIA Device Plugin" version=<
        3c378193
        commit: 3c378193fcebf6e955f0d65bd6f2aeed099ad8ea
 >
I0812 05:04:19.835765       1 main.go:238] Starting FS watcher for /var/lib/kubelet/device-plugins
I0812 05:04:19.836131       1 main.go:245] Starting OS watcher.
I0812 05:04:19.836347       1 main.go:260] Starting Plugins.
I0812 05:04:19.836376       1 main.go:317] Loading configuration.
I0812 05:04:19.837066       1 main.go:342] Updating config with default resource matching patterns.
I0812 05:04:19.837365       1 main.go:353] 
Running with config:
{
  "version": "v1",
  "flags": {
    "migStrategy": "none",
    "failOnInitError": false,
    "mpsRoot": "",
    "nvidiaDriverRoot": "/",
    "nvidiaDevRoot": "/",
    "gdsEnabled": false,
    "mofedEnabled": false,
    "useNodeFeatureAPI": null,
    "deviceDiscoveryStrategy": "auto",
    "plugin": {
      "passDeviceSpecs": true,
      "deviceListStrategy": [
        "envvar"
      ],
      "deviceIDStrategy": "uuid",
      "cdiAnnotationPrefix": "cdi.k8s.io/",
      "nvidiaCTKPath": "/usr/bin/nvidia-ctk",
      "containerDriverRoot": "/driver-root"
    }
  },
  "resources": {
    "gpus": [
      {
        "pattern": "*",
        "name": "nvidia.com/gpu"
      }
    ]
  },
  "sharing": {
    "timeSlicing": {}
  },
  "imex": {}
}
I0812 05:04:19.837377       1 main.go:356] Retrieving plugins.
E0812 05:04:19.837549       1 factory.go:112] Incompatible strategy detected auto
E0812 05:04:19.837557       1 factory.go:113] If this is a GPU node, did you configure the NVIDIA Container Toolkit?
E0812 05:04:19.837563       1 factory.go:114] You can check the prerequisites at: https://github.com/NVIDIA/k8s-device-plugin#prerequisites
E0812 05:04:19.837569       1 factory.go:115] You can learn how to set the runtime at: https://github.com/NVIDIA/k8s-device-plugin#quick-start
E0812 05:04:19.837576       1 factory.go:116] If this is not a GPU node, you should set up a toleration or nodeSelector to only deploy this plugin on GPU nodes
I0812 05:04:19.837584       1 main.go:381] No devices found. Waiting indefinitely.
```

it  is working node
```
ls /etc/crio/crio.conf.d/
100-runtime.conf  10-crio.conf  20-runtime.conf  99-nvidia.conf  99-nvidia-hooks.conf  99-runtime.conf
```
non-working
```
ls /etc/crio/crio.conf.d/
10-crio.conf  99-nvidia.conf
```

working:
```
cat /etc/crio/crio.conf.d/99-nvidia.conf 

[crio]

  [crio.runtime]
    default_runtime = "crun"

    [crio.runtime.runtimes]

      [crio.runtime.runtimes.nvidia]
        runtime_path = "/usr/bin/nvidia-container-runtime"
        runtime_type = "oci"
```
```
cat /etc/crio/crio.conf.d/99-nvidia-hooks.conf 
[crio.runtime]
hooks_dir = ["/usr/share/containers/oci/hooks.d", "/etc/containers/oci/hooks.d"]
```
```
cat /etc/crio/crio.conf.d/99-runtime.conf 
[crio.runtime]
default_runtime = "crun"
cgroup_manager = "systemd"

[crio.runtime.runtimes.crun]
runtime_path = "/usr/bin/crun"
runtime_type = "oci"
runtime_root = "/run/crun"
```
```
# I think it does not used
cat /etc/crio/crio.conf.d/100-runtime.conf 
[crio.runtime]
default_runtime = "crun"
cgroup_manager = "systemd"

[crio.runtime.runtimes.crun]
runtime_path = "/usr/bin/crun"
runtime_type = "oci"
runtime_root = "/run/crun"
```
so 
do this
```
sudo mkdir -p /usr/share/containers/oci/hooks.d
[sudo] password for ths-3: 
ths-3@THS-PC-3:~$ sudo tee /usr/share/containers/oci/hooks.d/oci-nvidia-hook.json <<'JSON'
{
  "version": "1.0.0",
  "hook": {
    "path": "/usr/bin/nvidia-container-toolkit",
    "args": ["nvidia-container-toolkit", "prestart"]
  },
  "when": { "always": true },
  "stages": ["prestart"]
}
JSON
{
  "version": "1.0.0",
  "hook": {
    "path": "/usr/bin/nvidia-container-toolkit",
    "args": ["nvidia-container-toolkit", "prestart"]
  },
  "when": { "always": true },
  "stages": ["prestart"]
}
```


and do this
```
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

try this config
```                            
servingEngineSpec:
  runtimeClassName: "crun"

  modelSpec:
    - name: "opt125m"
      repository: "vllm/vllm-openai"
      tag: "v0.8.4"
      modelURL: "facebook/opt-125m"

      replicaCount: 2

      requestCPU: 6
      requestMemory: "16Gi"
      requestGPU: 1

      # (optional) pin to your GPU nodes; label them first
      #   kubectl label node <node1> gpu=true
      #   kubectl label node <node2> gpu=true
      nodeSelector:
        gpu: "true"

      # Keep replicas on different nodes
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  # Adjust if your chart uses different labels; these are common defaults
                  - key: app.kubernetes.io/name
                    operator: In
                    values: ["vllm-stack"]
                  - key: app.kubernetes.io/component
                    operator: In
                    values: ["serving-engine"]
              topologyKey: kubernetes.io/hostname

      # Extra safety to spread by node
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values: ["vllm-stack"]
              - key: app.kubernetes.io/component
                operator: In
                values: ["serving-engine"]

      # (only if your GPU nodes are tainted)
      # tolerations:
      #   - key: "nvidia.com/gpu"
      #     operator: "Exists"
      #     effect: "NoSchedule"

```

```
helm install  vllm vllm/vllm-stack \
  -f tutorials/assets/values-01-minimal-example2.yaml
```


Expose the vllm-router-service port to the host machine:
```
kubectl port-forward --address 0.0.0.0 svc/vllm-router-service 30080:80
```


for running another model you can just change this 
modelURL: "facebook/opt-125m"
but it does not work for me because of internet problem or unknown reason
so I download the model manually 
with git 
```
sudo apt install git-lfs
```
for example 
```
git clone https://huggingface.co/Qwen/Qwen3-0.6B
```
copy that on ```/models``` directory in root in all nodes
then use this config yaml
```
servingEngineSpec:
  runtimeClassName: "crun"

  modelSpec:
    - name: "qwen3"
      repository: "vllm/vllm-openai"
      tag: "v0.8.4"
      modelURL: "/models/Qwen3-0.6B"

      replicaCount: 2

      requestCPU: 6
      requestMemory: "16Gi"
      requestGPU: 1

      # (optional) pin to your GPU nodes; label them first
      #   kubectl label node <node1> gpu=true
      #   kubectl label node <node2> gpu=true
      nodeSelector:
        gpu: "true"


      # Add path
      extraVolumes:
        - name: local-models
          hostPath:
            path: /models/Qwen3-0.6B   # path on each node
            type: Directory
      extraVolumeMounts:
        - name: local-models
          mountPath: /models/Qwen3-0.6B
          readOnly: true

      # Keep replicas on different nodes
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  # Adjust if your chart uses different labels; these are common defaults
                  - key: app.kubernetes.io/name
                    operator: In
                    values: ["vllm-stack"]
                  - key: app.kubernetes.io/component
                    operator: In
                    values: ["serving-engine"]
              topologyKey: kubernetes.io/hostname

      # Extra safety to spread by node
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values: ["vllm-stack"]
              - key: app.kubernetes.io/component
                operator: In
                values: ["serving-engine"]

      # (only if your GPU nodes are tainted)
      # tolerations:
      #   - key: "nvidia.com/gpu"
      #     operator: "Exists"
      #     effect: "NoSchedule"
```


## Having one model on two node

lets start with 
#### Setting Up a Kuberay Operator on Your Kubernetes Environment

Add the KubeRay Helm repository:
```
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update
```

Install the Custom Resource Definitions (CRDs) and the KubeRay operator (version 1.2.0) in the default namespace:
```
helm install kuberay-operator kuberay/kuberay-operator --version 1.2.0
```
it has problem for me after running error permission
I run this
after that to skip this error 
```
NS=default
# Get the container name (usually "manager"):
kubectl -n $NS get deploy kuberay-operator -o jsonpath='{.spec.template.spec.containers[0].name}'; echo
# Save it as MANAGER if you want (optional)
MANAGER=$(kubectl -n $NS get deploy kuberay-operator -o jsonpath='{.spec.template.spec.containers[0].name}')

# a) Seccomp → Unconfined
kubectl -n $NS patch deploy kuberay-operator --type=json -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/securityContext",
   "value":{"seccompProfile":{"type":"Unconfined"}}}
]'

# b) AppArmor → unconfined (targets that container specifically)
kubectl -n $NS patch deploy kuberay-operator --type=json -p="[
  {\"op\":\"add\",\"path\":\"/spec/template/metadata/annotations\",
   \"value\":{\"container.apparmor.security.beta.kubernetes.io/${MANAGER}\":\"unconfined\"}}
]"
```

#### Verify the KubeRay Configuration
Check the Operator Pod Status:

Ensure that the KubeRay operator pod is running:
```
kubectl get pods -A | grep kuberay-operator
```
Expected Output: Example output:
```
NAME                                          READY   STATUS    RESTARTS   AGE
kuberay-operator-975995b7d-75jqd              1/1     Running   0          25h
```

### basic-pipeline-parallel

Step 1: Basic explanation of Ray and Kuberay
1. Ray is a framework designed for distributed workloads, such as distributed training and inference. It operates by running multiple processes—typically containers or pods—to distribute and synchronize tasks efficiently.

1. Ray organizes these processes into a Ray cluster, which consists of a single head node and multiple worker nodes. The term "node" here refers to a logical process, which can be deployed as a container or pod.

1. KubeRay is a Kubernetes operator that simplifies the creation and management of Ray clusters within a Kubernetes environment. Without KubeRay, setting up Ray nodes requires manual configuration.

1. Using KubeRay, you can easily deploy Ray clusters on Kubernetes. These clusters enable distributed inference with vLLM, supporting both tensor parallelism and pipeline parallelism.