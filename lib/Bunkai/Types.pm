package Bunkai::Types;

use 5.034;
use strict;
use warnings;

use Type::Library -base, -declare => qw(
  ModuleName
  VersionValue
  AdvisoryId
  IssueReason
  Vulnerability
  VulnerabilityList
  Dependency
  DependencyList
  PlannedIssue
  PlannedIssueList
  CpanfileUpdate
  CpanfileUpdateList
  ParserResult
  FlowResult
);

use Type::Utils -all;
use Types::Standard qw(ArrayRef Bool Dict Enum Int Optional Str Undef);

our $VERSION = '0.0.4';

declare ModuleName, as Str, where { length };

declare VersionValue, as Str | Undef;

declare AdvisoryId, as Str | Undef;

declare IssueReason,
  as Enum ['missing_version', 'outdated', 'vulnerability_fix'];

declare Vulnerability,
  as Dict [
    type          => Optional [Enum ['vulnerability', 'error']],
    cve_id        => Optional [AdvisoryId],
    description   => Optional [Str | Undef],
    fixed_version => Optional [VersionValue],
  ];

declare VulnerabilityList, as ArrayRef [Vulnerability];

declare Dependency,
  as Dict [
    module              => ModuleName,
    version             => Optional [VersionValue],
    has_version         => Optional [Bool],
    latest_version      => Optional [VersionValue],
    is_outdated         => Optional [Bool],
    vulnerabilities     => Optional [VulnerabilityList],
    has_vulnerabilities => Optional [Bool],
  ];

declare DependencyList, as ArrayRef [Dependency];

declare PlannedIssue,
  as Dict [
    id              => Str,
    module          => ModuleName,
    current_version => VersionValue,
    target_version  => Str,
    reason          => IssueReason,
    advisory_id     => AdvisoryId,
  ];

declare PlannedIssueList, as ArrayRef [PlannedIssue];

declare CpanfileUpdate,
  as Dict [
    module  => ModuleName,
    version => Str,
    reason  => Optional [IssueReason],
  ];

declare CpanfileUpdateList, as ArrayRef [CpanfileUpdate];

declare ParserResult,
  as Dict [
    success       => Bool,
    data          => DependencyList,
    cpanfile_path => Str,
    reason        => Optional [Str],
    error         => Optional [Str],
  ];

declare FlowResult,
  as Dict [
    success   => Bool,
    exit_code => Optional [Int],
    message   => Optional [Str],
  ];

__PACKAGE__ -> meta -> make_immutable;

1;
