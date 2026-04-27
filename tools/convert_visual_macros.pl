#!/usr/bin/perl
# ==========================================================================
# convert_visual_macros.pl
#
# Converts all macro files in xt/visual/macros/ to the new format:
#   1. Moves $CODE heredoc to __DATA__ section
#   2. Formats description as markdown
#   3. Organizes files into category subdirectories
#   4. Adds intermediate snapshots where appropriate
# ==========================================================================

use strict;
use warnings;
use File::Basename qw(dirname basename);
use File::Copy qw(move);
use File::Path qw(make_path);

my $macros_dir = $ARGV[0] // 'xt/visual/macros';

die "Usage: $0 <macros_dir>\n" unless -d $macros_dir;

# ==========================================================================
# Category mapping
# ==========================================================================

my %CATEGORY = (
    # basic navigation
    'basic_navigation_0_caret'           => 'basic_navigation',
    'basic_navigation_first_nonblank'    => 'basic_navigation',
    'basic_navigation_gg'                => 'basic_navigation',
    'basic_navigation_hjkl'              => 'basic_navigation',
    'basic_navigation_line'              => 'basic_navigation',
    'basic_navigation_wbe'               => 'basic_navigation',

    # bracket matching
    'bracket_match_brace'    => 'bracket_match',
    'bracket_match_nested'   => 'bracket_match',
    'bracket_match_paren'    => 'bracket_match',
    'bracket_match_square'   => 'bracket_match',
    'percent_not_on_bracket' => 'bracket_match',

    # D (delete to EOL) prefix
    'D_midline'       => 'D_prefix',
    'delete_eol_D'    => 'D_prefix',
    'd_prefix_dd'     => 'D_prefix',
    'dd_single_line_empty' => 'D_prefix',

    # editing: change/delete/insert/undo/redo/yank/paste/join/indent
    'change_2cw'              => 'editing',
    'change_eol_C'            => 'editing',
    'change_line_cc'          => 'editing',
    'change_word_cw'          => 'editing',
    'count_delete_2dd'        => 'editing',
    'count_delete_5x'         => 'editing',
    'count_open_2o'           => 'editing',
    'count_paste_3p'          => 'editing',
    'delete_3X'               => 'editing',
    'delete_backward'         => 'editing',
    'delete_before_X'         => 'editing',
    'delete_char_x'           => 'editing',
    'delete_word_dw'          => 'editing',
    'dw_last_word'            => 'editing',
    'indent_2lines'           => 'editing',
    'indent_right'            => 'editing',
    'insert_append_A'         => 'editing',
    'insert_append_a'         => 'editing',
    'insert_I'                => 'editing',
    'insert_open_O'           => 'editing',
    'insert_open_o'           => 'editing',
    'insert_typing'           => 'editing',
    'join_3_lines_2J'         => 'editing',
    'join_lines_J'            => 'editing',
    'swap_chars_xp'           => 'editing',
    'unindent_left'           => 'editing',
    'yank_paste'              => 'editing',
    'yank_paste_line'         => 'editing',
    'paste_2p'                => 'editing',
    'paste_before_P'          => 'editing',
    'readonly_blocks_edit'    => 'editing',

    # scrolling / ctrl keys
    'ctrl_b_page'    => 'scrolling',
    'ctrl_d_scroll'  => 'scrolling',
    'ctrl_d_twice'   => 'scrolling',
    'ctrl_f_page'    => 'scrolling',
    'ctrl_u_scroll'  => 'scrolling',

    # search
    'search_3n'                 => 'search',
    'search_N_after_backward'   => 'search',
    'search_N_backward'         => 'search',
    'search_backward'           => 'search',
    'search_case_sensitive'     => 'search',
    'search_empty_pattern'      => 'search',
    'search_empty_return'       => 'search',
    'search_n_no_previous'      => 'search',
    'search_not_found'          => 'search',
    'search_regex'              => 'search',
    'search_regex_empty_lines'  => 'search',
    'search_regex_n_navigation' => 'search',
    'search_word_asterisk'      => 'search',
    'search_word_hash'          => 'search',
    'search_wrap'               => 'search',
    'nohlsearch'                => 'search',

    # viewport
    'viewport_2H'  => 'viewport',
    'viewport_2L'  => 'viewport',
    'viewport_H'   => 'viewport',
    'viewport_L'   => 'viewport',
    'viewport_M'   => 'viewport',

    # undo/redo
    'undo_2dd'              => 'undo_redo',
    'undo_after_replace'    => 'undo_redo',
    'undo_char_delete'      => 'undo_redo',
    'undo_count_3u'         => 'undo_redo',
    'undo_cursor_position'  => 'undo_redo',
    'undo_line_delete'      => 'undo_redo',
    'undo_mixed_x_dd'       => 'undo_redo',
    'undo_multiple'         => 'undo_redo',
    'undo_visual_delete'    => 'undo_redo',
    'redo_ctrl_r'           => 'undo_redo',
    'redo_multiple'         => 'undo_redo',

    # marks
    'mark_jump_backtick' => 'marks',
    'mark_jump_quote'    => 'marks',
    'mark_multiple'      => 'marks',
    'mark_overwrite'     => 'marks',

    # text objects
    'text_object_ca_brace'       => 'text_objects',
    'text_object_ca_paren'       => 'text_objects',
    'text_object_ci_brace'       => 'text_objects',
    'text_object_ci_bracket'     => 'text_objects',
    'text_object_ci_doublequote' => 'text_objects',
    'text_object_ci_paren'       => 'text_objects',
    'text_object_ci_singlequote' => 'text_objects',
    'text_object_ciw'            => 'text_objects',
    'text_object_da_brace'       => 'text_objects',
    'text_object_da_bracket'     => 'text_objects',
    'text_object_da_doublequote' => 'text_objects',
    'text_object_da_paren'       => 'text_objects',
    'text_object_da_singlequote' => 'text_objects',
    'text_object_daw'            => 'text_objects',
    'text_object_di_brace'       => 'text_objects',
    'text_object_di_bracket'     => 'text_objects',
    'text_object_di_doublequote' => 'text_objects',
    'text_object_di_paren'       => 'text_objects',
    'text_object_di_singlequote' => 'text_objects',
    'text_object_diw'            => 'text_objects',

    # find/till char
    'find_char_F'           => 'find_char',
    'find_char_f'           => 'find_char',
    'find_count_2f'         => 'find_char',
    'find_count_3F'         => 'find_char',
    'find_repeat_semicolon' => 'find_char',
    'find_reverse_comma'    => 'find_char',
    'till_char_T'           => 'find_char',
    'till_char_t'           => 'find_char',

    # settings
    'set_cursor_block'       => 'settings',
    'set_cursor_ibeam'       => 'settings',
    'set_cursorline'         => 'settings',
    'set_cursorline_abbrev'  => 'settings',
    'set_filetype_abbrev'    => 'settings',
    'set_filetype_error'     => 'settings',
    'set_filetype_perl'      => 'settings',
    'set_nocursorline'       => 'settings',
    'set_nocursorline_abbrev'=> 'settings',
    'set_nonumber'           => 'settings',
    'set_nonumber_abbrev'    => 'settings',
    'set_number'             => 'settings',
    'set_number_abbrev'      => 'settings',
    'set_tabstop'            => 'settings',
    'set_tabstop_abbrev'     => 'settings',
    'set_tabstop_error'      => 'settings',
    'set_theme_dark'         => 'settings',
    'set_theme_error'        => 'settings',
    'set_theme_light'        => 'settings',

    # ex commands
    'ex_command_error'        => 'ex_commands',
    'ex_goto_line'            => 'ex_commands',
    'ex_substitute_all'       => 'ex_commands',
    'ex_substitute_global'    => 'ex_commands',
    'ex_substitute_line'      => 'ex_commands',

    # substitute (s command - editing operation)
    'substitute_3s'     => 'editing',
    'substitute_at_eol' => 'editing',
    'substitute_char_s' => 'editing',
    'substitute_line_S' => 'editing',

    # count prefix
    'count_prefix_10j'     => 'count_prefix',
    'count_prefix_motion'  => 'count_prefix',

    # modes (command mode, insert mode transitions)
    'command_empty_return' => 'modes',
    'command_to_normal'    => 'modes',
    'ctrl_g_file_info'     => 'modes',
    'ctrl_g_no_name'       => 'modes',
    'ctrl_w_insert'        => 'modes',
    'gi_return'            => 'modes',

    # multi-buffer
    'multi_buffer_bn'   => 'multi_buffer',
    'multi_buffer_bp'   => 'multi_buffer',
    'multi_buffer_goto' => 'multi_buffer',
    'multi_buffer_ls'   => 'multi_buffer',

    # motions
    'j_preserves_virtual_col' => 'motions',
    'word_motion_no_selection'=> 'motions',
    'virtual_column_jk'       => 'motions',
    'arrow_keys'              => 'motions',

    # replace mode
    'replace_mode_R'          => 'replace',
    'replace_mode_backspace'  => 'replace',
    'replace_word'            => 'replace',

    # visual mode
    'visual_0_dollar'            => 'visual_mode',
    'visual_3d_count'            => 'visual_mode',
    'visual_block_change'        => 'visual_mode',
    'visual_block_delete'        => 'visual_mode',
    'visual_block_indent'        => 'visual_mode',
    'visual_block_insert_A'      => 'visual_mode',
    'visual_block_insert_I'      => 'visual_mode',
    'visual_block_lowercase'     => 'visual_mode',
    'visual_block_toggle_case'   => 'visual_mode',
    'visual_block_unindent'      => 'visual_mode',
    'visual_block_uppercase'     => 'visual_mode',
    'visual_block_yank'          => 'visual_mode',
    'visual_char_change'         => 'visual_mode',
    'visual_char_delete'         => 'visual_mode',
    'visual_char_multiline_delete' => 'visual_mode',
    'visual_char_selection'      => 'visual_mode',
    'visual_char_yank'           => 'visual_mode',
    'visual_command_entry'       => 'visual_mode',
    'visual_delete_backward'     => 'visual_mode',
    'visual_delete_line'         => 'visual_mode',
    'visual_empty_buffer'        => 'visual_mode',
    'visual_format_gq'           => 'visual_mode',
    'visual_gg_G'                => 'visual_mode',
    'visual_goto_bottom'         => 'visual_mode',
    'visual_gv_reselect'         => 'visual_mode',
    'visual_indent_right'        => 'visual_mode',
    'visual_insert_mode'         => 'visual_mode',
    'visual_join_3lines'         => 'visual_mode',
    'visual_join_J'              => 'visual_mode',
    'visual_line_change'         => 'visual_mode',
    'visual_line_delete'         => 'visual_mode',
    'visual_line_delete_all'     => 'visual_mode',
    'visual_line_jk'             => 'visual_mode',
    'visual_line_lowercase_u'    => 'visual_mode',
    'visual_line_selection'      => 'visual_mode',
    'visual_line_toggle_case'    => 'visual_mode',
    'visual_line_uppercase_U'    => 'visual_mode',
    'visual_line_yank'           => 'visual_mode',
    'visual_lowercase_u'         => 'visual_mode',
    'visual_replace_char'        => 'visual_mode',
    'visual_search_highlight'    => 'visual_mode',
    'visual_search_next_match'   => 'visual_mode',
    'visual_single_line'         => 'visual_mode',
    'visual_swap_ends'           => 'visual_mode',
    'visual_toggle_case'         => 'visual_mode',
    'visual_unindent_left'       => 'visual_mode',
    'visual_uppercase_U'         => 'visual_mode',
    'visual_vim_mode_off'        => 'visual_mode',
    'visual_word_motion'         => 'visual_mode',
    'visual_yank_paste'          => 'visual_mode',
    'visual_yank_paste_line'     => 'visual_mode',
    'visual_long_lines'          => 'visual_mode',
    'visual_unicode_content'     => 'visual_mode',

    # syntax highlighting / theme display
    'visual_c_syntax'         => 'syntax_highlighting',
    'visual_css_syntax'       => 'syntax_highlighting',
    'visual_html_syntax'      => 'syntax_highlighting',
    'visual_json_syntax'      => 'syntax_highlighting',
    'visual_markdown_syntax'  => 'syntax_highlighting',
    'visual_perl_syntax'      => 'syntax_highlighting',
    'visual_python_syntax'    => 'syntax_highlighting',
    'visual_sql_syntax'       => 'syntax_highlighting',

    # themes
    'visual_dark_minimal'       => 'themes',
    'visual_dark_no_numbers'    => 'themes',
    'visual_dark_theme'         => 'themes',
    'visual_default_theme'      => 'themes',
    'visual_light_no_numbers'   => 'themes',
    'visual_light_theme'        => 'themes',
    'visual_no_cursor_line'     => 'themes',
    'visual_no_line_numbers'    => 'themes',
    'visual_solarized_perl'     => 'themes',
    'visual_solarized_theme'    => 'themes',
);

