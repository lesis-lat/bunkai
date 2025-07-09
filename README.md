<p align="center">
  <h3 align="center"><b>Bunkai (分解)</b></h3>
  <p align="center">A minimalist, dependency-aware Software Composition Analysis (SCA) tool for Perl.</p>
  <p align="center">
    <a href="https://github.com/lesis-lat/bunkai/blob/main/LICENSE.md">
      <img src="https://img.shields.io/badge/license-MIT-blue.svg">
    </a>
     <a href="https://github.com/lesis-lat/bunkai/releases">
      <img src="https://img.shields.io/badge/version-0.0.1-blue.svg">
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

Bunkai v0.0.2
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
requires "Mojo::UserAgent";
requires "YAML::Tiny", "1.73";
requires "Find::Lib", "1.04";
requires "JSON", "4.07";
```

Running Bunkai will produce the following output:

```bash
$ perl bunkai.pl --path ./path/to/project

Find::Lib                                1.04
JSON                                     4.07
Warning: Module 'Mojo::UserAgent' has no version specified.
YAML::Tiny                               1.73
```

The tool will exit with a non-zero status code if any warnings are issued.

---

### Contribution

Your contributions and suggestions are heartily ♥ welcome. Please, report bugs via the project's issues page and see the security policy for vulnerability disclosures. (✿ ◕‿◕)

---

### License

This work is licensed under the [MIT License](/LICENSE.md).