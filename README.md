# MDE Agent Lab

A repeatable Windows x64 installer for testing visibility of local AI coding tools in Microsoft Defender for Endpoint (MDE).

**Installing an agent is not proof that Defender has detected, inventoried, or classified it.** This project installs the tools, checks that their CLI launchers work, and reports local MDE sensor state. Validate cloud telemetry separately.

## What gets installed

| Component | Installation method | Purpose |
| --- | --- | --- |
| Claude Code | Official npm package `@anthropic-ai/claude-code` | Local AI coding CLI |
| Codex CLI | Official npm package `@openai/codex` | Local AI coding CLI |
| GitHub Copilot CLI | Official npm package `@github/copilot` | Local AI coding CLI |
| GitHub CLI (`gh`) | Official GitHub release MSI | GitHub command-line client; not itself an AI agent |
| PowerShell 7 | Official PowerShell release MSI | Shell prerequisite |
| Node.js | Official Node.js LTS MSI | npm and CLI runtime support |
| Microsoft Copilot on Windows | Microsoft Store via WinGet | Optional desktop app, distinct from GitHub Copilot CLI |

The script does not install VS Code, Claude Desktop, Git for Windows, WSL, MDE, or an Entra agent identity. It does not create accounts, configure API keys, sign in, submit model prompts, run attack simulations, or change Defender protection settings.

## Requirements

- Windows x64 and a 64-bit PowerShell session. Windows 11 is the tested OS; ARM64 and 32-bit systems are rejected.
- Administrator rights for the machine-wide installations. Launch PowerShell using **Run as administrator**; the script does not elevate itself.
- Internet access to GitHub release/API/download endpoints, `nodejs.org`, and `registry.npmjs.org` and their download dependencies.
- For the desktop app: Windows App Installer (`winget`), Microsoft Store access, and a signed-in user session. Store policy and regional availability still apply.
- For MDE tests: an already-onboarded device, healthy sensor, appropriate Defender licensing, and permission to view the device and advanced hunting data.
- For actual AI-agent use: suitable provider account, subscription or API entitlement, organization approval, and access to the provider's service endpoints. Installation does not grant service access.

Use an isolated lab with synthetic data. Azure Government hosting does not make these commercial AI services Government-authorized. Confirm your organization's data-handling and egress requirements before signing in or sending prompts.

## Get the installer

Repository: <https://github.com/Cyberlorians/mde-agent-lab>

Download the repository through GitHub's **Code > Download ZIP**, extract it, and review [Install-AgentLab.ps1](Install-AgentLab.ps1). Private repositories require authorized GitHub access. No personal access token needs to be embedded in the script.

If GitHub CLI and Git are already installed, you can instead use:

```powershell
gh repo clone Cyberlorians/mde-agent-lab
Set-Location .\mde-agent-lab
```

`gh repo clone` requires Git, which this installer does not install. ZIP download avoids that dependency.

## Install

Open 64-bit PowerShell **as administrator**, change to the extracted repository folder, and run one of these commands.

### All components, including the desktop app

Run this in the interactive user session that should receive the Copilot app:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-AgentLab.ps1
```

The Store install accepts the source and package agreements. Review the applicable terms before running. If elevation uses a different Windows account, the app registration is for that account rather than the original desktop user.

### CLI tools only

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-AgentLab.ps1 -SkipCopilotApp
```

Use `-SkipCopilotApp` for SYSTEM-based deployment, including Azure VM Run Command. SYSTEM cannot perform this user-scoped Store installation. The script rejects a SYSTEM run without the switch before installing anything.

The `ExecutionPolicy` argument applies only to the launched PowerShell process. It does not persist a policy change, override organizational Group Policy, or bypass App Control. Use your organization's approved signing/distribution method where required.

## What the script changes

1. Validates Windows x64, administrator rights, and Store installation context.
2. Creates `%ProgramData%\AgentLabInstall` for downloaded installers and MSI logs.
3. Installs PowerShell 7 if its standard executable is absent. Validates the MSI's Microsoft Authenticode signature.
4. Installs a current Node.js LTS version if the standard installation is missing or older than major version 22. Validates the MSI's OpenJS/Node.js Foundation signature.
5. Installs GitHub CLI if its standard executable is absent. Verifies the MSI SHA-256 against the digest published by the official `cli/cli` release API. A release digest check is not an independent build-attestation verification.
6. Installs or updates the three official npm packages into `%ProgramFiles%\AgentCLIs`, explicitly allowing Claude Code's package installation script. npm retrieves package dependencies; this is not an offline bundle.
7. Adds the CLI, GitHub CLI, Node.js, and PowerShell directories to the machine `PATH` without duplicating matching entries.
8. Executes version checks and reads the `Sense` service and local MDE onboarding state. It warns, but does not onboard or repair MDE, if those checks fail.
9. Unless skipped, installs the Copilot Store app for the current user and verifies its package registration.

