# Bunkai Documentation

This directory holds the documentation of Bunkai. Each document introduces
the concepts it depends on before using them, so the order below is also a
reading order.

## Documents

[Architecture](architecture.md) describes how Bunkai is put together: the
design the modules follow, how they are organised, the flow of a run through
them, the data that travels between them, and a reference for every component
with what it receives and what it returns.

## Elsewhere in the repository

| Topic | Where |
| --- | --- |
| What Bunkai is, installation, usage | [../README.md](../README.md) |
| Test suites and mutation testing | [../README.md](../README.md), [../tests](../tests) |
| Contribution process | [../.github/CONTRIBUTING.md](../.github/CONTRIBUTING.md) |
| Security reporting | [../SECURITY.md](../SECURITY.md) |
| License | [../LICENSE.md](../LICENSE.md) |
| Coding style | [LESIS Perl style guide](https://github.com/lesis-lat/perl-style-guide) |

## Following the code

| Question | Section |
| --- | --- |
| What happens when I run it | [Program Flow](architecture.md#program-flow) |
| How the modules are laid out | [Module Organization](architecture.md#module-organization) |
| What a component receives and returns | [Component Reference](architecture.md#component-reference) |
| What travels between the components | [Data](architecture.md#data) |
| Why a run exits the way it does | [Exit Status](architecture.md#exit-status) |

## Maintenance

The documentation is part of the code base and changes with it. A change that
adds, removes or renames a component, alters what it receives or returns, or
changes the shapes declared in the type library is not complete until this
directory reflects it. Component tables and type names are the items that
drift most easily and are checked first in review.
