# DagKnows Installation Wizard - Testing Guide

This guide provides comprehensive testing scenarios for the DagKnows installation wizard.

## 🎯 Prerequisites

### Test Environment
- **Fresh Ubuntu/Debian VM** (recommended for clean tests)
- **Minimum**: 16GB RAM, 50GB disk
- **Network**: Stable internet connection
- **Access**: sudo privileges

### Recommended Test Platforms
1. **Local VM**: VirtualBox/VMware Ubuntu 22.04
2. **Cloud VM**: AWS EC2 t3.xlarge, Azure B4ms
3. **Docker Desktop**: For basic functionality tests

### Before Each Test
```bash
# Start with a clean slate
cd ~
rm -rf dkapp
git clone https://github.com/dagknows/dkapp.git
cd dkapp
```

## 📋 Test Scenarios

---

## **Test 1: Fresh Installation (Happy Path)**

**Objective**: Verify complete installation works end-to-end

**Steps**:
```bash
1. Start fresh VM
2. cd dkapp
3. ./install.sh
4. Answer all prompts:
   - DagKnows URL: https://YOUR_VM_IP
   - Database Password: testpass123
   - Super User Email: admin@test.com
   - Names: Admin User
   - Super User Password: TestPass123! (use same for encryption)
   - Organization: testorg
   - Skip mail config (press Enter)
   - Skip OpenAI config (press Enter)
   - Encryption: TestPass123! (same password)
5. Wait for completion
```

**Expected Results**:
- ✅ All steps complete without errors
- ✅ Services start successfully
- ✅ Final message shows access URL
- ✅ Warning about running `newgrp docker` if sg was used

**Verify**:
```bash
# Check services
docker ps
# Should see: postgres, elasticsearch, nginx, req-router, etc.

# Access the application
curl -k https://localhost
# Should return HTML content

# Check logs
make logs
```

**Time**: ~10-15 minutes

---

## **Test 2: Password Recommendation Validation**

**Objective**: Verify password prompts show recommendations

**Steps**:
```bash
1. Start fresh VM
2. cd dkapp
3. ./install.sh
4. Proceed to Super User configuration
5. Observe prompts
```

**Expected Results**:
- ✅ Before password prompt, see:
  ```
  ⚠ IMPORTANT:
  Use the SAME password for both Super User and encryption.
  ```
- ✅ Prompt says: "Super User Password (will also be used for encryption)"
- ✅ At encryption step, see:
  ```
  ⚠ USE THE SAME PASSWORD as your Super User password
  ```

**Verify**:
- User is clearly informed to use same password
- Prompts are prominent and clear

**Time**: ~5 minutes (up to password entry)

---

## **Test 3: Sequential Image Pull (ECR Rate Limit Prevention)**

**Objective**: Verify images are pulled sequentially with `make pull`

**Steps**:
```bash
1. Start fresh VM (no Docker images cached)
2. cd dkapp
3. Complete installation up to service startup
4. Watch for "Pulling Docker Images" step
5. Monitor the process
```

**Expected Results**:
- ✅ After database services start, see:
  ```
  ============================================================
              Pulling Docker Images                 
  ============================================================
  
  ℹ Pulling Docker images from public ECR...
  ℹ This downloads images one by one to avoid concurrent request limits.
  ```
- ✅ Images pull one at a time (not in parallel)
- ✅ No "rate limit exceeded" errors

**Verify**:
```bash
# Watch docker pull happening
docker images | grep public.ecr.aws
# Images should appear one by one

# Check logs don't show rate limit errors
make logs | grep -i "rate limit"
# Should be empty
```

**Time**: ~5-10 minutes (image pulling)

---

## **Test 4: Docker Group Handling**

**Objective**: Verify `sg docker` is used when group isn't active

**Steps**:
```bash
1. Start fresh VM
2. cd dkapp
3. ./install.sh
4. Watch for "Docker Group Configuration" section
```

**Expected Results**:
- ✅ User is added to docker group
- ✅ Script detects group not active in session
- ✅ Messages show:
  ```
  ℹ Docker group not active in current session
  ℹ Will use 'sg docker' to run Docker commands with group permissions
  ```
