package Bench;

# VERSION

use 5.010001;
use strict;
use warnings;

use List::Util qw/shuffle/;
use Module::Loaded;
use Time::HiRes qw/gettimeofday tv_interval/;

my $bench_called;
my ($t0, $ti);

sub _set_start_time {
    $t0 = [gettimeofday];
}

sub _set_interval {
    $ti = tv_interval($t0, [gettimeofday]);
}

sub import {
    _set_start_time;
    no strict 'refs';
    my $caller = caller();
    *{"$caller\::bench"} = \&bench;
}

sub _fmt_num {
    my ($num, $unit, $nsig) = @_;
    $nsig //= 4;
    my $fmt;

    my $l = $num ? int(log(abs($num))/log(10)) : 0;
    if ($l >= $nsig) {
        $fmt = "%.0f";
    } elsif ($l < 0) {
        $fmt = "%.${nsig}f";
    } else {
        $fmt = "%.".($nsig-$l-1)."f";
    }
    #say "D:fmt=$fmt";
    sprintf($fmt, $num) . ($unit // "");
}

sub bench($;$) {
    my ($subs0, $opts) = @_;
    $opts //= {};
    $opts   = {n=>$opts} if ref($opts) ne 'HASH';
    my %subs;
    if (ref($subs0) eq 'CODE') {
        %subs = (a=>$subs0);
    } elsif (ref($subs0) eq 'HASH') {
        %subs = %$subs0;
    } elsif (ref($subs0) eq 'ARRAY') {
        my $name = "a";
        for (@$subs0) { $subs{$name++} = $_ }
    } else {
        die "Usage: bench(CODE|{a=>CODE,b=>CODE, ...}|[CODE, CODE, ...], ".
            "{opt=>val, ...})";
    }
    die "Please specify one or more subs"
        unless keys %subs;

    my $use_dumbbench;
    if ($opts->{dumbbench}) {
        $use_dumbbench++;
        require Dumbbench;
    } elsif (!defined $opts->{dumbbench}) {
        $use_dumbbench++ if is_loaded('Dumbbench');
    }

    my @res;
    my $void = !defined(wantarray);
    if ($use_dumbbench) {

        $opts->{dumbbench_options} //= {};
        my $bench = Dumbbench->new(%{ $opts->{dumbbench_options} });
        $bench->add_instances(
            map { Dumbbench::Instance::PerlSub->new(code => $subs{$_}) }
                keys %subs
        );
        $bench->run;
        $bench->report;

    } else {

        my %calltimes; # key=name, val=per-call time

        for my $name (shuffle keys %subs) {
            my $code = $subs{$name};

            my $n = $opts->{n};

            # run code once to set default n & j (to reduce the number of
            # time-interval-taking when n is negative)
            my $i = 0;
            _set_start_time;
            $code->();
            _set_interval;
            my $j = $ti ? int(1/$ti) : 1000;
            $i++;
            if ($ti <= 0.01) {
                $n //= 100;
            } else {
                $n //= int(1/$ti);
            }

            if ($n >= 0) {
                while ($i < $n) {
                    $code->();
                    $i++;
                }
                _set_interval;
            } else {
                $n = -$n;
                while (1) {
                    for (1..$j) {
                        $code->();
                        $i++;
                    }
                    _set_interval;
                    last if $ti >= $n;
                }
            }
            my $res = join(
                "",
                (keys(%subs) > 1 ? "$name: " : ""),
                sprintf("%d calls (%s/s), %s (%s/call)",
                        $i, _fmt_num($ti ? $i/$ti : 0), _fmt_num($ti, "s"),
                        _fmt_num($ti/$i*1000, "ms"))
            );
            say $res if $void;
            push @res, $res;
            $calltimes{$name} = $ti/$i;
        }

        if (keys(%subs) > 1) {
            my @subs = sort {$a->[1] <=> $b->[1]}
                map {[$_, $calltimes{$_}]} keys %subs;
            if ($subs[0][1] > 0) {
                my $res = "Fastest is $subs[0][0] (";
                for (1..@subs-1) {
                    $res .= ($_ > 1 ? ", ":"") .
                        _fmt_num($subs[$_][1]/$subs[0][1], "x")." $subs[$_][0]";
                }
                $res .= ")";
                say $res if $void;
                push @res, $res;
            }
        }
    }

    $bench_called++;
    join("\n", @res);
}

END {
    _set_interval;
    say _fmt_num($ti, "s") unless $bench_called || $ENV{HARNESS_ACTIVE};
}

1;
# ABSTRACT: Benchmark running times of Perl code

=head1 SYNOPSIS

 # time the whole program
 % perl -MBench -e'...'
 0.0123s

 # basic usage of bench()
 % perl -MBench -e'bench sub { ... }'
 100 calls (58548/s), 0.0017s (0.0171ms/call)

 # get bench result in a variable
 % perl -MBench -E'my $res = bench sub { ... }'

 # specify bench options
 % perl -MBench -E'bench sub { ... }, 100'
 % perl -MBench -E'bench sub { ... }, {n=>-5}'
 304347 calls (60665/s), 5.017s (0.0165ms/call)

 # use Dumbbench as the backend
 % perl -MDumbbench -MBench -E'bench sub { ... }'
 % perl -MBench -E'bench sub { ... }, {dumbbench=>1, dumbbench_options=>{...}}'
 Ran 26 iterations (6 outliers).
 Rounded run time per iteration: 2.9029e-02 +/- 4.8e-05 (0.2%)

 # bench multiple codes
 % perl -MBench -E'bench {a=>sub{...}, b=>sub{...}}, {n=>-2}'
 % perl -MBench -E'bench [sub{...}, sub{...}]'; # automatically named a, b, ...
 b: 100 calls (5357/s), 0.0187s (0.1870ms/call)
 a: 100 calls (12120/s), 0.0083s (0.0825ms/call)
 Fastest is a (2.267x b)


=head1 DESCRIPTION

This module is an alternative to L<Benchmark>. It provides some nice defaults
and a simpler interface. There is only one function, B<bench()>, and it is
exported by default. If bench() is never called, the whole program will be
timed.

This module can utilize L<Dumbbench> as the backend.

=head1 FUNCTIONS

=head2 bench SUB(S)[, OPTS] => RESULT

Run Perl code and time it. Exported by default. Will print the result if called
in void context. SUB can be a coderef for specifying a single sub, or
hashref/arrayref for specifying multiple subs.

Options are specified in hashref OPTS. Available options:

=over 4

=item * n => INT

Run the code C<n> times, or if negative, until at least C<n> seconds.

If unspecified, the default behaviour is to run at most 1 second or 100 times.

=item * dumbbench => BOOL

If 0, do not use L<Dumbbench> even if it is available. If 1, require and use
L<Dumbbench>. If left undef, will use L<Dumbbench> if it is already loaded.

=item * dumbbench_options => HASHREF

Options that will be passed to Dumbbench constructor, e.g.
{target_rel_precision=>0.005, initial_runs=>20}.

=back


=head1 NOTES

B<Prototypes>. I'm a bit ticked off that I can't write C<bench { code ... }>,
instead I have to settle with C<bench sub { code ... }>. This is because I also
want the same C<bench> function to be able to benchmark multiple subroutines
(i.e. C<< bench { sub1 => code, ... } >> as well as C<< bench [code, ...] >>.
Maybe when Perl 5 has multiple dispatch?


=head1 SEE ALSO

L<bench>, command-line interface for this module

L<Benchmark>

L<Dumbbench>

=cut
