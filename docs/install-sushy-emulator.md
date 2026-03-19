# Installing Sushy Redfish Emulator on Fedora Server

This document explains **why and how to install the Sushy Redfish emulator** for your lab environment with Single Node OpenShift (SNO) and BareMetalHost provisioning.

---

## Why Sushy Emulator?

BareMetalHost objects in OpenShift require a **Redfish-compliant BMC** to perform actions like:

- Power on/off
- Boot from virtual media
- Provision operating systems

In lab or virtual environments, you usually **don’t have a physical BMC**. The **Sushy emulator** provides a **software Redfish endpoint** that:

- Simulates a real BMC
- Supports Redfish API calls for provisioning
- Works with libvirt/KVM VMs
- Can serve virtual media (ISO images) to VMs

This allows you to **test BareMetalHost workflows in a fully virtual environment**.

---

## Prerequisites

- Fedora Server installed
- KVM virtualization enabled
- libvirt installed and running
- Python 3 and pip available

---

## Passo a Passo.

## Step 1: Install Sushy Tools

```bash
sudo dnf install -y python3-pip libvirt-devel
sudo pip3 install sushy-tools
```
---

## Step 2: Generate SSL Certificate

```bash
openssl req -x509 -newkey rsa:2048 -nodes -keyout ~/bmc-key.pem -out ~/bmc-cert.pem -days 365 \
  -subj "/CN=localhost"
```  
- bmc-key.pem → private key
- bmc-cert.pem → public certificate
  
You will use these in the systemd service.

---

## Step 3: Create Systemd Service
```bash
sudo vim /etc/systemd/system/sushy.service
```

Sample Unit file

```bash
[Unit]
Description=Sushy Redfish Emulator
After=network.target libvirtd.service

[Service]
Type=simple
LimitNOFILE=65535
ExecStart=/usr/local/bin/sushy-emulator \
    -i 0.0.0.0 -p 8000 \
    --libvirt-uri "qemu:///system" \
    --ssl-certificate /"YOUR PATH TO IT"/bmc-cert.pem \
    --ssl-key /"YOUR PATH TO IT"/bmc-key.pem
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```
Explanation:

 - LimitNOFILE=65535 → avoids “too many open files” errors during multiple VM provisioning
 - --libvirt-uri "qemu:///system" → allows Sushy to manage KVM VMs
 - --ssl-certificate and --ssl-key → secure Redfish endpoint
 - Restart=always → ensures emulator restarts if it crashes

 ---
 ## Step 4: Enable and Start Service
 
 ```bash
 sudo systemctl daemon-reload
 sudo systemctl enable --now sushy.service
 ```
 Check status:
 
 ```bash
 sudo systemctl status sushy.service
```
---

## Step 5: Verify Redfish Endpoint

Open a browser or use curl:
```bash
curl -k https://localhost:8000/redfish/v1/Systems/
```
You should see JSON output describing the virtual BMC.

---

## Step 6: Connect BareMetalHost to Emulator

Use the BMC address in your BareMetalHost spec:

```yaml
bmc:
  address: redfish-virtualmedia://<HOST_IP>:8000/redfish/v1/Systems/<SYSTEM_ID>
  credentialsName: <BMC_SECRET>
  disableCertificateVerification: true
```

- <HOST_IP> → your Fedora host IP
- <SYSTEM_ID> → UUID assigned by Sushy for the VM


##