- ✅ Commands use `sg docker -c 'make updb'`
- ✅ Final message reminds about `newgrp docker`

**Verify**:
```bash
# After installation
groups
# Should include 'docker'

# Try without newgrp (will fail)
docker ps
# Permission denied

# Use newgrp
newgrp docker
docker ps
# Works!
```

**Time**: ~2 minutes

---

## **Test 5: Interrupt During Configuration**

**Objective**: Verify resume after Ctrl+C during config

**Steps**:
```bash
1. Start fresh VM
2. cd dkapp
3. ./install.sh
4. When prompted for Super User password, press Ctrl+C
5. Run ./install.sh again
```

**Expected Results**:
- ✅ First run: Installation interrupted
- ✅ Second run: Starts from beginning (no partial config saved)
- ✅ Configuration starts fresh
- ✅ No corrupted state

**Verify**:
```bash
# Check no partial files exist
ls -la .env .env.gpg
# Should not exist after first Ctrl+C
```

**Time**: ~5 minutes

---

## **Test 6: Interrupt After Encryption**

**Objective**: Verify resume from service startup

**Steps**:
```bash
1. Start fresh VM
2. cd dkapp
3. ./install.sh
4. Complete all configuration and encryption
5. When "Starting Database Services" appears, press Ctrl+C
6. Run ./install.sh again
```

**Expected Results**:
- ✅ Second run detects `.env.gpg` exists
- ✅ Shows:
  ```
  ============================================================
             Existing Installation Detected                 
  ============================================================
  
  ✓ Found existing encrypted configuration (.env.gpg)
  ⚠ Services are not running
  
  Resume from starting services? (yes/no) [yes]:
  ```
- ✅ Resumes from `make updb`
- ✅ Completes successfully

**Verify**:
```bash
# After resume
docker ps
# All services should be running

make status
# All checks pass
```

**Time**: ~10 minutes

---

## **Test 7: Interrupt During Image Pull**

**Objective**: Verify resume continues pulling remaining images

**Steps**:
```bash
1. Start fresh VM
2. cd dkapp
3. ./install.sh
4. During "Pulling Docker Images", press Ctrl+C after 2-3 images
5. Run ./install.sh again
6. Choose to resume
```

**Expected Results**:
- ✅ Second run detects partial images
- ✅ Continues pulling remaining images
- ✅ Skips already-pulled images
- ✅ Completes successfully

**Verify**:
```bash
# Check which images were pulled
docker images | grep public.ecr.aws | wc -l
# Should show all 9 images eventually

# After completion, all services run
docker ps | wc -l
# Should show 12+ containers
```

**Time**: ~8 minutes

---

## **Test 8: Run on Already-Installed System**

**Objective**: Verify detection of running installation

**Steps**:
```bash
1. Complete full installation (Test 1)
2. Verify services are running
3. Run ./install.sh again
```

**Expected Results**:
- ✅ Detects running services:
  ```
  ✓ Found existing encrypted configuration (.env.gpg)
  ✓ Application services are already running!
  
  Your DagKnows installation appears to be complete.
  
  Available actions:
    1. View logs: make logs
    2. Restart services: make restart
    3. Check status: make status
    4. Reconfigure: make reconfigure
  
  Do you want to reinstall anyway? (yes/no) [no]:
  ```
- ✅ Pressing 'no' exits gracefully
- ✅ Pressing 'yes' offers to reinstall

**Verify**:
```bash
# System remains stable after check
docker ps
# All services still running

make status
# All checks still pass
```

**Time**: ~2 minutes

---

## **Test 9: Reconfigure Existing Installation**

**Objective**: Verify configuration backup and reconfiguration

**Steps**:
```bash
1. Complete full installation
2. Run ./install.sh again
3. Choose to reinstall (yes)
4. At configuration step, choose to reconfigure (yes)
5. Enter different values
```

**Expected Results**:
- ✅ Shows:
  ```
  ⚠ Existing configuration detected.
  Do you want to reconfigure? (yes/no) [no]: yes
  
  ℹ Backed up existing config to .env.gpg.backup.1234567890
  ```
