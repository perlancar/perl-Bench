package Bench;
# ABSTRACT: Benchmark running times of Perl code

use 5.010;
use strict;
use warnings;

use Module::Loaded;
use Time::HiRes qw/gettimeofday tv_interval/;

my $bench_called;
my ($t0, $ti);

sub _set_time0    { $t0 = [gettimeofday] }

sub _set_interval { $ti = tv_interval($t0, [gettimeofday]) }

sub import {
    _set_time0;
    no strict 'refs';
    my $caller = caller();
    *{"$caller\::bench"} = \&bench;
}

sub _fmt_sec {
    my $t = shift;
    my $fmt;

    if ($t > 1) {
        $fmt = "%.3fs";
    } elsif ($t > 0.1) {
        $fmt = "%.4fs";
    } else {
        $t *= 1000;
        if ($t > 0.1) {
            $fmt = "%.3fms";
        } elsif ($t > 0.01) {
            $fmt = "%.4fms";
        } else {
            $fmt = "%.5fms";
        }
    }
    sprintf($fmt, $t);
}

sub bench($;$) {
    my $opts;
    if (ref($_[0]) eq 'CODE') {
        my $sub = shift;
        $opts = shift;
        $opts //= {};
        $opts = {n=>$opts} if ref($opts) ne 'HASH';
        $opts->{subs} //= {CODE=>$sub};
    } elsif (ref($_[0]) eq 'HASH') {
        $opts = shift;
    } else {
        die "Usage: bench(CODEREF, OPTS) or bench(OPTS)";
    }
    die "Please specify one or more subs"
        unless $opts->{subs} && keys %{$opts->{subs}};

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
            map { Dumbbench::Instance::PerlSub->new(code => $opts->{subs}{$_}) }
                keys %{ $opts->{subs} }
        );
        $bench->run;
        $bench->report;

    } else {

        for my $codename (keys %{ $opts->{subs} }) {
            my $code = $opts->{subs}{$codename};

            my $n = $opts->{n};

            my $i = 0;

            # run code once to set default n & j (to reduce the number of
            # time-interval-taking when n is negative)
            my $j = 1;
            _set_time0;
            $code->();
            _set_interval;
            $i++;
            if ($ti >= 2) {
                $n //= 1;
            } else {
                $n //= -2;
                $j = $ti ? int(1/$ti) : 1000;
            }

            _set_time0;
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
                (keys(%{$opts->{subs}}) > 1 ? "$codename: " : ""),
                sprintf("%d calls (%.0f/s), %s (%s/call)",
                        $i, $i/$ti, _fmt_sec($ti),
                        _fmt_sec($i ? $ti/$i : 0))
            );
            say $res if $void;
            push @res, $res;
        }

    }

    $bench_called++;
    join("\n", @res);
}

END {
    $ti = tv_interval($t0, [gettimeofday]);
    say _fmt_sec($ti) unless $bench_called || $ENV{HARNESS_ACTIVE};
}

1;
__END__

=head1 SYNOPSIS

 # time the whole program
 % perl -MBench -e'...'
 0.1234s

 # basic usage of bench()
 % perl -MBench -e'bench sub { ... }'
 397 calls (198/s), 2.0054s (0.0051s/call)

 # get bench result in a variable
 % perl -MBench -E'my $res = bench sub { ... }'

 # specify bench options
 % perl -MBench -E'bench sub { ... }, 100'
 % perl -MBench -E'bench sub { ... }, {n=>-5}'

 # use Dumbbench as the backend
 % perl -MDumbbench -MBench -E'bench sub { ... }'
 % perl -MBench -E'bench sub { ... }, {dummbench=>1, dumbbench_options=>{...}}'
 Ran 26 iterations (6 outliers).
 Rounded run time per iteration: 2.9029e-02 +/- 4.8e-05 (0.2%)

 # bench multiple codes
 % perl -MBench -E'bench {subs=>{a=>sub {...}, b=>sub {...}}, n=>-2}'
 a: 397 calls (198/s), 2.0054s (0.0051s/call)
 b: 294 calls (146/s), 2.0094s (0.0068s/call)


=head1 DESCRIPTION

This module is an alternative to L<Benchmark>. It provides some nice defaults
and a simpler interface. There is only one function, B<bench()>, and it is
exported by default. If bench() is never called, the whole program will be
timed.

This module can utilize L<Dumbbench> as the backend.

=head1 FUNCTIONS

=head2 bench

Syntax:

 bench(CODEREF)                    # bench a single sub, default options
 bench(CODEREF, HASHREF)           # specify options
 bench(CODEREF, INT)               # equivalent to bench(CODEREF, {n=>INT})
 bench(HASHREF)                    # bench multiple subs, must specify 'subs'

Run Perl code and time it. Exported by default. Will print the result if called
in void context.

Options are specified in HASHREF. Available options:

=over 4

=item * n => INT

Run the code C<n> times, or if negative, until at least C<n> seconds.

If unspecified, the default behaviour is: if code runs for more than 2 seconds,
it will only be run once (n=1). Otherwise n=-2.

=item * subs => HASHREF

Specify subroutine(s) to time. You normally need not specify this option, unless
you want to time several subroutines instead of just one.

=item * dumbbench => BOOL

If 0, do not use L<Dumbbench> even if it is available. If 1, require and use
L<Dumbbench>. If left undef, will use L<Dumbbench> if it is already loaded.

=item * dumbbench_options => HASHREF

Options that will be passed to Dumbbench constructor, e.g.
{target_rel_precision=>0.005, initial_runs=>20}.

=back


=head1 SEE ALSO

L<Benchmark>

L<Dumbbench>

=cut
