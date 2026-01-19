requires 'Getopt::Long',           '2.58';
requires 'Path::Tiny',             '0.150';
requires 'Const::Fast',            '0.014';
requires 'CPAN::Audit',            '20250115.001';
requires 'JSON::PP',               '4.16';
requires 'Module::CPANfile',       '1.1004';
requires 'MetaCPAN::Client',       '2.033000';

on 'test' => sub {
    requires 'Perl::Critic',        '1.140';
    requires 'Devel::Cover',        '1.36';
    requires 'File::Temp',          '0.2312';
    requires 'Test::More',          '1.302214';
    requires 'Test::MockModule',    '0.180.0';
    requires 'Test::Exception',     '0.43';
    requires 'Test::Fatal',         '0.017';
};