- ✅ Backup file created
- ✅ New configuration accepted
- ✅ Services restart with new config

**Verify**:
```bash
# Check backup exists
ls -la .env.gpg.backup.*
# Should show timestamped backup

# Old config preserved
gpg -o .env.old -d .env.gpg.backup.*
grep SUPER_USER .env.old
# Shows old values
```

**Time**: ~15 minutes

---

## **Test 10: Idempotency - Run Twice Back-to-Back**

**Objective**: Verify running installer twice is safe

**Steps**:
```bash
1. Complete full installation
2. Immediately run ./install.sh again (choose 'no' to reinstall)
3. Run ./install.sh again (choose 'yes' to reinstall)
4. Complete full reinstall
```

**Expected Results**:
- ✅ First rerun: Gracefully exits
- ✅ Second rerun: Completes successfully
- ✅ System remains stable
- ✅ Services continue running
- ✅ No duplicate containers

**Verify**:
```bash
# No duplicate containers
docker ps --format "{{.Names}}" | sort | uniq -d
# Should be empty

# Services healthy
make status
# All pass
```

**Time**: ~20 minutes

---

## **Test 11: System Updates Skip (Recent Update)**

**Objective**: Verify skip of recent system updates

**Steps**:
```bash
1. Manually run: sudo apt update && sudo apt upgrade -y
2. Wait 5 minutes
3. Run ./install.sh
4. Observe system update step
```

**Expected Results**:
- ✅ Shows:
  ```
  ============================================================
              Updating System Packages                 
  ============================================================
  
  ✓ System packages recently updated (skipping)
  ```
- ✅ Proceeds to next step immediately

**Time**: ~3 minutes

---

## **Test 12: Docker Already Installed**

**Objective**: Verify skip of Docker installation if present

**Steps**:
```bash
1. Manually install Docker:
   sudo apt-get install -y docker.io docker-compose
2. Add user to docker group:
   sudo usermod -aG docker $USER
3. Run ./install.sh
4. Observe Docker preparation step
```

**Expected Results**:
- ✅ Shows:
  ```
  ============================================================
           Preparing Docker Environment                 
  ============================================================
  
  ✓ Docker and docker-compose already installed
  ```
- ✅ Still ensures user is in docker group
- ✅ Proceeds quickly

**Time**: ~5 minutes

---

## **Test 13: Wrong Password Confirmation**

**Objective**: Verify password mismatch handling

**Steps**:
```bash
1. Start fresh VM
2. cd dkapp
3. ./install.sh
4. At Super User Password, enter: TestPass123!
5. At Confirm Password, enter: DifferentPass!
```

**Expected Results**:
- ✅ Shows error:
  ```
  ✗ Passwords do not match!
  ```
- ✅ Restarts configuration from beginning
- ✅ Doesn't save bad config

**Time**: ~5 minutes

---

## **Test 14: Network Interruption Recovery**

**Objective**: Verify recovery from network issues

**Steps**:
```bash
1. Start installation
2. During image pull, disable network:
   sudo ifconfig eth0 down
3. Wait for failure
4. Re-enable network:
   sudo ifconfig eth0 up
5. Run ./install.sh again
```

**Expected Results**:
- ✅ First run: Fails with network error
- ✅ Second run: Resumes and completes
- ✅ Pulls remaining images
- ✅ Services start successfully

**Time**: ~15 minutes

---

## **Test 15: Insufficient Permissions**

**Objective**: Verify handling of permission issues

**Steps**:
```bash
1. Run as non-sudo user without docker group
2. cd dkapp
3. ./install.sh
4. Observe behavior
```

**Expected Results**:
- ✅ System update prompts for sudo password
- ✅ Docker installation prompts for sudo password
- ✅ User added to docker group
- ✅ Uses `sg docker` for docker commands
- ✅ Completes successfully

**Time**: ~12 minutes

---

## 🔍 **Quick Verification Commands**

After any test, use these to verify:

```bash
# Check all services running
docker ps

# Check service health
make status

# View logs
make logs

# Test application access
curl -k https://localhost

# Check docker group
groups | grep docker

# Check configuration
ls -la .env.gpg

# Verify backups (if reconfigured)
ls -la .env.gpg.backup.*
```

