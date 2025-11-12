# Kubernetes Multi-Control Plane Deployment

## Description
This guide explains how to deploy a Kubernetes (K8s) cluster with multiple control-plane nodes (multi-cp) for high availability. By following these steps, you can set up a resilient and scalable Kubernetes environment suitable for production workloads.

---

## Prerequisites
Before starting, ensure you have the following:

- At least 3 machines/nodes for control planes (recommended odd number for quorum)
- At least 1 machine for worker nodes
- SSH access to all nodes
- Sudo privileges on all nodes
- container runtime installed
- kubeadm, kubelet, and kubectl installed on all nodes

---

## Step-by-Step Deployment

### Step 1: Create load balancer for kube-apiserver 

Create a kube-apiserver load balancer with a name that resolves to DNS.

In a cloud environment you should place your control plane nodes behind a TCP forwarding load balancer. This load balancer distributes traffic to all healthy control plane nodes in its target list. The health check for an apiserver is a TCP check on the port the kube-apiserver listens on (default value :6443).

It is not recommended to use an IP address directly in a cloud environment.

The load balancer must be able to communicate with all control plane nodes on the apiserver port. It must also allow incoming traffic on its listening port.

Make sure the address of the load balancer always matches the address of kubeadm's ControlPlaneEndpoint.

Read the Options for Software Load Balancing guide for more details.

keepalived and haproxy
For providing load balancing from a virtual IP the combination keepalived and haproxy has been around for a long time and can be considered well-known and well-tested:

The keepalived service provides a virtual IP managed by a configurable health check. Due to the way the virtual IP is implemented, all the hosts between which the virtual IP is negotiated need to be in the same IP subnet.
The haproxy service can be configured for simple stream-based load balancing thus allowing TLS termination to be handled by the API Server instances behind it.
This combination can be run either as services on the operating system or as static pods on the control plane hosts. The service configuration is identical for both cases.

#### keepalived configuration
The keepalived configuration consists of two files: the service configuration file and a health check script which will be called periodically to verify that the node holding the virtual IP is still operational.

keepalived and haproxy

