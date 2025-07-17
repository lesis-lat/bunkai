<p align="center">
  <h3 align="center"><b>Bunkai (分解)</b></h3>
  <p align="center">A minimalist, dependency-aware Software Composition Analysis (SCA) tool for Perl.</p>
  <p align="center">
    <a href="https://github.com/lesis-lat/bunkai/blob/main/LICENSE.md">
      <img src="https://img.shields.io/badge/license-MIT-blue.svg">
    </a>
     <a href="https://github.com/lesis-lat/bunkai/releases">
      <img src="https://img.shields.io/badge/version-0.0.3-blue.svg">
    </a>
  </p>
</p>

---

### Summary

Bunkai (分解, "analysis/to break down") is a simple, deterministic Software Composition Analysis (SCA) tool for Perl projects. It operates entirely by parsing a project's `cpanfile` to identify dependencies and their specified versions.

Designed with the principles of Flow-Based Programming, Bunkai is a single-purpose component that does one thing well: analyze your dependency manifest. It identifies all modules and warns when version specifications are missing—a common source of build instability and potential supply chain risks.

---

### Prerequisites

-   Perl 5.034+
-   `cpanm` (to install dependencies)

---

### Installation

```bash
# Clone the repository
git clone https://github.com/lesis-lat/bunkai.git && cd bunkai

# Install dependencies
cpanm --installdeps .
```

---

### Usage

Bunkai is a command-line tool that accepts the path to your project directory.

```bash
$ perl bunkai.pl --path /path/to/project
```
```bash
$ perl bunkai.pl --help

Bunkai v0.0.3
SCA for Perl Projects
=====================
    Command          Description
    -------          -----------
    -p, --path       Path to the project containing a cpanfile
    -h, --help       Display this help menu
```

### Example

Given a project directory with the following `cpanfile`:

```perl
requires "CryptX",                          "0.086";
requires "Net::CIDR::Set",                  "0.13";
```

Running Bunkai will produce the following output:

```bash
$ perl bunkai.pl --path ./path/to/project

CryptX                                   0.086
WARNING: Module 'CryptX' is outdated. Specified: 0.086, Latest: 0.087
SUGGEST: Upgrade to version 0.087 or later.
SECURITY: Module 'CryptX' has vulnerability CVE-2023-36328:
CryptX (requires 0.086) has 1 advisory
  * CPANSA-CryptX-2025-40914
    Perl CryptX before version 0.087 contains a dependency that may be susceptible to an integer overflow.  CryptX embeds a version of the libtommath library that is susceptible to an integer overflow associated with CVE-2023-36328.
    Affected range: <0.087
    Fixed range:    >=0.087

    CVEs: CVE-2025-40914, CVE-2023-36328

    References:
    https://github.com/advisories/GHSA-j3xv-6967-cv88
    https://github.com/libtom/libtommath/pull/546
    https://metacpan.org/release/MIK/CryptX-0.086/source/src/ltm/bn_mp_grow.c
    https://www.cve.org/CVERecord?id=CVE-2023-36328


Net::CIDR::Set                           0.13
WARNING: Module 'Net::CIDR::Set' is outdated. Specified: 0.13, Latest: 0.16
SUGGEST: Upgrade to version 0.16 or later.
SECURITY: Module 'Net::CIDR::Set' has vulnerability CVE-2021-47154:
Net-CIDR-Set (requires 0.13) has 1 advisory
  * CPANSA-Net-CIDR-Set-2025-40911
    Net::CIDR::Set versions 0.10 through 0.13 for Perl does not properly handle leading zero characters in IP CIDR address strings, which could allow attackers to bypass access control that is based on IP addresses.  Leading zeros are used to indicate octal numbers, which can confuse users who are intentionally using octal notation, as well as users who believe they are using decimal notation.  Net::CIDR::Set used code from Net::CIDR::Lite, which had a similar vulnerability CVE-2021-47154.
    Affected range: >=0.10,<=0.13
    Fixed range:    >=0.14

    CVEs: CVE-2025-40911

    References:
    https://blog.urth.org/2021/03/29/security-issues-in-perl-ip-address-distros/
    https://github.com/robrwo/perl-Net-CIDR-Set/commit/be7d91e8446ad8013b08b4be313d666dab003a8a.patch
    https://metacpan.org/release/RRWO/Net-CIDR-Set-0.14/changes
```

The tool will exit with a non-zero status code if any warnings are issued.

---

### Contribution

Your contributions and suggestions are heartily ♥ welcome. Please, report bugs via the project's issues page and see the security policy for vulnerability disclosures. (✿ ◕‿◕)

---

### License

This work is licensed under the [MIT License](/LICENSE.md).
