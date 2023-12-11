# dkapp
On prem version of the SaaS DagKnows app

## Requirements

### Instance
* 16 GB Memory
* 50 GB Storage

### Packages

```
apt-get update
apt-get install -y make docker.io docker-compose unzip python-pip3
```

## Instructions

1. Checkout this repo

```
git clone https://github.com/dagknows/dkapp.git
```

2. Start the app

```
make updb up logs
```