MSI installs are quiet and do not automatically reboot. Exit code 3010 produces a reboot warning. The script stops at errors and does not roll back earlier successful installations. In particular, a Store failure can leave all CLI installations working.

## Reruns and versioning

This is a repeatable workflow, **not a version-pinned or offline deployment**. Every run requests `@latest` for the three npm packages and can update them. Existing standard PowerShell 7 and GitHub CLI installations are reused, not automatically upgraded. Existing Node.js major version 22 or newer is reused. Nonstandard installations may not be recognized.

The npm script-approval option was validated with npm 11.19.0; behavior on other npm versions may differ. Review warnings and verify all CLI versions after running.

For strict reproducibility, pin and review package versions and installer hashes before rollout. Do not treat this lab script as an enterprise patch-management solution.

## Verify and launch

After installation, close the elevated installation window and open a **new normal-user terminal**. Existing terminals may have an old `PATH`. If a new window still inherits an old environment, sign out and back in or use full paths.

```powershell
claude.cmd --version
codex.cmd --version
copilot.cmd --version
gh --version
pwsh --version
node --version
```

Explicit `.cmd` launchers avoid PowerShell choosing npm's `.ps1` wrappers where script execution policy blocks those wrappers. A full-path check also works:

```powershell
& "$env:ProgramFiles\AgentCLIs\claude.cmd" --version
& "$env:ProgramFiles\AgentCLIs\codex.cmd" --version
& "$env:ProgramFiles\AgentCLIs\copilot.cmd" --version
& "$env:ProgramFiles\GitHub CLI\gh.exe" --version
```

The npm-installed CLI agents normally have **no Apps & Features entry**. Their absence there does not mean they are missing. Check the launchers and npm inventory:

```powershell
& "$env:ProgramFiles\nodejs\npm.cmd" list --global --depth=0 --prefix "$env:ProgramFiles\AgentCLIs"
Get-AppxPackage -Name Microsoft.Copilot | Select-Object Name, Version
```

### Sign in as the intended user

Launch one tool at a time from a synthetic-data folder in a normal-user terminal:

- `claude.cmd`: follow the Claude Code sign-in prompts.
- `codex.cmd`: follow the available Codex sign-in prompts.
- `copilot.cmd`: use `/login` when prompted for GitHub authentication.
- `gh auth login`: authenticate GitHub CLI separately as needed.
- Microsoft Copilot desktop app: launch it from Start and follow the app's sign-in flow.

Do not put credentials into the installer, repository, command-line arguments, or shared screenshots. Do not run interactive agents as SYSTEM or administrator just because installation required elevation.

## MDE validation procedure

### 1. Establish the baseline

In the Defender portal, locate the device and check its latest reporting time and sensor health. Record the device name and a UTC test start time. Local `Sense=Running` and onboarding state `1` are useful prerequisites, not proof that cloud telemetry is arriving.

### 2. Test execution visibility without sign-in

Run the version commands above in your normal-user session and record the time. Look in the device timeline or `DeviceProcessEvents` in advanced hunting for that device and time window.

Inspect file paths and command lines as well as process names. npm shims can launch `cmd.exe`, `node.exe`, or platform-specific native binaries. Do not assume a wrapper named `claude.cmd` must appear as the actual process image. Review the parent/child process tree to attribute execution.

Remote installation/version checks will show an Azure Run Command/SYSTEM context. A later RDP-user launch is a separate test and should not be confused with that baseline.

### 3. Test real agent activity

After signing into one agent, use a new lab folder containing no secrets. Keep default approval controls enabled. A suitable prompt is:

> In this test folder only, create a text file named agent-telemetry-test.txt containing MDE-AGENT-LAB and the current UTC time. Then run a command to display the file. Do not access other folders, install software, or change system settings. Ask before executing commands.

Repeat separately for each coding CLI and record the agent, user, directory, time, and approved actions. In Defender, examine `DeviceProcessEvents`, `DeviceFileEvents`, and `DeviceNetworkEvents`. Correlate process identifiers and creation times within the same device, not merely executable names.

