package Bench;
# ABSTRACT: Benchmark running times of Perl code

use 5.010;
use strict;
use warnings;

use Module::Loaded;
use Time::HiRes qw/gettimeofday tv_interval/;

my $bench_called;
my $t0;
my $fmt = "%.4fs";

sub import {
    $t0 = [gettimeofday];

    no strict 'refs';
    my $caller = caller();
    *{"$caller\::bench"} = \&bench;
}

sub bench(&;$) {
    $bench_called++;
    my ($code, $opts) = @_;
    $opts      //= {};
    $opts      =  {n=>$opts} if ref($opts) ne 'HASH';
    $opts->{n} //= 1;

    my $use_dumbbench;
    if ($opts->{dumbbench}) {
        $use_dumbbench++;
        require Dumbbench;
    } elsif (!defined $opts->{dumbbench}) {
        $use_dumbbench++ if is_loaded('Dumbbench');
    }

    my $res = "";

    if ($use_dumbbench) {

        $opts->{dumbbench_options} //= {};
        my $bench = Dumbbench->new(%{ $opts->{dumbbench_options} });
        $bench->add_instances(
            Dumbbench::Instance::PerlSub->new(code => $code),
        );
        $bench->run;
        $bench->report;

    } else {

        my $i = 0;
        $t0 = [gettimeofday];
        while (1) {
            last if $opts->{n} >= 0 && $i >= $opts->{n};
            $code->();
            $i++;
            last if $opts->{n} < 0 &&
                tv_interval($t0, [gettimeofday]) > -$opts->{n};
        }
        my $ti = tv_interval($t0, [gettimeofday]);
        if ($opts->{n} == 1) {
            $res = sprintf($fmt, $ti);
        } elsif ($opts->{n} != 0) {
            $res = sprintf "iterations=%d, total time=$fmt, avg time/iter=$fmt",
                $i, $ti, $ti/$i;
        }

    }

    say $res unless defined(wantarray) || !$res;
    $res;
}

END {
    say sprintf($fmt, tv_interval($t0, [gettimeofday])) unless $bench_called;
}

1;
__END__

=head1 SYNOPSIS

 # time the whole program
 % perl -MBench -e'...'
 0.1234s

 # basic usage of bench()
 % perl -MBench -e'bench sub { ... }'
 0.1234s

 # get bench result in a variable
 % perl -MBench -E'my $res = bench sub { ... }; say "Spent ", $res'
 Spent 0.1234s

 # specify bench options
 % perl -MBench -E'bench sub { ... }, 100'
 % perl -MBench -E'bench sub { ... }, {n=>-5, ...}'


=head1 DESCRIPTION

This module is a simpler alternative to L<Benchmark>.


=head1 FUNCTIONS

=head2 bench CODEREF, OPTIONS => RESULT

Run Perl code and time it. Exported by default. Will print the result in void
context. OPTIONS is a hashref (defaults to {n=>1}) or a number (defaults to 1,
which means {n=>1}).

Will use Dumbbench

Available options:

=over 4

=item * n => INT (defaults to 1)

Run the code C<n> times, or if negative, until at least C<n> seconds.

=item * dumbbench => BOOL (defaults to undef)

If 0, do not use L<Dumbbench> even if it's available. If 1, require and use
L<Dumbbench>. If left undef, will use L<Dumbbench> if it's already loaded.

=item * dumbbench_options => HASHREF

Options that will be passed to Dumbbench constructor, e.g.
{target_rel_precision=>0.005, initial_runs=>20}.

=back


=head1 SEE ALSO

L<Benchmark>

L<Dumbbench>

=cut
