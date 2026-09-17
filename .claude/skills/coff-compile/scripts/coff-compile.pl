#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use 5.030;

use Digest::MD5 qw(md5_hex);
use Encode qw(decode encode_utf8 FB_CROAK);
use File::Basename qw(basename dirname);
use File::Find qw(find);
use File::Spec;
use FindBin;
use JSON::PP;
use lib "$FindBin::Bin/lib";

use Coff::Workflow qw(run_workflow llm user step publish_files);

my $JSON = JSON::PP->new->canonical->utf8->allow_nonref;

exit run_workflow(
    name     => 'coff-compile',
    script   => $0,
    workflow => \&workflow,
);

sub workflow {
    my @args = @_;
    my $plan = step { _make_plan(\@args) } 'select-targets', { args => \@args };
    return ["failed: $plan->{error}"] unless $plan->{ok};

    my @report;
    for my $item (@{ $plan->{items} }) {
        if ($item->{skip} && !$plan->{force}) {
            if (!$plan->{lint_only} && @{ $item->{bundle_files} }) {
                my $bundle = step {
                    publish_files(files => $item->{bundle_files});
                } 'sync-bundle', {
                    source => $item->{source},
                    md5    => $item->{md5},
                    files  => $item->{bundle_files},
                };
                push @report, "$item->{source}: failed: $bundle->{error}"
                    unless $bundle->{ok};
            }
            next;
        }

        my $candidate_answer = llm('lint-candidates', {
            path    => $item->{source},
            content => $item->{content},
        });
        my $candidate_result = step {
            _validate_candidates($candidate_answer, $item->{content});
        } 'validate-lint-candidates', {
            source => $item->{source},
            answer => $candidate_answer,
            md5    => $item->{md5},
        };
        if (!$candidate_result->{ok}) {
            push @report, "$item->{source}: failed: $candidate_result->{error}";
            next;
        }

        my $candidate_count = @{ $candidate_result->{candidates} };
        my ($applied, $rejected) = (0, 0);
        if ($candidate_count) {
            my $approval = user('lint-approval', {
                path       => $item->{source},
                candidates => [
                    map {
                        +{
                            index => $_,
                            label => $candidate_result->{candidates}[$_]{label},
                        }
                    } 0 .. $candidate_count - 1
                ],
            });
            my $lint = step {
                _apply_lint($item, $candidate_result->{candidates}, $approval);
            } 'apply-lint', {
                source     => $item->{source},
                source_md5 => $item->{md5},
                candidates => $candidate_result->{candidates},
                approval   => $approval,
            };
            if (!$lint->{ok}) {
                push @report, "$item->{source}: failed: $lint->{error}";
                next;
            }
            $item->{content} = $lint->{content};
            $item->{md5} = $lint->{md5};
            $applied = $lint->{applied};
            $rejected = $candidate_count - $applied;

            if ($plan->{lint_only}) {
                push @report, "$item->{source}: linted ($applied applied, $rejected rejected)";
                next;
            }

            my $confirmation = user('compile-confirmation', {
                path     => $item->{source},
                applied  => $applied,
                rejected => $rejected,
                message  => "Lint 完了。$applied 件適用、$rejected 件却下。コンパイルしますか？",
            });
            if ($confirmation !~ /\A\s*(?:yes|y)\s*\z/i) {
                push @report, "$item->{source}: linted ($applied applied, $rejected rejected)";
                next;
            }
        }
        elsif ($plan->{lint_only}) {
            next;
        }

        if ($item->{dullmify}) {
            my $perl_answer = llm('dullmify-perl', {
                path     => $item->{source},
                content  => $item->{content},
                existing => $item->{existing_perl},
            });
            my $body_answer = llm('dullmify-skill', {
                path    => $item->{source},
                name    => $item->{name},
                content => $item->{content},
            });
            my $prepared = step {
                _prepare_dullmify($item, $perl_answer, $body_answer);
            } 'prepare-dullmify', {
                source      => $item->{source},
                source_md5  => $item->{md5},
                perl_answer => $perl_answer,
                body_answer => $body_answer,
            };
            if (!$prepared->{ok}) {
                push @report, "$item->{source}: failed: $prepared->{error}";
                next;
            }

            my $document = $prepared->{document};
            if ($item->{translate}) {
                $document = llm('translate', {
                    path    => $item->{source},
                    content => $document,
                });
            }
            my $published = step {
                _publish_compiled($item, $document, $prepared->{perl});
            } 'publish-dullmified', {
                source     => $item->{source},
                source_md5 => $item->{md5},
                document   => $document,
                perl       => $prepared->{perl},
                outputs    => $item->{outputs},
                bundle     => $item->{bundle_files},
            };
            if (!$published->{ok}) {
                push @report, "$item->{source}: failed: $published->{error}";
                next;
            }
        }
        else {
            my $document = $item->{content};
            if ($item->{translate}) {
                $document = llm('translate', {
                    path    => $item->{source},
                    content => $document,
                });
            }
            my $published = step {
                _publish_compiled($item, $document, undef);
            } 'publish-compiled', {
                source     => $item->{source},
                source_md5 => $item->{md5},
                document   => $document,
                outputs    => $item->{outputs},
                bundle     => $item->{bundle_files},
            };
            if (!$published->{ok}) {
                push @report, "$item->{source}: failed: $published->{error}";
                next;
            }
        }

        my $suffix = $applied ? " ($applied lint changes)" : '';
        push @report, "$item->{source}: compiled$suffix";
    }
    return \@report;
}

