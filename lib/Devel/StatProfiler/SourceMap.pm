package Devel::StatProfiler::SourceMap;

use strict;
use warnings;

use Devel::StatProfiler::Utils qw(check_serializer read_file read_data write_data_part write_file);
use File::Path;
use File::Spec::Functions;
use Digest::SHA qw(sha1_hex);

sub new {
    my ($class, %opts) = @_;
    my $self = bless {
        map             => {},
        reverse_map     => {},
        current_map     => undef,
        current_file    => undef,
        ignore_mapping  => 0,
        serializer      => $opts{serializer} || 'storable',
    }, $class;

    check_serializer($self->{serializer});

    return $self;
}

sub start_file_mapping {
    my ($self, $physical_file) = @_;
    die "Causal failure for '$physical_file'" if $self->{current_map};

    if ($self->{map}{$physical_file}) {
        $self->{ignore_mapping} = 1;
        return;
    }

    $self->{current_map} = [1, $physical_file, 1];
    $self->{current_file} = $physical_file;
    push @{$self->{map}{$physical_file}}, $self->{current_map};
}

sub end_file_mapping {
    my ($self, $physical_line) = @_;

    if (my $map = $self->{current_map}) {
        delete $self->{map}{$self->{current_file}}
            if $map->[0] == 1 && $map->[1] eq $self->{current_file} && $map->[2] == 1;
    }

    for my $entry (@{$self->{map}{$self->{current_file}} || []}) {
        $self->{reverse_map}{$entry->[1]}{$self->{current_file}} = 1;
    }

    # add last line
    push @{$self->{map}{$self->{current_file}}}, [$physical_line + 1, undef, $physical_line + 1]
        if $self->{map}{$self->{current_file}};

    $self->{ignore_mapping} = 0;
    $self->{current_map} = undef;
    $self->{current_file} = undef;
}

sub add_file_mapping {
    my ($self, $physical_line, $mapped_file, $mapped_line) = @_;
    die "Causal failure for '$self->{current_file}'" unless $self->{current_map};

    return if $self->{ignore_mapping};

    my ($st, $en) = (substr($mapped_file, 0, 1), substr($mapped_file, -1, 1));
    if ($st eq $en && ($st eq '"' || $st eq "'")) {
        $mapped_file = substr($mapped_file, 1, -1);
    }

    if ($physical_line == $self->{current_map}[0] + 1) {
        $self->{current_map} = [$physical_line, $mapped_file, 0 + $mapped_line];
        $self->{map}{$self->{current_file}}->[-1] = $self->{current_map};
    } else {
        $self->{current_map} = [$physical_line, $mapped_file, 0 + $mapped_line];
        push @{$self->{map}{$self->{current_file}}}, $self->{current_map};
    }
}

sub add_sources_from_reader {
    my ($self, $r) = @_;

    my $source_code = $r->get_source_code;
    for my $name (keys %$source_code) {
        next unless $source_code->{$name} =~ /^#line\s+\d+\s+/m;

        my $eval_name = 'eval:' . sha1_hex($source_code->{$name});

        next if $self->{map}{$eval_name};

        $self->start_file_mapping($eval_name);

        while ($source_code->{$name} =~ /^#line\s+(\d+)\s+(.+?)$/mg) {
            my $line = substr($source_code->{$name}, 0, pos($source_code->{$name})) =~ tr/\n/\n/;
            $self->add_file_mapping($line + 2, $2, $1);
        }

        $self->end_file_mapping($source_code->{$name} =~ tr/\n/\n/);
    }
}

sub map_source {
    my ($self, $sources, $process_id) = @_;

    for my $key (keys %{$self->{map}}) {
        for my $entry (@{$self->{map}{$key}}) {
            if ($entry->[1]) { # skip sentinel entry for last line
                my $hash = $sources->get_hash_by_name($process_id, $entry->[1]);

                if ($hash) {
                    delete $self->{reverse_map}{$entry->[1]};
                    $entry->[1] = "eval:$hash";
                    $self->{reverse_map}{"eval:$hash"}{$key} = 1;
                }
            }
        }
    }
}

sub save {
    my ($self, $root_dir) = @_;
    my $state_dir = File::Spec::Functions::catdir($root_dir, '__state__');

    File::Path::mkpath($state_dir);

    write_data_part($self->{serializer}, $state_dir, 'sourcemap', $self->{map});
}

sub load_and_merge {
    my ($self, $file) = @_;
    my $data = read_data($self->{serializer}, $file);

    for my $key (keys %$data) {
        $self->{map}{$key} = $data->{$key};

        for my $entry (@{$data->{$key}}) {
            $self->{reverse_map}{$entry->[1]}{$key} = 1
                if $entry->[1]; # skip sentinel entry for last line
        }
    }
}

sub get_mapping {
    my ($self, $file) = @_;

    return $self->{map}{$file};
}

sub get_reverse_mapping {
    my ($self, $file) = @_;

    return unless $self->{reverse_map}{$file};
    return (keys %{$self->{reverse_map}{$file}})[0];
}

1;
