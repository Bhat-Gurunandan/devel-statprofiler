#!/usr/bin/env perl

use t::lib::Test;

use Devel::StatProfiler::Aggregator;
use Time::HiRes qw(usleep);

my ($profile_dir, $template);
BEGIN { ($profile_dir, $template) = temp_profile_dir(); }

use Devel::StatProfiler -template => $template, -interval => 1000, -source => 'all_evals';

my $file = __FILE__;
my $hlin = "#line";

my $line1 = __LINE__ + 3;
eval <<"EOT";
$hlin $line1 "$file"
sub foo1 {
    usleep(50000);
}
EOT

my $line2 = __LINE__ + 4;
eval <<"EOT";
usleep(50000);
$hlin $line2 "$file"
sub foo2 {
    usleep(50000);
}
EOT

eval <<"EOT";
$hlin 10 "non overlapping"
sub bar1 {
    usleep(50000);
}
EOT

eval <<"EOT";
$hlin 30 "non overlapping"
sub bar2 {
    usleep(50000);
}
EOT

eval <<"EOT";
$hlin 10 "overlapping"





sub baz1 {
    usleep(50000);
}
EOT

eval <<"EOT";
$hlin 12 "overlapping"
sub baz2 {
    usleep(50000);
}
EOT

foo1();
foo2();
bar1();
bar2();
baz1();
baz2();

Devel::StatProfiler::stop_profile();

my ($profile_file) = glob "$template.*";

my $r1 = Devel::StatProfiler::Report->new(sources => 1);
$r1->add_trace_file($profile_file);
$r1->_fetch_source(__FILE__);
# no need to finalize the report for comparison

my $r2 = Devel::StatProfiler::Report->new(sources => 1);
$r2->add_trace_file($profile_file);
# no need to finalize the report for comparison

my $a1 = Devel::StatProfiler::Aggregator->new(
    root_directory => File::Spec::Functions::catdir($profile_dir, 'aggr1'),
);
$a1->process_trace_files($profile_file);
$a1->save;
my $r3 = $a1->merged_report('__main__');
# no need to finalize the report for comparison

my $a2 = Devel::StatProfiler::Aggregator->new(
    root_directory => File::Spec::Functions::catdir($profile_dir, 'aggr1'),
);
my $r4 = $a2->merged_report('__main__');
# no need to finalize the report for comparison

my %eval_map = (
    'eval:6b3cd1d74ca85645e1b7441e303697abb2167799' => [
        [1, 'eval:6b3cd1d74ca85645e1b7441e303697abb2167799', 1],
        [3, 'second-eval', 20],
        [4, undef, 4],
    ],
    'eval:6ff7e35277e7400744f567ed096bec957a590b44' => [
        [2, 'first-eval', 10],
        [3, undef, 3],
    ],
);

my %full_map = (
    %eval_map,
    't/lib/Test/LineMap.pm' => [
        [1, 't/lib/Test/LineMap.pm', 1],
        [9, 'one-file.pm', 40],
        [13, 'other-file.pm', 30],
        [17, 'one-file.pm', 20],
        [21, 'other-file.pm', 40],
        [23, undef, 23],
    ]
);

eq_or_diff($r1->{sourcemap}{map}, \%full_map);
eq_or_diff($r2->{sourcemap}{map}, \%eval_map);
eq_or_diff($r3->{sourcemap}{map}, \%eval_map);
eq_or_diff($r4->{sourcemap}{map}, \%eval_map);

done_testing();
