requires 'perl', '5.30';

requires 'Getopt::Long',     '2.58';
requires 'Path::Tiny',       '0.148';
requires 'Const::Fast',      '0.014';
requires 'CPAN::Audit',      '20250115.001';
requires 'JSON::PP',         '4.16';
requires 'Module::CPANfile', '1.1004';

on 'test' => sub {
    requires 'Test::More',      '1.302214';
    requires 'Test::Exception', '0.43';
    requires 'File::Temp',      '0.2311';
    requires 'Test::Fatal',     '0.017';
};

on 'develop' => sub {
    requires 'Perl::Critic',  '1.140';
    requires 'Devel::Cover',  '1.36';
};
