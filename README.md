# Remote Linux Reinstaller

**An experimental remote Linux reinstall project for SSH-accessible machines.**

This repository is moving toward a simple app that can reinstall Linux remotely, but it is **not yet a production-ready one-command reinstall tool**.

## Current State

As of 2026-05-03, the repository contains:

- a shell-based installer entry point in `install.sh`
- distro-specific installers for Ubuntu, Debian, Proxmox, Fedora, Rocky Linux, Arch, and Alpine
- a separate RAM-based second-stage installer intended for single-disk or boot-disk workflows

What is **not yet established by the repository itself**:

- a verified fully automated reinstall flow for single-disk remote hosts
- evidence that the RAM-based handoff completes without manual recovery work
- end-to-end hardware validation across the advertised distributions

The current codebase should be treated as a **prototype**. For now, the safest use is code review and disposable VM testing, especially with a second disk attached.

## Project Goal

The long-term goal is a simple remote installation app that:

- preserves network reachability while replacing the target OS
- supports a small set of practical Linux targets first
- handles bootloader, disk partitioning, and SSH bootstrap safely
- makes single-disk reinstall workflows recoverable and understandable

## Known Gaps

The main blocker right now is the remote reinstall handoff for machines where the target disk is also the current boot disk.

In the current repository state:

- the README previously described a fully automated flow more confidently than the code supports
- the RAM-based path is clearly still under construction
- issue [#1](https://github.com/zarigata/remote-reinstall/issues/1) already tracks that the RAM install path does not yet work as intended

That means this project should not yet be presented as a finished replacement for rescue-media or out-of-band reinstall methods.

## Safe Testing Guidance

If you want to experiment with the current scripts, prefer this order:

1. Test in a disposable VM.
2. Use a second disk instead of the currently booted disk.
3. Keep console or rescue access available outside SSH.
4. Assume you may need manual recovery.

## Repository Layout

```text
remote-reinstall/
├── install.sh
├── ram-installer.sh
├── lib/
│   ├── common.sh
│   ├── network.sh
│   └── partition.sh
├── distros/
│   ├── ubuntu.sh
│   ├── debian.sh
│   ├── proxmox.sh
│   ├── fedora.sh
│   ├── rocky.sh
│   ├── arch.sh
│   └── alpine.sh
└── README.md
```

## Practical Next Steps

The highest-value next milestones appear to be:

1. make the RAM-based handoff reproducible and self-contained
2. document the expected control flow for first-stage and second-stage installs
3. reduce the supported workflow to the smallest path that can be validated end to end
4. add repeatable VM-based validation notes before broadening claims again

## Contributing

Contributions are welcome, especially around:

- clarifying the remote reinstall control flow
- making the single-disk/RAM path concrete and testable
- tightening distro-specific installers where behavior is already clear
- documenting validation steps and recovery expectations

## License

MIT License. See [LICENSE](LICENSE).