The consumer Copilot desktop app is a different product and may not support the same local command/file actions. Test its launch and a benign synthetic-data interaction separately. Do not count manually executed shell commands as agent-generated actions.

### 4. Record distinct outcomes

| Evidence | What it establishes | What it does not establish |
| --- | --- | --- |
| Successful version command | CLI is installed and executable | MDE received the event |
| Process event in Defender | Endpoint execution telemetry arrived | Full prompt capture or AI-agent classification |
| Correlated file/network events | Those observed actions can be associated with a process | Every file read, TLS payload, prompt, or response was captured |
| Software inventory entry | Defender recognizes an installed product | Complete npm inventory or proof the agent ran |
| AI-specific inventory/classification | That feature identified the tool in that tenant | Automatic Entra Agent ID registration |

Allow for ingestion and inventory delays. Inspect a broad device/time window before narrowing filters. If normal process events arrive but no AI inventory entry appears, record those as different results. AI-specific capabilities, supported products, licensing, and Government-cloud availability must be verified for the target tenant. Benign installation is not expected to guarantee an alert.

## Validation performed

On a Windows 11 x64 lab device, the CLI-only installer completed and these version checks passed:

| Tool | Verified version |
| --- | --- |
| Claude Code | 2.1.280 |
| Codex CLI | 0.156.1 |
| GitHub Copilot CLI | 1.0.88 |
| GitHub CLI | 2.101.0 |
| PowerShell | 7.6.6 |
| Node.js | 24.21.0 |

The MDE sensor remained running and locally onboarded. The interactive Copilot Store installation, provider sign-ins, actual agent tasks, and Defender-side telemetry/classification were **not validated as part of that installer test**. These version numbers document an observed run, not pinned defaults.

CI checks Windows PowerShell 5.1 and PowerShell 7 syntax only; it does not install software or exercise Store/authentication/Defender flows.

## Troubleshooting

- **Command not found:** refresh the terminal environment or use the full paths shown above.
- **No Apps & Features entry:** use CLI version checks and `npm list`; npm packages do not have normal MSI uninstall registrations.
- **Store error:** verify App Installer, Store access, current user, region, and policy. Rerun with `-SkipCopilotApp` if only CLI tools are needed. Do not weaken security policy to force installation.
- **MSI error:** inspect `%ProgramData%\AgentLabInstall\*.msi.log`. A required reboot is reported but not performed.
- **Signature/checksum mismatch:** stop and investigate the download and official release. Do not remove integrity checks.
- **GitHub API rate limit or network failure:** verify approved egress and retry later. The script uses unauthenticated public release queries.
- **MDE warning or no telemetry:** verify device onboarding, sensor connectivity, tenant permissions, and reporting freshness separately. The installer does not resolve those conditions.
- **Read-only Program Files update error:** rerun the installer as administrator for CLI updates; do not grant ordinary users write access to the shared executable directory.

## Uninstall

In an elevated PowerShell session, remove the three CLI packages from this installer's prefix:

```powershell
& "$env:ProgramFiles\nodejs\npm.cmd" uninstall --global --prefix "$env:ProgramFiles\AgentCLIs" @anthropic-ai/claude-code @openai/codex @github/copilot
```

Uninstall GitHub CLI, Node.js, and PowerShell through Windows Installed Apps only if other workloads do not need them. Remove Microsoft Copilot through Installed Apps in its user session. Review and remove only unused PATH entries and leftover installer files created by this project. Provider tokens and per-user configuration are not necessarily deleted by package uninstall; use each provider's sign-out/revocation procedure before retiring the VM. Do not remove MDE.

## Official references

- [Claude Code setup](https://code.claude.com/docs/en/setup)
- [Codex CLI](https://developers.openai.com/codex/cli)
- [GitHub Copilot CLI](https://github.com/github/copilot-cli)
- [GitHub CLI installation](https://github.com/cli/cli#installation)
- [Microsoft Copilot Store listing](https://apps.microsoft.com/detail/9nht9rb2f4hd)
- [MDE process events](https://learn.microsoft.com/defender-xdr/advanced-hunting-deviceprocessevents-table)
- [MDE file events](https://learn.microsoft.com/defender-xdr/advanced-hunting-devicefileevents-table)
- [MDE network events](https://learn.microsoft.com/defender-xdr/advanced-hunting-devicenetworkevents-table)