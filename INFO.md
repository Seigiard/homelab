# NAS

## Equipment

HP ProDesk 600 G3 SFF:
[h10032.www1.hp.com/ctg/Manual/c05387853.pdf](https://h10032.www1.hp.com/ctg/Manual/c05387853.pdf)

- Intel Quad-Core i5-6400 CPU @ 2.70GHz
- RAM 16 GB DDR4 (+ empty 2 slots)
- SSD Crucial 256 GB
- Intel HD Graphics 530
- PCI Express x16 + PCI Express x4 sloty

### Future upgrades

скорее всего, 6pin проприоритарный, надо исследовать

[What kind of 6 pin connector is this on my HP ProDesk 600? : r/computer](https://www.reddit.com/r/computer/comments/1k20v94/what_kind_of_6_pin_connector_is_this_on_my_hp/)

> It will be a proprietary HP connector, you'll need to find one specific to that model
>
> Well, its a Molex connector. I did a quick search and it seems this might be the cable you're looking for a "m2-l20611" cable.
>
> Thank you very much! I just bought this cable from eBay using the part number you found. Turns out the port is HP proprietary and is called “P160” but this is not mentioned in HPs documentation.

TODO: Поставить m2ssd + один диск и не морочить голову питанием на данный момент

## Tasks

## Этап 1

Install Ubuntu Server

### setup SSH

```sh
sudo apt update
sudo apt install openssh-server

sudo systemctl start ssh
sudo systemctl enable ssh

# проверка статуса
sudo systemctl status ssh

```

### Setup local domain

```sh
sudo apt install avahi-daemon avahi-utils
sudo nano /etc/avahi/avahi-daemon.conf
# [server]
# host-name=home
# domain-name=local
# use-ipv4=yes
# use-ipv6=yes

# [publish]
# publish-addresses=yes
# publish-hinfo=yes
# publish-workstation=yes
# publish-domain=yes

sudo systemctl restart avahi-daemon
sudo systemctl enable avahi-daemon
```

### Setup bash and apps

```sh
sudo apt install zellij micro mc
# TODO: github repo with all setups
```

### Setup dockers

**Install Docker**

[Ubuntu \| Docker Docs](https://docs.docker.com/engine/install/ubuntu/)

**Create folders**