sub _make_plan {
    my ($args) = @_;
    my ($options, $option_error) = _parse_options($args);
    return { ok => JSON::PP::false, error => $option_error } if $option_error;

    my ($sources, $source_error) = _resolve_sources($options->{selectors});
    return { ok => JSON::PP::false, error => $source_error } if $source_error;

    my @items;
    for my $source (@$sources) {
        my ($type, $name) = _source_type($source);
        my @outputs = _outputs_for($type, $name, $options->{targets});
        next unless @outputs;

        return { ok => JSON::PP::false, error => "empty source: $source" }
            unless -s $source;
        my ($content, $read_error) = _read_text($source);
        return { ok => JSON::PP::false, error => $read_error } if $read_error;
        my ($frontmatter, $frontmatter_error) = _frontmatter($content);
        return { ok => JSON::PP::false, error => "$source: $frontmatter_error" }
            if $frontmatter_error;

        my $dullmify = _directive_bool($frontmatter, 'coff-dullmify');
        return { ok => JSON::PP::false, error => "$source: coff-dullmify requires a skill source" }
            if $dullmify && $type ne 'skill';
        my $translate = !_directive_false($frontmatter, 'coff-translate');
        my ($bundle_names, $bundle_error) = _bundle_names($frontmatter);
        return { ok => JSON::PP::false, error => "$source: $bundle_error" }
            if $bundle_error;

        my $md5 = _file_md5($source);
        my @footer_outputs = map { $_->{path} } @outputs;
        if ($dullmify) {
            push @footer_outputs, map {
                File::Spec->catfile(dirname($_->{path}), 'scripts', "$name.pl")
            } grep { $_->{mode} eq 'body' } @outputs;
        }
        my $skip = 1;
        for my $path (@footer_outputs) {
            if ((_footer_md5($path) // '') ne $md5) {
                $skip = 0;
                last;
            }
        }

        my ($bundle_files, $bundle_collect_error) = _collect_bundle_files(
            $name, $bundle_names, \@outputs, $dullmify,
        );
        return { ok => JSON::PP::false, error => "$source: $bundle_collect_error" }
            if $bundle_collect_error;

        my $existing_perl = '';
        if ($dullmify) {
            my ($body_output) = grep { $_->{mode} eq 'body' } @outputs;
            my $existing_path = $body_output
                ? File::Spec->catfile(dirname($body_output->{path}), 'scripts', "$name.pl")
                : File::Spec->catfile('.claude', 'skills', $name, 'scripts', "$name.pl");
            if (-f $existing_path) {
                ($existing_perl, $read_error) = _read_text($existing_path);
                return { ok => JSON::PP::false, error => $read_error } if $read_error;
                $existing_perl =~ s/\n?# <!--\{"src":.*?"md5":"[a-f0-9]{32}"\} -->\s*\z//s;
            }
        }

        push @items, {
            source        => $source,
            type          => $type,
            name          => $name,
            content       => $content,
            md5           => $md5,
            dullmify      => $dullmify ? JSON::PP::true : JSON::PP::false,
            translate     => $translate ? JSON::PP::true : JSON::PP::false,
            outputs       => \@outputs,
            bundle_files  => $bundle_files,
            existing_perl => $existing_perl,
            skip           => $skip ? JSON::PP::true : JSON::PP::false,
        };
    }

    return {
        ok        => JSON::PP::true,
        force     => $options->{force},
        lint_only => $options->{lint_only},
        items     => \@items,
    };
}

sub _parse_options {
    my ($args) = @_;
    my %option = (
        force      => JSON::PP::false,
        lint_only  => JSON::PP::false,
        selectors  => [],
        agent      => [],
    );
    my ($explicit_out, $explicit_ref) = (0, 0);
    for (my $i = 0; $i < @$args; $i++) {
        my $arg = $args->[$i];
        if ($arg eq '--force') {
            $option{force} = JSON::PP::true;
        }
        elsif ($arg eq '--lint-only') {
            $option{lint_only} = JSON::PP::true;
        }
        elsif ($arg eq '--out') {
            return (undef, '--out requires a root') if ++$i >= @$args;
            $option{out} = $args->[$i];
            $explicit_out = 1;
        }
        elsif ($arg eq '--ref') {
            $option{ref} = JSON::PP::true;
            $explicit_ref = 1;
        }
        elsif ($arg eq '--agent') {
            return (undef, '--agent requires a name') if ++$i >= @$args;
            push @{ $option{agent} }, $args->[$i];
        }
        elsif ($arg =~ /\A--/) {
            return (undef, "unknown option: $arg");
        }
        else {
            push @{ $option{selectors} }, $arg;
        }
    }

    return (undef, '--ref requires --out') if $explicit_ref && !$explicit_out;
    return (undef, '--agent cannot be combined with --out or --ref')
        if @{ $option{agent} } && ($explicit_out || $explicit_ref);

    my @targets;
    if (@{ $option{agent} }) {
        my %seen;
        for my $agent (@{ $option{agent} }) {
            next if $seen{$agent}++;
            if ($agent eq 'claude-code') {
                push @targets, { root => '.claude', mode => 'body', types => [qw(skill outputstyle agent)] };
            }
            elsif ($agent eq 'codex') {
                push @targets, { root => '.agents', mode => 'ref', types => ['skill'] };
            }
            else {
                return (undef, "unknown agent: $agent");
            }
        }
    }
    elsif ($explicit_out) {
        push @targets, {
            root  => $option{out},
            mode  => $option{ref} ? 'ref' : 'body',
            types => [qw(skill outputstyle agent)],
        };
    }
    else {
        push @targets, { root => '.claude', mode => 'body', types => [qw(skill outputstyle agent)] };
    }
    $option{targets} = \@targets;
    return (\%option, undef);
}

sub _resolve_sources {
    my ($selectors) = @_;
    my @sources;
    if (!@$selectors) {
        for my $suffix (qw(skill.md outputstyle.md agent.md)) {
            push @sources, glob(File::Spec->catfile('.coff', 'src', "*.$suffix"));
        }
    }
    else {
        for my $selector (@$selectors) {
            my @matches;
            if ($selector =~ /\.(?:skill|outputstyle|agent)\.md\z/) {
                my $candidate = $selector =~ m{[/\\]}
                    ? $selector
                    : File::Spec->catfile('.coff', 'src', $selector);
                push @matches, $candidate if -f $candidate;
            }
            else {
                for my $suffix (qw(skill.md outputstyle.md agent.md)) {
                    my $candidate = File::Spec->catfile('.coff', 'src', "$selector.$suffix");
                    push @matches, $candidate if -f $candidate;
                }
            }
            return (undef, "source not found: $selector") unless @matches;
            return (undef, "ambiguous source: $selector") if @matches > 1;
            push @sources, $matches[0];
        }
    }
    my %seen;
    @sources = sort grep { !$seen{$_}++ } @sources;
    return (\@sources, undef);
}

sub _source_type {
    my ($source) = @_;
    my $file = basename($source);
    return ('skill', $1) if $file =~ /\A(.+)\.skill\.md\z/;
    return ('outputstyle', $1) if $file =~ /\A(.+)\.outputstyle\.md\z/;
    return ('agent', $1) if $file =~ /\A(.+)\.agent\.md\z/;
    die "unknown source type: $source\n";
}

sub _outputs_for {
    my ($type, $name, $targets) = @_;
    my @outputs;
    for my $target (@$targets) {
        my %allowed = map { $_ => 1 } @{ $target->{types} };
        next unless $allowed{$type};
        my $path;
        if ($type eq 'skill') {
            $path = File::Spec->catfile($target->{root}, 'skills', $name, 'SKILL.md');
        }
        elsif ($type eq 'outputstyle') {
            $path = File::Spec->catfile($target->{root}, 'output-styles', "$name.md");
        }
        else {
            $path = File::Spec->catfile($target->{root}, 'agents', "$name.md");
        }
        push @outputs, { %$target, path => $path };
    }
    return @outputs;
}

sub _frontmatter {
    my ($content) = @_;
    return (undef, 'frontmatter is missing') unless $content =~ /\A---\r?\n/;
    return ($1, undef) if $content =~ /\A---\r?\n(.*?)\r?\n---\r?\n/s;
    return (undef, 'frontmatter is not closed');
}

sub _directive_bool {
    my ($frontmatter, $key) = @_;
    return $frontmatter =~ /^\Q$key\E:\s*true\s*(?:#.*)?$/mi;
}

sub _directive_false {
    my ($frontmatter, $key) = @_;
    return $frontmatter =~ /^\Q$key\E:\s*false\s*(?:#.*)?$/mi;
}

sub _bundle_names {
    my ($frontmatter) = @_;
    return ([], undef) unless $frontmatter =~ /^coff-bundle:\s*(.*?)\s*$/mi;
    my $value = $1;
    return (undef, 'coff-bundle must be an inline list')
        unless $value =~ /\A\[(.*)\]\z/;
    my $inside = $1;
    return ([], undef) unless $inside =~ /\S/;
    my @names = map {
        my $name = $_;
        $name =~ s/^\s+|\s+$//g;
        $name =~ s/\A(['"])(.*)\1\z/$2/;
        $name;
    } split /,/, $inside;
    for my $name (@names) {
        return (undef, "invalid bundle directory: $name")
            unless $name =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/
                && $name ne '.' && $name ne '..';
    }
    return (\@names, undef);
}

sub _collect_bundle_files {
    my ($name, $bundle_names, $outputs, $dullmify) = @_;
    my %relative;
    for my $bundle (@$bundle_names) {
        my $root = File::Spec->catdir('.coff', 'src', $name, $bundle);
        return (undef, "bundle directory not found: $root") unless -d $root;
        my $error;
        find({
            no_chdir => 1,
            wanted   => sub {
                return if $error;
                my $path = $File::Find::name;
                if (-l $path) {
                    $error = "bundle contains a symlink: $path";
                    return;
                }
                return if -d $path;
                if (!-f $path) {
                    $error = "bundle contains a non-file: $path";
                    return;
                }
                my $suffix = File::Spec->abs2rel($path, $root);
                my ($content, $read_error) = _read_text($path);
                if ($read_error) {
                    $error = $read_error;
                    return;
                }
                $relative{ File::Spec->catfile($bundle, $suffix) } = $content;
            },
        }, $root);
        return (undef, $error) if $error;
    }

    if ($dullmify) {
        my $runtime = File::Spec->catfile($FindBin::Bin, 'lib', 'Coff', 'Workflow.pm');
        my ($content, $read_error) = _read_text($runtime);
        return (undef, $read_error) if $read_error;
        my $relative = File::Spec->catfile('scripts', 'lib', 'Coff', 'Workflow.pm');
        $relative{$relative} = $content unless exists $relative{$relative};
    }

    my @files;
    for my $output (@$outputs) {
        next unless $output->{mode} eq 'body';
        my $skill_dir = dirname($output->{path});
        for my $relative (sort keys %relative) {
            push @files, {
                path    => File::Spec->catfile($skill_dir, $relative),
                content => $relative{$relative},
            };
        }
    }
    return (\@files, undef);
}

sub _validate_candidates {
    my ($answer, $content) = @_;
    my ($decoded, $error) = _decode_json($answer);
    return { ok => JSON::PP::false, error => "invalid lint JSON: $error" } if $error;
    return { ok => JSON::PP::false, error => 'lint answer must be an array' }
        unless ref($decoded) eq 'ARRAY';
    my @lines = split /(?<=\n)/, $content, -1;
    pop @lines if @lines && $lines[-1] eq '';
    my $previous_end = 0;
    for my $candidate (@$decoded) {
        return { ok => JSON::PP::false, error => 'invalid lint candidate' }
            unless ref($candidate) eq 'HASH'
                && defined $candidate->{start}
                && defined $candidate->{end}
                && defined $candidate->{replacement}
                && defined $candidate->{label}
                && $candidate->{start} =~ /\A[1-9][0-9]*\z/
                && $candidate->{end} =~ /\A[1-9][0-9]*\z/
                && $candidate->{start} <= $candidate->{end}
                && $candidate->{end} <= @lines
                && $candidate->{start} > $previous_end;
        my $original = join '', @lines[$candidate->{start} - 1 .. $candidate->{end} - 1];
        return { ok => JSON::PP::false, error => 'lint replacement does not change the source' }
            if $candidate->{replacement} eq $original;
        $previous_end = $candidate->{end};
    }
    return { ok => JSON::PP::true, candidates => $decoded };
}

sub _apply_lint {
    my ($item, $candidates, $approval) = @_;
    return { ok => JSON::PP::false, error => 'source changed during lint' }
        unless _file_md5($item->{source}) eq $item->{md5};
    my ($indexes, $error) = _decode_json($approval);
    return { ok => JSON::PP::false, error => "invalid approval JSON: $error" } if $error;
    return { ok => JSON::PP::false, error => 'approval must be an array' }
        unless ref($indexes) eq 'ARRAY';
    my %selected;
    for my $index (@$indexes) {
        return { ok => JSON::PP::false, error => 'approval contains an invalid index' }
            if ref($index) || $index !~ /\A(?:0|[1-9][0-9]*)\z/ || $index >= @$candidates;
        $selected{$index} = 1;
    }

    my @lines = split /(?<=\n)/, $item->{content}, -1;
    pop @lines if @lines && $lines[-1] eq '';
    for my $index (sort { $b <=> $a } keys %selected) {
        my $candidate = $candidates->[$index];
        splice @lines,
            $candidate->{start} - 1,
            $candidate->{end} - $candidate->{start} + 1,
            $candidate->{replacement};
    }
    my $content = join '', @lines;
    my $published = publish_files(files => [{ path => $item->{source}, content => $content }]);
    return $published unless $published->{ok};
    return {
        ok      => JSON::PP::true,
        content => $content,
        md5     => _file_md5($item->{source}),
        applied => scalar keys %selected,
    };
}

sub _prepare_dullmify {
    my ($item, $perl, $body) = @_;
    return { ok => JSON::PP::false, error => 'generated Perl must start with #!/usr/bin/env perl' }
        unless $perl =~ /\A#!\/usr\/bin\/env perl\r?\n/;
    return { ok => JSON::PP::false, error => 'generated Perl contains a Markdown fence' }
        if $perl =~ /^\s*(?:```|~~~)/m;
    return { ok => JSON::PP::false, error => 'generated Perl already contains a footer' }
        if $perl =~ /# <!--\{"src":.*"md5":"[a-f0-9]{32}"\} -->/;
    return { ok => JSON::PP::false, error => 'thin skill body contains frontmatter' }
        if $body =~ /\A---\r?\n/;
    return { ok => JSON::PP::false, error => 'thin skill body contains a fenced code block' }
        if $body =~ /^\s*(?:```|~~~)/m;

    my ($frontmatter, $error) = _runtime_frontmatter($item->{content}, $item->{name});
    return { ok => JSON::PP::false, error => $error } if $error;
    $body =~ s/\A\s+//;
    $body =~ s/\s+\z//;
    return {
        ok       => JSON::PP::true,
        perl     => $perl,
        document => $frontmatter . "\n\n" . $body . "\n",
    };
}

sub _publish_compiled {
    my ($item, $document, $perl) = @_;
    return { ok => JSON::PP::false, error => 'source changed during compile' }
        unless _file_md5($item->{source}) eq $item->{md5};

    my ($compiled, $compile_error) = _compile_document(
        $document,
        $item->{name},
        $item->{dullmify},
    );
    return { ok => JSON::PP::false, error => $compile_error } if $compile_error;
    my $markdown_footer = '<!--{"src":"' . $item->{source} . '","md5":"' . $item->{md5} . '"} -->';
    my $perl_footer = '# ' . $markdown_footer;
    $compiled =~ s/\s+\z//;
    my $compiled_with_footer = $compiled . "\n" . $markdown_footer . "\n";

    my %files;
    for my $output (@{ $item->{outputs} }) {
        if ($output->{mode} eq 'body') {
            $files{ $output->{path} } = {
                path    => $output->{path},
                content => $compiled_with_footer,
            };
            if ($item->{dullmify}) {
                my $script_path = File::Spec->catfile(
                    dirname($output->{path}), 'scripts', "$item->{name}.pl",
                );
                my $program = $perl;
                $program =~ s/\s+\z//;
                $files{$script_path} = {
                    path       => $script_path,
                    content    => $program . "\n" . $perl_footer . "\n",
                    check_perl => JSON::PP::true,
                };
            }
        }
        else {
            my $canonical = File::Spec->catfile(
                '.claude', 'skills', $item->{name}, 'SKILL.md',
            );
            my $canonical_in_batch = grep { $_->{mode} eq 'body' && $_->{path} eq $canonical }
                @{ $item->{outputs} };
            return { ok => JSON::PP::false, error => "canonical output is missing: $canonical" }
                unless $canonical_in_batch || -f $canonical;
            my ($frontmatter, undef, $split_error) = _split_document($compiled);
            return { ok => JSON::PP::false, error => $split_error } if $split_error;
            my $stub = $frontmatter
                . "\n\nThis file is a reference. Read and follow `../../../.claude/skills/$item->{name}/SKILL.md`.\n"
                . $markdown_footer . "\n";
            $files{ $output->{path} } = { path => $output->{path}, content => $stub };
        }
    }
    for my $file (@{ $item->{bundle_files} }) {
        if (exists $files{ $file->{path} } && $files{ $file->{path} }{content} ne $file->{content}) {
            return { ok => JSON::PP::false, error => "conflicting output: $file->{path}" };
        }
        $files{ $file->{path} } = $file;
    }

    return publish_files(
        files    => [map { $files{$_} } sort keys %files],
        perl_inc => [File::Spec->catdir($FindBin::Bin, 'lib')],
    );
}

sub _runtime_frontmatter {
    my ($document, $name) = @_;
    my ($frontmatter, undef, $error) = _split_document($document);
    return (undef, $error) if $error;
    my @lines = split /\n/, $frontmatter;
    my @kept = ('---');
    my $skip = 0;
    my $has_name = 0;
    for my $line (@lines[1 .. $#lines - 1]) {
        if ($line =~ /^([A-Za-z0-9_-]+):/) {
            my $key = $1;
            $skip = $key =~ /^coff-/ || $key eq 'allowed-tools';
            if ($key eq 'name') {
                push @kept, "name: $name";
                $has_name = 1;
                next;
            }
        }
        push @kept, $line unless $skip;
    }
    splice @kept, 1, 0, "name: $name" unless $has_name;
    push @kept, 'allowed-tools: Bash(perl ${CLAUDE_SKILL_DIR}/scripts/' . $name . '.pl *)';
    push @kept, '---';
    return (join("\n", @kept), undef);
}

sub _compile_document {
    my ($document, $name, $dullmify) = @_;
    my ($frontmatter, $body, $error) = _split_document($document);
    return (undef, $error) if $error;
    my $joined = $frontmatter . "\n" . $body;
    my ($clean_frontmatter, $frontmatter_error) = $dullmify
        ? _runtime_frontmatter($joined, $name)
        : _clean_frontmatter($frontmatter, $name);
    return (undef, $frontmatter_error) if $frontmatter_error;
    $body = _strip_comments($body);
    $body =~ s/\A\s+//;
    $body =~ s/\s+\z//;
    return ($clean_frontmatter . "\n\n" . $body, undef);
}

sub _clean_frontmatter {
    my ($frontmatter, $name) = @_;
    my @lines = split /\n/, $frontmatter;
    my @kept = ('---');
    my $skip = 0;
    my $has_name = 0;
    for my $line (@lines[1 .. $#lines - 1]) {
        if ($line =~ /^([A-Za-z0-9_-]+):/) {
            my $key = $1;
            $skip = $key =~ /^coff-/;
            if ($key eq 'name') {
                push @kept, "name: $name";
                $has_name = 1;
                next;
            }
        }
        push @kept, $line unless $skip;
    }
    splice @kept, 1, 0, "name: $name" unless $has_name;
    push @kept, '---';
    return (join("\n", @kept), undef);
}

sub _split_document {
    my ($document) = @_;
    return (undef, undef, 'frontmatter is missing') unless $document =~ /\A---\r?\n/;
    if ($document =~ /\A(---\r?\n.*?\r?\n---)\r?\n?(.*)\z/s) {
        return ($1, $2, undef);
    }
    return (undef, undef, 'frontmatter is not closed');
}

sub _strip_comments {
    my ($body) = @_;
    my @lines = split /(?<=\n)/, $body, -1;
    my ($fence, $comment) = ('', 0);
    my $out = '';
    for my $line (@lines) {
        if (!$comment && $line =~ /^\s*(`{3,}|~{3,})/) {
            my $mark = substr($1, 0, 1);
            if (!$fence) {
                $fence = $mark;
            }
            elsif ($fence eq $mark) {
                $fence = '';
            }
            $out .= $line;
            next;
        }
        if ($fence) {
            $out .= $line;
            next;
        }
        my $position = 0;
        while ($position < length $line) {
            if ($comment) {
                my $end = index($line, '-->', $position);
                if ($end < 0) {
                    $position = length $line;
                    next;
                }
                $comment = 0;
                $position = $end + 3;
                next;
            }
            my $comment_at = index($line, '<!--', $position);
            my $tick_at = index($line, '`', $position);
            if ($tick_at >= 0 && ($comment_at < 0 || $tick_at < $comment_at)) {
                $out .= substr($line, $position, $tick_at - $position);
                my $ticks = 1;
                $ticks++ while substr($line, $tick_at + $ticks, 1) eq '`';
                my $token = '`' x $ticks;
                my $end = index($line, $token, $tick_at + $ticks);
                if ($end < 0) {
                    $out .= substr($line, $tick_at);
                    $position = length $line;
                }
                else {
                    $out .= substr($line, $tick_at, $end + $ticks - $tick_at);
                    $position = $end + $ticks;
                }
                next;
            }
            if ($comment_at >= 0) {
                $out .= substr($line, $position, $comment_at - $position);
                $comment = 1;
                $position = $comment_at + 4;
                next;
            }
            $out .= substr($line, $position);
            last;
        }
    }
    return $out;
}

sub _decode_json {
    my ($raw) = @_;
    my $decoded = eval { $JSON->decode(encode_utf8($raw)) };
    return (undef, $@ || 'decode failed') if $@;
    return ($decoded, undef);
}

sub _read_text {
    my ($path) = @_;
    open my $fh, '<:raw', $path or return (undef, "cannot read $path: $!");
    local $/;
    my $raw = <$fh>;
    close $fh or return (undef, "cannot close $path: $!");
    my $text = eval { decode('UTF-8', $raw, FB_CROAK) };
    return (undef, "$path is not UTF-8: $@") if $@;
    return ($text, undef);
}

sub _file_md5 {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "cannot read $path: $!\n";
    my $md5 = Digest::MD5->new->addfile($fh)->hexdigest;
    close $fh or die "cannot close $path: $!\n";
    return $md5;
}

sub _footer_md5 {
    my ($path) = @_;
    return undef unless -f $path;
    open my $fh, '<:raw', $path or return undef;
    my $last = '';
    $last = $_ while <$fh>;
    close $fh;
    return $1 if $last =~ /"md5":"([a-f0-9]{32})"/;
    return undef;
}
# <!--{"src":".coff/src/coff-compile.skill.md","md5":"1c20282ca32a5f732b2fa9189e6acdd4"} -->
