requires 'perl', '5.30';

requires 'Getopt::Long',     '2.52';
requires 'Module::CPANfile', '0.9043';
requires 'Path::Tiny',       '0.144';
requires 'Const::Fast',      '0.014';
requires 'MetaCPAN::Client', '2.033000;
requires 'HTTP::Tiny',       '0.090';
requires 'JSON::PP',         '4.16';
requires 'Time::HiRes',      '1.9778';

on 'test' => sub {
    requires 'Test::More',      '1.302193';
    requires 'Test::Exception', '0.43';
    requires 'File::Temp',      '0.2311';
};

on 'develop' => sub {
    requires 'Perl::Critic',  '1.140';
    requires 'Devel::Cover',  '1.36';
};
