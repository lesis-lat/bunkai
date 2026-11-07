requires 'Const::Fast',      '== 0.014';
requires 'Cpanel::JSON::XS', '== 4.80';
requires 'CPAN::Audit',      '== 20261105.001';
requires 'CPAN::Meta',       '== 2.150015';
requires 'Getopt::Long',     '== 2.58';
requires 'JSON::PP',         '== 4.18';
requires 'MetaCPAN::Client', '== 2.044000';
requires 'Path::Tiny',       '== 0.150';
requires 'Try::Tiny',        '== 0.32';
requires 'Type::Tiny',       '== 2.010001';

on 'test' => sub {
    requires 'File::Temp',       '== 0.2312';
    requires 'Test::Exception',  '== 0.43';
    requires 'Test::Fatal',      '== 0.019';
    requires 'Test::MockModule', '== 0.185.3';
    requires 'Test::More',       '== 1.302226';
    requires 'Readonly',         '== 2.05';
};

on 'develop' => sub {
    requires 'Perl::Tidy',     '== 20260826';
    requires 'Devel::Cover',   '== 1.52';
    requires 'Devel::Mutator', '== 0.03';
    requires 'Devel::NYTProf', '== 6.16';
    requires 'Perl::Critic',   '== 1.156';
};
