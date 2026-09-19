use strict;
use warnings;
use 5.030;

use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use IPC::Open3;
use JSON::PP;
use Symbol qw(gensym);
use Test::More;

use Coff::Workflow ();

my $JSON = JSON::PP->new->utf8;
my $tmp = tempdir(CLEANUP => 1);
my $state = File::Spec->catdir($tmp, 'state');
my $counter = File::Spec->catfile($tmp, 'counter');
my $lib = File::Spec->rel2abs(
    File::Spec->catdir('.coff', 'src', 'coff-dullmify', 'scripts', 'lib'),
);
my $script = File::Spec->catfile($tmp, 'sample.pl');
write_script($script);

my ($status, $stdout, $stderr) = run_script('start', 'stable');
is($status, 0, 'start succeeds');
is($stderr, '', 'start has no stderr');
my $first = decode_output($stdout);
is($first->{ask}{topic}, 'first', 'start returns the first llm topic');
is($first->{index}, 1, 'the preceding step occupies index zero');
my $run = $first->{run};

my $journal = $JSON->decode(read_file(journal_path($run)));
is($journal->{effects}[0]{result}{value}, 'journal value', 'journal keeps the step snapshot');
is($first->{ask}{input}{snapshot}, 'workflow value', 'workflow receives a detached step value');

($status, $stdout, $stderr) = run_script_with_input('one', 'resume', $run, 1);
is($status, 0, 'resume succeeds');
my $second = decode_output($stdout);
is($second->{ask}{topic}, 'second', 'resume advances to the next llm topic');
is($second->{index}, 3, 'second question follows the counter step');

($status, $stdout, $stderr) = run_script_with_input('two', 'resume', $run, $second->{index});
is($status, 0, 'second resume succeeds');
my $done = decode_output($stdout);
ok($done->{done}, 'workflow reaches done');
is_deeply($done->{report}, ['one:two'], 'answers reach the report');
is(read_file($counter), "1\n", 'a step before the last question runs once across resumes');
ok(!-e run_dir($run), 'done removes the run directory');

($status, $stdout, $stderr) = run_script('start', 'failure');
my $failure_question = decode_output($stdout);
($status, $stdout, $stderr) = run_script_with_input(
    'answer', 'resume', $failure_question->{run}, $failure_question->{index},
);
isnt($status, 0, 'workflow failure returns a failing status');
my $failed = decode_output($stdout);
ok($failed->{done}, 'failure is terminal');
like($failed->{failed}, qr/requested failure/, 'failure reason is returned as JSON');
ok(!-e run_dir($failure_question->{run}), 'failure removes the run directory');

($status, $stdout, $stderr) = run_script('start', 'stable');
my $non_deterministic = decode_output($stdout);
$journal = $JSON->decode(read_file(journal_path($non_deterministic->{run})));
$journal->{effects}[1]{ask}{input}{mode} = 'changed';
write_file(journal_path($non_deterministic->{run}), $JSON->canonical->encode($journal) . "\n");
($status, $stdout, $stderr) = run_script_with_input(
    'answer', 'resume', $non_deterministic->{run}, $non_deterministic->{index},
);
isnt($status, 0, 'changed llm input stops replay');
like(decode_output($stdout)->{failed}, qr/non-deterministic/, 'non-determinism is reported');
ok(!-e run_dir($non_deterministic->{run}), 'non-determinism removes the run directory');

done_testing();

sub write_script {
    my ($path) = @_;
    my $quoted_lib = $lib;
    $quoted_lib =~ s/(['\\])/\\$1/g;
    my $quoted_counter = $counter;
    $quoted_counter =~ s/(['\\])/\\$1/g;
    write_file($path, <<"PERL");
use strict;
use warnings;
use utf8;
use lib '$quoted_lib';
use Coff::Workflow qw(run_workflow llm step);
exit run_workflow(
    name => 'sample',
    argv => \\\@ARGV,
    workflow => sub {
        my (\$mode) = \@_;
        my \$snapshot = step { return { value => 'journal value' } };
        \$snapshot->{value} = 'workflow value';
        my \$first = llm('first', {
            mode     => \$mode,
            snapshot => \$snapshot->{value},
        });
        die "requested failure\n" if \$mode eq 'failure';
        # 最後の問いより前に置き、二度目の resume で再実行されないことを数える。
        step {
            my \$count = -e '$quoted_counter' ? 0 + read_counter('$quoted_counter') : 0;
            open my \$fh, '>', '$quoted_counter' or die \$!;
            print {\$fh} \$count + 1, "\n";
            close \$fh or die \$!;
            return 1;
        };
        my \$second = llm('second', { first => \$first });
        return ["\$first:\$second"];
    },
);

sub read_counter {
    my (\$path) = \@_;
    open my \$fh, '<', \$path or die \$!;
    my \$value = <\$fh> // 0;
    close \$fh or die \$!;
    return \$value;
}
PERL
}

sub run_script {
    return run_script_with_input('', @_);
}

sub run_script_with_input {
    my ($input, @args) = @_;
    my $error = gensym;
    local %ENV = (%ENV, XDG_STATE_HOME => $state);
    my $pid = open3(my $in, my $out, $error, $^X, $script, @args);
    print {$in} $input;
    close $in;
    local $/;
    my $stdout = <$out> // '';
    my $stderr = <$error> // '';
    waitpid($pid, 0);
    return ($? >> 8, $stdout, $stderr);
}

sub run_dir {
    return File::Spec->catdir($state, 'coff', 'sample', $_[0]);
}

sub journal_path {
    return File::Spec->catfile(run_dir($_[0]), 'journal.json');
}

sub decode_output {
    return $JSON->decode($_[0]);
}

sub read_file {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "cannot read $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}

sub write_file {
    my ($path, $content) = @_;
    make_path(dirname($path));
    open my $fh, '>:raw', $path or die "cannot write $path: $!";
    print {$fh} $content;
    close $fh;
}
