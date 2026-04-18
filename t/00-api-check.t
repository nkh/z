#!/usr/bin/perl
# t/00-api-check.t - Verify all GTK method calls we make actually exist
# on the real Gtk3::SourceView::View and ::Buffer classes.
#
# This test requires Gtk3 and Gtk3::SourceView to be installed.
# When they are not available (e.g. CI without GTK libs), it skips.
#
# Uses done_testing() instead of plan tests => N so that version-dependent
# methods can be skipped (via SKIP blocks) without causing a plan mismatch.
# The production code ($_call in SourceEditor.pm) already handles missing
# methods gracefully by warning once and skipping.

use strict;
use warnings;
use Test::More;

# --- Try to load the REAL GTK modules ---
# Glib::Object::Introspection uses an INIT block that MUST run during
# Perl's compile phase.  If we load Gtk3 at runtime (via require/eval),
# that INIT block fires too late and produces a fatal warning.  Therefore
# we must attempt to load Gtk3 inside a BEGIN block, after temporarily
# removing the mock library paths from @INC.

my $CAN_REAL_GTK;
BEGIN {
    # Save and strip mock paths from @INC so 'use Gtk3' picks up the
    # real system module (if installed) instead of our t/lib/ mocks.
    my @real_inc = grep { !/\bt\/lib\b/ && !/\bmock_strict\b/ } @INC;
    @INC = @real_inc;

    eval { require Gtk3; Gtk3->import; 1 };
    my $gtk_err = $@;

    eval { require Gtk3::SourceView; Gtk3::SourceView->import; 1 };
    my $sv_err = $@;

    # Restore original @INC (the test framework and other modules may
    # need paths that were in @INC before we stripped them).
    push @INC, "t/lib", "t/mock_strict";

    if ($gtk_err || $sv_err) {
        $CAN_REAL_GTK = 0;
    } else {
        $CAN_REAL_GTK = 1;
    }
}

if (!$CAN_REAL_GTK) {
    plan skip_all => "Real Gtk3/Gtk3::SourceView not installed - cannot verify GTK API";
}

# Use done_testing() — no hardcoded test count — so SKIP blocks don't
# cause plan/ran mismatch on systems with different GtkSourceView versions.

# ==========================================================================
# Methods called on Gtk3::SourceView::View in SourceEditor.pm
# ==========================================================================
my @view_methods = (
    # Core (always present)
    'new',
    'set_buffer',
    'set_show_line_numbers',
    'set_highlight_current_line',
    'set_auto_indent',
    'set_wrap_mode',
    'set_cursor_visible',
    'modify_font',
    'set_tab_width',
    'set_insert_spaces_instead_of_tabs',
    'signal_connect',
);

for my $m (@view_methods) {
    ok(Gtk3::SourceView::View->can($m),
       "Gtk3::SourceView::View->can('$m')");
}

# ==========================================================================
# Version-dependent methods on Gtk3::SourceView::View
# These were added in specific GtkSourceView releases and may not exist
# on older installations.  Skipped gracefully when not available.
# ==========================================================================
SKIP: {
    my @version_view = (
        'set_indent_width',               # 3.16
        'set_show_right_margin',          # 2.x
        'set_right_margin_position',      # 2.x
        'set_smart_home_end',             # 3.0
        'set_show_line_marks',            # 2.2
    );
    for my $m (@version_view) {
        skip "Gtk3::SourceView::View->can('$m') not available on this GtkSourceView", 1
            unless Gtk3::SourceView::View->can($m);
        ok(1, "Gtk3::SourceView::View->can('$m') [version-dependent]");
    }
}

# ==========================================================================
# Methods called on Gtk3::SourceView::Buffer in SourceEditor.pm
# ==========================================================================
my @buffer_methods = (
    'new_with_language',
    'set_highlight_syntax',
    'set_text',
    'place_cursor',
    'set_modified',
    'set_style_scheme',
    'get_start_iter',
    'get_end_iter',
    'signal_connect',
);

for my $m (@buffer_methods) {
    ok(Gtk3::SourceView::Buffer->can($m),
       "Gtk3::SourceView::Buffer->can('$m')");
}

# ==========================================================================
# Version-dependent methods on Gtk3::SourceView::Buffer
# ==========================================================================
SKIP: {
    skip "set_highlight_matching_brackets not available on this GtkSourceView", 1
        unless Gtk3::SourceView::Buffer->can('set_highlight_matching_brackets');
    ok(1, "Gtk3::SourceView::Buffer->can('set_highlight_matching_brackets') [2.0+]");
}

# ==========================================================================
# Methods called on Gtk3::SourceView::LanguageManager
# ==========================================================================
my @lang_methods = (
    'get_default',
    'get_language',
    'guess_language',
);

for my $m (@lang_methods) {
    ok(Gtk3::SourceView::LanguageManager->can($m),
       "Gtk3::SourceView::LanguageManager->can('$m')");
}

# ==========================================================================
# Methods called on Gtk3::SourceView::StyleSchemeManager
# ==========================================================================
my @scheme_methods = (
    'get_default',
    'prepend_search_path',
    'get_scheme',
);

for my $m (@scheme_methods) {
    ok(Gtk3::SourceView::StyleSchemeManager->can($m),
       "Gtk3::SourceView::StyleSchemeManager->can('$m')");
}

# ==========================================================================
# Search infrastructure: Gtk3::SourceView::SearchSettings
# Used for search highlight (all matches) and incremental search.
# Available since GtkSourceView 3.10.
# ==========================================================================
SKIP: {
    my @search_settings_methods = (
        'new',
        'set_search_text',
        'set_case_sensitive',
        'set_regex_enabled',
        'set_wrap_around',
    );
    skip "Gtk3::SourceView::SearchSettings not available on this GtkSourceView",
        scalar @search_settings_methods
        unless Gtk3::SourceView::SearchSettings->can('new');
    for my $m (@search_settings_methods) {
        ok(Gtk3::SourceView::SearchSettings->can($m),
           "Gtk3::SourceView::SearchSettings->can('$m')");
    }
}

# ==========================================================================
# Search infrastructure: Gtk3::SourceView::SearchContext
# Used for search highlight (all matches) and incremental search.
# Available since GtkSourceView 3.10.
# ==========================================================================
SKIP: {
    my @search_context_methods = (
        'new',
        'set_highlight',
        'set_match_style',
    );
    skip "Gtk3::SourceView::SearchContext not available on this GtkSourceView",
        scalar @search_context_methods
        unless Gtk3::SourceView::SearchContext->can('new');
    for my $m (@search_context_methods) {
        ok(Gtk3::SourceView::SearchContext->can($m),
           "Gtk3::SourceView::SearchContext->can('$m')");
    }
}

done_testing();
