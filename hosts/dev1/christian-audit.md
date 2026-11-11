# Christian command auditing

Enabled 2026-11-11 at approximately 19:03 AEST for local account `christian`,
UID 1001. The account has key-only SSH access and passwordless sudo.

Install and load the managed rules:

```sh
sudo apt-get install -y auditd
sudo install -o root -g root -m 600 ~/dotfiles/hosts/dev1/christian-audit.rules /etc/audit/rules.d/50-christian.rules
sudo augenrules --load
sudo systemctl enable --now auditd.service
sudo systemctl enable audit-rules.service
sudo auditctl -l
sudo auditctl -s
```

The rules cover `execve` and `execveat` on x86-64 and i386, retaining the SSH
login identity through sudo or su. A second pair covers processes running as
Christian without his login UID. Update the numeric UID if the account is
recreated. PAM's existing `pam_loginuid.so` sets the identity at SSH login.

Review commands with `sudo ausearch -k christian_exec -ts recent -i` or
`sudo ausearch -k christian_exec -ts today -i`. Records include timestamps,
arguments, working directory, session ID, and real/effective user IDs.
Logs are in `/var/log/audit/audit.log`. The package's default rotation is
five files of up to 8 MiB each. SSH and sudo authentication logs remain in
the system journal.

This records program execution, not a terminal transcript. Interactive shell
builtins and operations performed inside a running program are not individually
recorded. Full sudo access also allows changing local audit configuration.
Arguments may contain secrets; redact them in activity summaries.

Verification at 19:03:40 AEST used a temporary, loopback-only SSH key and ran
`id` and `sudo -n id`. Audit session 39 is administrator verification, including
PAM/MOTD commands, not Christian's activity. The temporary key was removed.
A separate public-key offer check verified the supplied key was accepted;
its expected failure to sign without the private key is also administrator testing.
