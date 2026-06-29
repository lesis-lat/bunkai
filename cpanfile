requires 'Getopt::Long',           '2.58';
requires 'Path::Tiny',             '0.150';
requires 'Const::Fast',            '0.014';
requires 'CPAN::Audit', '20260622.001';
requires 'JSON::PP', '4.18';
requires 'Module::CPANfile',       '1.1004';
requires 'MetaCPAN::Client', '2.043000';
requires 'Try::Tiny',              '0.32';

feature 'test' => sub {
    requires 'Perl::Critic',        '1.156';
    requires 'Devel::Cover',        '1.52';
    requires 'File::Temp',          '0.2312';
    requires 'Test::More',          '1.302219';
    requires 'Test::MockModule',    '0.180.0';
    requires 'Test::Exception',     '0.43';
    requires 'Test::Fatal',         '0.018';
};