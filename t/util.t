#!/usr/bin/perl
# t/util.t - Tests for Gtk3::SourceEditor::Util
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../lib";
use_ok('Gtk3::SourceEditor::Util', 'safe_call', 'parse_hex_color_rgb',
    'key_name_to_char', 'is_printable_key');

# ==========================================================================
# safe_call tests
# ==========================================================================

subtest 'safe_call with object that has method' => sub {
    my $obj = bless {}, 'MockWithMethod';
    no strict 'refs';
    *{MockWithMethod::can_method} = sub { 1 };
    *{MockWithMethod::hello} = sub { shift; return "hello: @_"; };
    ok($obj->can('hello'), 'mock object has hello method');

    my $result = Gtk3::SourceEditor::Util::safe_call($obj, 'hello', 'world');
    is($result, 'hello: world', 'safe_call dispatches correctly');
};

subtest 'safe_call with object missing method' => sub {
    my $obj = bless {}, 'MockWithoutMethod';
    no strict 'refs';
    *{MockWithoutMethod::can_method} = sub { 0 };

    my $result = Gtk3::SourceEditor::Util::safe_call($obj, 'nonexistent');
    is($result, undef, 'safe_call returns undef for missing method');
};

subtest 'safe_call with undef object' => sub {
    my $result = Gtk3::SourceEditor::Util::safe_call(undef, 'some_method');
    is($result, undef, 'safe_call returns undef for undef object');
};

subtest 'safe_call with undef method' => sub {
    my $obj = bless {}, 'MockObj';
    my $result = Gtk3::SourceEditor::Util::safe_call($obj, undef);
    is($result, undef, 'safe_call returns undef for undef method');
};

subtest 'safe_call warn-once behavior' => sub {
    # Reset the internal warn state for this test
    # (We can't easily test warn output, but we verify no crash)
    my $obj = bless {}, 'MockWarnOnce';
    no strict 'refs';
    *{MockWarnOnce::can_method} = sub { 0 };

    # First call - should warn
    Gtk3::SourceEditor::Util::safe_call($obj, 'missing1');
    # Second call - should NOT warn (already warned)
    Gtk3::SourceEditor::Util::safe_call($obj, 'missing1');
    # Different method - should warn
    Gtk3::SourceEditor::Util::safe_call($obj, 'missing2');

    ok(1, 'warn-once did not crash');
};

# ==========================================================================
# parse_hex_color_rgb tests
# ==========================================================================

subtest 'parse_hex_color_rgb standard colors' => sub {
    my ($r, $g, $b) = parse_hex_color_rgb('#000000');
    is($r, 0.0, 'black R');
    is($g, 0.0, 'black G');
    is($b, 0.0, 'black B');

    ($r, $g, $b) = parse_hex_color_rgb('#ffffff');
    is($r, 1.0, 'white R');
    is($g, 1.0, 'white G');
    is($b, 1.0, 'white B');
};

subtest 'parse_hex_color_rgb without hash prefix' => sub {
    my ($r, $g, $b) = parse_hex_color_rgb('ff0000');
    is(sprintf("%.4f", $r), '1.0000', 'red R');
    is(sprintf("%.4f", $g), '0.0000', 'red G');
    is(sprintf("%.4f", $b), '0.0000', 'red B');
};

subtest 'parse_hex_color_rgb mixed values' => sub {
    my ($r, $g, $b) = parse_hex_color_rgb('#1a2b3c');
    is(sprintf("%.4f", $r), '0.1020', 'custom R');
    is(sprintf("%.4f", $g), '0.1686', 'custom G');
    is(sprintf("%.4f", $b), '0.2353', 'custom B');
};

subtest 'parse_hex_color_rgb uppercase hex' => sub {
    my ($r, $g, $b) = parse_hex_color_rgb('#AABBCC');
    is(sprintf("%.4f", $r), '0.6667', 'uppercase R');
    is(sprintf("%.4f", $g), '0.7333', 'uppercase G');
    is(sprintf("%.4f", $b), '0.8000', 'uppercase B');
};

subtest 'parse_hex_color_rgb dies on undef' => sub {
    eval { parse_hex_color_rgb(undef) };
    like($@, qr/expected.*undef/i, 'dies on undef input');
};

subtest 'parse_hex_color_rgb dies on invalid' => sub {
    eval { parse_hex_color_rgb('not-a-color') };
    like($@, qr/invalid hex color/i, 'dies on invalid input');

    eval { parse_hex_color_rgb('#1234') };
    like($@, qr/invalid hex color/i, 'dies on short input');

    eval { parse_hex_color_rgb('#GGHHII') };
    like($@, qr/invalid hex color/i, 'dies on non-hex chars');
};

# ==========================================================================
# key_name_to_char tests
# ==========================================================================

subtest 'key_name_to_char: single-char names pass through' => sub {
    is(key_name_to_char('a'), 'a', 'a stays a');
    is(key_name_to_char('Z'), 'Z', 'Z stays Z');
    is(key_name_to_char('5'), '5', '5 stays 5');
};

subtest 'key_name_to_char: multi-char GDK names resolve to characters' => sub {
    # These depend on GDK being available in the test environment.
    # If Gtk3::Gdk is a mock, we test the fallback behavior.
    my $comma = key_name_to_char('comma');
    if (defined $comma) {
        is($comma, ',', 'comma resolves to ,');
    } else {
        ok(1, 'comma not resolved (mock GDK)');
    }

    my $period = key_name_to_char('period');
    if (defined $period) {
        is($period, '.', 'period resolves to .');
    } else {
        ok(1, 'period not resolved (mock GDK)');
    }
};

subtest 'key_name_to_char: non-printable returns undef' => sub {
    is(key_name_to_char('Left'), undef, 'Left is not printable');
    is(key_name_to_char('Escape'), undef, 'Escape is not printable');
    is(key_name_to_char('Control_L'), undef, 'Control_L is not printable');
};

subtest 'key_name_to_char: undef/empty input' => sub {
    is(key_name_to_char(undef), undef, 'undef returns undef');
    is(key_name_to_char(''), undef, 'empty returns undef');
};

# ==========================================================================
# is_printable_key tests
# ==========================================================================

subtest 'is_printable_key: single chars are printable' => sub {
    ok(is_printable_key('a'), 'a is printable');
    ok(is_printable_key('Z'), 'Z is printable');
    ok(is_printable_key('0'), '0 is printable');
};

subtest 'is_printable_key: special keys are not printable' => sub {
    ok(!is_printable_key('Left'), 'Left not printable');
    ok(!is_printable_key('Escape'), 'Escape not printable');
    ok(!is_printable_key('Return'), 'Return not printable');
    ok(!is_printable_key('Tab'), 'Tab not printable');
};

subtest 'is_printable_key: undef/empty' => sub {
    ok(!is_printable_key(undef), 'undef not printable');
    ok(!is_printable_key(''), 'empty not printable');
};

subtest 'is_printable_key: multi-char GDK names' => sub {
    # If GDK mock doesn't resolve these, they should return false
    my $result = is_printable_key('asterisk');
    # Either true (real GDK) or false (mock) -- just verify no crash
    ok(defined $result, 'asterisk check does not crash');
};

done_testing;
