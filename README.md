How to set up kubernetes cluster with nvidia-gpu for vllm

before every thing 
run following to be sure system is stable

```
sudo apt update
sudo apt upgrade
```
if following command is not available on your system
```
nvidia-smi
```
run this command instead
```
sudo ubuntu-drivers autoinstall
sudo reboot
```
now must nvidia-smi works after reboot if not resolve problem then continue the guideline


# xray 
```
sudo bash xray_setup.sh
# to check this properly works
# export http_proxy="socks5://127.0.0.1:1080"
# export https_proxy="socks5://127.0.0.1:1080"
# curl --proxy socks5://127.0.0.1:1080 https://ipinfo.io
```
# privoxy
```
sudo bash privoxy_setup.sh
# to check this properly works
# export http_proxy=http://127.0.0.1:8118
# export https_proxy=http://127.0.0.1:8118
# wget -qO- https://ipinfo.io/ip
```

# crio
```
sudo bash crio_setup.sh
# to check this properly works
# sudo systemctl status crio
```
# k8s
one of follwing must run
k8s setup node
```
sudo bash k8s_setup.sh --yes --role=node --join="$(ssh <controle-plane-user>@<controle-plane> 'kubeadm token create --print-join-command')"
# to check this properly works see in controle plane this must add in
# kubectl get nodes
# if added but it is not ready
# check pods and network pods like claico must be running
```
k8s setup node
```
sudo bash k8s_setup.sh --yes --role=control_plane
# to check this properly works see 
# kubectl get nodes
# if added but it is not ready
# check pods and network pods like claico must be running
```

# gpu
and if the node has nvidia-gpu

gpu crio setup


run this on your control_plane 
```
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.1/deployments/static/nvidia-device-plugin.yml
```

if the control plane must have pod itself
```
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
kubectl taint nodes --all node-role.kubernetes.io/master-
```
just one time for a cluster
```
sudo bash gpu-crio-setup.sh
# to check this properly works see in controle plane
# kubectl get pods -A -o wide
# find nvidia-device-plugin-* pod on node you has been add recently this to it and delete to has been run again this with
# kubectl delete pods nvidia-device-plugin-*  -n kube-system 
# then after it became running stable in kubectl get pods -A -o wide
# see it pod log it must have error about nvml
# after that in
# kubectl describe pods <your_node>
# must see gpu
```