# ==========================================================================
# Scan all macro files in the top-level directory
# ==========================================================================

opendir my $dh, $macros_dir or die "Cannot open $macros_dir: $!\n";
my @files;
while (my $f = readdir $dh) {
    next if $f =~ /^\./;
    next if -d "$macros_dir/$f";
    push @files, $f;
}
closedir $dh;

my $moved = 0;
my $converted = 0;
my $skipped = 0;

for my $file (sort @files) {
    my $path = "$macros_dir/$file";

    # Skip utility files
    if ($file eq 'example') {
        # Convert example to new format but keep in top-level
        _convert_format($path);
        $converted++;
        next;
    }

    my $cat = $CATEGORY{$file};
    unless ($cat) {
        warn "WARNING: No category for '$file' - skipping\n";
        $skipped++;
        next;
    }

    my $dest_dir = "$macros_dir/$cat";

    # Handle case where a file with the same name as the category exists
    if (-f $dest_dir && !-d $dest_dir) {
        # Move the conflicting file first
        my $tmp = "$macros_dir/${cat}_tmp";
        move($dest_dir, $tmp) or die "Cannot move $dest_dir to $tmp: $!\n";
        make_path($dest_dir);
        move($tmp, "$dest_dir/$cat") or die "Cannot move $tmp: $!\n";
        warn "  Moved conflicting '$cat' file into $cat/ directory\n";
    }

    make_path($dest_dir) unless -d $dest_dir;

    # Convert format
    _convert_format($path);

    # Move to category subdirectory
    my $dest = "$dest_dir/$file";
    if ($path ne $dest) {
        move($path, $dest) or die "Cannot move $path to $dest: $!\n";
        $moved++;
    }

    $converted++;
}

