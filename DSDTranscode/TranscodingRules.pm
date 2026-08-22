package Plugins::DSDTranscode::TranscodingRules;

# Builds and installs the wvpx->flc transcoding profiles directly into
# Slim::Player::TranscodingHelper's tables, instead of writing a
# custom-convert.conf and waiting for a restart.
#
# Notes on the tables we touch:
#   - %commandTable and %capabilities are package hashes keyed by
#     "<src>-<dst>-<model>-<clientid>" (clientid lowercased).
#   - getConvertCommand2() resolves a conversion in this order:
#       src-dst-model-clientid, src-dst-*-clientid, src-dst-model-*,
#       src-dst-*-*
#     so a per-player entry naturally wins over the model-wide default.
#   - enabledFormat() gates purely on preferences('server')->get('disabledformats'),
#     so removing wvpx-dsf-*-* / wvpx-dff-*-* from the enabled formats is
#     sufficient to block native DSD; no player-side flag is required.
#   - The capabilities hash uses the same I/F/T/U/D/E keys and
#     "KEY=value" strings that _getCapabilities() produces from
#     "# FT:{...}U:{...}D" comment lines in a conf file.

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Player::TranscodingHelper;
use Slim::Player::Client;

use Plugins::DSDTranscode::Log;

my $prefs = preferences('plugin.dsdtranscode');
my $log = Plugins::DSDTranscode::Log::get();

use constant SRC   => 'wvpx';   # WavPack file containing DSD
use constant DST   => 'flc';
use constant MODEL => 'squeezelite';

# The two native-DSD destinations we close off.
use constant NATIVE_ROUTES => ('wvpx-dsf-*-*', 'wvpx-dff-*-*');

# Install or roll back the server-wide rules, depending on the 'enabled' pref.
sub init {
	my $serverPrefs = preferences('server');

	if ($prefs->get('enabled')) {
		_disableNativeRoutes($serverPrefs) if $prefs->get('disableNativeDSD');
		_installProfile(MODEL, '*', $prefs->get('defaultRate'), $prefs->get('gain'));
	}
	else {
		# Plugin-level rollback: put native DSD routes back and drop our rule.
		_restoreNativeRoutes($serverPrefs);
		_removeProfile(MODEL, '*');
	}
}

# Remove the native-DSD destinations from the server's enabled formats.
sub _disableNativeRoutes {
	my $serverPrefs = shift;

	my @disabled = @{ $serverPrefs->get('disabledformats') || [] };
	my %have     = map { $_ => 1 } @disabled;
	my $changed  = 0;

	for my $route (NATIVE_ROUTES) {
		unless ($have{$route}) {
			push @disabled, $route;
			$changed = 1;
		}
	}

	$serverPrefs->set('disabledformats', \@disabled) if $changed;
}

# Restore the native-DSD destinations to the server's enabled formats.
sub _restoreNativeRoutes {
	my $serverPrefs = shift;

	my %drop = map { $_ => 1 } NATIVE_ROUTES;
	my @kept = grep { !$drop{$_} } @{ $serverPrefs->get('disabledformats') || [] };

	$serverPrefs->set('disabledformats', \@kept);
}

# The conversion command: decode WavPack to WAV, then re-encode to FLAC at a
# fixed output rate with the given headroom gain. The rate is a literal
# (not LMS's $RESAMPLE$ token) so the pinned rate is used regardless of the
# player's advertised samplerateLimit.
sub _command {
	my ($rate, $gain) = @_;
	$gain = -3 unless defined $gain && $gain ne '';
	$rate ||= 88200;

	return '[wvunpack] $FILE$ -wq $START$ $END$ -o - | '
		. '[sox] -q -t wav - -t flac -C 0 -b 24 - gain ' . $gain . ' rate -v -L ' . $rate;
}

# Capabilities for the profile: START/END (--skip/--until) are passed
# through to wvunpack; D is declared without a $RESAMPLE$ substitution
# because the rate is pinned in the command itself (see _command).
sub _capabilities {
	return {
		I => 'noArgs',
		F => 'noArgs',
		T => 'START=--skip=%t',
		U => 'END=--until=%v',
		D => 'noArgs',
		E => {},
	};
}

# Write a profile entry into TranscodingHelper's tables. The key encodes
# src-dst-model-clientid; a clientid of '*' means "any player of this model".
sub _installProfile {
	my ($model, $clientid, $rate, $gain) = @_;

	my $profile = join('-', SRC, DST, $model, $clientid);

	$Slim::Player::TranscodingHelper::commandTable{$profile} = _command($rate, $gain);
	$Slim::Player::TranscodingHelper::capabilities{$profile} = _capabilities();

	main::INFOLOG && $log->is_info
		&& $log->info("Installed profile $profile at ${rate}Hz (gain $gain)");

	return $profile;
}

# Remove a profile entry from TranscodingHelper's tables.
sub _removeProfile {
	my ($model, $clientid) = @_;

	my $profile = join('-', SRC, DST, $model, $clientid);

	delete $Slim::Player::TranscodingHelper::commandTable{$profile};
	delete $Slim::Player::TranscodingHelper::capabilities{$profile};
}

# Full cleanup: restore native DSD routes and drop every profile this plugin
# may have installed, including per-player overrides. Called when the plugin
# is disabled or removed, at which point its settings pages are no longer
# reachable to undo anything by hand. Not gated on the 'enabled' pref.
sub teardown {
	my $serverPrefs = preferences('server');

	_restoreNativeRoutes($serverPrefs);
	_removeProfile(MODEL, '*');

	for my $client (Slim::Player::Client::clients()) {
		next unless eval { $client->model eq MODEL };
		_removeProfile(MODEL, lc($client->id));
	}

	main::INFOLOG && $log->is_info && $log->info('DSDTranscode teardown complete');
}

# (Re)apply the correct profile for one player: install the player-specific
# override when one is set, otherwise remove any override so the model-wide
# default applies. Called from Plugin.pm on every new/reconnected client and
# from the player settings page whenever that player's override is saved.
sub rebuildFor {
	my $client = shift or return;

	if (!eval { $client->model eq MODEL }) {
		$log->warn("Could not determine model for client " . $client->id);
		return;
	}

	my $mac = lc($client->id);

	unless ($prefs->get('enabled')) {
		_removeProfile(MODEL, $mac);
		return;
	}

	my $clientPrefs = $prefs->client($client);
	my $override    = $clientPrefs->get('rateOverride');

	if (defined $override && $override ne '') {
		_installProfile(MODEL, $mac, $override, $clientPrefs->get('gainOverride'));
	}
	else {
		# No override set - fall back to the model-wide default profile.
		_removeProfile(MODEL, $mac);
	}
}

1;

__END__
