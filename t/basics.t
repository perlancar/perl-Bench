#!perl -T

use strict;
use warnings;

use Test::More tests => 5;
use Module::Loaded;
use Bench;

like(bench(sub {}), qr!2\.\d+s!, "bench single sub with default opts");
like(bench(sub {}, 2), qr!0\.\d+s!, "bench single sub with opts: 2");
like(bench(sub {}, {n=>0}), qr!0 calls!, "bench single sub with opts: {n=>0}");
like(bench({subs=>{a=>sub {}, b=>sub {}}, n=>0}), qr!^a: .+^b: !ms,
     "bench multiple subs");

SKIP: {
    # XXX use Capture::Tiny
    eval { require Dumbbench };
    skip "Can't load Dumbbench", 1 unless is_loaded("Dumbbench");
    like(bench(sub {}, {dumbbench=>1}), qr!^$!,
         "bench single sub with opts: {dumbbench=>1}");
}