---

## 📊 **Test Matrix**

| Test | Duration | Critical | Scenario |
|------|----------|----------|----------|
| 1. Fresh Install | 10-15 min | ✅ Yes | Happy path |
| 2. Password Prompts | 5 min | ✅ Yes | UX validation |
| 3. Sequential Pull | 5-10 min | ✅ Yes | ECR rate limits |
| 4. Docker Group | 2 min | ✅ Yes | Permission handling |
| 5. Interrupt Config | 5 min | ✅ Yes | Resume capability |
| 6. Interrupt After Encrypt | 10 min | ✅ Yes | Resume capability |
| 7. Interrupt Image Pull | 8 min | ⚠️ Medium | Resume capability |
| 8. Already Installed | 2 min | ✅ Yes | Detection logic |
| 9. Reconfigure | 15 min | ⚠️ Medium | Backup safety |
| 10. Idempotency | 20 min | ✅ Yes | Safety |
| 11. Skip Updates | 3 min | ⚠️ Medium | Optimization |
| 12. Docker Present | 5 min | ⚠️ Medium | Detection |
| 13. Password Mismatch | 5 min | ✅ Yes | Error handling |
| 14. Network Issues | 15 min | ⚠️ Medium | Recovery |
| 15. Permissions | 12 min | ✅ Yes | Security |

**Total Testing Time**: ~2-3 hours for all tests

---

## 🎯 **Minimum Test Set (Quick Validation)**

If time is limited, run these critical tests:

1. **Test 1** - Fresh Install (happy path)
2. **Test 2** - Password Prompts (UX)
3. **Test 3** - Sequential Pull (rate limits)
4. **Test 4** - Docker Group (permissions)
5. **Test 6** - Interrupt After Encrypt (resume)
6. **Test 8** - Already Installed (detection)

**Time**: ~45 minutes

---

## 🐛 **Common Issues and Solutions**

### Issue: "Permission denied" on docker commands
**Solution**: Run `newgrp docker` or logout/login

### Issue: Image pull fails
**Solution**: Check internet, try `make pull` manually

### Issue: Services don't start
**Solution**: Check logs with `make dblogs` and `make logs`

### Issue: Configuration lost
**Solution**: Check for `.env.gpg.backup.*` files

### Issue: Port already in use
**Solution**: Check `sudo lsof -i :80` and `sudo lsof -i :443`

---

## 📝 **Test Results Template**

Use this to document your test results:

```markdown
## Test Results - [Date]

### Environment
- OS: Ubuntu 22.04
- RAM: 16GB
- Platform: AWS EC2 t3.xlarge

### Test 1: Fresh Installation
- Status: ✅ Pass / ❌ Fail
- Duration: 12 minutes
- Notes: Completed successfully, all services running
- Issues: None

### Test 2: Password Prompts
- Status: ✅ Pass / ❌ Fail
- Duration: 5 minutes
- Notes: Prompts clear and prominent
- Issues: None

[... continue for all tests ...]

### Summary
- Total Tests: 15
- Passed: 14
- Failed: 1
- Critical Issues: 0
```

---

## 🚀 **Automated Testing Script**

For convenience, here's a test runner:

```bash
#!/bin/bash
# test-runner.sh

echo "DagKnows Installation Test Runner"
echo "=================================="

# Test 1: Fresh Install
echo "Test 1: Fresh Installation"
cd ~/dkapp
./install.sh <<EOF
yes
https://test.local
testpass
admin@test.com
Admin
User
TestPass123!
TestPass123!
testorg



TestPass123!
TestPass123!
EOF

# Verify
if docker ps | grep -q nginx; then
    echo "✅ Test 1 PASSED"
else
    echo "❌ Test 1 FAILED"
fi

# Add more tests...
```

---

## 📚 **Additional Resources**

- `RESUME_CAPABILITY.md` - Detailed resume logic
- `QUICKSTART.md` - User guide
- `README.md` - Full documentation
- `make help` - Available commands

---

**Happy Testing! 🎉**

If you find any issues, please report them with:
- Test scenario number
- Error messages
- System details
- Steps to reproduce

