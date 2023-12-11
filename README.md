# dkapp
On prem version of the SaaS DagKnows app

## Instructions

1. Requirements

Install docker:

```
apt-get update
apt-get install -y docker.io docker-compose
```

2. Checkout this repo

```
git checkout https://github.com/dagknows/dkapp.git
```

2. Start the app

```
make updb up logs
```

