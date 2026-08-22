package Plugins::DSDTranscode::Plugin;

# On-the-fly DSD -> PCM transcoding for Lyrion Music Server.
#
# WavPack-compressed DSD files (.wv) are transcoded to FLAC on the server at
# a pinned output sample rate, so that software volume control works on DSD
# content. Two things are set up:
#
#   A. The native wvpx->dsf / wvpx->dff routes are disabled, so DSD/DoP can
#      never reach a player directly from these files.
#   B. A wvpx->flc conversion rule is installed at a fixed sample rate,
#      server-wide by default, with an optional per-player override.
#

use strict;
use warnings;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Control::Request;
use Slim::Player::Client;

use Plugins::DSDTranscode::Log;
use Plugins::DSDTranscode::TranscodingRules;
use Plugins::DSDTranscode::Settings;
use Plugins::DSDTranscode::Settings::Player;

my $log = Plugins::DSDTranscode::Log::get();

# Server-wide preferences. Per-player overrides are stored as client prefs
# and managed by Plugins::DSDTranscode::Settings::Player.
my $prefs = preferences('plugin.dsdtranscode');

$prefs->init({
	enabled          => 1,      # master switch; off = full rollback
	disableNativeDSD => 1,      # Part A: block wvpx->dsf / wvpx->dff
	defaultRate      => 88200,  # Part C default output rate in Hz (88200/176400/352800)
	gain             => -3,     # headroom in dB applied before resampling
});

sub getDisplayName { 'PLUGIN_DSDTRANSCODE' }

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(@_);

	# Register the settings pages. Slim::Web::Settings->new() inspects
	# needsClient() itself to decide whether a page becomes server-wide
	# (Settings -> Plugins...) or per-player (Settings -> Player -> Extra
	# Settings), so nothing further needs wiring up here.
	if (main::WEBUI) {
		Plugins::DSDTranscode::Settings->new;
		Plugins::DSDTranscode::Settings::Player->new;
	}

	# Install the server-wide default profile and the disabledformats
	# entries (or roll everything back when the plugin is disabled).
	Plugins::DSDTranscode::TranscodingRules::init();

	# Apply the rules to players that are already connected, e.g. after a
	# server restart with players online.
	for my $client (Slim::Player::Client::clients()) {
		Plugins::DSDTranscode::TranscodingRules::rebuildFor($client);
	}

	# Apply the rules to players as they connect or reconnect later.
	Slim::Control::Request::subscribe(
		\&_onClientNew,
		[ ['client'], ['new', 'reconnect'] ],
	);

	main::INFOLOG && $log->is_info && $log->info('DSDTranscode initialized');
}

sub _onClientNew {
	my $request = shift;
	my $client  = $request->client || return;

	Plugins::DSDTranscode::TranscodingRules::rebuildFor($client);
}

# Best-effort cleanup when the plugin is disabled or removed. NOTE: the
# recommended removal procedure is to uncheck "Enable DSD transcoding" and
# restart first, so init()'s disable path restores everything cleanly.
# This hook is a safety net for cases where that step is skipped; it is
# not guaranteed to run on every uninstall path.
sub shutdownPlugin {
	Plugins::DSDTranscode::TranscodingRules::teardown();
}

1;

__END__
