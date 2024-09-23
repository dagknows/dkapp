# dkapp
On prem version of the SaaS DagKnows app

## Requirements

* 16 GB Memory
* 50 GB Storage

## Instructions

1. Checkout this repo

```
git clone https://github.com/dagknows/dkapp.git
```

2. Prepare Instance

Ubuntu:

```
cd dkapp
sudo apt update && sudo apt upgrade -y
sudo apt-get install -y make
make prepare
```

3. Ensure Docker is Started

Ubuntu:

```
sudo systemctl restart docker
```

4. Start the app

```
sudo make restart
```