For providing load balancing from a virtual IP the combination [keepalived](https://www.keepalived.org) and [haproxy](https://www.haproxy.com) has been around for a long time and can be considered well-known and well-tested:
- The `keepalived` service provides a virtual IP managed by a configurable health check. Due to the way the virtual IP is implemented, all the hosts between which the virtual IP is negotiated need to be in the same IP subnet.
- The `haproxy` service can be configured for simple stream-based load balancing thus allowing TLS termination to be handled by the API Server instances behind it.

This combination can be run either as services on the operating system or as static pods on the control plane hosts. The service configuration is identical for both cases.

### keepalived configuration

The `keepalived` configuration consists of two files: the service configuration file and a health check script which will be called periodically to verify that the node holding the virtual IP is still operational.

The files are assumed to reside in a `/etc/keepalived` directory. Note that however some Linux distributions may keep them elsewhere. The following configuration has been successfully used with `keepalived` version 2.0.20 and 2.2.4:

```bash
! /etc/keepalived/keepalived.conf
! Configuration File for keepalived
global_defs {
    router_id LVS_DEVEL
}
vrrp_script check_apiserver {
  script "/etc/keepalived/check_apiserver.sh"
  interval 3
  weight -2
  fall 10
  rise 2
}

vrrp_instance VI_1 {
    state ${STATE}
    interface ${INTERFACE}
    virtual_router_id ${ROUTER_ID}
    priority ${PRIORITY}
    authentication {
        auth_type PASS
        auth_pass ${AUTH_PASS}
    }
    virtual_ipaddress {
        ${APISERVER_VIP}
    }
    track_script {
        check_apiserver
    }
}
```

There are some placeholders in `bash` variable style to fill in:
- `${STATE}` is `MASTER` for one and `BACKUP` for all other hosts, hence the virtual IP will initially be assigned to the `MASTER`.
- `${INTERFACE}` is the network interface taking part in the negotiation of the virtual IP, e.g. `eth0`.
- `${ROUTER_ID}` should be the same for all `keepalived` cluster hosts while unique amongst all clusters in the same subnet. Many distros pre-configure its value to `51`.
- `${PRIORITY}` should be higher on the control plane node than on the backups. Hence `101` and `100` respectively will suffice.
- `${AUTH_PASS}` should be the same for all `keepalived` cluster hosts, e.g. `42`
- `${APISERVER_VIP}` is the virtual IP address negotiated between the `keepalived` cluster hosts.

The above `keepalived` configuration uses a health check script `/etc/keepalived/check_apiserver.sh` responsible for making sure that on the node holding the virtual IP the API Server is available. This script could look like this:

```
#!/bin/sh

errorExit() {
    echo "*** $*" 1>&2
    exit 1
}

curl -sfk --max-time 2 https://localhost:${APISERVER_DEST_PORT}/healthz -o /dev/null || errorExit "Error GET https://localhost:${APISERVER_DEST_PORT}/healthz"
```

Fill in the placeholder `${APISERVER_DEST_PORT}` with the port through which Kubernetes will talk to the API Server. That is the port haproxy or your load balancer will be listening on.

### haproxy configuration

The `haproxy` configuration consists of one file: the service configuration file which is assumed to reside in a `/etc/haproxy` directory. Note that however some Linux distributions may keep them elsewhere. The following configuration has been successfully used with `haproxy` version 2.4 and 2.8:

```bash
# /etc/haproxy/haproxy.cfg
#---------------------------------------------------------------------
# Global settings
#---------------------------------------------------------------------
global
    log stdout format raw local0
    daemon

#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option http-server-close
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 1
    timeout http-request    10s
    timeout queue           20s
    timeout connect         5s
    timeout client          35s
    timeout server          35s
    timeout http-keep-alive 10s
    timeout check           10s

#---------------------------------------------------------------------
# apiserver frontend which proxys to the control plane nodes
#---------------------------------------------------------------------
frontend apiserver
    bind *:${APISERVER_DEST_PORT}
    mode tcp
    option tcplog
    default_backend apiserverbackend

#---------------------------------------------------------------------
# round robin balancing for apiserver
#---------------------------------------------------------------------
backend apiserverbackend
    option httpchk

    http-check connect ssl
    http-check send meth GET uri /healthz
    http-check expect status 200

    mode tcp
    balance     roundrobin
    
    server ${HOST1_ID} ${HOST1_ADDRESS}:${APISERVER_SRC_PORT} check verify none
    # [...]
```
Again, there are some placeholders in `bash` variable style to expand:
- `${APISERVER_DEST_PORT}` the port through which Kubernetes will talk to the API Server.
- `${APISERVER_SRC_PORT}` the port used by the API Server instances
- `${HOST1_ID}` a symbolic name for the first load-balanced API Server host
- `${HOST1_ADDRESS}` a resolvable address (DNS name, IP address) for the first load-balanced API Server host
- additional `server` lines, one for each load-balanced API Server host

### Option 1: Run the services on the operating system

In order to run the two services on the operating system, the respective distribution's package manager can be used to install the software. This can make sense if they will be running on dedicated hosts not part of the Kubernetes cluster.

Having now installed the abovementioned configuration, the services can be enabled and started. On a recent RedHat-based system, `systemd` will be used for this:
```
# sudo systemctl enable haproxy --now
# sudo systemctl enable keepalived --now
```
With the services up, now the Kubernetes cluster can be bootstrapped using `kubeadm init` (see [below](#bootstrap-the-cluster)).



my deplyment

/etc/haproxy/haproxy.cfg 
```
global
    log stdout format raw local0
    daemon

defaults
        log     global
        mode    tcp
        option tcplog
        timeout connect 5s
        timeout client 30s
        timeout server 30s


#---------------------------------------------------------------------
# apiserver frontend which proxys to the control plane nodes
#---------------------------------------------------------------------
frontend apiserver
    bind *:6443
    mode tcp
    option tcplog
    default_backend apiserverbackend



#---------------------------------------------------------------------
# round robin balancing for apiserver
#---------------------------------------------------------------------
backend apiserverbackend
    option httpchk

    http-check connect ssl
    http-check send meth GET uri /healthz
    http-check expect status 200

    mode tcp
    balance     roundrobin
    
    server cp1 78.39.182.178:6443 check verify none
    server cp2 78.39.182.101:6443 check verify none
    server cp3 78.39.182.204:6443 check verify none
```

cat /etc/keepalived/keepalived.conf
```
global_defs {
    router_id LVS_DEVEL
}
vrrp_script check_apiserver {
  script "/etc/keepalived/check_apiserver.sh"
  interval 3
  weight -2
  fall 10
  rise 2
}

vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 101
    authentication {
        auth_type PASS
        auth_pass 123456789!@#$%^&*(
    }
    virtual_ipaddress {
        78.39.182.251
    }
    track_script {
        check_apiserver
    }
}
```





cat /etc/keepalived/check_apiserver.sh
```
#!/bin/sh

errorExit() {
    echo "*** $*" 1>&2
    exit 1
}

curl -sfk --max-time 2 https://localhost:6443/healthz -o /dev/null || errorExit "Error GET https://localhost:6443/healthz"
```


to join first control plane
```
sudo kubeadm init --control-plane-endpoint "78.39.182.251:6443" --upload-certs  --cri-socket unix:///var/run/crio/crio.sock
```

do this like before
```

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
```


calico plugin install 

curl -fsSL https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml | kubectl apply -f -