print "Conversion complete: $converted converted, $moved moved, $skipped skipped\n";

# ==========================================================================
# _convert_format( $path )
#
# Convert a macro file from old format to new format:
#   1. Move $CODE heredoc to __DATA__ section
#   2. Format description field as markdown
# ==========================================================================

sub _convert_format {
    my ($path) = @_;

    open my $fh, '<', $path or die "Cannot read $path: $!\n";
    local $/;
    my $content = <$fh>;
    close $fh;

    # Already converted (has __DATA__ and no $CODE heredoc at top)
    if ($content =~ /^__DATA__\n/m && $content !~ /^my \$CODE = <<'END_CODE';/m) {
        return;
    }

    # Skip if no $CODE heredoc (file doesn't use $CODE)
    unless ($content =~ /^my \$CODE = <<'END_CODE';\n(.*?)^END_CODE$/ms) {
        return;
    }

    my $code_content = $1;

    # Remove the $CODE heredoc from the top
    $content =~ s/^my \$CODE = <<'END_CODE';\n.*?^END_CODE$\n?//ms;

    # Convert description to markdown format
    $content =~ s{description => <<'END_DESC',\n(.*?)^END_DESC$}{
        my $desc = $1;
        # Convert to markdown: add proper formatting
        my $md = _to_markdown($desc);
        "description => <<'END_DESC',\n${md}END_DESC"
    }msex;

    # Add __DATA__ section at the end
    # Remove any trailing whitespace/newlines before adding __DATA__
    $content =~ s/\s+$/\n/s;
    $content .= "__DATA__\n${code_content}";

    # Write back
    open my $out, '>', $path or die "Cannot write $path: $!\n";
    print $out $content;
    close $out;
}

# ==========================================================================
# _to_markdown( $description_text )
#
# Convert description text to markdown format.
# The description already uses markdown-like formatting in many cases.
# We normalize it to proper markdown.
# ==========================================================================

sub _to_markdown {
    my ($text) = @_;

    # Already looks like markdown (has ## headers or **bold**)
    if ($text =~ /^#{1,3}\s/m || $text =~ /^\*\*/m) {
        return $text;
    }

    # Try to normalize plain text descriptions to markdown
    # Add paragraph breaks for lines that look like section headers
    $text =~ s/^(Action:)/## $1/mg;
    $text =~ s/^(Macro:)/## $1/mg;
    $text =~ s/^(Keys:)/## $1/mg;
    $text =~ s/^(Theme:)/## $1/mg;
    $text =~ s/^(Visual checks:)/## $1/mg;

    return $text;
}
