#!perl -T

use strict;
use warnings;

use Test::More tests => 4;
use Module::Loaded;
use Bench;

like(bench(sub {sleep 1}), qr/^1\.\d+s$/, "bench with default opts");
like(bench(sub {sleep 1}, 2), qr!total time=2\.\d+s!, "bench with opts: 2");
like(bench(sub {sleep 1}, {n=>0}), qr/^$/, "bench with opts: {n=>0}");
like(bench(sub {}, -2), qr!total time=2\.\d+s!, "bench with opts: -2");

# XXX test opt dumbbench

