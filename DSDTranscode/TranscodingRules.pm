package Plugins::DSDTranscode::TranscodingRules;

# Builds and installs wvpx->flc transcoding profiles directly into
# Slim::Player::TranscodingHelper's tables, instead of writing a
# custom-convert.conf and waiting for a restart.
#
# CONFIRMED against the actual TranscodingHelper.pm / CapabilitiesHelper.pm
# pulled from the slimserver repo:
#   - %Slim::Player::TranscodingHelper::commandTable and ::capabilities
#     are plain package 'our' hashes, freely writable from here.
#   - profile keys are "<src>-<dst>-<model>-<clientid>", clientid
#     lowercased (loadConversionTables does lc($4) when parsing a file;
#     we lc($client->id) here to match).
#   - getConvertCommand2() tries, in this order:
#       src-dst-model-clientid, src-dst-*-clientid,
#       src-dst-model-*,        src-dst-*-*
#     so a per-player entry naturally wins over the model-wide default
#     without any file-precedence trickery.
#   - enabledFormat() gates purely on preferences('server')->get('disabledformats'),
#     with no reference to what the player advertised - so disabling
#     wvpx-dsf-*-* / wvpx-dff-*-* here is sufficient on its own; a
#     client-side "-e dsd" is redundant once this is in place, not required.
#   - the capabilities hash shape (I/F/T/U/D/E keys, T and U holding a
#     "KEY=value" string) mirrors exactly what _getCapabilities() produces
#     when parsing a "# FT:{START=--skip=%t}U:{END=--until=%v}D" comment
#     line from a conf file.

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Player::TranscodingHelper;
use Slim::Player::Client;

use Plugins::DSDTranscode::Log;

my $prefs = preferences('plugin.dsdtranscode');
my $log = Plugins::DSDTranscode::Log::get();

use constant SRC   => 'wvpx';   # WavPack containing DSD - confirmed in original guide sec. 5.1
use constant DST   => 'flc';
use constant MODEL => 'squeezelite';

# The two native-DSD destinations to close off (guide sec. 6, row 2 & 3).
use constant NATIVE_ROUTES => ('wvpx-dsf-*-*', 'wvpx-dff-*-*');

sub init {
	my $serverPrefs = preferences('server');

	if ($prefs->get('enabled')) {
		_disableNativeRoutes($serverPrefs) if $prefs->get('disableNativeDSD');
		_installProfile(MODEL, '*', $prefs->get('defaultRate'), $prefs->get('gain'));
	}
	else {
		# plugin-level rollback: put native DSD routes back and drop our rule
		_restoreNativeRoutes($serverPrefs);
		_removeProfile(MODEL, '*');
	}
}

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

sub _restoreNativeRoutes {
	my $serverPrefs = shift;

	my %drop = map { $_ => 1 } NATIVE_ROUTES;
	my @kept = grep { !$drop{$_} } @{ $serverPrefs->get('disabledformats') || [] };

	$serverPrefs->set('disabledformats', \@kept);
}

# Mirrors the sox/wvunpack pipeline from the original guide sec. 8.5,
# with the target rate and gain substituted in as literals rather than
# via LMS's own $RESAMPLE$/%d tokens - same reasoning as the guide's own
# custom-convert.conf rule: we want a fixed rate, not the samplerateLimit
# LMS would otherwise compute (guide sec. 8.1).
sub _command {
	my ($rate, $gain) = @_;
	$gain = -3 unless defined $gain && $gain ne '';
	$rate ||= 88200;

	return '[wvunpack] $FILE$ -wq $START$ $END$ -o - | '
		. '[sox] -q -t wav - -t flac -C 0 -b 24 - gain ' . $gain . ' rate -v -L ' . $rate;
}

sub _capabilities {
	return {
		I => 'noArgs',
		F => 'noArgs',
		T => 'START=--skip=%t',
		U => 'END=--until=%v',
		D => 'noArgs',   # declared but no $RESAMPLE$ substitution - see guide sec. 8.1
		E => {},
	};
}

sub _installProfile {
	my ($model, $clientid, $rate, $gain) = @_;

	my $profile = join('-', SRC, DST, $model, $clientid);

	$Slim::Player::TranscodingHelper::commandTable{$profile} = _command($rate, $gain);
	$Slim::Player::TranscodingHelper::capabilities{$profile} = _capabilities();

	main::INFOLOG && $log->is_info
		&& $log->info("Installed profile $profile at ${rate}Hz (gain $gain)");

	return $profile;
}

sub _removeProfile {
	my ($model, $clientid) = @_;

	my $profile = join('-', SRC, DST, $model, $clientid);

	delete $Slim::Player::TranscodingHelper::commandTable{$profile};
	delete $Slim::Player::TranscodingHelper::capabilities{$profile};
}

# Best-effort cleanup for when the plugin is being removed, not just
# disabled via its own "enabled" checkbox. NOT gated on the 'enabled'
# pref - this always restores native DSD/DoP and removes every profile
# this plugin may have installed, including per-player overrides, since
# by this point the plugin's own settings pages won't be reachable to
# undo anything by hand.
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

# Called from Plugin.pm on every new/reconnected client, and from the
# player settings page whenever that player's override is saved.
sub rebuildFor {
	my $client = shift or return;

	# model() is defined per concrete player subclass (Client.pm's own
	# modelName() is a stub) - confirmed the field exists and is what
	# gets snapshotted into per-client server prefs in initPrefs().
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
		# no override set - fall through to the model-wide default profile
		_removeProfile(MODEL, $mac);
	}
}

1;

__END__
