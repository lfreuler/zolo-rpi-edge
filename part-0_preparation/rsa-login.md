Hier ein **Mini-Guide** für dich, damit du vom Main-Raspberry auf deine Worker kommst ohne jedes Mal `-i` anzugeben:

---

# 🔑 SSH Key-Setup Mini Guide

## 1. Key an richtigen Ort verschieben

```bash
mv /home/pi/.rsa /home/pi/.ssh/id_rsa
chmod 600 /home/pi/.ssh/id_rsa
```

👉 Jetzt wird der Key automatisch von `ssh` genutzt.

---

## 2. SSH Config anlegen

Datei erstellen/öffnen:

```bash
nano ~/.ssh/config
```

Beispiel einfügen:

```text
Host worker1
  HostName 192.168.1.101
  User pi

Host worker2
  HostName 192.168.1.102
  User pi
```

Speichern und schließen.

---

## 3. Verbinden

```bash
ssh worker1
ssh worker2
```

---

## 4. Optional: Key Agent nutzen (für mehrere Sessions)

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa
```

---

➡️ Danach läuft alles ohne `-i` und ohne Passworteingabe.

Soll ich dir gleich ein **Template für 5 Worker** machen, wo du nur noch die IPs austauschst?





scp /home/pi/.ssh/id_rsa 192.168.1.102:/home/pi/.ssh/id_rsa
scp /home/pi/.ssh/id_rsa 192.168.1.103:/home/pi/.ssh/id_rsa
scp /home/pi/.ssh/id_rsa 192.168.1.104:/home/pi/.ssh/id_rsa
scp /home/pi/.ssh/id_rsa.pub 192.168.1.102:/home/pi/.ssh/id_rsa.pub
scp /home/pi/.ssh/id_rsa.pub 192.168.1.103:/home/pi/.ssh/id_rsa.pub
scp /home/pi/.ssh/id_rsa.pub 192.168.1.104:/home/pi/.ssh/id_rsa.pub


# Auf ALLEN Raspis (inkl. Bootstrap)
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub
chmod 600 ~/.ssh/authorized_keys
